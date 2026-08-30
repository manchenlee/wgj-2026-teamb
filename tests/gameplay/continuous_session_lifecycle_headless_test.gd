extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")
const PROFILE_SCRIPT := preload("res://data/character_profiles/phase_character_profile.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")

const PSYCHOLOGICAL_MODE := CONTROLLER_SCRIPT.InteractionMode.PSYCHOLOGICAL
const PHYSIOLOGICAL_MODE := CONTROLLER_SCRIPT.InteractionMode.PHYSIOLOGICAL
const COMPATIBILITY_SOURCE := CONTROLLER_SCRIPT.CharacterExpressionSource.COMPATIBILITY

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_success_routes_directly_without_reset()
	await _test_forced_success_routes_directly()
	await _test_continuous_band_progression_and_dialogue_pool()
	await _test_failure_routes_and_peak_depletion()
	await _test_physiological_combo_lifecycle()
	await _test_explicit_new_run_reset()
	await _test_actual_ending_fade_remains()
	if _failures.is_empty():
		print("Continuous-session lifecycle headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_success_routes_directly_without_reset() -> void:
	var game = await _create_game()
	var physical_threshold := float(game.active_phase_config.success_condition.get("physical_value", 100.0))
	var emotional_threshold := float(game.active_phase_config.success_condition.get("emotional_value", 70.0))
	game.arousal_model.physical = physical_threshold - 0.001
	game.arousal_model.emotional = emotional_threshold
	game.arousal_model.peak = 100.0
	game.arousal_model.peak_has_activated = true
	game._check_ending()
	_assert(not game.ending_transition_started and game.run_active, "Physical below the success threshold ended the run.")

	game.dialogue_panel.append_history("continuous history marker", "companion")
	var history_before: Array = game.dialogue_panel.get_dialogue_history()
	var phase_before: int = game.active_phase_index
	var config_before = game.active_phase_config
	game.arousal_model.physical = physical_threshold
	var scores_before := [physical_threshold, emotional_threshold, game.arousal_model.peak]
	var endings: Array[String] = []
	game.ending_requested.connect(func(ending_type: String) -> void: endings.append(ending_type))
	game.phase_transition_overlay = null
	game._check_ending()

	_assert(endings == [CONFIG.SUCCESS_ENDING], "Threshold success did not route directly to the final success ending: %s" % str(endings))
	_assert(game.ending_transition_started and not game.run_active, "Final success did not begin canonical ending teardown.")
	_assert(game.active_phase_index == phase_before and game.active_phase_config == config_before, "Final success created a second gameplay phase/config.")
	_assert([game.arousal_model.physical, game.arousal_model.emotional, game.arousal_model.peak] == scores_before, "Final success reset scores before ending.")
	_assert(game.dialogue_panel.get_dialogue_history() == history_before, "Final success cleared dialogue history before ending.")
	_assert(not game.has_method("_has_next_phase") and not game.has_method("_begin_phase_transition") and not game.has_method("_complete_phase_transition"), "Obsolete automatic phase-transition methods remain callable.")
	await _free_game(game)


func _test_forced_success_routes_directly() -> void:
	var game = await _create_game()
	var endings: Array[String] = []
	game.ending_requested.connect(func(ending_type: String) -> void: endings.append(ending_type))
	game.phase_transition_overlay = null
	game.force_ending(CONFIG.SUCCESS_ENDING)
	_assert(endings == [CONFIG.SUCCESS_ENDING], "Forced success did not request the final success ending: %s" % str(endings))
	_assert(game.ending_transition_started, "Forced success did not enter canonical ending progression.")
	await _free_game(game)


func _test_continuous_band_progression_and_dialogue_pool() -> void:
	var game = await _create_game()
	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	game.force_spawn_spot()
	var spots_before: Array = game.spot_manager._active_spots.duplicate()
	_assert(not spots_before.is_empty(), "Continuous-session test could not create an active note.")
	game.set_interaction_mode(PSYCHOLOGICAL_MODE)
	game.dialogue_panel.append_history("band continuity marker", "companion")
	game.psychological_dialogue_controller.current_line = "preserved line"
	game.psychological_dialogue_controller.current_entry = {"marker": "preserved entry"}
	game.psychological_dialogue_controller.current_prompt = {"text": "preserved prompt"}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game.physiological_dialogue_controller.current_line = "preserved physiological line"
	game.physiological_dialogue_controller.current_entry = {"marker": "preserved physiological entry"}
	game.physiological_dialogue_controller.current_prompt = {"text": "preserved physiological prompt"}
	game.choice_timeout_timer.start(4.0)
	game.request_character_expression(COMPATIBILITY_SOURCE, PROFILE_SCRIPT.ExpressionState.POSITIVE)
	game.has_switched_to_game_bgm = true
	game.last_requested_bgm_key = "overall_high"
	game.arousal_model.emotional = 60.0
	game.arousal_model.peak = 42.0
	game.arousal_model.peak_has_activated = true
	var phase_before: int = game.active_phase_index
	var config_before = game.active_phase_config
	var dialogue_entries_before: Array = game.psychological_dialogue_controller.entries.duplicate(true)
	var physiological_entries_before: Array = game.physiological_dialogue_controller.entries.duplicate(true)
	var preserved_before := _capture_continuous_state(game, spots_before)
	var overlay_visible_before: bool = game.phase_transition_overlay.visible

	for band in range(6):
		game.arousal_model.physical = _score_inside_band(band)
		game._sync_physiological_visual_band()
		_assert(game.current_visual_band == band, "Continuous run did not reach visual band %d." % band)
		_assert(game.run_active and not game.ending_transition_started, "Visual band %d ended or stopped the run below the peak threshold." % band)
		_assert(game.active_phase_index == phase_before and game.active_phase_config == config_before, "Visual band %d changed gameplay config." % band)
		_assert(game.phase_transition_overlay.visible == overlay_visible_before, "Visual band %d started the obsolete white fade." % band)

	game.arousal_model.physical = 49.0
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 2, "Band 3 to 2 reversal failed.")
	_assert(game._get_active_phase_id() == "phase_1", "Physical 49 did not return to Phase 1.")
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 3, "Physical 50 did not enter the first Phase 2 band.")
	_assert(game._get_active_phase_id() == "phase_2", "Physical 50 did not enter Phase 2.")
	_assert(game.psychological_dialogue_controller.entries == dialogue_entries_before, "Band-family crossing reloaded/changed the psychological pool.")
	_assert(game.physiological_dialogue_controller.entries == physiological_entries_before, "Band-family crossing reloaded/changed the physiological pool.")
	_assert(_capture_continuous_state(game, spots_before) == preserved_before, "Band-family progression reset continuous history/dialogue/timers/notes/mode/BGM/expression state.")

	var merged_ids := _candidate_ids(game.psychological_dialogue_controller._get_matching_entries(60.0, 60.0))
	_assert(_contains_prefix(merged_ids, "phase1_") and _contains_prefix(merged_ids, "phase2_"), "Former Phase 1 and Phase 2 dialogue are not available in the same run: %s" % str(merged_ids))
	game.phase_transition_overlay = null
	var endings: Array[String] = []
	game.ending_requested.connect(func(ending_type: String) -> void: endings.append(ending_type))
	game.arousal_model.physical = float(game.active_phase_config.success_condition.get("physical_value", 100.0))
	game.arousal_model.emotional = float(game.active_phase_config.success_condition.get("emotional_value", 70.0))
	game._check_ending()
	_assert(endings == [CONFIG.SUCCESS_ENDING], "Deterministic continuous flow did not finish at final success.")
	await _free_game(game)


func _test_failure_routes_and_peak_depletion() -> void:
	await _assert_failure_route(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.0, 50.0, 50.0, false)
	await _assert_failure_route(CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 100.0, 10.0, 0.0, false)
	await _assert_failure_route(CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, 10.0, 100.0, 0.0, false)
	await _assert_runtime_decay_depletion()
	await _assert_runtime_penalty_depletion()
	var game = await _create_game()
	var endings: Array[String] = []
	game.ending_requested.connect(func(ending_type: String) -> void: endings.append(ending_type))
	game.phase_transition_overlay = null
	game.force_ending(CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING)
	_assert(endings == [CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING], "Safe-word forced failure route changed.")
	await _free_game(game)


func _assert_runtime_decay_depletion() -> void:
	var game = await _create_game()
	var endings: Array[String] = []
	game.ending_requested.connect(func(result: String) -> void: endings.append(result))
	game.phase_transition_overlay = null
	game.arousal_model.physical = 0.5
	game.arousal_model.emotional = 50.0
	game.arousal_model.peak = 50.0
	game.arousal_model.peak_has_activated = true
	game.arousal_model.physical_activity_grace_remaining = 0.0
	game._process(1.0)
	_assert(game.arousal_model.physical == 0.0, "Runtime decay setup did not reach physiological zero.")
	_assert(endings == [CONFIG.PEAK_DEPLETION_FAILURE_ENDING], "Runtime decay did not route physiological depletion: %s" % str(endings))
	await _free_game(game)


func _assert_runtime_penalty_depletion() -> void:
	var game = await _create_game()
	var endings: Array[String] = []
	game.ending_requested.connect(func(result: String) -> void: endings.append(result))
	game.phase_transition_overlay = null
	game.arousal_model.physical = 5.0
	game.arousal_model.emotional = 50.0
	game.arousal_model.peak = 50.0
	game.arousal_model.peak_has_activated = true
	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	game.spot_manager.force_spawn_click_note()
	game.force_expire_spot()
	game._process(0.0)
	_assert(game.arousal_model.physical == 0.0, "Physiological expiry penalty setup did not reach zero.")
	_assert(endings == [CONFIG.PEAK_DEPLETION_FAILURE_ENDING], "Physiological expiry penalty did not route depletion: %s" % str(endings))
	await _free_game(game)


func _test_physiological_combo_lifecycle() -> void:
	var game = await _create_game()
	_assert(game.current_combo == 0 and game.max_combo == 0, "A new run did not initialize both combo counters to zero.")
	game.set_interaction_mode(PHYSIOLOGICAL_MODE)

	game.spot_manager.force_spawn_click_note()
	game.spot_manager.force_complete_spot()
	_assert(game.current_combo == 1 and game.max_combo == 1, "First Click completion did not establish combo 1.")
	game.spot_manager.force_spawn_spot()
	game.spot_manager.force_complete_spot()
	_assert(game.current_combo == 2 and game.max_combo == 2, "Second whole-note completion did not establish combo 2.")
	game.spot_manager.force_spawn_rub_note()
	game.spot_manager.force_complete_spot()
	_assert(game.current_combo == 3 and game.max_combo == 3, "Click, Slide, and Rub did not share one combo sequence.")

	game.set_interaction_mode(PSYCHOLOGICAL_MODE)
	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	_assert(game.current_combo == 3 and game.max_combo == 3, "Mode switching changed combo state.")
	game.arousal_model.physical = _score_inside_band(3)
	game._sync_physiological_visual_band()
	game.arousal_model.physical = _score_inside_band(2)
	game._sync_physiological_visual_band()
	_assert(game.current_combo == 3 and game.max_combo == 3, "Visual-band or presentation-family switching changed combo state.")

	game.set_interaction_mode(PSYCHOLOGICAL_MODE)
	game.psychological_dialogue_controller.current_entry = {
		"choice": [{"id": "good", "effect": "positive"}],
		"response": {"good": ["combo-neutral good reply"]},
	}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game._on_choice_selected("good", "combo-neutral good choice")
	_assert(game.current_combo == 3 and game.max_combo == 3, "A good dialogue choice changed combo state.")
	game.psychological_dialogue_controller.current_entry = {
		"choice": [{"id": "bad", "effect": "negative"}],
		"response": {"bad": ["combo-neutral bad reply"]},
	}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game._on_choice_selected("bad", "combo-neutral bad choice")
	_assert(game.current_combo == 3 and game.max_combo == 3, "A bad dialogue choice changed combo state.")

	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	game.spot_manager.force_spawn_spot()
	var partial_slide := game.spot_manager._active_spots.back() as SlideNote
	var required_count := maxi(partial_slide.checkpoints.size() - 1, 1)
	var completed_count := clampi(ceili(float(required_count) * 0.5), 1, required_count - 1)
	partial_slide._armed = true
	partial_slide._next_checkpoint_index = completed_count + 1
	var partial_ratio := partial_slide.get_progress_ratio()
	var physical_before_partial_expiry: float = game.arousal_model.physical
	game.spot_manager.force_expire_spot()
	_assert(partial_ratio >= 0.5 and partial_ratio < 1.0, "Zero-penalty partial-expiry setup did not produce unresolved progress at or above 50%.")
	_assert(is_equal_approx(game.arousal_model.physical, physical_before_partial_expiry), "Zero-penalty partial expiry changed physiological scoring.")
	_assert(game.current_combo == 0 and game.max_combo == 3, "Zero-penalty partial expiry did not break only the current combo.")

	game.spot_manager.force_spawn_click_note()
	game.spot_manager.force_spawn_click_note()
	game.spot_manager.force_spawn_click_note()
	var ordered_notes: Array = game.spot_manager._active_spots.duplicate()
	_assert(ordered_notes.size() == 3, "Multiple-active-note combo test could not create three notes.")
	if ordered_notes.size() == 3:
		(ordered_notes[0] as InteractionNote).force_complete()
		_assert(game.current_combo == 1, "First same-frame ordered outcome did not produce combo 1.")
		(ordered_notes[1] as InteractionNote).force_complete()
		_assert(game.current_combo == 2, "Second same-frame ordered outcome did not produce combo 2.")
		(ordered_notes[2] as InteractionNote).force_expire()
		_assert(game.current_combo == 0 and game.max_combo == 3, "Later same-frame expiry did not break combo in normal signal order.")

	for expected_combo in range(1, 5):
		game.spot_manager.force_spawn_click_note()
		game.spot_manager.force_complete_spot()
		_assert(game.current_combo == expected_combo, "Post-break success did not continue from combo %d." % expected_combo)
		_assert(game.max_combo == maxi(3, expected_combo), "max_combo changed without a new record at combo %d." % expected_combo)

	game.spot_manager.force_spawn_click_note()
	game.spot_manager.force_expire_spot()
	_assert(game.current_combo == 0 and game.max_combo == 4, "A genuine miss did not preserve the existing max combo.")
	game.spot_manager.force_spawn_click_note()
	game.spot_manager.force_complete_spot()
	game.spot_manager.force_spawn_rub_note()
	var combo_before_ending: int = game.current_combo
	var max_combo_before_ending: int = game.max_combo
	game.force_ending(CONFIG.SUCCESS_ENDING)
	_assert(game.current_combo == combo_before_ending and game.max_combo == max_combo_before_ending, "Ending teardown fabricated an outcome or reset combo state.")

	game.reset_run()
	_assert(game.current_combo == 0 and game.max_combo == 0, "Genuine new-run reset did not clear both combo counters.")
	await _free_game(game)


func _assert_failure_route(ending_type: String, physical: float, emotional: float, peak: float, activated: bool) -> void:
	var game = await _create_game()
	var endings: Array[String] = []
	game.ending_requested.connect(func(result: String) -> void: endings.append(result))
	game.phase_transition_overlay = null
	game.arousal_model.physical = physical
	game.arousal_model.emotional = emotional
	game.arousal_model.peak = peak
	game.arousal_model.peak_has_activated = activated
	game._check_ending()
	_assert(endings == [ending_type], "Failure route %s changed: %s" % [ending_type, str(endings)])
	await _free_game(game)


func _test_explicit_new_run_reset() -> void:
	var game = await _create_game()
	game.arousal_model.physical = 90.0
	game.arousal_model.emotional = 80.0
	game.arousal_model.peak = 70.0
	game.arousal_model.peak_has_activated = true
	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	game.dialogue_panel.append_history("must be cleared", "companion")
	game.request_character_expression(COMPATIBILITY_SOURCE, PROFILE_SCRIPT.ExpressionState.NEGATIVE)
	game.force_spawn_spot()
	game.reset_run()
	_assert([game.arousal_model.physical, game.arousal_model.emotional, game.arousal_model.peak] == [20.0, 20.0, 0.0], "Explicit new run did not restore the Phase 1 starting scores.")
	_assert(not game.arousal_model.peak_has_activated, "Explicit new run retained peak activation.")
	_assert(game.current_visual_band == 1 and game.current_character_presentation_family == 0, "Explicit new run did not derive early presentation from starting physical.")
	_assert(game.interaction_mode == PSYCHOLOGICAL_MODE, "Explicit new run did not restore psychological interaction mode.")
	_assert(not game.get_character_expression_request_state().requests.has(COMPATIBILITY_SOURCE), "Explicit new run retained expression requests.")
	_assert(not _history_contains(game.dialogue_panel.get_dialogue_history(), "must be cleared"), "Explicit new run retained prior dialogue history.")
	_assert(game.spot_manager._active_spots.is_empty(), "Explicit new run retained active interaction notes.")
	await _free_game(game)


func _test_actual_ending_fade_remains() -> void:
	var game = await _create_game()
	_assert(not game.phase_transition_overlay.visible, "Ending overlay unexpectedly started visible.")
	game.force_ending(CONFIG.SUCCESS_ENDING)
	_assert(game.phase_transition_overlay.visible, "Actual ending did not start its fade overlay.")
	_assert(game.phase_transition_overlay.color.r == 0.0 and game.phase_transition_overlay.color.g == 0.0 and game.phase_transition_overlay.color.b == 0.0, "Actual ending fade is no longer black.")
	_assert(game.ending_transition_started, "Actual ending fade did not retain canonical ending state.")
	await _free_game(game)


func _create_game():
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	return game


func _free_game(game) -> void:
	game.queue_free()
	await process_frame


func _capture_continuous_state(game, spots: Array) -> Dictionary:
	var spot_state: Array[Dictionary] = []
	for spot in spots:
		spot_state.append({
			"id": spot.get_instance_id(),
			"position": spot.global_position,
			"progress": spot.get_progress_ratio(),
			"lifetime_paused": spot.lifetime_timer.paused,
			"lifetime_stopped": spot.lifetime_timer.is_stopped(),
		})
	return {
		"emotional": game.arousal_model.emotional,
		"peak": game.arousal_model.peak,
		"peak_activated": game.arousal_model.peak_has_activated,
		"mode": game.interaction_mode,
		"history": game.dialogue_panel.get_dialogue_history(),
		"psychological_line": game.psychological_dialogue_controller.current_line,
		"psychological_entry": game.psychological_dialogue_controller.current_entry.duplicate(true),
		"psychological_prompt": game.psychological_dialogue_controller.current_prompt.duplicate(true),
		"pending_choice": game.psychological_dialogue_controller.choice_prompt_pending,
		"physiological_line": game.physiological_dialogue_controller.current_line,
		"physiological_entry": game.physiological_dialogue_controller.current_entry.duplicate(true),
		"physiological_prompt": game.physiological_dialogue_controller.current_prompt.duplicate(true),
		"psychological_timer": _timer_state(game.psychological_dialogue_timer),
		"physiological_timer": _timer_state(game.physiological_dialogue_timer),
		"choice_timer": _timer_state(game.choice_timeout_timer),
		"spot_spawn_timer": _timer_state(game.spot_spawn_timer),
		"compatibility_expression": game.get_character_expression_request_state().requests.get(COMPATIBILITY_SOURCE, {}).duplicate(true),
		"spot_active": game.spot_manager._active,
		"spot_suspended": game.spot_manager._suspended,
		"spots": spot_state,
		"bgm_switched": game.has_switched_to_game_bgm,
		"bgm_key": game.last_requested_bgm_key,
	}


func _timer_state(timer: Timer) -> Dictionary:
	return {
		"paused": timer.paused,
		"stopped": timer.is_stopped(),
	}


func _score_inside_band(band: int) -> float:
	return (float(band) + 0.5) * 100.0 / 6.0


func _candidate_ids(candidates: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for candidate in candidates:
		ids.append(String(candidate.get("id", "")))
	ids.sort()
	return ids


func _contains_prefix(values: Array[String], prefix: String) -> bool:
	for value in values:
		if value.begins_with(prefix):
			return true
	return false


func _history_contains(history: Array[Dictionary], text_value: String) -> bool:
	for item in history:
		if item.get("text", "") == text_value:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

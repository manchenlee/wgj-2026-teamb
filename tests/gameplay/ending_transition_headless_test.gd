extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const GAME_SCRIPT := preload("res://scripts/core/game_session_controller.gd")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for mode in [GAME_SCRIPT.InteractionMode.PSYCHOLOGICAL, GAME_SCRIPT.InteractionMode.PHYSIOLOGICAL]:
		await _check_ending(mode, CONFIG.SUCCESS_ENDING, 100.0, 95.0)
		await _check_ending(mode, CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 100.0, 50.0)
		await _check_ending(mode, CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, 50.0, 100.0)
		await _check_ending(mode, CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.0, 0.0)
		await _check_ending(mode, CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING, -1.0, -1.0)
	await _check_choice_trigger()
	await _check_safe_word_ending_presentation()
	if _failures.is_empty():
		print("Ending transition headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _check_ending(mode: int, ending_type: String, physical: float, emotional: float) -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_interaction_mode(mode)
	if physical >= 0.0:
		game.arousal_model.physical = physical
		game.arousal_model.emotional = emotional
		game._sync_physiological_visual_band(false)
	if mode == GAME_SCRIPT.InteractionMode.PSYCHOLOGICAL:
		game.dialogue_panel.append_history("A currently streaming dialogue line that needs to finish.", "companion")
	var endings: Array[String] = []
	game.ending_requested.connect(func(result: String) -> void: endings.append(result))
	if physical >= 0.0:
		game._check_ending()
	else:
		game.force_ending(ending_type)
	var label := "%s in mode %d" % [ending_type, mode]
	_assert(game.pending_ending_type == ending_type, "%s did not lock its result." % label)
	_assert(not game.run_active and game.ending_transition_started, "%s kept gameplay running." % label)
	_assert(game.spot_spawn_timer.is_stopped() and game.choice_timeout_timer.is_stopped(), "%s left timers running." % label)
	var physical_at_lock: float = game.arousal_model.physical
	game.force_ending(CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING)
	game._check_ending()
	game.apply_debug_values(17.0)
	game.toggle_interaction_mode()
	_assert(game.pending_ending_type == ending_type and game.arousal_model.physical == physical_at_lock,
		"%s allowed a duplicate trigger or score change." % label)
	var dialogue_ending: bool = ending_type != CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING \
			and not (ending_type == CONFIG.SUCCESS_ENDING and mode == GAME_SCRIPT.InteractionMode.PHYSIOLOGICAL)
	if dialogue_ending:
		await create_timer(0.9).timeout
		_assert(game.interaction_mode == GAME_SCRIPT.InteractionMode.PSYCHOLOGICAL,
			"%s did not reach psychological mode." % label)
		var history: Array = game.dialogue_panel.get_dialogue_history()
		var expected_line := "啊！……" if ending_type == CONFIG.SUCCESS_ENDING else "唔……"
		_assert(not history.is_empty() and history.back().get("line", "") == expected_line,
			"%s did not show its final dialogue." % label)
	else:
		await create_timer(0.5).timeout
		if ending_type == CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING:
			_assert(game.resolve_character_visual_state().get("base_state_key", "") == "negative",
				"%s did not switch to negative art." % label)
		elif ending_type == CONFIG.SUCCESS_ENDING:
			_assert(game.shooting_tail_active, "%s did not show shooting tail." % label)
	await create_timer(0.9).timeout
	_assert(game.phase_transition_overlay.visible, "%s did not fade." % label)
	var fade_color: Color = game.phase_transition_overlay.color
	var expected_white := ending_type == CONFIG.SUCCESS_ENDING
	_assert((fade_color.r > 0.9) == expected_white and (fade_color.g > 0.9) == expected_white,
		"%s faded to the wrong color." % label)
	await create_timer(0.7).timeout
	_assert(endings == [ending_type], "%s emitted duplicate or wrong ending: %s" % [label, str(endings)])
	game.queue_free()
	await process_frame

func _check_choice_trigger() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var endings: Array[String] = []
	game.ending_requested.connect(func(result: String) -> void: endings.append(result))
	game.psychological_dialogue_controller.current_entry = \
		game.psychological_dialogue_controller._select_entry(50.0, 50.0, true)
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game._on_choice_selected("option_1", "【繼續調教。】")
	_assert(game.pending_ending_type == CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING,
		"Psychological incorrect choice did not lock its ending.")
	_assert(game._has_failed_safe_word_choice, "Wrong safe-word choice was not recorded.")
	await create_timer(0.9).timeout
	var history: Array = game.dialogue_panel.get_dialogue_history()
	_assert(not history.is_empty() and history.back().get("line", "") == "唔……",
		"Wrong safe-word choice did not show its transition line.")
	await create_timer(1.4).timeout
	_assert(endings == [CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING],
		"Wrong safe-word choice did not enter ending five.")
	game.queue_free()
	await process_frame

func _check_safe_word_ending_presentation() -> void:
	var ending = ENDING_SCENE.instantiate()
	ending.safe_word = "測試詞"
	ending.set_result(CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING)
	root.add_child(ending)
	_assert(ending.chapter_number_label.text.contains("V"), "Safe-word ending did not show number five.")
	_assert(ending._background.texture.resource_path.ends_with("end01.png"),
		"Safe-word ending did not reuse ending one's image.")
	_assert(ending._novel_screen != null and ending._novel_screen._entries.size() == 9,
		"Safe-word ending did not load all workbook dialogue lines.")
	if ending._novel_screen != null and not ending._novel_screen._entries.is_empty():
		_assert(str(ending._novel_screen._entries[0].get("text", "")).contains("測試詞、測試詞"),
			"Safe-word ending did not insert the chosen safe word.")
	ending.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

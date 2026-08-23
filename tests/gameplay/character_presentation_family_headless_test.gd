extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const GAME_SESSION_CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")

const EARLY_FAMILY := 0
const LATE_FAMILY := 1
const PHYSIOLOGICAL_MODE := 1

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_band_family_mapping_and_rebuild_guard()
	await _test_live_family_crossing_preserves_gameplay_state()
	await _test_reset_and_legacy_phase_compatibility()
	if _failures.is_empty():
		print("Character presentation-family headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_band_family_mapping_and_rebuild_guard() -> void:
	for band in range(6):
		var expected_family := EARLY_FAMILY if band <= 2 else LATE_FAMILY
		_assert(
			GAME_SESSION_CONTROLLER_SCRIPT.visual_band_to_character_presentation_family(band) == expected_family,
			"Visual band %d resolved to the wrong character presentation family." % band
		)

	var controller = GAME_SESSION_CONTROLLER_SCRIPT.new()
	_assert(controller._sync_character_presentation_family_for_visual_band(0), "Initial early-family synchronization did not apply.")
	var early_profile = controller.active_character_profile
	_assert(early_profile.profile_id == "phase_1_profile", "Bands 0-2 did not select the existing Phase 1 profile.")
	_assert(not controller._sync_character_presentation_family_for_visual_band(1), "Band 0 to 1 unnecessarily rebuilt the early family.")
	_assert(controller.active_character_profile == early_profile, "Same-family movement replaced the early profile cache.")
	_assert(controller._sync_character_presentation_family_for_visual_band(3), "Band 2 to 3 did not apply the late family.")
	var late_profile = controller.active_character_profile
	_assert(late_profile.profile_id == "phase_2_profile", "Bands 3-5 did not select the existing Phase 2 profile.")
	_assert(not controller._sync_character_presentation_family_for_visual_band(4), "Band 3 to 4 unnecessarily rebuilt the late family.")
	_assert(controller.active_character_profile == late_profile, "Same-family movement replaced the late profile cache.")
	_assert(controller._sync_character_presentation_family_for_visual_band(2), "Band 3 to 2 did not restore the early family.")
	_assert(controller.active_character_profile == early_profile, "Downward switching did not reuse the cached early profile.")
	controller.free()


func _test_live_family_crossing_preserves_gameplay_state() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame

	_assert(game.current_visual_band == 2, "Initial physical score did not synchronize visual band 2.")
	_assert(game.current_character_presentation_family == EARLY_FAMILY, "Initialization did not silently select the early family.")
	_assert(game.active_character_profile.profile_id == "phase_1_profile", "Initialization selected the wrong profile.")

	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	game.force_spawn_spot()
	var active_spots: Array = game.spot_manager._active_spots.duplicate()
	_assert(not active_spots.is_empty(), "The preservation test could not create an active interaction note.")

	game.psychological_dialogue_controller.current_line = "preserved psychological line"
	game.psychological_dialogue_controller.current_entry = {"marker": "psychological"}
	game.psychological_dialogue_controller.current_prompt = {"text": "pending"}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game.physiological_dialogue_controller.current_line = "preserved physiological line"
	game.physiological_dialogue_controller.current_entry = {"marker": "physiological"}
	game.dialogue_panel.append_history("preserved history", "companion")
	game.choice_panel.show_choices([
		{"id": "good", "text": "left"},
		{"id": "bad", "text": "right"},
	])
	game.choice_timeout_timer.start(4.0)
	game.choice_timeout_timer.set_paused(true)

	game.arousal_model.physical = 50.0
	game.arousal_model.emotional = 61.0
	game.arousal_model.peak = 37.0
	game.arousal_model.peak_has_activated = true
	var state_before := _capture_gameplay_state(game)
	var note_state_before := _capture_note_state(active_spots)
	var timer_state_before := _capture_timer_state(game)
	var phase_index_before: int = game.active_phase_index
	var fade_visible_before: bool = game.phase_transition_overlay.visible
	var ending_count := {"value": 0}
	game.ending_requested.connect(func(_ending_type: String) -> void: ending_count.value += 1)

	game._sync_physiological_visual_band()

	_assert(game.current_visual_band == 3, "The upward crossing did not reach band 3.")
	_assert(game.current_character_presentation_family == LATE_FAMILY, "Band 3 did not select the late family.")
	_assert(game.active_character_profile.profile_id == "phase_2_profile", "Band 3 did not apply the existing Phase 2 profile.")
	_assert(_capture_gameplay_state(game) == state_before, "A presentation-family crossing mutated gameplay/dialogue/choice state.")
	_assert(_capture_note_state(active_spots) == note_state_before, "A presentation-family crossing moved, recreated, or reset an active note.")
	_assert(_capture_timer_state(game) == timer_state_before, "A presentation-family crossing changed runtime timer state.")
	_assert(game.active_phase_index == phase_index_before, "A presentation-family crossing changed the gameplay phase.")
	_assert(game.phase_transition_overlay.visible == fade_visible_before, "A presentation-family crossing started a phase fade.")
	_assert(not game.phase_transition_in_progress, "A presentation-family crossing started the legacy phase transition.")
	_assert(not game.ending_transition_started and ending_count.value == 0, "A presentation-family crossing evaluated or routed an ending.")

	game.arousal_model.physical = 49.0
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 2, "The downward crossing did not return to band 2.")
	_assert(game.current_character_presentation_family == EARLY_FAMILY, "Band 2 did not restore the early family.")
	_assert(game.active_character_profile.profile_id == "phase_1_profile", "Downward crossing did not restore the Phase 1 profile.")

	game.queue_free()
	await process_frame


func _test_reset_and_legacy_phase_compatibility() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.arousal_model.physical = 75.0
	game._sync_physiological_visual_band(false)
	_assert(game.current_character_presentation_family == LATE_FAMILY, "Reset setup did not select the late family.")
	game.reset_run()
	_assert(game.current_visual_band == 2, "Reset did not derive band 2 from starting physical 40.")
	_assert(game.current_character_presentation_family == EARLY_FAMILY, "Reset did not re-synchronize the early family from physical score.")

	game.start_direct_in_phase_2()
	_assert(game.active_phase_index == 1, "Legacy direct Phase 2 start no longer selected gameplay Phase 2.")
	_assert(game.current_visual_band == 2, "Legacy Phase 2 reset did not retain the configured physical-score band.")
	_assert(game.current_character_presentation_family == EARLY_FAMILY, "Gameplay Phase 2 incorrectly overrode the band-derived presentation family.")
	_assert(game.active_character_profile.profile_id == "phase_1_profile", "Gameplay phase still owns the character profile after reset.")
	game.queue_free()
	await process_frame


func _capture_gameplay_state(game) -> Dictionary:
	return {
		"physical": game.arousal_model.physical,
		"emotional": game.arousal_model.emotional,
		"peak": game.arousal_model.peak,
		"peak_has_activated": game.arousal_model.peak_has_activated,
		"interaction_mode": game.interaction_mode,
		"psychological_line": game.psychological_dialogue_controller.current_line,
		"psychological_entry": game.psychological_dialogue_controller.current_entry.duplicate(true),
		"psychological_prompt": game.psychological_dialogue_controller.current_prompt.duplicate(true),
		"pending_choice": game.psychological_dialogue_controller.choice_prompt_pending,
		"physiological_line": game.physiological_dialogue_controller.current_line,
		"physiological_entry": game.physiological_dialogue_controller.current_entry.duplicate(true),
		"history": game.dialogue_panel.get_dialogue_history(),
		"choice_data": game.choice_panel._choice_data.duplicate(true),
		"spot_active": game.spot_manager._active,
		"spot_suspended": game.spot_manager._suspended,
		"bgm_switched": game.has_switched_to_game_bgm,
		"bgm_key": game.last_requested_bgm_key,
	}


func _capture_note_state(spots: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spot in spots:
		if not is_instance_valid(spot):
			result.append({"invalid": true})
			continue
		result.append({
			"instance_id": spot.get_instance_id(),
			"position": spot.position,
			"global_position": spot.global_position,
			"progress": spot.get_progress_ratio(),
			"lifetime_paused": spot.lifetime_timer.paused,
			"lifetime_stopped": spot.lifetime_timer.is_stopped(),
			"lifetime_left": spot.lifetime_timer.time_left,
		})
	return result


func _capture_timer_state(game) -> Dictionary:
	return {
		"psychological": _timer_state(game.psychological_dialogue_timer),
		"physiological": _timer_state(game.physiological_dialogue_timer),
		"choice": _timer_state(game.choice_timeout_timer),
		"spots": _timer_state(game.spot_spawn_timer),
	}


func _timer_state(timer: Timer) -> Dictionary:
	return {
		"paused": timer.paused,
		"stopped": timer.is_stopped(),
		"time_left": timer.time_left,
	}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const STATUS_HUD_SCENE := preload("res://scenes/components/StatusHUD.tscn")

const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_shared_mode_toggle_boundary()
	await _test_numeric_hud_and_legacy_visibility()
	await _test_combo_hud_presentation()
	await _test_warning_presentation_apis()
	if _failures.is_empty():
		print("Mode toggle and temporary HUD headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_shared_mode_toggle_boundary() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame

	var mode_toggle: InteractionModeToggle = game.get_node("%InteractionModeToggle")
	var choice_panel: ChoicePanel = game.get_node("%ChoicePanel")
	var legacy_rings: Control = game.get_node("CharacterAlignmentRoot/MainCharacterArea/CentralArousalVisualization")
	var counts := {"transitions": 0}
	game.interaction_mode_changed.connect(func(_mode: int) -> void: counts.transitions += 1)

	_assert(game.interaction_mode == PSYCHOLOGICAL_MODE, "Game did not start in psychological mode.")
	_assert(mode_toggle.get_interaction_mode() == PSYCHOLOGICAL_MODE, "Mode UI did not synchronize its initial authoritative mode.")
	_assert(mode_toggle.get_node("ModeLabel").text == "對話", "Psychological mode label is incorrect.")
	_assert(choice_panel.visible, "Psychological mode did not leave the choice layer visible.")
	_assert(game.spot_manager._suspended, "Psychological mode did not suspend physiological interaction.")
	_assert(not legacy_rings.visible, "Legacy circular arousal visualization is not hidden.")
	game.set_legacy_arousal_visualization_visible(true)
	_assert(legacy_rings.visible, "Legacy circular arousal visualization cannot be re-enabled.")
	game.set_legacy_arousal_visualization_visible(false)

	var q_event := InputEventAction.new()
	q_event.action = &"toggle_interaction_mode"
	q_event.pressed = true
	game._unhandled_input(q_event)
	_assert(game.interaction_mode == PHYSIOLOGICAL_MODE, "Q did not switch to physiological mode.")
	_assert(mode_toggle.get_interaction_mode() == PHYSIOLOGICAL_MODE, "Mode UI did not synchronize after Q input.")
	_assert(mode_toggle.get_node("ModeLabel").text == "調音", "Physiological mode label is incorrect.")
	_assert(not choice_panel.visible, "Physiological mode did not hide the choice layer.")
	_assert(not game.spot_manager._suspended, "Physiological mode did not resume physical interaction.")
	_assert(counts.transitions == 1, "Q emitted an unexpected number of authoritative mode changes.")

	mode_toggle.get_node("ToggleButton").emit_signal("pressed")
	_assert(game.interaction_mode == PSYCHOLOGICAL_MODE, "Mouse-button request did not switch to psychological mode.")
	_assert(mode_toggle.get_interaction_mode() == PSYCHOLOGICAL_MODE, "Mode UI did not synchronize after its click request.")
	_assert(mode_toggle.get_node("ModeLabel").text == "對話", "Mode label did not return to psychological state.")
	_assert(choice_panel.visible, "Mouse-button switch did not restore psychological choice behavior.")
	_assert(game.spot_manager._suspended, "Mouse-button switch did not suspend physiological interaction.")
	_assert(counts.transitions == 2, "Mouse-button request emitted an unexpected number of authoritative mode changes.")

	for switch_index in range(10):
		if switch_index % 2 == 0:
			game._unhandled_input(q_event)
		else:
			mode_toggle.get_node("ToggleButton").emit_signal("pressed")
	_assert(counts.transitions == 12, "Rapid Q/click switching duplicated or dropped authoritative transitions.")
	_assert(game.interaction_mode == PSYCHOLOGICAL_MODE, "Rapid switching ended in the wrong authoritative mode.")
	_assert(mode_toggle.get_interaction_mode() == game.interaction_mode, "Rapid switching desynchronized the mode UI.")

	game.queue_free()
	await process_frame


func _test_numeric_hud_and_legacy_visibility() -> void:
	var hud: StatusHUD = STATUS_HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame

	var physical_label: Label = hud.get_node("NumericScores/PhysicalScore/Value")
	var emotional_label: Label = hud.get_node("NumericScores/EmotionalScore/Value")
	var legacy_meter: Control = hud.get_node("ArousalMeter")
	var affection_track: ColorRect = hud.get_node("ReferenceMeter/Track")
	var affection_fill: ColorRect = hud.get_node("ReferenceMeter/Track/Fill")
	var affection_label: Label = hud.get_node("ReferenceMeter/PeakValueLabel")

	hud.update_values(0.0, 100.0, 0.0)
	_assert(physical_label.text == "0", "Physical HUD did not render zero.")
	_assert(emotional_label.text == "100", "Emotional HUD did not render 100 independently.")
	_assert(affection_label.text == "0/100", "Affection HUD did not render zero.")
	_assert(is_zero_approx(affection_fill.size.x), "Affection bar was not empty at zero.")

	hud.update_values(42.4, 67.6, 50.0)
	_assert(physical_label.text == "42", "Physical HUD middle-value rounding is incorrect.")
	_assert(emotional_label.text == "68", "Emotional HUD middle-value rounding is incorrect.")
	_assert(affection_label.text == "50/100", "Affection HUD did not render its midpoint.")
	_assert(
		is_equal_approx(affection_fill.size.x, affection_track.size.x * 0.5),
		"Affection bar did not fill to its midpoint."
	)
	_assert(affection_fill.color == Color(1, 0.76, 0.24, 1), "Affection bar is not yellow.")

	hud.update_values(100.0, 0.0, 100.0)
	_assert(physical_label.text == "100", "Physical HUD did not render 100.")
	_assert(emotional_label.text == "0", "Emotional HUD did not render zero independently.")
	_assert(affection_label.text == "100/100", "Affection HUD did not render its maximum.")
	_assert(
		is_equal_approx(affection_fill.size.x, affection_track.size.x),
		"Affection bar did not fill the complete track at 100."
	)
	_assert(not legacy_meter.visible, "Legacy StatusHUD meter is not hidden by default.")
	_assert(legacy_meter.has_node("HeartIcon"), "Legacy heart meter node was removed.")
	_assert(legacy_meter.has_node("ArousalFillBar"), "Legacy fill calculation node was removed.")

	hud.set_legacy_meter_visible(true)
	_assert(legacy_meter.visible, "Legacy StatusHUD meter cannot be re-enabled through its presentation API.")
	hud.set_legacy_meter_visible(false)
	_assert(not legacy_meter.visible, "Legacy StatusHUD meter could not be hidden again.")

	hud.queue_free()
	await process_frame


func _test_combo_hud_presentation() -> void:
	var hud: StatusHUD = STATUS_HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame
	var combo_label: Label = hud.get_node("ComboLabel")
	var physical_label: Label = hud.get_node("NumericScores/PhysicalScore/Value")
	var emotional_label: Label = hud.get_node("NumericScores/EmotionalScore/Value")
	var legacy_meter: Control = hud.get_node("ArousalMeter")
	hud.update_values(42.4, 67.6, 25.0)

	_assert(not combo_label.visible, "Combo HUD was visible at zero.")
	hud.update_combo(1, true)
	_assert(not combo_label.visible, "Combo HUD was visible at one.")
	_assert(hud._combo_pulse_tween == null, "A hidden combo started a pulse tween.")
	hud.update_combo(2)
	_assert(combo_label.visible and combo_label.text == "2 COMBO", "Combo HUD did not show the threshold value.")
	hud.update_combo(12)
	_assert(combo_label.text == "12 COMBO", "Combo HUD did not render a higher value.")

	hud.update_combo(3, true)
	var first_pulse: Tween = hud._combo_pulse_tween
	_assert(first_pulse != null and first_pulse.is_valid(), "Visible combo increment did not request a pulse tween.")
	hud.update_combo(4, true)
	var replacement_pulse: Tween = hud._combo_pulse_tween
	_assert(replacement_pulse != null and replacement_pulse != first_pulse, "Rapid combo update did not replace the prior pulse tween.")
	_assert(not first_pulse.is_valid(), "Replaced combo pulse tween remained active.")
	_assert(combo_label.scale == Vector2.ONE, "Rapid combo updates accumulated label scale.")

	hud.set_score_warnings(true, false)
	hud.update_combo(0)
	_assert(not combo_label.visible, "Combo break did not hide the label.")
	_assert(combo_label.scale == Vector2.ONE and hud._combo_pulse_tween == null, "Combo break did not restore neutral pulse state.")
	_assert(hud.is_physical_low_warning_active() and not hud.is_emotional_low_warning_active(), "Combo presentation interfered with score-warning state.")
	_assert(physical_label.text == "42" and emotional_label.text == "68", "Combo presentation changed numeric score labels.")
	_assert(not legacy_meter.visible, "Combo presentation changed legacy-meter visibility.")

	hud.queue_free()
	await process_frame


func _test_warning_presentation_apis() -> void:
	var hud: StatusHUD = STATUS_HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame
	var physical_label: Label = hud.get_node("NumericScores/PhysicalScore/Value")
	var emotional_label: Label = hud.get_node("NumericScores/EmotionalScore/Value")

	hud.set_score_warnings(true, false)
	_assert(hud.is_physical_low_warning_active(), "Physical numeric warning API did not activate.")
	_assert(not hud.is_emotional_low_warning_active(), "Physical warning incorrectly activated emotional presentation.")
	_assert(physical_label.get_theme_constant("outline_size") == 5, "Physical warning did not emphasize its numeric value.")
	_assert(emotional_label.get_theme_constant("outline_size") != 5, "Physical warning emphasized the emotional numeric value.")

	hud.set_score_warnings(false, true)
	_assert(not hud.is_physical_low_warning_active(), "Physical numeric warning API did not clear.")
	_assert(hud.is_emotional_low_warning_active(), "Emotional numeric warning API did not activate independently.")
	_assert(physical_label.modulate == Color.WHITE, "Cleared physical warning left presentation residue.")
	_assert(emotional_label.get_theme_constant("outline_size") == 5, "Emotional warning did not emphasize its numeric value.")
	hud.set_score_warnings(false, false)
	_assert(not hud.is_processing(), "HUD warning animation kept processing after both warnings cleared.")
	hud.queue_free()
	await process_frame

	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var mode_toggle: InteractionModeToggle = game.get_node("%InteractionModeToggle")
	var mode_label: Label = mode_toggle.get_node("ModeLabel")
	var talk_button: TextureButton = mode_toggle.get_node("TalkButton")
	var music_button: TextureButton = mode_toggle.get_node("MusicButton")
	var affection_track: ColorRect = game.get_node("%StatusHUD/ReferenceMeter/Track")
	var affection_fill: ColorRect = game.get_node("%StatusHUD/ReferenceMeter/Track/Fill")
	var affection_label: Label = game.get_node("%StatusHUD/ReferenceMeter/PeakValueLabel")
	var original_physical: float = game.arousal_model.physical
	var original_emotional: float = game.arousal_model.emotional
	var psychological_label_text: String = mode_label.text
	var transition_counts := {"mode": 0}
	game.interaction_mode_changed.connect(func(_mode: int) -> void: transition_counts.mode += 1)

	mode_toggle.set_imbalance_warning(true, PHYSIOLOGICAL_MODE)
	await process_frame
	_assert(mode_toggle.is_imbalance_warning_active(), "Mode-toggle warning API did not activate.")
	_assert(mode_toggle.get_lower_score_mode() == PHYSIOLOGICAL_MODE, "Mode-toggle warning did not store the lower side.")
	_assert(mode_label.text == psychological_label_text, "Warning changed the authoritative psychological mode label.")
	mode_toggle._warning_pulse_time = 0.0
	mode_toggle._process(0.0)
	var warning_alpha_max: float = music_button.modulate.a
	var warning_scale_max: float = music_button.scale.x
	mode_toggle._process(PI / InteractionModeToggle.WARNING_PULSE_SPEED)
	_assert(warning_alpha_max - music_button.modulate.a >= 0.7, "Mode-toggle warning alpha pulse is not visually distinct enough.")
	_assert(warning_scale_max - music_button.scale.x >= 0.1, "Mode-toggle warning scale pulse is not visually distinct enough.")
	mode_toggle.get_node("ToggleButton").emit_signal("pressed")
	_assert(transition_counts.mode == 1, "Clicking a glowing toggle did not perform exactly one mode change.")
	_assert(game.interaction_mode == PHYSIOLOGICAL_MODE, "Clicking a glowing toggle changed to the wrong mode.")
	_assert(mode_label.text != psychological_label_text, "Glowing toggle did not update to the authoritative physiological label.")
	_assert(mode_toggle.is_imbalance_warning_active(), "Mode switching cleared an unchanged warning state.")

	var q_event := InputEventAction.new()
	q_event.action = &"toggle_interaction_mode"
	q_event.pressed = true
	game._unhandled_input(q_event)
	_assert(transition_counts.mode == 2, "Q on a glowing toggle did not perform exactly one mode change.")
	_assert(mode_toggle.is_imbalance_warning_active(), "Q mode switching cleared an unchanged warning state.")
	_assert(game.arousal_model.physical == original_physical, "Warning animation or mode switching changed physical score.")
	_assert(game.arousal_model.emotional == original_emotional, "Warning animation or mode switching changed emotional score.")

	game.arousal_model.physical = 60.0
	game.arousal_model.emotional = 20.0
	game._update_presentation()
	_assert(affection_label.text == "60/100", "Live affection HUD did not display the physical score.")
	_assert(
		is_equal_approx(affection_fill.size.x, affection_track.size.x * 0.6),
		"Live affection bar did not react to physical-score changes."
	)
	game.arousal_model.emotional = 80.0
	game._update_presentation()
	_assert(affection_label.text == "60/100", "Emotional score incorrectly changed affection HUD.")

	mode_toggle.set_imbalance_warning(false, -1)
	_assert(not mode_toggle.is_imbalance_warning_active(), "Mode-toggle warning API did not deactivate.")
	_assert(mode_toggle.get_lower_score_mode() == -1, "Deactivated toggle warning retained its lower side.")
	_assert(not mode_toggle.is_processing(), "Mode-toggle warning animation kept processing after clear.")
	_assert(talk_button.modulate == Color.WHITE and music_button.modulate == Color.WHITE, "Cleared toggle warning retained alpha modulation.")
	_assert(talk_button.scale == Vector2.ONE and music_button.scale == Vector2.ONE, "Cleared toggle warning retained pulse scale.")
	game.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

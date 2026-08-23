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

	hud.update_values(0.0, 100.0, 50.0)
	_assert(physical_label.text == "0", "Physical HUD did not render zero.")
	_assert(emotional_label.text == "100", "Emotional HUD did not render 100 independently.")

	hud.update_values(42.4, 67.6, 25.0)
	_assert(physical_label.text == "42", "Physical HUD middle-value rounding is incorrect.")
	_assert(emotional_label.text == "68", "Emotional HUD middle-value rounding is incorrect.")

	hud.update_values(100.0, 0.0, 75.0)
	_assert(physical_label.text == "100", "Physical HUD did not render 100.")
	_assert(emotional_label.text == "0", "Emotional HUD did not render zero independently.")
	_assert(not legacy_meter.visible, "Legacy StatusHUD meter is not hidden by default.")
	_assert(legacy_meter.has_node("HeartIcon"), "Legacy heart meter node was removed.")
	_assert(legacy_meter.has_node("ArousalFillBar"), "Legacy fill calculation node was removed.")

	hud.set_legacy_meter_visible(true)
	_assert(legacy_meter.visible, "Legacy StatusHUD meter cannot be re-enabled through its presentation API.")
	hud.set_legacy_meter_visible(false)
	_assert(not legacy_meter.visible, "Legacy StatusHUD meter could not be hidden again.")

	hud.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

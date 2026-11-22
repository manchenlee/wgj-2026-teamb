extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame

	var mode_toggle: InteractionModeToggle = game.get_node("%InteractionModeToggle")
	var talk_button: TextureButton = mode_toggle.talk_button
	var music_button: TextureButton = mode_toggle.music_button
	var shortcut_group: Control = mode_toggle.get_node("ShortcutGroup")
	var hint_position := shortcut_group.position
	var q_event := InputEventAction.new()
	q_event.action = &"toggle_interaction_mode"
	q_event.pressed = true

	_check(game.interaction_mode == PHYSIOLOGICAL_MODE, "Game did not begin in physiological mode.")
	_check(talk_button.visible and not music_button.visible, "Physiological mode must show the psychological switch UI.")
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_UNCLICKED, "Psychological switch must use its normal art without a warning.")
	_check(music_button.position == talk_button.position, "Mode UI buttons must share one slot.")
	_check(shortcut_group.visible and hint_position.y >= talk_button.size.y, "Q hint must remain below the mode UI.")
	mode_toggle.set_imbalance_warning(true, PSYCHOLOGICAL_MODE)
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_WARNING and mode_toggle.is_processing(), "Lower psychological side must show a blinking warning.")
	mode_toggle.set_imbalance_warning(true, PHYSIOLOGICAL_MODE)
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_UNCLICKED and not mode_toggle.is_processing(), "Warning for the active mode must not affect the opposite icon.")

	game._unhandled_input(q_event)
	_check(game.interaction_mode == PSYCHOLOGICAL_MODE, "Q did not switch to dialogue mode.")
	_check(music_button.visible and not talk_button.visible, "Psychological mode must show the physiological switch UI.")
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_WARNING and mode_toggle.is_processing(), "Lower physiological side must show a blinking warning after switching.")
	_check(shortcut_group.visible and shortcut_group.position == hint_position, "Q hint changed after Q input.")
	mode_toggle.set_imbalance_warning(false, -1)
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_UNCLICKED and not mode_toggle.is_processing(), "Clearing imbalance must restore the normal physiological art.")

	music_button.emit_signal("pressed")
	_check(game.interaction_mode == PHYSIOLOGICAL_MODE, "Clicking physiological UI did not switch to physiological mode.")
	_check(talk_button.visible and not music_button.visible, "Click did not restore the psychological switch UI.")
	_check(shortcut_group.visible and shortcut_group.position == hint_position, "Q hint changed after clicking.")

	talk_button.emit_signal("pressed")
	_check(game.interaction_mode == PSYCHOLOGICAL_MODE, "Clicking psychological UI did not switch to psychological mode.")
	_check(music_button.visible and not talk_button.visible, "Click did not restore the physiological switch UI.")

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Interaction mode toggle headless test passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

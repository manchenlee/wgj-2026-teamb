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
	_check(music_button.visible and not talk_button.visible, "Physiological mode must show only tuning UI.")
	_check(music_button.position == talk_button.position, "Mode UI buttons must share one slot.")
	_check(shortcut_group.visible and hint_position.y >= music_button.size.y, "Q hint must remain below the mode UI.")

	game._unhandled_input(q_event)
	_check(game.interaction_mode == PSYCHOLOGICAL_MODE, "Q did not switch to dialogue mode.")
	_check(talk_button.visible and not music_button.visible, "Psychological mode must show only dialogue UI.")
	_check(shortcut_group.visible and shortcut_group.position == hint_position, "Q hint changed after Q input.")

	talk_button.emit_signal("pressed")
	_check(game.interaction_mode == PHYSIOLOGICAL_MODE, "Clicking dialogue UI did not switch to tuning mode.")
	_check(music_button.visible and not talk_button.visible, "Click did not restore only tuning UI.")
	_check(shortcut_group.visible and shortcut_group.position == hint_position, "Q hint changed after clicking.")

	music_button.emit_signal("pressed")
	_check(game.interaction_mode == PSYCHOLOGICAL_MODE, "Clicking tuning UI did not switch to dialogue mode.")
	_check(talk_button.visible and not music_button.visible, "Click did not restore only dialogue UI.")

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

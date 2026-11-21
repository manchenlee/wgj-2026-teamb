extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var menu: PauseMenu = main.pause_menu
	_assert(not menu.visible, "Pause menu should start hidden.")
	main._show_game()
	await process_frame
	var first_game: Control = main.current_screen
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	_assert(menu.visible and paused, "Escape did not pause gameplay and show the menu.")
	_assert(main.active_bgm_player.stream_paused, "Gameplay music continued while paused.")
	Input.parse_input_event(escape)
	await process_frame
	_assert(not menu.visible and not paused, "Escape did not resume gameplay.")
	_assert(not main.active_bgm_player.stream_paused, "Gameplay music stayed paused after resume.")
	menu.open()
	menu._restart_button.pressed.emit()
	await process_frame
	_assert(not paused and not menu.visible, "Restart left the game paused.")
	_assert(main.current_screen != first_game, "Restart did not create a new gameplay session.")
	_assert(main.current_screen_id == "game", "Restart did not return to gameplay.")
	main.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Pause menu headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

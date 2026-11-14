extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CLICK_SCENE := preload("res://scenes/components/ClickNote.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	game.set_interaction_mode(1)
	var click := CLICK_SCENE.instantiate() as ClickNote
	click.setup({})
	click.set_meta("bound_pitch", 72)
	click.set_meta("note_type", InteractionSpotManager.NoteType.CLICK)
	root.add_child(click)
	click.audio_note_reached.connect(game.spot_manager._on_spot_audio_note_reached.bind(click))
	click.progressed.connect(game.spot_manager._on_spot_progressed.bind(click))
	click.completed.connect(game.spot_manager._on_spot_completed.bind(click))
	game.arousal_model.physical = 48.6
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click.target_center
	click._gui_input(press)
	_check(game.arousal_model.physical >= 50.0, "Click did not cross the physiological 50 threshold")
	_check(game.interaction_mode == 0 and game.spot_manager._suspended, "Safe-word transition did not suspend physiological spots")
	_check(game._first_safe_word_shown, "Safe-word dialogue was not shown")
	_check(game.violin_audio._clef_backend.active_note_count() == 1, "Safe-word transition cut off the triggering Click")
	game.violin_audio.stop_all()
	click.queue_free()
	game.queue_free()
	await process_frame

	var manual_game = GAME_SCENE.instantiate()
	root.add_child(manual_game)
	manual_game.set_interaction_mode(1)
	manual_game.violin_audio.play_click(72)
	_check(manual_game.violin_audio._clef_backend.active_note_count() == 1, "Manual-switch setup produced no note")
	manual_game.set_interaction_mode(0)
	_check(manual_game.violin_audio._clef_backend.active_note_count() == 0, "Manual psychological switch failed to stop violin audio")
	manual_game.queue_free()
	await process_frame

	if _failures.is_empty():
		print("Safe-word note audio headless tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

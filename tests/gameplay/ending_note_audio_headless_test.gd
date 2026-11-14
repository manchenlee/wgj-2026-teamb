extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CLICK_SCENE := preload("res://scenes/components/ClickNote.tscn")
const RUB_SCENE := preload("res://scenes/components/RubNote.tscn")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rub := RUB_SCENE.instantiate() as RubNote
	rub.setup({})
	_check(CONFIG.RUB_REQUIRED_SCRUB_DISTANCE == 600.0 and rub.required_scrub_distance == 600.0, "Rub completion distance is not 600")
	rub.free()

	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	game.toggle_interaction_mode()
	var click := CLICK_SCENE.instantiate() as ClickNote
	click.setup({})
	click.set_meta("bound_pitch", 72)
	click.set_meta("note_type", InteractionSpotManager.NoteType.CLICK)
	root.add_child(click)
	click.audio_note_reached.connect(game.spot_manager._on_spot_audio_note_reached.bind(click))
	click.progressed.connect(game.spot_manager._on_spot_progressed.bind(click))
	click.completed.connect(game.spot_manager._on_spot_completed.bind(click))
	game.arousal_model.physical = 98.6
	game.arousal_model.emotional = 95.0
	game._safe_word_threshold_reached = true
	game._safe_word_pending = false
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click.target_center
	click._gui_input(press)
	_check(game.violin_audio._clef_backend.active_note_count() == 1, "Final Click did not start its bound-pitch audio")
	_check(game.arousal_model.physical == 100.0, "Final Click did not bring physiological score to 100")
	game._check_ending()
	_check(game.ending_transition_started and not game.run_active, "Final Click did not enter the ending transition")
	_check(game.violin_audio._clef_backend.active_note_count() == 1, "Ending teardown cut off the final Click audio")
	game.violin_audio.stop_all()
	_check(game.violin_audio._clef_backend.active_note_count() == 0, "Explicit audio cleanup failed")
	click.queue_free()
	game.queue_free()
	await process_frame

	if _failures.is_empty():
		print("Ending note audio headless tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

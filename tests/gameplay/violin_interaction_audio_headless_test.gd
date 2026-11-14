extends SceneTree

const SLIDE_SCENE := preload("res://scenes/components/SlideNote.tscn")
const RUB_SCENE := preload("res://scenes/components/RubNote.tscn")
const AUDIO_SCRIPT := preload("res://scripts/gameplay/violin_sample_player.gd")

var _pitch: int = 69
var _pitch_queries: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio := AUDIO_SCRIPT.new() as ViolinSamplePlayer
	audio.pitch_provider = Callable(self, "_get_pitch")
	root.add_child(audio)
	var slide := SLIDE_SCENE.instantiate() as SlideNote
	slide.setup({"checkpoints": PackedVector2Array([Vector2(100, 100), Vector2(220, 100), Vector2(220, 220), Vector2(100, 220)]), "checkpoint_radius": 40.0})
	root.add_child(slide)
	slide.audio_note_reached.connect(audio.play_slide_checkpoint)
	slide._start_drag(Vector2(100, 100), -1)
	_check(audio._voice_serial == 1 and _pitch_queries == 1 and is_equal_approx(audio._voices[0].pitch_scale, 1.0), "Slide start pitch queried once")
	_pitch = 72
	_check(is_equal_approx(audio._voices[0].pitch_scale, 1.0), "Slide start pitch stays fixed")
	slide._process_pointer_move(Vector2(220, 100))
	_check(audio._voice_serial == 2 and _pitch_queries == 2 and is_equal_approx(audio._voices[1].pitch_scale, pow(2.0, 3.0 / 12.0)), "Slide checkpoint pitch queried once")
	_pitch = 76
	slide._process_pointer_move(Vector2(220, 220))
	_check(audio._voice_serial == 3 and _pitch_queries == 3 and is_equal_approx(audio._voices[2].pitch_scale, pow(2.0, 7.0 / 12.0)), "Slide third checkpoint pitch queried once")
	_pitch = 67
	slide._process_pointer_move(Vector2(100, 220))
	_check(audio._voice_serial == 4 and _pitch_queries == 4 and is_equal_approx(audio._voices[3].pitch_scale, pow(2.0, -2.0 / 12.0)), "Four-note Slide produced four independent pitch events")
	audio.stop_all()
	_check(not audio._voices[3].playing, "Slide cancellation")
	var rub := RUB_SCENE.instantiate() as RubNote
	rub.setup({"required_scrub_distance": 600.0, "valid_motion_threshold": 3.0, "max_delta_per_event": 24.0, "target_center": Vector2(108, 108), "target_radius": 52.0})
	root.add_child(rub)
	rub.audio_motion_valid.connect(func() -> void: audio.rub_motion(rub.get_instance_id()))
	rub.interaction_ended.connect(func() -> void: audio.end_rub(rub.get_instance_id()))
	rub._gui_input(_press(Vector2(108, 108), true))
	_check(audio._rub_source_id == 0, "Rub hold must be silent")
	rub._process_pointer_move(Vector2(110, 108))
	_check(audio._rub_source_id == 0, "Subthreshold Rub must be silent")
	rub._process_pointer_move(Vector2(128, 108))
	_check(audio._rub_source_id == rub.get_instance_id(), "Valid Rub starts sound")
	_check(_pitch_queries == 5, "Rub start queried MIDI pitch once")
	var initial_pitch := audio._rub_player.pitch_scale
	_pitch = 76
	rub._process_pointer_move(Vector2(108, 108))
	_check(is_equal_approx(audio._rub_player.pitch_scale, initial_pitch) and _pitch_queries == 5, "Rub pitch held during rapid transition")
	for i in 8:
		await create_timer(0.05).timeout
		rub._process_pointer_move(Vector2(128, 108) if i % 2 == 0 else Vector2(108, 108))
	_check(is_equal_approx(audio._rub_player.pitch_scale, initial_pitch) and _pitch_queries == 5, "Continuous Rub keeps one pitch after old change interval")
	await create_timer(0.16).timeout
	_check(audio._rub_source_id == 0, "Rub inactivity timeout")
	rub._process_pointer_move(Vector2(128, 108))
	_check(audio._rub_source_id == rub.get_instance_id(), "Rub resumes after inactivity")
	_check(_pitch_queries == 6 and is_equal_approx(audio._rub_player.pitch_scale, pow(2.0, 7.0 / 12.0)), "Resumed Rub queries new pitch once")
	rub._gui_input(_press(Vector2(128, 108), false))
	_check(audio._rub_source_id == 0, "Rub release")
	audio.stop_all()
	_check(not audio._rub_player.playing, "Rub cleanup")
	if _failures.is_empty():
		print("Violin interaction audio headless tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _get_pitch() -> int:
	_pitch_queries += 1
	return _pitch

func _press(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

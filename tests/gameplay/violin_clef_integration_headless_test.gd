extends SceneTree

const AUDIO_SCRIPT := preload("res://scripts/gameplay/violin_sample_player.gd")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CLICK_SCENE := preload("res://scenes/components/ClickNote.tscn")
const SLIDE_SCENE := preload("res://scenes/components/SlideNote.tscn")
const RUB_SCENE := preload("res://scenes/components/RubNote.tscn")

var _pitch: int = 69
var _queries: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := OS.get_environment("VIOLIN_SF2_PATH")
	if path.is_empty():
		path = "res://assets/audio/soundfonts/generaluser_gs/GeneralUser-GS.sf2"
	var audio := AUDIO_SCRIPT.new() as ViolinSamplePlayer
	audio.soundfont_path = path
	audio.pitch_provider = Callable(self, "_get_pitch")
	root.add_child(audio)
	_check(audio._clef_backend.is_available(), "Clef backend did not load")
	var violin_bus := AudioServer.get_bus_index(&"Violin")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(violin_bus), audio.violin_gain_db), "Violin bus gain")
	_check(AudioServer.get_bus_effect(violin_bus, 0) is AudioEffectHardLimiter, "Violin limiter")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(&"clef_ch_0")) == &"Violin", "SF2 bus route")
	var timeline_file := FileAccess.open("res://data/violin_timeline.json", FileAccess.READ)
	var timeline: Dictionary = JSON.parse_string(timeline_file.get_as_text())
	var pitches: Dictionary = {55: true, 62: true, 69: true, 76: true}
	for note in timeline["notes"]:
		pitches[note["pitch"]] = true
	for pitch in pitches:
		for preset in [audio.pizzicato_preset, audio.arco_preset]:
			_check(not audio._clef_backend.bank.get_instruments(preset, pitch, 100, 0).is_empty(), "SF2 preset %d lacks MIDI pitch %d" % [preset, pitch])
	var click := CLICK_SCENE.instantiate() as ClickNote
	click.setup({"target_center": Vector2(84, 84), "target_radius": 40.0})
	root.add_child(click)
	click.audio_note_reached.connect(audio.play_click)
	click._gui_input(_press(Vector2(10, 10)))
	_check(_queries == 0, "Invalid Click queried pitch")
	click._gui_input(_press(Vector2(84, 84)))
	_check(_queries == 1 and audio._clef_backend.active_note_count() == 1, "Successful Click Note On")
	_check(_has_note(audio, 69), "Click fixed MIDI pitch")
	for i in 20:
		audio.play_click()
	_check(audio._clef_backend.active_note_count() <= audio.max_voices, "Rapid Click exceeded note cap")
	await create_timer(0.60).timeout
	_check(audio._clef_backend.active_note_count() == 0, "Click release tails remained")
	var slide := SLIDE_SCENE.instantiate() as SlideNote
	slide.setup({"checkpoints": PackedVector2Array([Vector2(100, 100), Vector2(220, 100), Vector2(220, 220), Vector2(100, 220)]), "checkpoint_radius": 40.0})
	root.add_child(slide)
	slide.audio_note_reached.connect(audio.play_slide_checkpoint)
	var before := _queries
	for entry in [[Vector2(100, 100), 69], [Vector2(220, 100), 72], [Vector2(220, 220), 76], [Vector2(100, 220), 67]]:
		_pitch = entry[1]
		if _queries == before:
			slide._start_drag(entry[0], -1)
		else:
			slide._process_pointer_move(entry[0])
		_check(_has_note(audio, _pitch), "Slide checkpoint fixed pitch %d" % _pitch)
	_check(_queries == before + 4, "Four Slide checkpoints each queried pitch once")
	await create_timer(0.55).timeout
	_check(audio._clef_backend.active_note_count() == 0, "Slide voices remained")
	var rub := RUB_SCENE.instantiate() as RubNote
	rub.setup({"required_scrub_distance": 600.0, "valid_motion_threshold": 3.0, "max_delta_per_event": 24.0, "target_center": Vector2(108, 108), "target_radius": 52.0})
	root.add_child(rub)
	rub.audio_motion_valid.connect(func() -> void: audio.rub_motion(rub.get_instance_id()))
	rub.interaction_ended.connect(func() -> void: audio.end_rub(rub.get_instance_id()))
	rub._gui_input(_press(Vector2(108, 108)))
	_check(audio._clef_rub_token == 0, "Stationary Rub played")
	_pitch = 62
	rub._process_pointer_move(Vector2(128, 108))
	var rub_queries := _queries
	_check(audio._clef_rub_token != 0 and _has_note(audio, 62), "Valid Rub Note On")
	_pitch = 76
	for i in 16:
		audio._process(0.025)
		rub._process_pointer_move(Vector2(108, 108) if i % 2 == 0 else Vector2(128, 108))
	_check(_queries == rub_queries and _has_note(audio, 62), "Continuous Rub changed pitch")
	audio._process(0.16)
	_check(audio._clef_rub_token != 0, "Rub released during a normal stroke reversal")
	audio._process(0.16)
	_check(audio._clef_rub_token == 0, "Inactive Rub did not release")
	rub._process_pointer_move(Vector2(108, 108))
	_check(_queries == rub_queries + 1 and _has_note(audio, 76), "Resumed Rub did not query new pitch")
	audio.stop_rub()
	audio.rub_motion(777, 69)
	var token := audio._clef_rub_token
	var voice_count := audio._clef_backend.pool.get_voice_count()
	for i in 12:
		audio._process(0.008)
		audio.rub_motion(777, 76)
	_check(audio._clef_rub_token == token and _has_note(audio, 69), "Rub retriggered or changed pitch")
	_check(audio._clef_backend.pool.get_voice_count() == voice_count, "Rub added voices")
	var channel: int = audio._clef_backend._notes[token]["channel"]
	var bus_index := AudioServer.get_bus_index("clef_ch_%d" % channel)
	var attenuation := AudioServer.get_bus_volume_db(bus_index)
	_check(attenuation < -0.1 and attenuation >= -4.0, "Rub attenuation exceeded range or did not modulate")
	audio._process(0.32)
	_check(audio._clef_rub_token == 0, "Rub inactivity did not release")
	_check(is_zero_approx(AudioServer.get_bus_volume_db(bus_index)), "Rub left channel attenuated")
	audio.stop_all()
	_check(audio._clef_backend.pool.get_voice_count() == 0, "Cancellation left SF2 voices")
	audio.play_click()
	paused = true
	await process_frame
	await process_frame
	_check(audio._clef_backend.pool.get_voice_count() == 0, "Pause left SF2 voices")
	paused = false
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	game.violin_audio.pitch_provider = Callable(self, "_get_pitch")
	_check(game.violin_audio._clef_backend.is_available(), "Gameplay did not select Clef")
	var game_click := CLICK_SCENE.instantiate() as ClickNote
	game_click.setup({"target_center": Vector2(84, 84), "target_radius": 40.0})
	root.add_child(game_click)
	game_click.audio_note_reached.connect(game.spot_manager._on_spot_audio_note_reached.bind(game_click))
	game_click._gui_input(_press(Vector2(84, 84)))
	_check(game.violin_audio._clef_backend.active_note_count() == 1, "Gameplay Click route")
	var game_slide := SLIDE_SCENE.instantiate() as SlideNote
	game_slide.setup({"checkpoints": PackedVector2Array([Vector2(100, 100), Vector2(220, 100), Vector2(220, 220), Vector2(100, 220)]), "checkpoint_radius": 40.0})
	root.add_child(game_slide)
	game_slide.audio_note_reached.connect(game.spot_manager._on_spot_audio_note_reached.bind(game_slide))
	var game_slide_queries := _queries
	game_slide._start_drag(Vector2(100, 100), -1)
	game_slide._process_pointer_move(Vector2(220, 100))
	game_slide._process_pointer_move(Vector2(220, 220))
	game_slide._process_pointer_move(Vector2(100, 220))
	_check(game.violin_audio._clef_arco_token != 0, "Gameplay Slide route")
	_check(_queries == game_slide_queries + 4, "Gameplay Slide did not produce four events")
	var game_rub := RUB_SCENE.instantiate() as RubNote
	game_rub.setup({"required_scrub_distance": 600.0, "valid_motion_threshold": 3.0, "max_delta_per_event": 24.0, "target_center": Vector2(108, 108), "target_radius": 52.0})
	root.add_child(game_rub)
	game_rub.audio_motion_valid.connect(game.spot_manager._on_spot_audio_motion_valid.bind(game_rub))
	game_rub._gui_input(_press(Vector2(108, 108)))
	game_rub._process_pointer_move(Vector2(128, 108))
	_check(game.violin_audio._clef_rub_token != 0, "Gameplay Rub route")
	game._stop_runtime_timers()
	_check(game.violin_audio._clef_backend.pool.get_voice_count() == 0, "Restart cleanup")
	game.violin_audio.play_click()
	_check(game.violin_audio._clef_backend.active_note_count() == 1, "Scene transition setup")
	game.queue_free()
	audio.queue_free()
	await process_frame
	_check(not is_instance_valid(game), "Scene transition did not free playing voices")
	_finish()


func _has_note(audio: ViolinSamplePlayer, pitch: int) -> bool:
	for note in audio._clef_backend._notes.values():
		if note["pitch"] == pitch and not note.get("releasing", false):
			return true
	return false


func _get_pitch() -> int:
	_queries += 1
	return _pitch


func _press(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Violin Clef gameplay integration test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

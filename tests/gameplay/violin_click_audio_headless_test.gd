extends SceneTree

const CLICK_SCENE := preload("res://scenes/components/ClickNote.tscn")
const AUDIO_SCRIPT := preload("res://scripts/gameplay/violin_sample_player.gd")

var _pitch: int = 69
var _requests: int = 0
var _pitch_queries: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var audio := AUDIO_SCRIPT.new() as ViolinSamplePlayer
	audio.pitch_provider = Callable(self, "_get_pitch")
	root.add_child(audio)
	var violin_bus := AudioServer.get_bus_index(&"Violin")
	if violin_bus < 0 or not is_equal_approx(AudioServer.get_bus_volume_db(violin_bus), audio.violin_gain_db):
		_fail("Configurable violin gain was not applied")
	if violin_bus >= 0 and not AudioServer.get_bus_effect(violin_bus, 0) is AudioEffectHardLimiter:
		_fail("Overlapping violin voices have no limiter")
	var click := CLICK_SCENE.instantiate() as ClickNote
	click.setup({"target_center": Vector2(84, 84), "target_radius": 40.0})
	root.add_child(click)
	click.audio_note_reached.connect(func() -> void:
		_requests += 1
		audio.play_click()
	)
	click._gui_input(_press(Vector2(10, 10)))
	if _requests != 0 or audio._voice_serial != 0:
		_fail("Invalid Click triggered audio")
	_pitch = 72
	click._gui_input(_press(Vector2(84, 84)))
	if _requests != 1 or audio._voice_serial != 1:
		_fail("Successful Click did not trigger once")
	if _pitch_queries != 1:
		_fail("Successful Click did not query pitch exactly once")
	elif not is_equal_approx(audio._voices[0].pitch_scale, pow(2.0, 3.0 / 12.0)):
		_fail("Click pitch was not read at input time")
	click._gui_input(_press(Vector2(84, 84)))
	if _requests != 1:
		_fail("Resolved Click retriggered audio")
	audio.stop_all()
	if audio._voices[0].playing:
		_fail("Stop did not clean up Click voice")
	for i in 20:
		audio.play_click()
	if audio._voices.size() != audio.max_voices or audio._voice_serial != 21:
		_fail("Rapid Click voice pool exceeded its cap")
	paused = true
	await process_frame
	await process_frame
	if audio._voices.any(func(voice: AudioStreamPlayer) -> bool: return voice.playing):
		_fail("Paused game kept Click voices playing")
	paused = false
	if _failures.is_empty():
		print("Violin Click audio headless test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _get_pitch() -> int:
	_pitch_queries += 1
	return _pitch

func _press(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event

func _fail(message: String) -> void:
	_failures.append(message)

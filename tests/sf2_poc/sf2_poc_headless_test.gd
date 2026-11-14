extends SceneTree

const PLAYER_SCRIPT := preload("res://tests/sf2_poc/sf2_poc_player.gd")
const FONT_ENV := "SF2_POC_PATH"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := OS.get_environment(FONT_ENV)
	if path.is_empty():
		_fail("SF2_POC_PATH is required")
		return
	var player: Sf2PocPlayer = PLAYER_SCRIPT.new()
	root.add_child(player)
	if not player.load_soundfont(path):
		_fail("SoundFont load failed")
		return
	var names := player.preset_names()
	print("FONT=", player.sf2_data.bank_name, " BANK0_PRESETS=", names.size(), " TOTAL_PRESETS=", player.sf2_data.presets.size())
	for preset in [40, 44, 45]:
		print("PRESET_%d=%s" % [preset, names.get(preset, "MISSING")])
		if not names.has(preset):
			_fail("Required preset missing")
			return
	var violin_bus := AudioServer.get_bus_index(&"Violin")
	_assert(violin_bus >= 0, "Violin bus exists")
	_assert(is_equal_approx(AudioServer.get_bus_volume_db(violin_bus), 10.0), "Violin gain")
	_assert(AudioServer.get_bus_effect(violin_bus, 0) is AudioEffectHardLimiter, "Violin limiter")
	_assert(AudioServer.get_bus_send(AudioServer.get_bus_index(&"clef_ch_0")) == &"Violin", "Clef channel routes to Violin")
	var start_ms := Time.get_ticks_msec()
	var pizz := player.note_on(45, 69, 100, 0)
	var elapsed_ms := Time.get_ticks_msec() - start_ms
	_assert(pizz != null and pizz.playing, "Pizzicato Note On")
	print("NOTE_ON_CALL_MS=", elapsed_ms)
	_assert(pizz.key == 69 and pizz.channel == 0, "MIDI pitch and channel")
	_assert(pizz.bus == &"clef_ch_0", "Voice bus assignment")
	player.note_off(69, 0)
	await create_timer(0.15).timeout
	_assert(pizz.is_idle() or pizz.is_releasing(), "Pizzicato release after Note Off")
	var soft := player.note_on(40, 62, 40, 1)
	var loud := player.note_on(40, 69, 120, 2)
	_assert(soft != null and loud != null, "Arco polyphony starts")
	_assert(soft != loud and soft.playing and loud.playing, "Different channels remain polyphonic")
	_assert(loud._velocity_db > soft._velocity_db, "Velocity changes voice gain")
	await create_timer(0.20).timeout
	_assert(soft.playing and loud.playing, "Arco sustains")
	player.note_off(62, 1)
	player.note_off(69, 2)
	var trem := player.note_on(44, 55, 100, 3)
	_assert(trem != null and trem.playing, "Tremolo Note On")
	await create_timer(0.20).timeout
	_assert(trem.playing, "Tremolo sustains")
	player.note_off(55, 3)
	var first := player.note_on(45, 69, 100, 4)
	var second := player.note_on(45, 69, 100, 4)
	_assert(first != null and second != null and second.playing, "Rapid retrigger")
	player.release_all()
	await create_timer(0.60).timeout
	print("VOICES_AFTER_600MS=", player.pool.get_voice_count())
	_assert(player.pool.get_active_voices().all(func(voice: ClefVoice) -> bool: return voice.is_releasing()), "All notes enter release")
	await create_timer(7.00).timeout
	_assert(player.pool.get_voice_count() == 0, "Natural release eventually cleans up")
	player.note_on(40, 69, 100, 5)
	player.force_stop_all()
	_assert(player.pool.get_voice_count() == 0, "Immediate cancellation cleanup")
	player.queue_free()
	if _failures.is_empty():
		print("SF2_POC_PASS")
		quit(0)
	else:
		print("SF2_POC_FAIL_COUNT=", _failures.size())
		quit(1)


func _assert(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
		push_error("SF2_POC_FAIL: " + label)


func _fail(message: String) -> void:
	push_error("SF2_POC_FAIL: " + message)
	quit(1)

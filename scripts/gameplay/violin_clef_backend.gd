class_name ViolinClefBackend
extends Node

const VIOLIN_BUS: StringName = &"Violin"
const MAX_CHANNELS: int = 16

var soundfont_path: String = ""
var pizzicato_preset: int = 45
var arco_preset: int = 40
var max_notes: int = 8

var bank: ClefBank
var pool: ClefVoicePool
var _notes: Dictionary = {}
var _release_tweens: Dictionary = {}
var _next_token: int = 1


func _ready() -> void:
	if soundfont_path.is_empty():
		push_warning("Violin SF2 path is empty; using procedural fallback")
		return
	if not FileAccess.file_exists(soundfont_path):
		push_warning("Violin SF2 file is missing: %s; using procedural fallback" % soundfont_path)
		return
	var result := Sf2Reader.read_file(soundfont_path)
	if not result.ok:
		push_warning("Violin SF2 failed to load: %s" % result.error_message)
		return
	for preset in [pizzicato_preset, arco_preset]:
		var found := false
		for entry in result.data.presets:
			if entry.bank == 0 and entry.preset_index == preset:
				found = true
				break
		if not found:
			push_warning("Violin SF2 preset %d is missing; using procedural fallback" % preset)
			return
	bank = ClefBank.new()
	bank.load_from_sf2(result.data)
	for channel in MAX_CHANNELS:
		var name := "clef_ch_%d" % channel
		var index := AudioServer.get_bus_index(name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, VIOLIN_BUS)
	pool = ClefVoicePool.new(self, mini(max_notes, MAX_CHANNELS) * 2)


func is_available() -> bool:
	return bank != null


func play_note(preset: int, pitch: int, velocity: int, duration: float = 0.0) -> int:
	if bank == null or pitch < 0 or pitch > 127:
		return 0
	var channel := _free_channel()
	if channel < 0:
		_stop_token(_oldest_token())
		channel = _free_channel()
	var instruments: Array[ClefInstrumentInfo] = bank.get_instruments(preset, pitch, clampi(velocity, 1, 127), channel)
	if instruments.is_empty():
		return 0
	var voice := pool.start_note(channel, pitch, clampi(velocity, 1, 127), instruments)
	if voice == null:
		return 0
	var token := _next_token
	_next_token += 1
	_notes[token] = {"channel": channel, "pitch": pitch}
	if duration > 0.0:
		var tween := create_tween()
		_release_tweens[token] = tween
		tween.tween_interval(duration)
		tween.tween_callback(func() -> void: release_note(token))
	return token


func release_note(token: int) -> void:
	if not _notes.has(token):
		return
	if _notes[token].get("releasing", false):
		return
	if _release_tweens.has(token):
		(_release_tweens[token] as Tween).kill()
		_release_tweens.erase(token)
	var channel: int = _notes[token]["channel"]
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("clef_ch_%d" % channel), 0.0)
	for voice in pool.get_active_voices_for_channel(channel):
		voice.quick_stop()
	_notes[token]["releasing"] = true
	var tween := create_tween()
	_release_tweens[token] = tween
	tween.tween_interval(0.08)
	tween.tween_callback(func() -> void: _stop_token(token))


func force_stop_all() -> void:
	for note: Dictionary in _notes.values():
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("clef_ch_%d" % int(note["channel"])), 0.0)
	for tween: Tween in _release_tweens.values():
		tween.kill()
	_release_tweens.clear()
	_notes.clear()
	if pool != null:
		pool.force_stop_all()


func active_note_count() -> int:
	return _notes.size()


func set_note_attenuation_db(token: int, attenuation_db: float) -> void:
	# A note owns its channel until its release tail ends. Only attenuate: no gain boost.
	if not _notes.has(token) or _notes[token].get("releasing", false):
		return
	var channel: int = _notes[token]["channel"]
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("clef_ch_%d" % channel), clampf(attenuation_db, -80.0, 0.0))


func _free_channel() -> int:
	for channel in mini(max_notes, MAX_CHANNELS):
		var used := false
		for note in _notes.values():
			if note["channel"] == channel:
				used = true
				break
		if not used:
			return channel
	return -1


func _oldest_token() -> int:
	var oldest := 0
	for token: int in _notes:
		if oldest == 0 or token < oldest:
			oldest = token
	return oldest


func _stop_token(token: int) -> void:
	if not _notes.has(token):
		return
	var channel: int = _notes[token]["channel"]
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("clef_ch_%d" % channel), 0.0)
	for voice in pool.get_active_voices_for_channel(channel):
		voice.force_stop()
	if _release_tweens.has(token):
		(_release_tweens[token] as Tween).kill()
		_release_tweens.erase(token)
	_notes.erase(token)


func _exit_tree() -> void:
	force_stop_all()

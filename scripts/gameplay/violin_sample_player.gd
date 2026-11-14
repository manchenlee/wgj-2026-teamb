class_name ViolinSamplePlayer
extends Node

const ClefBackendClass := preload("res://scripts/gameplay/violin_clef_backend.gd")

# These streams and generated tones remain available when no usable SF2 is configured.
@export var pizzicato_sample: AudioStream
@export var arco_sample: AudioStream
@export var tremolo_sample: AudioStream
@export var soundfont_path: String = ""
@export_range(0, 127) var pizzicato_preset: int = 45
@export_range(0, 127) var arco_preset: int = 40
@export_range(0, 127) var tremolo_preset: int = 44
@export_range(36, 96) var sample_root_pitch: int = 69
@export_range(2, 24) var max_voices: int = 8
@export_range(0.1, 0.15, 0.005) var rub_inactivity_seconds: float = 0.125
@export_range(-12.0, 18.0, 0.5) var violin_gain_db: float = 10.0

const VIOLIN_BUS: StringName = &"Violin"

var pitch_provider: Callable
var _voices: Array[AudioStreamPlayer] = []
var _voice_serial: int = 0
var _rub_player: AudioStreamPlayer
var _rub_source_id: int = 0
var _rub_idle: float = 0.0
var _arco_player: AudioStreamPlayer
var _voice_generation: Dictionary = {}
var _voice_tweens: Dictionary = {}
var _rub_tween: Tween
var _clef_backend: ViolinClefBackend
var _clef_arco_token: int = 0
var _clef_rub_token: int = 0

func _process(delta: float) -> void:
	if get_tree().paused:
		if _rub_source_id != 0 or _voices.any(func(voice: AudioStreamPlayer) -> bool: return voice.playing) or (_clef_backend != null and _clef_backend.active_note_count() > 0):
			stop_all()
		return
	if _rub_source_id == 0:
		return
	_rub_idle += delta
	if _rub_idle >= rub_inactivity_seconds:
		stop_rub()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_violin_bus()
	_clef_backend = ClefBackendClass.new()
	var soundfont_override := OS.get_environment("VIOLIN_SF2_PATH")
	_clef_backend.soundfont_path = soundfont_override if not soundfont_override.is_empty() else soundfont_path
	_clef_backend.pizzicato_preset = pizzicato_preset
	_clef_backend.arco_preset = arco_preset
	_clef_backend.tremolo_preset = tremolo_preset
	_clef_backend.max_notes = max_voices
	add_child(_clef_backend)
	if pizzicato_sample == null:
		pizzicato_sample = _make_development_sample(&"pizzicato")
	if arco_sample == null:
		arco_sample = _make_development_sample(&"arco")
	if tremolo_sample == null:
		tremolo_sample = _make_development_sample(&"tremolo")
	for i in max_voices:
		var player := AudioStreamPlayer.new()
		player.name = "ViolinVoice%d" % i
		player.bus = VIOLIN_BUS
		add_child(player)
		_voices.append(player)
	_rub_player = AudioStreamPlayer.new()
	_rub_player.name = "ViolinRub"
	_rub_player.bus = VIOLIN_BUS
	add_child(_rub_player)

func _ensure_violin_bus() -> void:
	var bus_index := AudioServer.get_bus_index(VIOLIN_BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, String(VIOLIN_BUS))
		AudioServer.set_bus_send(bus_index, &"Master")
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -6.0
		AudioServer.add_bus_effect(bus_index, limiter)
	AudioServer.set_bus_volume_db(bus_index, violin_gain_db)

func play_click() -> void:
	var pitch := _current_pitch()
	if pitch < 0:
		return
	if _clef_backend.is_available() and _clef_backend.play_note(pizzicato_preset, pitch, 108, 0.18) != 0:
		return
	var voice := _next_voice()
	voice.stream = pizzicato_sample
	voice.pitch_scale = pow(2.0, float(pitch - sample_root_pitch) / 12.0)
	voice.volume_db = -13.0
	voice.play()

func _current_pitch() -> int:
	return int(pitch_provider.call()) if pitch_provider.is_valid() else -1

func _next_voice() -> AudioStreamPlayer:
	var voice := _voices[_voice_serial % _voices.size()]
	_voice_serial += 1
	if voice == _arco_player:
		_arco_player = null
	if _voice_tweens.has(voice):
		(_voice_tweens[voice] as Tween).kill()
	voice.stop()
	_voice_generation[voice] = _voice_serial
	return voice

func play_slide_checkpoint() -> void:
	var pitch := _current_pitch()
	if pitch < 0:
		return
	if _clef_backend.is_available():
		if _clef_arco_token != 0:
			_clef_backend.release_note(_clef_arco_token)
		_clef_arco_token = _clef_backend.play_note(arco_preset, pitch, 105, 0.35)
		if _clef_arco_token != 0:
			return
	if _arco_player != null and _arco_player.playing:
		_release_voice(_arco_player, 0.09)
	var voice := _next_voice()
	_arco_player = voice
	voice.stream = arco_sample
	voice.pitch_scale = pow(2.0, float(pitch - sample_root_pitch) / 12.0)
	voice.volume_db = -32.0
	voice.play()
	var generation: int = _voice_generation[voice]
	var tween := create_tween()
	_voice_tweens[voice] = tween
	tween.tween_property(voice, "volume_db", -13.0, 0.045)
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void:
		if _voice_generation.get(voice, -1) == generation:
			_release_voice(voice, 0.12)
	)

func _release_voice(voice: AudioStreamPlayer, duration: float) -> void:
	var generation: int = _voice_generation.get(voice, -1)
	if _voice_tweens.has(voice):
		(_voice_tweens[voice] as Tween).kill()
	var tween := create_tween()
	_voice_tweens[voice] = tween
	tween.tween_property(voice, "volume_db", -50.0, duration)
	tween.tween_callback(func() -> void:
		if _voice_generation.get(voice, -1) == generation:
			voice.stop()
	)

func rub_motion(source_id: int) -> void:
	if _rub_source_id != source_id or (_clef_backend.is_available() and _clef_rub_token == 0) or (not _clef_backend.is_available() and not _rub_player.playing):
		var pitch := _current_pitch()
		if pitch < 0:
			return
		if _clef_backend.is_available():
			if _clef_rub_token != 0:
				_clef_backend.release_note(_clef_rub_token)
			_clef_rub_token = _clef_backend.play_note(tremolo_preset, pitch, 100)
			if _clef_rub_token != 0:
				_rub_source_id = source_id
				_rub_idle = 0.0
				return
		if _rub_tween != null:
			_rub_tween.kill()
		_rub_source_id = source_id
		_rub_player.stop()
		_rub_player.stream = tremolo_sample
		_rub_player.pitch_scale = pow(2.0, float(pitch - sample_root_pitch) / 12.0)
		_rub_player.volume_db = -35.0
		_rub_player.play()
		_rub_tween = create_tween()
		_rub_tween.tween_property(_rub_player, "volume_db", -16.0, 0.04)
	_rub_idle = 0.0

func end_rub(source_id: int) -> void:
	if source_id == _rub_source_id:
		stop_rub()

func stop_all() -> void:
	if _clef_backend != null:
		_clef_backend.force_stop_all()
	_clef_arco_token = 0
	_clef_rub_token = 0
	for tween: Tween in _voice_tweens.values():
		tween.kill()
	_voice_tweens.clear()
	for voice in _voices:
		voice.stop()
	_voice_generation.clear()
	_arco_player = null
	stop_rub()
	if _rub_player != null:
		_rub_player.stop()

func stop_rub() -> void:
	_rub_source_id = 0
	if _clef_rub_token != 0:
		_clef_backend.release_note(_clef_rub_token)
		_clef_rub_token = 0
	if _rub_player != null:
		if not _rub_player.playing:
			return
		if _rub_tween != null:
			_rub_tween.kill()
		var player := _rub_player
		var tween := create_tween()
		_rub_tween = tween
		tween.tween_property(player, "volume_db", -50.0, 0.045)
		tween.tween_callback(func() -> void:
			if _rub_source_id == 0:
				player.stop()
		)

func _exit_tree() -> void:
	if _clef_backend != null:
		_clef_backend.force_stop_all()
	for voice in _voices:
		voice.stop()
	if _rub_player != null:
		_rub_player.stop()

func _make_development_sample(kind: StringName) -> AudioStreamWAV:
	const RATE := 22050
	var duration := 0.22 if kind == &"pizzicato" else 0.7
	var count := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var frequency := 440.0
	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-19.0 * t) if kind == &"pizzicato" else minf(t * 35.0, 1.0) * minf((duration - t) * 12.0, 1.0)
		var wobble := 1.0 + 0.14 * sin(TAU * 24.0 * t) if kind == &"tremolo" else 1.0
		var wave := (sin(TAU * frequency * t) + 0.28 * sin(TAU * frequency * 2.0 * t)) * envelope * wobble * 0.24
		var value := int(clampf(wave, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = RATE
	sample.data = bytes
	if kind == &"tremolo":
		sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sample.loop_begin = int(RATE * 0.06)
		sample.loop_end = int(RATE * 0.62)
	return sample

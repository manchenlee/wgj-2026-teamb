class_name Sf2PocPlayer
extends Node

# Isolated Clef runtime trial. No gameplay node references this class.
const VIOLIN_BUS: StringName = &"Violin"
const MAX_VOICES: int = 16

var bank: ClefBank
var pool: ClefVoicePool
var sf2_data: Sf2Data
var active_notes: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	pool = ClefVoicePool.new(self, MAX_VOICES)


func load_soundfont(path: String) -> bool:
	var result := Sf2Reader.read_file(path)
	if not result.ok:
		push_error("SF2 PoC: %s" % result.error_message)
		return false
	sf2_data = result.data
	bank = ClefBank.new()
	bank.load_from_sf2(sf2_data)
	return true


func preset_names() -> Dictionary:
	var names: Dictionary = {}
	if sf2_data == null:
		return names
	for preset in sf2_data.presets:
		if preset.bank == 0:
			names[preset.preset_index] = preset.name
	return names


func note_on(preset: int, pitch: int, velocity: int, channel: int) -> ClefVoice:
	if bank == null or pitch < 0 or pitch > 127 or velocity < 1 or velocity > 127 or channel < 0 or channel > 15:
		return null
	var instruments: Array[ClefInstrumentInfo] = bank.get_instruments(preset, pitch, velocity, channel)
	if instruments.is_empty():
		return null
	var voice := pool.start_note(channel, pitch, velocity, instruments)
	if voice != null:
		active_notes["%d:%d" % [channel, pitch]] = true
	return voice


func note_off(pitch: int, channel: int) -> void:
	pool.stop_note(channel, pitch)
	active_notes.erase("%d:%d" % [channel, pitch])


func release_all() -> void:
	if pool != null:
		pool.stop_all()
	active_notes.clear()


func force_stop_all() -> void:
	if pool != null:
		pool.force_stop_all()
	active_notes.clear()


func _exit_tree() -> void:
	force_stop_all()


func _ensure_buses() -> void:
	var violin_index := AudioServer.get_bus_index(VIOLIN_BUS)
	if violin_index < 0:
		AudioServer.add_bus()
		violin_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(violin_index, VIOLIN_BUS)
		AudioServer.set_bus_send(violin_index, &"Master")
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -6.0
		AudioServer.add_bus_effect(violin_index, limiter)
	AudioServer.set_bus_volume_db(violin_index, 10.0)
	for channel in 16:
		var channel_name := "clef_ch_%d" % channel
		if AudioServer.get_bus_index(channel_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, channel_name)
		AudioServer.set_bus_send(index, VIOLIN_BUS)

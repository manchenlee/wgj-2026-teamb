extends Node

const SOUND_FONT_ENV := "SF2_POC_PATH"
const PRESETS := {KEY_1: 45, KEY_2: 40, KEY_3: 44}
const KEYS := {KEY_Z: 55, KEY_X: 62, KEY_C: 69, KEY_V: 76}
const CHANNELS := {KEY_Z: 0, KEY_X: 1, KEY_C: 2, KEY_V: 3}

var _player: Sf2PocPlayer
var _preset: int = 45
var _held: Dictionary = {}


func _ready() -> void:
	_player = Sf2PocPlayer.new()
	add_child(_player)
	var path := OS.get_environment(SOUND_FONT_ENV)
	if path.is_empty() or not _player.load_soundfont(path):
		push_warning("Set SF2_POC_PATH to a licensed .sf2 file before running this scene")
		return
	print("SF2 PoC loaded: ", path)
	print("1=Pizzicato Strings (45), 2=Violin (40), 3=Tremolo Strings (44); Z/X/C/V=G3/D4/A4/E5; release key=Note Off")
	var names := _player.preset_names()
	print("Selected presets: 40=", names.get(40, "missing"), ", 44=", names.get(44, "missing"), ", 45=", names.get(45, "missing"))


func _unhandled_key_input(event: InputEvent) -> void:
	if _player.bank == null or event.echo:
		return
	if event.pressed and PRESETS.has(event.keycode):
		_preset = PRESETS[event.keycode]
		print("Selected preset: ", _player.preset_names().get(_preset, "missing"))
		return
	if not KEYS.has(event.keycode):
		return
	var pitch: int = KEYS[event.keycode]
	if event.pressed and not _held.has(event.keycode):
		var channel: int = CHANNELS[event.keycode]
		_held[event.keycode] = [pitch, channel]
		var voice := _player.note_on(_preset, pitch, 100, channel)
		print("Note On: preset=%d pitch=%d channel=%d voice=%s" % [_preset, pitch, channel, voice != null])
	elif not event.pressed and _held.has(event.keycode):
		var note: Array = _held[event.keycode]
		_player.note_off(note[0], note[1])
		_held.erase(event.keycode)
		print("Note Off: pitch=%d channel=%d" % [note[0], note[1]])

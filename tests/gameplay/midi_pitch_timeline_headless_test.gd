extends SceneTree

const TIMELINE_SCRIPT := preload("res://scripts/gameplay/midi_pitch_timeline.gd")
const TIMELINE_PATH := "res://data/violin_timeline.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var timeline: MidiPitchTimeline = TIMELINE_SCRIPT.new()
	_assert(timeline.load_from_file(TIMELINE_PATH), "Generated MIDI timeline failed validation.")
	_assert(timeline.notes.size() == 554, "Unexpected MIDI note count.")
	_assert(absf(timeline.loop_duration_seconds - 145.540563) < 0.001, "OGG loop length changed.")
	_assert(timeline.get_pitch_at_time(2.5) == 71, "First active MIDI pitch is incorrect.")
	_assert(timeline.get_pitch_at_time(0.0) in MidiPitchTimeline.OPEN_STRING_PITCHES, "Opening rest did not choose an open string.")
	_assert(timeline.get_pitch_at_time(2.5 + timeline.loop_duration_seconds) == 71, "Looping changed the first note pitch.")
	_assert(timeline.get_pitch_at_time(timeline.loop_duration_seconds) == timeline.get_pitch_at_time(0.0), "Exact loop boundary did not wrap.")
	_assert(timeline.get_pitch_at_time(timeline.loop_duration_seconds - 0.001) == 83, "Final MIDI note was lost before the OGG loop.")

	var synthetic: MidiPitchTimeline = TIMELINE_SCRIPT.new()
	_assert(synthetic.load_from_data({
		"loop_duration_seconds": 4.0,
		"notes": [
			{"start": 0.5, "end": 2.0, "pitch": 60},
			{"start": 1.0, "end": 1.5, "pitch": 74},
			{"start": 3.0, "end": 3.5, "pitch": 71},
		]
	}), "Synthetic timeline failed validation.")
	_assert(synthetic.get_pitch_at_time(0.75) == 60, "First active note was not selected.")
	_assert(synthetic.get_pitch_at_time(1.25) == 74, "Overlapping note did not select the latest onset.")
	_assert(synthetic.get_pitch_at_time(1.75) == 60, "Long overlapping note did not resume after the short note.")
	_assert(synthetic.get_pitch_at_time(2.25) == 62, "Rest did not choose the nearest open string to the preceding note.")
	_assert(synthetic.get_pitch_at_time(2.8) == 69, "Rest did not choose the nearest open string to the upcoming note.")
	_assert(synthetic.get_pitch_at_time(4.75) == 60, "Synthetic loop did not wrap.")
	var empty: MidiPitchTimeline = TIMELINE_SCRIPT.new()
	empty.default_open_string_pitch = 55
	_assert(empty.load_from_data({"loop_duration_seconds": 2.0, "notes": []}), "Empty timeline failed validation.")
	_assert(empty.get_pitch_at_time(0.5) == 55, "Configurable default open string was not used.")

	if _failures.is_empty():
		print("MIDI pitch timeline headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

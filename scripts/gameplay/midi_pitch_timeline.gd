class_name MidiPitchTimeline
extends RefCounted

const OPEN_STRING_PITCHES: Array[int] = [55, 62, 69, 76] # G3, D4, A4, E5

var default_open_string_pitch: int = 69
var loop_duration_seconds: float = 0.0
var notes: Array[Dictionary] = []


func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	return load_from_data(parsed)


func load_from_data(data: Dictionary) -> bool:
	var duration := float(data.get("loop_duration_seconds", 0.0))
	var raw_notes: Variant = data.get("notes", [])
	if duration <= 0.0 or not raw_notes is Array:
		return false
	var validated: Array[Dictionary] = []
	var last_start := -1.0
	for entry: Variant in raw_notes:
		if not entry is Dictionary:
			return false
		var note: Dictionary = entry
		var start := float(note.get("start", -1.0))
		var end := float(note.get("end", -1.0))
		var pitch := int(note.get("pitch", -1))
		if start < last_start or start < 0.0 or end <= start or end > duration + 0.02 or pitch < 0 or pitch > 127:
			return false
		validated.append(note)
		last_start = start
	loop_duration_seconds = duration
	notes = validated
	return true


func get_pitch_at_time(playback_position: float) -> int:
	if loop_duration_seconds <= 0.0 or notes.is_empty():
		return _valid_default_pitch()
	var position := fposmod(playback_position, loop_duration_seconds)
	var active_pitch := -1
	var latest_start := -1.0
	var nearest_pitch := -1
	var nearest_distance := INF
	for note: Dictionary in notes:
		var start := float(note["start"])
		var end := float(note["end"])
		var pitch := int(note["pitch"])
		if start <= position and position < end and start >= latest_start:
			active_pitch = pitch
			latest_start = start
		var distance := minf(_circular_distance(position, start), _circular_distance(position, minf(end, loop_duration_seconds)))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_pitch = pitch
	if active_pitch >= 0:
		return active_pitch
	return _nearest_open_string(nearest_pitch)


func _circular_distance(position: float, note_position: float) -> float:
	var distance := absf(position - note_position)
	return minf(distance, loop_duration_seconds - distance)


func _nearest_open_string(reference_pitch: int) -> int:
	if reference_pitch < 0:
		return _valid_default_pitch()
	var chosen := OPEN_STRING_PITCHES[0]
	for pitch: int in OPEN_STRING_PITCHES:
		if absi(reference_pitch - pitch) < absi(reference_pitch - chosen):
			chosen = pitch
	return chosen


func _valid_default_pitch() -> int:
	return default_open_string_pitch if default_open_string_pitch in OPEN_STRING_PITCHES else 69

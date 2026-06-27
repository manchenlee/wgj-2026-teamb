class_name DirectionSequenceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var rng := RandomNumberGenerator.new()
var current_sequence: Array[String] = []
var current_index: int = 0
var wrong_inputs: int = 0
var time_left: float = 0.0
var round_active: bool = false

func _init() -> void:
	rng.randomize()

func start_round() -> void:
	current_sequence.clear()
	current_index = 0
	wrong_inputs = 0
	time_left = Config.DIRECTION_SEQUENCE_TIME_LIMIT
	round_active = true

	var count := rng.randi_range(Config.DIRECTION_SEQUENCE_LENGTH_MIN, Config.DIRECTION_SEQUENCE_LENGTH_MAX)
	var directions := ["Left", "Right", "Up", "Down"]
	for _i in count:
		current_sequence.append(directions[rng.randi_range(0, directions.size() - 1)])

func tick(delta: float) -> bool:
	if not round_active:
		return false
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		round_active = false
		return true
	return false

func submit_input(direction: String) -> Dictionary:
	if not round_active:
		return {"result": "inactive"}

	var expected := current_sequence[current_index]
	if direction == expected:
		current_index += 1
		var finished := current_index >= current_sequence.size()
		if finished:
			round_active = false
			return {"result": "round_success"}
		return {"result": "correct"}

	wrong_inputs += 1
	round_active = false
	return {"result": "wrong"}

func clear_round() -> void:
	current_sequence.clear()
	current_index = 0
	wrong_inputs = 0
	time_left = 0.0
	round_active = false

func get_sequence_text() -> String:
	var parts: Array[String] = []
	for index in current_sequence.size():
		var arrow := _to_arrow(current_sequence[index])
		if index < current_index:
			parts.append("[font_size=60][color=#71d99e]%s[/color][/font_size]" % arrow)
		elif index == current_index and round_active:
			parts.append("[b][font_size=72][color=#fff1a8]%s[/color][/font_size][/b]" % arrow)
		else:
			parts.append("[font_size=60][color=#7d7d87]%s[/color][/font_size]" % arrow)
	if parts.is_empty():
		return "[center][font_size=44][color=#7d7d87]Waiting for round...[/color][/font_size][/center]"
	return "[center]%s[/center]" % "     ".join(parts)

func _to_arrow(direction: String) -> String:
	match direction:
		"Left":
			return "←"
		"Right":
			return "→"
		"Up":
			return "↑"
		"Down":
			return "↓"
		_:
			return "?"

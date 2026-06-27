class_name DirectionSequenceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var rng := RandomNumberGenerator.new()
var directions: Array[String] = []
var anchor_offsets: Array[Vector2] = []
var current_index: int = -1
var prompt_active: bool = false

func _init() -> void:
	rng.randomize()

func start_sequence() -> Dictionary:
	clear_sequence()
	var pool := ["Left", "Right", "Up", "Down"]
	var sequence_length := rng.randi_range(
		Config.DIRECTION_SEQUENCE_LENGTH_MIN,
		Config.DIRECTION_SEQUENCE_LENGTH_MAX
	)
	var last_anchor := Vector2.INF
	for _step in sequence_length:
		directions.append(pool[rng.randi_range(0, pool.size() - 1)])
		var next_anchor := _pick_anchor(last_anchor)
		anchor_offsets.append(next_anchor)
		last_anchor = next_anchor
	current_index = 0
	prompt_active = not directions.is_empty()
	return get_current_prompt()

func get_current_prompt() -> Dictionary:
	if not prompt_active or current_index < 0 or current_index >= directions.size():
		return {}
	return {
		"direction": directions[current_index],
		"anchor_offset": anchor_offsets[current_index],
		"arrow": _to_arrow(directions[current_index]),
		"step_index": current_index,
		"step_count": directions.size()
	}

func submit_input(direction: String) -> Dictionary:
	if not prompt_active or current_index < 0 or current_index >= directions.size():
		return {"result": "inactive"}

	var expected := directions[current_index]
	var current_anchor := anchor_offsets[current_index]
	if direction == expected:
		current_index += 1
		if current_index >= directions.size():
			prompt_active = false
			return {
				"result": "sequence_complete",
				"direction": expected,
				"anchor_offset": current_anchor
			}
		return {
			"result": "correct",
			"direction": expected,
			"anchor_offset": current_anchor,
			"next_prompt": get_current_prompt()
		}

	prompt_active = false
	return {
		"result": "wrong",
		"expected": expected,
		"direction": direction,
		"anchor_offset": current_anchor
	}

func clear_sequence() -> void:
	directions.clear()
	anchor_offsets.clear()
	current_index = -1
	prompt_active = false

func get_prompt_debug_state() -> String:
	if not prompt_active:
		return "waiting"
	var current_prompt := get_current_prompt()
	return "%s %d/%d @ (%.0f, %.0f)" % [
		str(current_prompt.get("direction", "")),
		int(current_prompt.get("step_index", 0)) + 1,
		int(current_prompt.get("step_count", 0)),
		current_prompt.get("anchor_offset", Vector2.ZERO).x,
		current_prompt.get("anchor_offset", Vector2.ZERO).y
	]

func get_sequence_progress_text() -> String:
	if directions.is_empty() or current_index < 0:
		return ""
	return "%d/%d" % [current_index + 1, directions.size()]

func _pick_anchor(previous_anchor: Vector2) -> Vector2:
	var available: Array = Config.ARROW_PROMPT_ANCHOR_OFFSETS
	var next_anchor: Vector2 = available[rng.randi_range(0, available.size() - 1)]
	if available.size() <= 1:
		return next_anchor
	while next_anchor == previous_anchor:
		next_anchor = available[rng.randi_range(0, available.size() - 1)]
	return next_anchor

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

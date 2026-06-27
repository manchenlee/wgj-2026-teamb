class_name DirectionSequenceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var rng := RandomNumberGenerator.new()
var current_direction: String = ""
var current_anchor_offset: Vector2 = Vector2.ZERO
var prompt_active: bool = false

func _init() -> void:
	rng.randomize()

func spawn_prompt() -> Dictionary:
	var directions := ["Left", "Right", "Up", "Down"]
	current_direction = directions[rng.randi_range(0, directions.size() - 1)]
	var anchor_offsets: Array = Config.ARROW_PROMPT_ANCHOR_OFFSETS
	current_anchor_offset = anchor_offsets[rng.randi_range(0, anchor_offsets.size() - 1)]
	prompt_active = true
	return {
		"direction": current_direction,
		"anchor_offset": current_anchor_offset,
		"arrow": _to_arrow(current_direction)
	}

func submit_input(direction: String) -> Dictionary:
	if not prompt_active or current_direction.is_empty():
		return {"result": "inactive"}

	if direction == current_direction:
		prompt_active = false
		return {
			"result": "correct",
			"direction": current_direction,
			"anchor_offset": current_anchor_offset
		}

	var expected := current_direction
	prompt_active = false
	return {
		"result": "wrong",
		"expected": expected,
		"direction": direction,
		"anchor_offset": current_anchor_offset
	}

func clear_prompt() -> void:
	current_direction = ""
	current_anchor_offset = Vector2.ZERO
	prompt_active = false

func get_prompt_debug_state() -> String:
	if not prompt_active:
		return "waiting"
	return "%s @ (%.0f, %.0f)" % [current_direction, current_anchor_offset.x, current_anchor_offset.y]

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

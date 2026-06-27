class_name DirectionSequenceController
extends RefCounted

var rng := RandomNumberGenerator.new()
var phase_config = null
var directions: Array[String] = []
var anchor_ids: Array[String] = []
var available_anchor_ids: Array[String] = []
var current_index: int = -1
var visible_count: int = 0
var prompt_active: bool = false

func _init() -> void:
	rng.randomize()

func set_phase_config(next_phase_config) -> void:
	phase_config = next_phase_config

func set_prompt_anchor_ids(ids: Array[String]) -> void:
	available_anchor_ids = ids.duplicate()

func start_sequence() -> Dictionary:
	clear_sequence()
	var sequence_length := rng.randi_range(
		_get_phase_int("direction_sequence_length_min", 3),
		_get_phase_int("direction_sequence_length_max", 4)
	)
	var directions_pool := _build_direction_pool(sequence_length)
	var last_anchor_id := ""
	for step_index in range(sequence_length):
		directions.append(directions_pool[step_index])
		var next_anchor_id := _pick_anchor_id(last_anchor_id)
		anchor_ids.append(next_anchor_id)
		last_anchor_id = next_anchor_id
	current_index = 0
	visible_count = 0
	prompt_active = not directions.is_empty()
	return reveal_next_prompt()

func get_current_prompt() -> Dictionary:
	if not prompt_active or current_index < 0 or current_index >= directions.size() or current_index >= visible_count:
		return {}
	return {
		"direction": directions[current_index],
		"anchor_id": anchor_ids[current_index],
		"arrow": _to_arrow(directions[current_index]),
		"step_index": current_index,
		"step_count": directions.size()
	}

func reveal_next_prompt() -> Dictionary:
	if not prompt_active or visible_count >= directions.size():
		return {}
	var prompt_index := visible_count
	visible_count += 1
	return {
		"prompt_id": prompt_index,
		"direction": directions[prompt_index],
		"anchor_id": anchor_ids[prompt_index],
		"arrow": _to_arrow(directions[prompt_index]),
		"step_index": prompt_index,
		"step_count": directions.size()
	}

func has_more_hidden_prompts() -> bool:
	return prompt_active and visible_count < directions.size()

func submit_input(direction: String) -> Dictionary:
	if not prompt_active or current_index < 0 or current_index >= directions.size() or current_index >= visible_count:
		return {"result": "inactive"}

	var expected := directions[current_index]
	var current_anchor_id := anchor_ids[current_index]
	var consumed_index := current_index
	if direction == expected:
		current_index += 1
		if current_index >= directions.size():
			prompt_active = false
			return {
				"result": "sequence_complete",
				"consumed_prompt_id": consumed_index,
				"direction": expected,
				"anchor_id": current_anchor_id
			}
		var auto_revealed_prompt := {}
		if current_index >= visible_count:
			auto_revealed_prompt = reveal_next_prompt()
		return {
			"result": "correct",
			"consumed_prompt_id": consumed_index,
			"direction": expected,
			"anchor_id": current_anchor_id,
			"next_prompt": get_current_prompt(),
			"auto_revealed_prompt": auto_revealed_prompt
		}

	prompt_active = false
	return {
		"result": "wrong",
		"consumed_prompt_id": consumed_index,
		"expected": expected,
		"direction": direction,
		"anchor_id": current_anchor_id
	}

func clear_sequence() -> void:
	directions.clear()
	anchor_ids.clear()
	current_index = -1
	visible_count = 0
	prompt_active = false

func get_prompt_debug_state() -> String:
	if not prompt_active:
		return "waiting"
	var current_prompt := get_current_prompt()
	return "%s %d/%d @ %s" % [
		str(current_prompt.get("direction", "")),
		int(current_prompt.get("step_index", 0)) + 1,
		int(current_prompt.get("step_count", 0)),
		str(current_prompt.get("anchor_id", "?"))
	]

func get_sequence_progress_text() -> String:
	if directions.is_empty() or current_index < 0:
		return ""
	return "%d/%d" % [current_index + 1, directions.size()]

func _build_direction_pool(sequence_length: int) -> Array[String]:
	var base_directions: Array[String] = ["Left", "Right", "Up", "Down"]
	base_directions.shuffle()
	var result: Array[String] = []
	for index in range(sequence_length):
		result.append(base_directions[index % base_directions.size()])
	return result

func _pick_anchor_id(previous_anchor_id: String) -> String:
	var available: Array[String] = available_anchor_ids
	if available.is_empty():
		available = ["HeadLeft", "HeadRight", "Chest", "LeftArm", "RightArm", "Waist"]
	var next_anchor_id := available[rng.randi_range(0, available.size() - 1)]
	if available.size() <= 1:
		return next_anchor_id
	while next_anchor_id == previous_anchor_id:
		next_anchor_id = available[rng.randi_range(0, available.size() - 1)]
	return next_anchor_id

func _get_phase_int(property_name: String, fallback: int) -> int:
	if phase_config != null:
		return int(phase_config.get(property_name))
	return fallback

func _to_arrow(direction: String) -> String:
	match direction:
		"Left":
			return "\u2190"
		"Right":
			return "\u2192"
		"Up":
			return "\u2191"
		"Down":
			return "\u2193"
		_:
			return "?"

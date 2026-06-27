class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const TEST_TEXT := "皜祈岫皜祈岫皜祈岫皜祈岫皜祈岫皜祈岫皜祈岫皜祈岫皜祈岫皜祈岫"

var phase_config = null
var current_prompt: Dictionary = {}
var current_entry: Dictionary = {}
var entries: Array = []
var event_counter: int = 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func set_phase_config(next_phase_config) -> void:
	phase_config = next_phase_config
	_load_feedback_entries()

func reset() -> void:
	current_prompt = {}
	current_entry = {}
	event_counter = 0

func next_event(physical: float, emotional: float) -> Dictionary:
	event_counter += 1
	current_entry = _select_entry(physical, emotional)

	if event_counter % 3 == 0:
		current_prompt = _build_choice_prompt(current_entry, physical, emotional)
		return current_prompt

	current_prompt = {}
	return {"text": _get_feedback_line(current_entry, physical, emotional)}

func apply_choice(choice_quality: String, model) -> Dictionary:
	var delta_value := 0.0
	match choice_quality:
		"good":
			delta_value = float(_get_choice_reward_values().get("good", 10.0))
		"neutral":
			delta_value = float(_get_choice_reward_values().get("neutral", 3.0))
		"bad":
			delta_value = -float(_get_choice_penalty_values().get("bad", 5.0))

	model.apply_emotional(delta_value)
	var reply := _get_choice_response(choice_quality, current_entry)
	current_prompt = {}
	current_entry = {}
	return {"reply": reply, "delta": delta_value}

func get_timeout_reply() -> String:
	var reply := _get_feedback_line(current_entry, -1.0, -1.0)
	current_prompt = {}
	current_entry = {}
	return reply

func _load_feedback_entries() -> void:
	entries.clear()
	var feedback_data_path := _get_feedback_data_path()
	if feedback_data_path.is_empty():
		push_warning("Feedback dialogue file path is empty for active phase.")
		return
	if not FileAccess.file_exists(feedback_data_path):
		push_warning("Feedback dialogue file not found: %s" % feedback_data_path)
		return

	var raw_text := FileAccess.get_file_as_string(feedback_data_path)
	if raw_text.is_empty():
		push_warning("Feedback dialogue file is empty: %s" % feedback_data_path)
		return

	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Feedback dialogue file has invalid JSON structure: %s" % feedback_data_path)
		return
	var parsed_dict := parsed as Dictionary

	var parsed_entries: Variant = parsed_dict.get("entries", [])
	if typeof(parsed_entries) != TYPE_ARRAY:
		push_warning("Feedback dialogue entries field is not an array: %s" % feedback_data_path)
		return

	for entry_variant in parsed_entries as Array:
		if typeof(entry_variant) == TYPE_DICTIONARY:
			entries.append(entry_variant)

func _select_entry(physical: float, emotional: float) -> Dictionary:
	var target_physical := _classify_physical_state(physical)
	var target_emotional := _classify_emotional_state(emotional)
	if target_physical.is_empty() or target_emotional.is_empty():
		return {}

	var matches: Array[Dictionary] = []
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if str(condition.get("physical", "")) != target_physical:
			continue
		if str(condition.get("emotional", "")) != target_emotional:
			continue
		matches.append(entry)

	if matches.is_empty():
		return {}
	return matches[rng.randi_range(0, matches.size() - 1)].duplicate(true)

func _build_choice_prompt(entry: Dictionary, physical: float, emotional: float) -> Dictionary:
	if entry.is_empty():
		return {
			"text": _build_test_prompt_text(physical, emotional),
			"choices": [
				{"id": "good", "text": TEST_TEXT},
				{"id": "bad", "text": TEST_TEXT}
			]
		}

	var choices: Array[Dictionary] = []
	var preferred_choice_ids := ["good", "bad"]
	for preferred_choice_id in preferred_choice_ids:
		for choice_variant in entry.get("choice", []):
			var choice := choice_variant as Dictionary
			var choice_id := str(choice.get("id", ""))
			if choice_id != preferred_choice_id:
				continue
			choices.append({
				"id": choice_id,
				"text": str(choice.get("text", Config.RESPONSE_BUTTON_TEXT))
			})
			break
		if choices.size() == 2:
			break

	if choices.is_empty():
		for choice_variant in entry.get("choice", []):
			var choice := choice_variant as Dictionary
			var choice_id := str(choice.get("id", ""))
			if choice_id.is_empty() or choice_id == "neutral":
				continue
			choices.append({
				"id": choice_id,
				"text": str(choice.get("text", Config.RESPONSE_BUTTON_TEXT))
			})
			if choices.size() == 2:
				break

	return {
		"text": _get_feedback_line(entry, physical, emotional),
		"choices": choices
	}

func _get_feedback_line(entry: Dictionary, physical: float, emotional: float) -> String:
	if entry.is_empty():
		return _build_test_feedback_text(physical, emotional)
	return _pick_random_text(entry.get("feedback", []), Config.FEEDBACK_MESSAGE_TEXT)

func _get_choice_response(choice_quality: String, entry: Dictionary) -> String:
	if entry.is_empty():
		return TEST_TEXT

	var response_map := entry.get("response", {}) as Dictionary
	var reply_list: Variant = response_map.get(choice_quality, [])
	return _pick_random_text(reply_list, Config.FEEDBACK_MESSAGE_TEXT)

func _pick_random_text(source: Variant, fallback: String) -> String:
	if typeof(source) != TYPE_ARRAY:
		return fallback
	var text_options: Array = source
	if text_options.is_empty():
		return fallback
	return str(text_options[rng.randi_range(0, text_options.size() - 1)])

func _classify_physical_state(physical: float) -> String:
	if physical < _get_phase_value("feedback_physical_low_threshold", 30.0):
		return "low"
	return ""

func _classify_emotional_state(emotional: float) -> String:
	if emotional < _get_phase_value("feedback_emotional_low_threshold", 30.0):
		return "low"
	if emotional >= _get_phase_value("feedback_emotional_high_threshold", 60.0):
		return "high"
	return ""

func _build_test_feedback_text(_physical: float, _emotional: float) -> String:
	return TEST_TEXT

func _build_test_prompt_text(_physical: float, _emotional: float) -> String:
	return TEST_TEXT

func _get_feedback_data_path() -> String:
	return String(_get_phase_value("dialogue_data_source", "res://assets/dialogue/feedback.json"))

func _get_choice_reward_values() -> Dictionary:
	return _get_phase_value("choice_reward_values", {"good": 10.0, "neutral": 3.0})

func _get_choice_penalty_values() -> Dictionary:
	return _get_phase_value("choice_penalty_values", {"bad": 5.0})

func _get_phase_value(property_name: String, fallback: Variant) -> Variant:
	if phase_config != null:
		return phase_config.get(property_name)
	return fallback

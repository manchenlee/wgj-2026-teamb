class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const FEEDBACK_DATA_PATH := "res://assets/dialogue/feedback.json"
const TEST_TEXT := "測試測試測試測試測試測試測試測試測試測試"

var current_prompt: Dictionary = {}
var current_entry: Dictionary = {}
var entries: Array = []
var event_counter: int = 0
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
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
			delta_value = Config.EMOTIONAL_GAIN_GOOD_CHOICE
		"neutral":
			delta_value = Config.EMOTIONAL_GAIN_NEUTRAL_CHOICE
		"bad":
			delta_value = -Config.EMOTIONAL_PENALTY_BAD_CHOICE

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
	if not FileAccess.file_exists(FEEDBACK_DATA_PATH):
		push_warning("Feedback dialogue file not found: %s" % FEEDBACK_DATA_PATH)
		return

	var raw_text := FileAccess.get_file_as_string(FEEDBACK_DATA_PATH)
	if raw_text.is_empty():
		push_warning("Feedback dialogue file is empty: %s" % FEEDBACK_DATA_PATH)
		return

	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Feedback dialogue file has invalid JSON structure: %s" % FEEDBACK_DATA_PATH)
		return
	var parsed_dict := parsed as Dictionary

	var parsed_entries: Variant = parsed_dict.get("entries", [])
	if typeof(parsed_entries) != TYPE_ARRAY:
		push_warning("Feedback dialogue entries field is not an array: %s" % FEEDBACK_DATA_PATH)
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
				{"id": "neutral", "text": TEST_TEXT}
			]
		}

	var choices: Array[Dictionary] = []
	for choice_variant in entry.get("choice", []):
		var choice := choice_variant as Dictionary
		var choice_id := str(choice.get("id", ""))
		if choice_id.is_empty():
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
	if physical < Config.FEEDBACK_PHYSICAL_LOW_THRESHOLD:
		return "low"
	return ""

func _classify_emotional_state(emotional: float) -> String:
	if emotional < Config.FEEDBACK_EMOTIONAL_LOW_THRESHOLD:
		return "low"
	if emotional >= Config.FEEDBACK_EMOTIONAL_HIGH_THRESHOLD:
		return "high"
	return ""

func _build_test_feedback_text(_physical: float, _emotional: float) -> String:
	return TEST_TEXT

func _build_test_prompt_text(_physical: float, _emotional: float) -> String:
	return TEST_TEXT

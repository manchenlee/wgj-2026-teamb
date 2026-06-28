class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var phase_config = null
var current_prompt: Dictionary = {}
var current_entry: Dictionary = {}
var current_feedback_index: int = -1
var choice_prompt_pending: bool = false
var entries: Array = []
var rng := RandomNumberGenerator.new()
var safe_word: String = Config.SAFE_WORD_DEFAULT

func _init() -> void:
	rng.randomize()

func set_phase_config(next_phase_config) -> void:
	phase_config = next_phase_config
	_load_feedback_entries()

func set_safe_word(next_safe_word: String) -> void:
	safe_word = next_safe_word.strip_edges()
	if safe_word.is_empty():
		safe_word = Config.SAFE_WORD_DEFAULT

func reset() -> void:
	current_prompt = {}
	current_entry = {}
	current_feedback_index = -1
	choice_prompt_pending = false

func next_event(physical: float, emotional: float, force_safe_word: bool = false) -> Dictionary:
	if choice_prompt_pending:
		return {}
	if current_entry.is_empty():
		current_entry = _select_entry(physical, emotional, force_safe_word)
		current_feedback_index = -1
	current_prompt = _build_next_prompt(current_entry)
	return current_prompt

func apply_choice(choice_id: String, model) -> Dictionary:
	var choice := _get_choice_definition(current_entry, choice_id)
	var effect := str(choice.get("effect", ""))
	var delta_value := 0.0
	match effect:
		"positive":
			delta_value = float(_get_choice_reward_values().get("good", 10.0))
		"negative":
			delta_value = -float(_get_choice_penalty_values().get("bad", 5.0))
		"bad_ending":
			delta_value = -float(_get_choice_penalty_values().get("bad", 5.0))
		_:
			match choice_id:
				"good":
					delta_value = float(_get_choice_reward_values().get("good", 10.0))
				"neutral":
					delta_value = float(_get_choice_reward_values().get("neutral", 3.0))
				"bad":
					delta_value = -float(_get_choice_penalty_values().get("bad", 5.0))
	if not is_zero_approx(delta_value):
		model.apply_emotional(delta_value)
	var ending_type := ""
	if effect == "bad_ending":
		ending_type = Config.SAFEWORD_IGNORED_FAILURE_ENDING
	var reply := _get_choice_response(choice_id, current_entry, ending_type.is_empty())
	current_prompt = {}
	current_entry = {}
	current_feedback_index = -1
	choice_prompt_pending = false
	return {"reply": reply, "delta": delta_value, "ending_type": ending_type}

func get_timeout_reply() -> String:
	var reply := _get_current_feedback_line(current_entry)
	current_prompt = {}
	current_entry = {}
	current_feedback_index = -1
	choice_prompt_pending = false
	return reply

func has_safe_word_event() -> bool:
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if str(condition.get("event", "")) == "safe_word":
			return true
	return false

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
			entries.append((entry_variant as Dictionary).duplicate(true))

func _select_entry(physical: float, emotional: float, force_safe_word: bool = false) -> Dictionary:
	if force_safe_word:
		return _select_safe_word_entry()

	var target_physical := _classify_state(
		physical,
		float(_get_phase_value("feedback_physical_low_threshold", Config.FEEDBACK_PHYSICAL_LOW_THRESHOLD)),
		float(_get_phase_value("feedback_physical_high_threshold", Config.FEEDBACK_PHYSICAL_HIGH_THRESHOLD))
	)
	var target_emotional := _classify_state(
		emotional,
		float(_get_phase_value("feedback_emotional_low_threshold", Config.FEEDBACK_EMOTIONAL_LOW_THRESHOLD)),
		float(_get_phase_value("feedback_emotional_high_threshold", Config.FEEDBACK_EMOTIONAL_HIGH_THRESHOLD))
	)
	var phase_number := _get_phase_number()
	if target_physical.is_empty() or target_emotional.is_empty() or phase_number < 1:
		return {}

	var matches: Array[Dictionary] = []
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if int(condition.get("phase", -1)) != phase_number:
			continue
		if str(condition.get("physical", "")) != target_physical:
			continue
		if str(condition.get("emotional", "")) != target_emotional:
			continue
		matches.append(entry)

	if matches.is_empty():
		return {}
	return matches[rng.randi_range(0, matches.size() - 1)].duplicate(true)

func _select_safe_word_entry() -> Dictionary:
	var matches: Array[Dictionary] = []
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if str(condition.get("event", "")) == "safe_word":
			matches.append(entry)

	if matches.is_empty():
		return {}
	return matches[rng.randi_range(0, matches.size() - 1)].duplicate(true)

func _build_next_prompt(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {"text": Config.FEEDBACK_MESSAGE_TEXT}

	var feedback_lines := _get_feedback_lines(entry)
	if feedback_lines.is_empty():
		_clear_current_sequence()
		return {"text": Config.FEEDBACK_MESSAGE_TEXT}

	current_feedback_index = mini(current_feedback_index + 1, feedback_lines.size() - 1)
	var is_last_feedback_line := current_feedback_index >= feedback_lines.size() - 1
	var choices: Array[Dictionary] = []
	if is_last_feedback_line:
		choices = _build_choices(entry)
	if choices.is_empty() and is_last_feedback_line:
		var terminal_text := _get_current_feedback_line(entry)
		_clear_current_sequence()
		return {"text": terminal_text}
	if choices.is_empty():
		return {"text": _get_current_feedback_line(entry)}
	choice_prompt_pending = true
	return {"text": _get_current_feedback_line(entry), "choices": choices}

func _get_current_feedback_line(entry: Dictionary) -> String:
	var feedback_lines := _get_feedback_lines(entry)
	if feedback_lines.is_empty():
		return Config.FEEDBACK_MESSAGE_TEXT
	var clamped_index := clampi(current_feedback_index, 0, feedback_lines.size() - 1)
	return _format_text(str(feedback_lines[clamped_index]))

func _get_feedback_lines(entry: Dictionary) -> Array:
	var feedback_variant: Variant = entry.get("feedback", [])
	if typeof(feedback_variant) != TYPE_ARRAY:
		return []
	return feedback_variant as Array

func _build_choices(entry: Dictionary) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for choice_variant in entry.get("choice", []):
		var choice := choice_variant as Dictionary
		var choice_id := str(choice.get("id", ""))
		if choice_id.is_empty():
			continue
		choices.append({
			"id": choice_id,
			"text": _format_text(str(choice.get("text", Config.RESPONSE_BUTTON_TEXT)))
		})
		if choices.size() == 2:
			break
	return choices

func _get_choice_response(choice_id: String, entry: Dictionary, use_fallback: bool = true) -> String:
	var response_map := entry.get("response", {}) as Dictionary
	var reply_list: Variant = response_map.get(choice_id, [])
	return _format_text(_pick_random_text(reply_list, Config.FEEDBACK_MESSAGE_TEXT if use_fallback else ""))

func _get_choice_definition(entry: Dictionary, choice_id: String) -> Dictionary:
	for choice_variant in entry.get("choice", []):
		var choice := choice_variant as Dictionary
		if str(choice.get("id", "")) == choice_id:
			return choice
	return {}

func _clear_current_sequence() -> void:
	current_prompt = {}
	current_entry = {}
	current_feedback_index = -1
	choice_prompt_pending = false

func _pick_random_text(source: Variant, fallback: String) -> String:
	if typeof(source) != TYPE_ARRAY:
		return fallback
	var text_options: Array = source
	if text_options.is_empty():
		return fallback
	return str(text_options[rng.randi_range(0, text_options.size() - 1)])

func _classify_state(value: float, low_threshold: float, high_threshold: float) -> String:
	if value >= high_threshold:
		return "high"
	if value <= low_threshold:
		return "low"
	var midpoint := (low_threshold + high_threshold) * 0.5
	if value >= midpoint:
		return "high"
	return "low"

func _format_text(text_value: String) -> String:
	return text_value.replace("{safe_word}", safe_word)

func _get_phase_number() -> int:
	if phase_config == null:
		return -1
	var phase_id := String(phase_config.phase_id)
	if phase_id.begins_with("phase_"):
		return int(phase_id.trim_prefix("phase_"))
	return -1

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

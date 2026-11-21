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
var current_line: String = ""
var _queued_response_lines: Array = []
var _queued_response_speakers: Array = []
var _queued_response_expressions: Array = []
var _data_source_property: String = "psychological_dialogue_data_source"
var _choices_enabled: bool = true
var _last_entry_id: String = ""
var _ordinary_bag: Array[Dictionary] = []
var _ordinary_pool_ids: Array[String] = []

func _init() -> void:
	rng.randomize()

func configure(data_source_property: String, choices_enabled: bool) -> void:
	_data_source_property = data_source_property
	_choices_enabled = choices_enabled
	if phase_config != null:
		_load_feedback_entries()

func set_phase_config(next_phase_config) -> void:
	phase_config = next_phase_config
	_load_feedback_entries()

func set_safe_word(next_safe_word: String) -> void:
	safe_word = Config.normalize_safe_word(next_safe_word)

func is_safe_word_choice_pending() -> bool:
	if not choice_prompt_pending:
		return false
	var condition := current_entry.get("condition", {}) as Dictionary
	return str(condition.get("event", "")) == "safe_word"

func reset(clear_history: bool = false) -> void:
	current_prompt = {}
	current_entry = {}
	current_feedback_index = -1
	choice_prompt_pending = false
	current_line = ""
	_queued_response_lines.clear()
	_queued_response_speakers.clear()
	_queued_response_expressions.clear()
	if clear_history:
		_last_entry_id = ""
		_ordinary_bag.clear()
		_ordinary_pool_ids.clear()

func next_event(physical: float, emotional: float, force_safe_word: bool = false, include_safe_word: bool = false) -> Dictionary:
	if choice_prompt_pending:
		return {}
	if not _queued_response_lines.is_empty():
		current_line = _format_text(str(_queued_response_lines.pop_front()))
		var queued_speaker := str(_queued_response_speakers.pop_front()) if not _queued_response_speakers.is_empty() else ""
		var queued_expression := str(_queued_response_expressions.pop_front()) if not _queued_response_expressions.is_empty() else ""
		return {"text": current_line, "speaker": queued_speaker, "expression": queued_expression}
	if current_entry.is_empty():
		current_entry = _select_entry(physical, emotional, force_safe_word, include_safe_word)
		current_feedback_index = -1
	current_prompt = _build_next_prompt(current_entry)
	current_line = str(current_prompt.get("text", ""))
	return current_prompt

func apply_choice(choice_id: String, model) -> Dictionary:
	var choice := _get_choice_definition(current_entry, choice_id)
	var effect := str(choice.get("effect", ""))
	var is_wrong_choice := _is_wrong_choice(choice_id, effect)
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
	if effect == "bad_ending" or (is_safe_word_choice_pending() and is_wrong_choice):
		ending_type = Config.SAFEWORD_IGNORED_FAILURE_ENDING
	var response_map := current_entry.get("response", {}) as Dictionary
	var speaker_map := current_entry.get("response_speakers", {}) as Dictionary
	var expression_map := current_entry.get("response_expressions", {}) as Dictionary
	var authored_responses := response_map.get(choice_id, []) as Array
	var authored_speakers := speaker_map.get(choice_id, []) as Array
	var authored_expressions := expression_map.get(choice_id, []) as Array
	var reply := ""
	var reply_speaker := ""
	var reply_expression := ""
	if not authored_responses.is_empty():
		reply = _format_text(str(authored_responses[0]))
		reply_speaker = str(authored_speakers[0]) if not authored_speakers.is_empty() and authored_speakers[0] is String else ""
		reply_expression = str(authored_expressions[0]) if not authored_expressions.is_empty() and authored_expressions[0] is String else ""
		for index in range(1, authored_responses.size()):
			_queued_response_lines.append(authored_responses[index])
			_queued_response_speakers.append(authored_speakers[index] if index < authored_speakers.size() and authored_speakers[index] is String else "")
			_queued_response_expressions.append(authored_expressions[index] if index < authored_expressions.size() and authored_expressions[index] is String else "")
	else:
		reply = _get_choice_response(choice_id, current_entry, ending_type.is_empty())
	current_line = reply
	current_prompt = {}
	current_entry = {}
	current_feedback_index = -1
	choice_prompt_pending = false
	return {
		"reply": reply,
		"reply_speaker": reply_speaker,
		"reply_expression": reply_expression,
		"delta": delta_value,
		"ending_type": ending_type,
		"choice_effect": effect,
		"is_wrong_choice": is_wrong_choice
	}

func get_current_line() -> String:
	return current_line

func is_group_complete() -> bool:
	return current_entry.is_empty() and _queued_response_lines.is_empty() and not choice_prompt_pending

func has_safe_word_event() -> bool:
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if str(condition.get("event", "")) == "safe_word":
			return true
	return false

func _load_feedback_entries() -> void:
	entries.clear()
	_ordinary_bag.clear()
	_ordinary_pool_ids.clear()
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
			var entry := (entry_variant as Dictionary).duplicate(true)
			if not _choices_enabled and entry.has("choice"):
				push_warning(
					"Dialogue stream '%s' does not allow choices; authored choice was ignored."
					% _data_source_property
				)
				entry.erase("choice")
			entries.append(entry)

func _select_entry(physical: float, emotional: float, force_safe_word: bool = false, include_safe_word: bool = false) -> Dictionary:
	var selected: Dictionary = {}
	if force_safe_word:
		selected = _draw_safe_word_entry(_get_safe_word_entries())
	else:
		var ordinary_matches := _get_matching_entries(physical, emotional)
		if include_safe_word:
			var safe_matches := _get_safe_word_entries()
			var safe_alternatives: Array[Dictionary] = []
			for entry in safe_matches:
				if str(entry.get("id", "")) != _last_entry_id:
					safe_alternatives.append(entry)
			if not safe_alternatives.is_empty():
				safe_matches = safe_alternatives
			elif not ordinary_matches.is_empty():
				safe_matches.clear()
			var ordinary_weight := ordinary_matches.size()
			if ordinary_weight > 1 and not _last_entry_id.is_empty():
				for entry in ordinary_matches:
					if str(entry.get("id", "")) == _last_entry_id:
						ordinary_weight -= 1
						break
			var total_weight := ordinary_weight + safe_matches.size()
			if total_weight > 0 and rng.randi_range(0, total_weight - 1) < safe_matches.size():
				selected = _draw_safe_word_entry(safe_matches)
		if selected.is_empty():
			selected = _draw_ordinary_entry(ordinary_matches)
	if selected.is_empty():
		return {}
	_last_entry_id = str(selected.get("id", ""))
	return selected

func _draw_safe_word_entry(matches: Array[Dictionary]) -> Dictionary:
	if matches.is_empty():
		return {}
	return matches[rng.randi_range(0, matches.size() - 1)].duplicate(true)

func _draw_ordinary_entry(matches: Array[Dictionary]) -> Dictionary:
	if matches.is_empty():
		_ordinary_bag.clear()
		_ordinary_pool_ids.clear()
		return {}
	var pool_ids: Array[String] = []
	for entry in matches:
		pool_ids.append(str(entry.get("id", "")))
	if pool_ids != _ordinary_pool_ids:
		_ordinary_pool_ids = pool_ids
		_ordinary_bag.clear()
	if _ordinary_bag.is_empty():
		_ordinary_bag.assign(matches)
		for index in range(_ordinary_bag.size() - 1, 0, -1):
			var swap_index := rng.randi_range(0, index)
			var swap_entry := _ordinary_bag[index]
			_ordinary_bag[index] = _ordinary_bag[swap_index]
			_ordinary_bag[swap_index] = swap_entry
		if _ordinary_bag.size() > 1 and str(_ordinary_bag[-1].get("id", "")) == _last_entry_id:
			var swap_index := rng.randi_range(0, _ordinary_bag.size() - 2)
			var swap_entry := _ordinary_bag[-1]
			_ordinary_bag[-1] = _ordinary_bag[swap_index]
			_ordinary_bag[swap_index] = swap_entry
	return _ordinary_bag.pop_back().duplicate(true)

func _get_matching_entries(physical: float, emotional: float) -> Array[Dictionary]:

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
	if target_physical.is_empty() or target_emotional.is_empty():
		return []

	var matches: Array[Dictionary] = []
	var seen_signatures: Dictionary = {}
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if str(condition.get("physical", "")) not in [target_physical, "any"]:
			continue
		if str(condition.get("emotional", "")) not in [target_emotional, "any"]:
			continue
		# Legacy phase variants share one condition-based pool. Collapse only exact
		# semantic duplicates so placeholder copies do not receive extra weight.
		var signature := _get_phase_independent_entry_signature(entry)
		if seen_signatures.has(signature):
			continue
		seen_signatures[signature] = true
		matches.append(entry)
	return matches

func _get_phase_independent_entry_signature(entry: Dictionary) -> String:
	var semantic_entry := entry.duplicate(true)
	semantic_entry.erase("id")
	var condition := semantic_entry.get("condition", {}) as Dictionary
	condition.erase("phase")
	semantic_entry["condition"] = condition
	return JSON.stringify(semantic_entry)

func _get_safe_word_entries() -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var condition := entry.get("condition", {}) as Dictionary
		if str(condition.get("event", "")) == "safe_word":
			matches.append(entry)

	return matches

func _build_next_prompt(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {"text": Config.FEEDBACK_MESSAGE_TEXT}

	var feedback_lines := _get_feedback_lines(entry)
	if feedback_lines.is_empty():
		_clear_current_sequence()
		return {"text": Config.FEEDBACK_MESSAGE_TEXT}

	current_feedback_index = mini(current_feedback_index + 1, feedback_lines.size() - 1)
	var is_last_feedback_line := current_feedback_index >= feedback_lines.size() - 1
	var speaker := _get_current_feedback_speaker(entry)
	var expression := _get_current_feedback_expression(entry)
	var choices: Array[Dictionary] = []
	if is_last_feedback_line:
		choices = _build_choices(entry)
	if choices.is_empty() and is_last_feedback_line:
		var terminal_text := _get_current_feedback_line(entry)
		_clear_current_sequence()
		return {"text": terminal_text, "speaker": speaker, "expression": expression}
	if choices.is_empty():
		return {"text": _get_current_feedback_line(entry), "speaker": speaker, "expression": expression}
	choice_prompt_pending = true
	return {"text": _get_current_feedback_line(entry), "speaker": speaker, "expression": expression, "choices": choices}

func _get_current_feedback_expression(entry: Dictionary) -> String:
	var expressions := entry.get("feedback_expressions", []) as Array
	if current_feedback_index >= 0 and current_feedback_index < expressions.size():
		var expression: Variant = expressions[current_feedback_index]
		return str(expression) if expression is String else ""
	return ""

func _get_current_feedback_speaker(entry: Dictionary) -> String:
	var speakers := entry.get("feedback_speakers", []) as Array
	if current_feedback_index >= 0 and current_feedback_index < speakers.size():
		var speaker: Variant = speakers[current_feedback_index]
		return str(speaker) if speaker is String else ""
	return ""

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
	if not _choices_enabled:
		return choices
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

func _is_wrong_choice(choice_id: String, effect: String) -> bool:
	match effect:
		"negative", "bad_ending":
			return true
		"positive":
			return false
	return choice_id == "bad"

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

func _get_feedback_data_path() -> String:
	return String(_get_phase_value(_data_source_property, ""))

func _get_choice_reward_values() -> Dictionary:
	return _get_phase_value("choice_reward_values", {"good": 10.0, "neutral": 3.0})

func _get_choice_penalty_values() -> Dictionary:
	return _get_phase_value("choice_penalty_values", {"bad": 5.0})

func _get_phase_value(property_name: String, fallback: Variant) -> Variant:
	if phase_config != null:
		return phase_config.get(property_name)
	return fallback

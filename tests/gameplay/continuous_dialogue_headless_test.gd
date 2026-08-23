extends SceneTree

const DIALOGUE_CONTROLLER_SCRIPT := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const PHASE_1_CONFIG_SCRIPT := preload("res://data/phases/phase_1_config.gd")
const PHASE_2_CONFIG_SCRIPT := preload("res://data/phases/phase_2_config.gd")

const CONDITIONS := [
	{"physical": 30.0, "emotional": 30.0, "physical_state": "low", "emotional_state": "low", "suffix": "physical_low_emotional_low"},
	{"physical": 30.0, "emotional": 60.0, "physical_state": "low", "emotional_state": "high", "suffix": "physical_low_emotional_high"},
	{"physical": 60.0, "emotional": 30.0, "physical_state": "high", "emotional_state": "low", "suffix": "physical_high_emotional_low"},
	{"physical": 60.0, "emotional": 60.0, "physical_state": "high", "emotional_state": "high", "suffix": "physical_high_emotional_high"},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_psychological_merged_pool()
	_test_physiological_duplicate_handling()
	_test_phase_config_does_not_gate_candidates()
	_test_safe_word_remains_special()
	if _failures.is_empty():
		print("Continuous-dialogue headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_psychological_merged_pool() -> void:
	var controller = _make_controller("psychological_dialogue_data_source", true)
	for condition in CONDITIONS:
		var candidates: Array[Dictionary] = controller._get_matching_entries(
			condition.physical,
			condition.emotional
		)
		var ids := _candidate_ids(candidates)
		_assert(candidates.size() == 2, "Psychological %s pool has %d candidates instead of 2." % [condition.suffix, candidates.size()])
		_assert(_contains_prefix(ids, "phase1_"), "Psychological %s pool lost its former Phase 1 entry: %s" % [condition.suffix, str(ids)])
		_assert(_contains_prefix(ids, "phase2_"), "Psychological %s pool lost its former Phase 2 entry: %s" % [condition.suffix, str(ids)])
		for candidate in candidates:
			var candidate_condition := candidate.get("condition", {}) as Dictionary
			_assert(candidate_condition.get("physical") == condition.physical_state, "Psychological candidate escaped physical condition filtering.")
			_assert(candidate_condition.get("emotional") == condition.emotional_state, "Psychological candidate escaped emotional condition filtering.")


func _test_physiological_duplicate_handling() -> void:
	var controller = _make_controller("physiological_dialogue_data_source", false)
	_assert(controller.entries.size() == 8, "Physiological authored records were deleted instead of retained.")
	for condition in CONDITIONS:
		var raw_ids := _raw_condition_ids(controller.entries, condition)
		var candidates: Array[Dictionary] = controller._get_matching_entries(
			condition.physical,
			condition.emotional
		)
		_assert(raw_ids.size() == 2, "Physiological %s does not retain both legacy records: %s" % [condition.suffix, str(raw_ids)])
		_assert(_contains_prefix(raw_ids, "phase1_") and _contains_prefix(raw_ids, "phase2_"), "Physiological %s lost a legacy phase record: %s" % [condition.suffix, str(raw_ids)])
		_assert(candidates.size() == 1, "Exact physiological placeholder duplicates distort %s weighting: %d effective candidates." % [condition.suffix, candidates.size()])


func _test_phase_config_does_not_gate_candidates() -> void:
	var controller = _make_controller("psychological_dialogue_data_source", true)
	var phase_1_ids := _candidate_ids(controller._get_matching_entries(60.0, 60.0))
	controller.set_phase_config(PHASE_2_CONFIG_SCRIPT.new())
	var phase_2_ids := _candidate_ids(controller._get_matching_entries(60.0, 60.0))
	_assert(phase_1_ids == phase_2_ids, "Changing compatibility phase config changed the continuous dialogue pool: %s vs %s" % [str(phase_1_ids), str(phase_2_ids)])
	_assert(phase_2_ids.size() == 2 and _contains_prefix(phase_2_ids, "phase1_") and _contains_prefix(phase_2_ids, "phase2_"), "Both authored families are not available under one config: %s" % str(phase_2_ids))


func _test_safe_word_remains_special() -> void:
	var controller = _make_controller("psychological_dialogue_data_source", true)
	_assert(controller.has_safe_word_event(), "Safe-word event disappeared from the merged data source.")
	for condition in CONDITIONS:
		for candidate in controller._get_matching_entries(condition.physical, condition.emotional):
			_assert(candidate.get("condition", {}).get("event", "") != "safe_word", "Safe-word event entered the ordinary condition pool.")
	var safe_word_entry: Dictionary = controller._select_entry(60.0, 60.0, true)
	_assert(safe_word_entry.get("id", "") == "safe_word_event_01", "Forced safe-word selection changed: %s" % str(safe_word_entry.get("id", "")))


func _make_controller(data_source_property: String, choices_enabled: bool):
	var controller = DIALOGUE_CONTROLLER_SCRIPT.new()
	controller.configure(data_source_property, choices_enabled)
	controller.set_phase_config(PHASE_1_CONFIG_SCRIPT.new())
	return controller


func _candidate_ids(candidates: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for candidate in candidates:
		ids.append(String(candidate.get("id", "")))
	ids.sort()
	return ids


func _raw_condition_ids(entries: Array, condition: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var entry_condition := entry.get("condition", {}) as Dictionary
		if entry_condition.get("physical", "") == condition.physical_state and entry_condition.get("emotional", "") == condition.emotional_state:
			ids.append(String(entry.get("id", "")))
	ids.sort()
	return ids


func _contains_prefix(values: Array[String], prefix: String) -> bool:
	for value in values:
		if value.begins_with(prefix):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends SceneTree

const DIALOGUE_CONTROLLER_SCRIPT := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const PHASE_CONFIG_SCRIPT := preload("res://data/phases/phase_config.gd")

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
	_test_physiological_dialogue_is_disabled()
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
		_assert(candidates.size() == 3, "Psychological %s pool has %d candidates instead of 3." % [condition.suffix, candidates.size()])
		_assert(ids == ["psychological_dialogue_01", "psychological_dialogue_03", "psychological_dialogue_04"], "Psychological pool IDs differ from workbook conversations: %s" % str(ids))
		for candidate in candidates:
			var candidate_condition := candidate.get("condition", {}) as Dictionary
			_assert(candidate_condition.get("physical") == "any", "Psychological workbook dialogue is not available across physical states.")
			_assert(candidate_condition.get("emotional") == "any", "Psychological workbook dialogue is not available across emotional states.")


func _test_physiological_dialogue_is_disabled() -> void:
	var controller = _make_controller("physiological_dialogue_data_source", false)
	_assert(controller.entries.is_empty(), "Physiological interaction unexpectedly loaded dialogue events.")


func _test_safe_word_remains_special() -> void:
	var controller = _make_controller("psychological_dialogue_data_source", true)
	_assert(controller.has_safe_word_event(), "Safe-word event disappeared from the merged data source.")
	for condition in CONDITIONS:
		for candidate in controller._get_matching_entries(condition.physical, condition.emotional):
			_assert(candidate.get("condition", {}).get("event", "") != "safe_word", "Safe-word event entered the ordinary condition pool.")
	var safe_word_entry: Dictionary = controller._select_entry(60.0, 60.0, true)
	_assert(safe_word_entry.get("id", "") == "psychological_dialogue_02", "Forced safe-word selection changed: %s" % str(safe_word_entry.get("id", "")))


func _make_controller(data_source_property: String, choices_enabled: bool):
	var controller = DIALOGUE_CONTROLLER_SCRIPT.new()
	controller.configure(data_source_property, choices_enabled)
	controller.set_phase_config(PHASE_CONFIG_SCRIPT.new())
	return controller


func _candidate_ids(candidates: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for candidate in candidates:
		ids.append(String(candidate.get("id", "")))
	ids.sort()
	return ids


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

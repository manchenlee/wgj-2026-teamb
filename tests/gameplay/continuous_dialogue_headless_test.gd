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
	_test_shuffle_bag_and_safe_word_independence()
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
		_assert(candidates.size() == 9, "Psychological %s pool has %d candidates instead of 9." % [condition.suffix, candidates.size()])
		_assert(ids == [
			"psychological_dialogue_01", "psychological_dialogue_03", "psychological_dialogue_04",
			"psychological_dialogue_05", "psychological_dialogue_06", "psychological_dialogue_07",
			"psychological_dialogue_08", "psychological_dialogue_09", "psychological_dialogue_10",
		], "Psychological pool IDs differ from workbook conversations: %s" % str(ids))
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


func _test_shuffle_bag_and_safe_word_independence() -> void:
	var controller = _make_controller("psychological_dialogue_data_source", true)
	controller.rng.seed = 42
	var previous_id := ""
	for cycle in range(3):
		var seen: Dictionary = {}
		for index in range(9):
			var entry: Dictionary = controller._select_entry(60.0, 60.0)
			var entry_id := str(entry.get("id", ""))
			_assert(entry_id != previous_id, "Dialogue repeated immediately on cycle %d draw %d." % [cycle, index])
			_assert(not seen.has(entry_id), "Dialogue repeated before the bag was empty: %s" % entry_id)
			seen[entry_id] = true
			previous_id = entry_id
			controller.reset()
		_assert(seen.size() == 9, "Bag cycle %d did not include all ordinary dialogues." % cycle)
	var first_ordinary: Dictionary = controller._select_entry(60.0, 60.0)
	var remaining: int = controller._ordinary_bag.size()
	var forced_safe_word: Dictionary = controller._select_entry(60.0, 60.0, true)
	_assert(forced_safe_word.get("id", "") == "psychological_dialogue_02", "Forced safe word did not select its event.")
	_assert(controller._ordinary_bag.size() == remaining, "Safe word consumed an ordinary bag entry.")
	_assert(first_ordinary.get("id", "") != "psychological_dialogue_02", "Ordinary bag contained safe word.")
	var saw_random_safe_word := false
	for index in range(100):
		var bag_size_before: int = controller._ordinary_bag.size()
		var entry: Dictionary = controller._select_entry(60.0, 60.0, false, true)
		if entry.get("id", "") == "psychological_dialogue_02":
			_assert(controller._ordinary_bag.size() == bag_size_before, "Random safe word consumed the ordinary bag.")
			saw_random_safe_word = true
			break
	_assert(saw_random_safe_word, "Safe word was not available after its first display.")
	controller.reset(true)
	_assert(controller._last_entry_id.is_empty(), "New run kept the previous dialogue ID.")
	_assert(controller._ordinary_bag.is_empty(), "New run kept the previous ordinary bag.")


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

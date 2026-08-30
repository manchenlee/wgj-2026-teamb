extends SceneTree

const AROUSAL_MODEL_SCRIPT := preload("res://scripts/gameplay/arousal_model.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")
const DIALOGUE_CHOICE_CONTROLLER_SCRIPT := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const ENDING_EVALUATOR_SCRIPT := preload("res://scripts/gameplay/ending_evaluator.gd")
const PHASE_1_CONFIG_SCRIPT := preload("res://data/phases/phase_1_config.gd")
const PHASE_2_CONFIG_SCRIPT := preload("res://data/phases/phase_2_config.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_temporary_physical_depletion_policy()
	_test_legacy_peak_depletion_restoration()
	_test_runtime_physical_depletion_paths()
	_test_imbalance_boundaries()
	_test_ending_priority()
	_test_safe_word_path()
	if _failures.is_empty():
		print("EndingEvaluator headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_temporary_physical_depletion_policy() -> void:
	_assert(CONFIG.USE_PHYSICAL_FOR_DEPLETION_FAILURE, "Temporary physical-depletion policy is not enabled.")
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.0, 50.0, 50.0, false)
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.0, 50.0, 0.0, false)
	_assert_ending("", 50.0, 50.0, 0.0, true)


func _test_legacy_peak_depletion_restoration() -> void:
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 50.0, 50.0, 0.0, true, false)
	_assert_ending("", 0.0, 50.0, 50.0, false, false)
	_assert_ending("", 50.0, 50.0, 0.0, false, false)


func _test_runtime_physical_depletion_paths() -> void:
	var decay_model = _make_model(0.5, 50.0, 50.0, true)
	decay_model.set_phase_config(PHASE_1_CONFIG_SCRIPT.new())
	decay_model.apply_decay(1.0)
	_assert(
		ENDING_EVALUATOR_SCRIPT.evaluate(decay_model, decay_model.phase_config) == CONFIG.PEAK_DEPLETION_FAILURE_ENDING,
		"Passive decay reaching physical zero did not trigger depletion failure."
	)

	var penalty_model = _make_model(2.0, 50.0, 50.0, true)
	penalty_model.apply_physical(-5.0)
	_assert(
		ENDING_EVALUATOR_SCRIPT.evaluate(penalty_model, PHASE_1_CONFIG_SCRIPT.new()) == CONFIG.PEAK_DEPLETION_FAILURE_ENDING,
		"A physiological penalty reaching zero did not trigger depletion failure."
	)


func _test_imbalance_boundaries() -> void:
	for phase_config in [PHASE_1_CONFIG_SCRIPT.new(), PHASE_2_CONFIG_SCRIPT.new()]:
		_assert(float(phase_config.failure_thresholds.get("physical_counterpart_below", -1.0)) == 70.0, "Physical counterpart threshold is not 70 in %s." % phase_config.phase_id)
		_assert(float(phase_config.failure_thresholds.get("emotional_counterpart_below", -1.0)) == 70.0, "Emotional counterpart threshold is not 70 in %s." % phase_config.phase_id)

	var phase_config = PHASE_1_CONFIG_SCRIPT.new()
	_assert_ending(CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 100.0, 69.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 100.0, 69.999, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.SUCCESS_ENDING, 100.0, 70.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.SUCCESS_ENDING, 100.0, 90.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, 69.0, 100.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, 69.999, 100.0, 50.0, true, true, phase_config)
	_assert_ending("", 70.0, 100.0, 50.0, true, true, phase_config)
	_assert_ending("", 90.0, 100.0, 50.0, true, true, phase_config)
	_assert_ending("", 95.0, 10.0, 50.0, true, true, phase_config)


func _test_ending_priority() -> void:
	var phase_config = PHASE_1_CONFIG_SCRIPT.new()
	_assert_ending(CONFIG.SUCCESS_ENDING, 100.0, 70.0, 0.0, false, true, phase_config)
	_assert_ending(CONFIG.SUCCESS_ENDING, 100.0, 100.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.0, 50.0, 100.0, true, true, phase_config)
	_assert_ending(CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 100.0, 60.0, 100.0, true, true, phase_config)
	_assert_ending("", 99.999, 100.0, 100.0, true, true, phase_config)
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.0, 100.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 100.0, 60.0, 50.0, true, true, phase_config)
	_assert_ending(CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, 60.0, 100.0, 50.0, true, true, phase_config)


func _test_safe_word_path() -> void:
	var controller = DIALOGUE_CHOICE_CONTROLLER_SCRIPT.new()
	controller.current_entry = {
		"choice": [{"id": "bad", "effect": "bad_ending"}],
		"response": {"bad": ["safe-word failure"]},
	}
	controller.choice_prompt_pending = true
	var outcome: Dictionary = controller.apply_choice("bad", _make_model(50.0, 50.0, 50.0, true))
	_assert(
		String(outcome.get("ending_type", "")) == CONFIG.SAFEWORD_IGNORED_FAILURE_ENDING,
		"Authored safe-word failure no longer bypasses EndingEvaluator with its existing ID."
	)


func _assert_ending(
		expected: String,
		physical: float,
		emotional: float,
		peak: float,
		peak_has_activated: bool,
		use_physical_for_depletion_failure: bool = true,
		phase_config = null
) -> void:
	var model = _make_model(physical, emotional, peak, peak_has_activated)
	var actual: String = ENDING_EVALUATOR_SCRIPT.evaluate(
		model,
		phase_config,
		use_physical_for_depletion_failure
	)
	_assert(
		actual == expected,
		"Ending for physical %.3f, emotional %.3f, peak %.3f, activated %s, physical policy %s was '%s' instead of '%s'." % [
			physical,
			emotional,
			peak,
			str(peak_has_activated),
			str(use_physical_for_depletion_failure),
			actual,
			expected,
		]
	)


func _make_model(physical: float, emotional: float, peak: float, peak_has_activated: bool):
	var model = AROUSAL_MODEL_SCRIPT.new()
	model.physical = physical
	model.emotional = emotional
	model.peak = peak
	model.peak_has_activated = peak_has_activated
	return model


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

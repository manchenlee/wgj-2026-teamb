extends SceneTree

const AROUSAL_MODEL_SCRIPT := preload("res://scripts/gameplay/arousal_model.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")
const DIALOGUE_CHOICE_CONTROLLER_SCRIPT := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const ENDING_EVALUATOR_SCRIPT := preload("res://scripts/gameplay/ending_evaluator.gd")
const PHASE_1_CONFIG_SCRIPT := preload("res://data/phases/phase_1_config.gd")
const PHASE_2_CONFIG_SCRIPT := preload("res://data/phases/phase_2_config.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_score_boundaries()
	_test_displayed_integer_conversion()
	_test_peak_and_phase_independence()
	_test_safe_word_path()
	if _failures.is_empty():
		print("EndingEvaluator headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_score_boundaries() -> void:
	var cases: Array = [
		[0.0, 0.0, CONFIG.PEAK_DEPLETION_FAILURE_ENDING],
		[0.0, 40.0, ""],
		[40.0, 0.0, ""],
		[100.0, 100.0, CONFIG.SUCCESS_ENDING],
		[100.0, 95.0, CONFIG.SUCCESS_ENDING],
		[95.0, 100.0, CONFIG.SUCCESS_ENDING],
		[100.0, 90.0, CONFIG.SUCCESS_ENDING],
		[90.0, 100.0, CONFIG.SUCCESS_ENDING],
		[100.0, 89.0, ""],
		[100.0, 80.0, ""],
		[100.0, 70.0, ""],
		[100.0, 69.0, CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING],
		[89.0, 100.0, ""],
		[80.0, 100.0, ""],
		[70.0, 100.0, ""],
		[69.0, 100.0, CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING],
		[99.0, 99.0, ""],
	]
	for entry in cases:
		_assert_ending(String(entry[2]), float(entry[0]), float(entry[1]))


func _test_displayed_integer_conversion() -> void:
	# StatusHUD displays int(round(Config.clamp_value(value))).
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, 0.49, 0.49)
	_assert_ending("", 0.5, 0.49)
	_assert_ending(CONFIG.SUCCESS_ENDING, 99.5, 89.5)
	_assert_ending("", 99.49, 89.5)
	_assert_ending("", 99.5, 89.49)
	_assert_ending(CONFIG.PHYSICAL_IMBALANCE_FAILURE_ENDING, 99.5, 69.49)
	_assert_ending("", 99.5, 69.5)
	_assert_ending(CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, 69.49, 99.5)
	_assert_ending("", 69.5, 99.5)
	_assert_ending(CONFIG.PEAK_DEPLETION_FAILURE_ENDING, -1.0, -1.0)
	_assert_ending(CONFIG.SUCCESS_ENDING, 101.0, 95.0)


func _test_peak_and_phase_independence() -> void:
	for phase_config in [null, PHASE_1_CONFIG_SCRIPT.new(), PHASE_2_CONFIG_SCRIPT.new()]:
		for peak in [0.0, 50.0, 100.0]:
			for activated in [false, true]:
				var model = _make_model(100.0, 80.0, peak, activated)
				model.set_phase_config(phase_config)
				_assert(
					ENDING_EVALUATOR_SCRIPT.evaluate(model) == "",
					"100/80 ended with peak %.1f, activation %s, phase %s." % [peak, str(activated), str(phase_config)]
				)
				model.physical = 0.0
				model.emotional = 0.0
				_assert(ENDING_EVALUATOR_SCRIPT.evaluate(model) == CONFIG.PEAK_DEPLETION_FAILURE_ENDING, "0/0 depended on peak or phase.")


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


func _assert_ending(expected: String, physical: float, emotional: float) -> void:
	var actual: String = ENDING_EVALUATOR_SCRIPT.evaluate(_make_model(physical, emotional, 0.0, false))
	_assert(actual == expected, "Ending for physical %.3f, emotional %.3f was '%s' instead of '%s'." % [physical, emotional, actual, expected])


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

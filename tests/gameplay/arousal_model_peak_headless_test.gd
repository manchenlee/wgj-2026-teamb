extends SceneTree

const AROUSAL_MODEL_SCRIPT := preload("res://scripts/gameplay/arousal_model.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")
const PHASE_1_CONFIG_SCRIPT := preload("res://data/phases/phase_1_config.gd")
const PHASE_2_CONFIG_SCRIPT := preload("res://data/phases/phase_2_config.gd")

const EPSILON: float = 0.0001

var _failures: Array[String] = []


func _initialize() -> void:
	_test_perfect_balance_rates_and_times()
	_test_absolute_level_ordering()
	_test_balance_curve()
	_test_minimum_active_threshold()
	_test_negative_loss_is_not_level_scaled()
	_test_zero_score_penalties()
	_test_peak_clamping_and_activation()
	_test_delta_integration()
	_test_phase_formula_parity()
	if _failures.is_empty():
		print("ArousalModel peak headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_perfect_balance_rates_and_times() -> void:
	var cases: Array = [
		[20.0, 0.06, 1666.6667],
		[40.0, 0.24, 416.6667],
		[60.0, 0.54, 185.1852],
		[80.0, 0.96, 104.1667],
		[100.0, 1.5, 66.6667],
	]
	for test_case in cases:
		var score: float = test_case[0]
		var expected_rate: float = test_case[1]
		var expected_seconds: float = test_case[2]
		var actual_rate := _measure_rate(score, score)
		_assert_approx(actual_rate, expected_rate, EPSILON, "Perfect-balance rate at %.0f/%.0f" % [score, score])
		_assert_approx(100.0 / actual_rate, expected_seconds, 0.01, "Ideal time to 100 at %.0f/%.0f" % [score, score])
	_assert_approx(
		CONFIG.MAX_POSITIVE_PEAK_GAIN_RATE,
		1.5,
		EPSILON,
		"Central maximum positive peak rate"
	)


func _test_absolute_level_ordering() -> void:
	var previous_rate := -1.0
	for score in [20.0, 40.0, 60.0, 80.0, 100.0]:
		var current_rate := _measure_rate(score, score)
		_assert(current_rate > previous_rate, "Perfect-balance rate did not increase at %.0f/%.0f." % [score, score])
		previous_rate = current_rate


func _test_balance_curve() -> void:
	var perfect_rate := _measure_rate(100.0, 100.0)
	var difference_five_rate := _measure_rate(100.0, 95.0)
	var difference_ten_rate := _measure_rate(100.0, 90.0)
	var difference_fifteen_rate := _measure_rate(100.0, 85.0)
	var difference_thirty_rate := _measure_rate(100.0, 70.0)
	var same_level_maximum := CONFIG.MAX_POSITIVE_PEAK_GAIN_RATE * 0.95 * 0.95
	_assert(perfect_rate > difference_five_rate, "Perfect balance was not the strongest positive case.")
	_assert_approx(difference_five_rate, same_level_maximum * 0.2, EPSILON, "Difference-five balance factor")
	_assert(difference_five_rate > difference_ten_rate, "Positive balance gain did not decline from difference 5 to 10.")
	_assert_approx(difference_fifteen_rate, 0.0, EPSILON, "Difference-fifteen neutral rate")
	_assert_approx(difference_thirty_rate, -2.0, EPSILON, "Difference-thirty ordinary loss")


func _test_minimum_active_threshold() -> void:
	_assert_approx(_measure_rate(19.0, 19.0), 0.0, EPSILON, "Both scores below the active threshold")
	_assert_approx(_measure_rate(19.0, 20.0), 0.0, EPSILON, "One score below the active threshold")
	_assert_approx(_measure_rate(20.0, 20.0), 0.06, EPSILON, "Inclusive active threshold")


func _test_negative_loss_is_not_level_scaled() -> void:
	var low_level_loss := _measure_rate(40.0, 20.0)
	var high_level_loss := _measure_rate(100.0, 80.0)
	_assert_approx(low_level_loss, high_level_loss, EPSILON, "Level-independent imbalance loss")
	_assert_approx(low_level_loss, -2.0 / 3.0, EPSILON, "Difference-twenty loss rate")


func _test_zero_score_penalties() -> void:
	var both_zero_model = AROUSAL_MODEL_SCRIPT.new()
	both_zero_model.physical = 0.0
	both_zero_model.emotional = 0.0
	both_zero_model.peak = 10.0
	both_zero_model.peak_has_activated = true
	both_zero_model.update_peak(1.0)
	_assert_approx(both_zero_model.peak, 4.0, EPSILON, "Two independent zero-score penalties")

	var one_zero_model = AROUSAL_MODEL_SCRIPT.new()
	one_zero_model.physical = 0.0
	one_zero_model.emotional = 10.0
	one_zero_model.peak = 10.0
	one_zero_model.peak_has_activated = true
	one_zero_model.update_peak(1.0)
	_assert_approx(one_zero_model.peak, 7.0, EPSILON, "One zero-score penalty")


func _test_peak_clamping_and_activation() -> void:
	var upper_model = AROUSAL_MODEL_SCRIPT.new()
	upper_model.physical = 100.0
	upper_model.emotional = 100.0
	upper_model.peak = 99.9
	upper_model.update_peak(1.0)
	_assert_approx(upper_model.peak, 100.0, EPSILON, "Upper peak clamp")
	_assert(upper_model.peak_has_activated, "Positive peak did not activate the historical flag.")

	var lower_model = AROUSAL_MODEL_SCRIPT.new()
	lower_model.physical = 100.0
	lower_model.emotional = 70.0
	lower_model.peak = 0.5
	lower_model.peak_has_activated = true
	lower_model.update_peak(1.0)
	_assert_approx(lower_model.peak, 0.0, EPSILON, "Lower peak clamp")
	_assert(lower_model.peak_has_activated, "Peak activation flag was cleared by depletion.")

	var inactive_model = AROUSAL_MODEL_SCRIPT.new()
	inactive_model.physical = 0.0
	inactive_model.emotional = 0.0
	inactive_model.update_peak(1.0)
	_assert_approx(inactive_model.peak, 0.0, EPSILON, "Inactive zero peak clamp")
	_assert(not inactive_model.peak_has_activated, "A clamped zero peak falsely activated the historical flag.")


func _test_delta_integration() -> void:
	var one_step_model = AROUSAL_MODEL_SCRIPT.new()
	one_step_model.physical = 80.0
	one_step_model.emotional = 80.0
	one_step_model.update_peak(10.0)

	var many_step_model = AROUSAL_MODEL_SCRIPT.new()
	many_step_model.physical = 80.0
	many_step_model.emotional = 80.0
	for step in range(100):
		many_step_model.update_peak(0.1)
	_assert_approx(one_step_model.peak, 9.6, EPSILON, "One-step time integration")
	_assert_approx(many_step_model.peak, one_step_model.peak, 0.001, "Frame-rate-independent time integration")


func _test_phase_formula_parity() -> void:
	var phase_1 = PHASE_1_CONFIG_SCRIPT.new()
	var phase_2 = PHASE_2_CONFIG_SCRIPT.new()
	_assert_approx(
		phase_1.max_positive_peak_gain_rate,
		phase_2.max_positive_peak_gain_rate,
		EPSILON,
		"Phase maximum positive-rate parity"
	)
	for scores in [[100.0, 100.0], [100.0, 95.0], [100.0, 70.0], [0.0, 0.0]]:
		var phase_1_rate := _measure_rate(scores[0], scores[1], phase_1)
		var phase_2_rate := _measure_rate(scores[0], scores[1], phase_2)
		_assert_approx(phase_1_rate, phase_2_rate, EPSILON, "Phase formula parity at %s" % [str(scores)])


func _measure_rate(physical: float, emotional: float, phase_config = null) -> float:
	var model = AROUSAL_MODEL_SCRIPT.new()
	if phase_config != null:
		model.set_phase_config(phase_config)
	model.physical = physical
	model.emotional = emotional
	model.peak = 50.0
	model.peak_has_activated = true
	model.update_peak(1.0)
	return model.peak - 50.0


func _assert_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert(
		absf(actual - expected) <= tolerance,
		"%s was %.6f instead of %.6f." % [label, actual, expected]
	)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

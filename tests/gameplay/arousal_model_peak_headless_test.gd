extends SceneTree

const AROUSAL_MODEL_SCRIPT := preload("res://scripts/gameplay/arousal_model.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")
const PHASE_1_CONFIG_SCRIPT := preload("res://data/phases/phase_1_config.gd")
const PHASE_2_CONFIG_SCRIPT := preload("res://data/phases/phase_2_config.gd")

const EPSILON: float = 0.0001

var _failures: Array[String] = []


func _initialize() -> void:
	_test_perfect_balance_rates()
	_test_level_factor_floor_and_cap()
	_test_balance_curve()
	_test_minimum_active_threshold()
	_test_negative_loss_is_not_level_scaled()
	_test_zero_score_penalties()
	_test_physical_and_emotional_clamping()
	_test_peak_clamping_and_activation()
	_test_delta_integration()
	_test_phase_configuration_is_applied()
	if _failures.is_empty():
		print("ArousalModel peak headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_perfect_balance_rates() -> void:
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var scores: Array[float] = [
		config.minimum_active_threshold,
		config.peak_full_gain_level,
		CONFIG.MAX_VALUE,
	]
	for score in scores:
		var level := clampf(score / config.peak_full_gain_level, 0.0, 1.0)
		var expected_level_factor := maxf(level * level, config.minimum_peak_level_factor)
		var expected_rate: float = config.max_positive_peak_gain_rate * expected_level_factor
		var actual_rate := _measure_rate(score, score, config)
		_assert_approx(actual_rate, expected_rate, EPSILON, "Perfect-balance rate at %.0f/%.0f" % [score, score])
		_assert(actual_rate > 0.0, "Perfect-balance rate was not positive at %.0f/%.0f." % [score, score])


func _test_level_factor_floor_and_cap() -> void:
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var threshold_rate := _measure_rate(
		config.minimum_active_threshold,
		config.minimum_active_threshold,
		config
	)
	var full_rate := _measure_rate(config.peak_full_gain_level, config.peak_full_gain_level, config)
	var capped_rate := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE, config)
	_assert_approx(
		threshold_rate,
		config.max_positive_peak_gain_rate * config.minimum_peak_level_factor,
		EPSILON,
		"Minimum positive level factor"
	)
	_assert_approx(full_rate, config.max_positive_peak_gain_rate, EPSILON, "Full-gain level")
	_assert_approx(capped_rate, full_rate, EPSILON, "Level factor upper cap")


func _test_balance_curve() -> void:
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var perfect_rate := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE, config)
	var difference_five_rate := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE - config.peak_balance_best_diff, config)
	var middle_difference: float = (config.peak_balance_best_diff + config.peak_balance_ok_diff) * 0.5
	var difference_ten_rate := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE - middle_difference, config)
	var difference_fifteen_rate := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE - config.peak_balance_ok_diff, config)
	var difference_thirty_rate := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE - config.peak_balance_fail_diff, config)
	_assert(perfect_rate > difference_five_rate, "Perfect balance was not the strongest positive case.")
	_assert(difference_five_rate > difference_ten_rate, "Positive balance gain did not decline from difference 5 to 10.")
	_assert_approx(difference_fifteen_rate, 0.0, EPSILON, "Difference-fifteen neutral rate")
	_assert_approx(difference_thirty_rate, -config.peak_loss_rate_imbalanced, EPSILON, "Difference-thirty ordinary loss")


func _test_minimum_active_threshold() -> void:
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var below_threshold: float = config.minimum_active_threshold - 1.0
	_assert_approx(_measure_rate(below_threshold, below_threshold, config), 0.0, EPSILON, "Both scores below the active threshold")
	_assert_approx(_measure_rate(below_threshold, config.minimum_active_threshold, config), 0.0, EPSILON, "One score below the active threshold")
	_assert(_measure_rate(config.minimum_active_threshold, config.minimum_active_threshold, config) > 0.0, "Inclusive active threshold did not gain peak.")


func _test_negative_loss_is_not_level_scaled() -> void:
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var loss_difference: float = (config.peak_balance_ok_diff + config.peak_balance_fail_diff) * 0.5
	var low_level_loss := _measure_rate(config.peak_full_gain_level, config.peak_full_gain_level - loss_difference, config)
	var high_level_loss := _measure_rate(CONFIG.MAX_VALUE, CONFIG.MAX_VALUE - loss_difference, config)
	_assert_approx(low_level_loss, high_level_loss, EPSILON, "Level-independent imbalance loss")
	_assert(low_level_loss < 0.0, "Imbalanced scores did not lose peak.")


func _test_zero_score_penalties() -> void:
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var both_zero_model = AROUSAL_MODEL_SCRIPT.new()
	both_zero_model.set_phase_config(config)
	both_zero_model.physical = 0.0
	both_zero_model.emotional = 0.0
	both_zero_model.peak = 10.0
	both_zero_model.peak_has_activated = true
	both_zero_model.update_peak(1.0)
	_assert_approx(both_zero_model.peak, 10.0 - config.peak_zero_value_extra_loss_rate * 2.0, EPSILON, "Two independent zero-score penalties")

	var one_zero_model = AROUSAL_MODEL_SCRIPT.new()
	one_zero_model.set_phase_config(config)
	one_zero_model.physical = 0.0
	one_zero_model.emotional = 10.0
	one_zero_model.peak = 10.0
	one_zero_model.peak_has_activated = true
	one_zero_model.update_peak(1.0)
	_assert_approx(one_zero_model.peak, 10.0 - config.peak_zero_value_extra_loss_rate, EPSILON, "One zero-score penalty")


func _test_physical_and_emotional_clamping() -> void:
	var model = AROUSAL_MODEL_SCRIPT.new()
	model.physical = 90.0
	model.apply_physical(20.0)
	_assert_approx(model.physical, 100.0, EPSILON, "Upper physical clamp")
	model.apply_physical(-120.0)
	_assert_approx(model.physical, 0.0, EPSILON, "Lower physical clamp")

	model.emotional = 90.0
	model.apply_emotional(20.0)
	_assert_approx(model.emotional, 100.0, EPSILON, "Upper emotional clamp")
	model.apply_emotional(-120.0)
	_assert_approx(model.emotional, 0.0, EPSILON, "Lower emotional clamp")


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
	var config = PHASE_1_CONFIG_SCRIPT.new()
	var one_step_model = AROUSAL_MODEL_SCRIPT.new()
	one_step_model.set_phase_config(config)
	one_step_model.physical = 80.0
	one_step_model.emotional = 80.0
	one_step_model.update_peak(10.0)

	var many_step_model = AROUSAL_MODEL_SCRIPT.new()
	many_step_model.set_phase_config(config)
	many_step_model.physical = 80.0
	many_step_model.emotional = 80.0
	for step in range(100):
		many_step_model.update_peak(0.1)
	_assert_approx(one_step_model.peak, config.max_positive_peak_gain_rate * 10.0, EPSILON, "One-step time integration")
	_assert_approx(many_step_model.peak, one_step_model.peak, 0.001, "Frame-rate-independent time integration")


func _test_phase_configuration_is_applied() -> void:
	for config in [PHASE_1_CONFIG_SCRIPT.new(), PHASE_2_CONFIG_SCRIPT.new()]:
		var rate := _measure_rate(
			config.peak_full_gain_level,
			config.peak_full_gain_level,
			config
		)
		_assert_approx(
			rate,
			config.max_positive_peak_gain_rate,
			EPSILON,
			"Configured full-gain rate for %s" % [config.phase_id]
		)


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

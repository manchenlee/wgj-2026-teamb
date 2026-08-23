class_name ArousalModel
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

const POSITIVE_BALANCE_FACTOR_AT_BEST_THRESHOLD: float = 0.2

var phase_config = null
var physical: float = 40.0
var emotional: float = 40.0
var peak: float = 0.0
var physical_activity_grace_remaining: float = 0.0
var emotional_activity_grace_remaining: float = 0.0
var peak_has_activated: bool = false

func set_phase_config(next_phase_config) -> void:
	phase_config = next_phase_config

func reset() -> void:
	physical = _get_config_value("starting_physical_value", 40.0)
	emotional = _get_config_value("starting_emotional_value", 40.0)
	peak = _get_config_value("starting_peak_value", 0.0)
	physical_activity_grace_remaining = 0.0
	emotional_activity_grace_remaining = 0.0
	peak_has_activated = peak > 0.0

func apply_physical(delta_value: float) -> void:
	physical = Config.clamp_value(physical + delta_value)

func apply_emotional(delta_value: float) -> void:
	emotional = Config.clamp_value(emotional + delta_value)

func refresh_physical_activity() -> void:
	physical_activity_grace_remaining = _get_config_value("physical_activity_grace_seconds", 1.4)

func refresh_emotional_activity() -> void:
	emotional_activity_grace_remaining = _get_config_value("emotional_activity_grace_seconds", 2.8)

func apply_decay(delta: float) -> void:
	physical_activity_grace_remaining = maxf(physical_activity_grace_remaining - delta, 0.0)
	emotional_activity_grace_remaining = maxf(emotional_activity_grace_remaining - delta, 0.0)

	if physical_activity_grace_remaining <= 0.0:
		physical = Config.clamp_value(physical - _get_config_value("physical_decay_rate", 2.0) * delta)
	if emotional_activity_grace_remaining <= 0.0:
		emotional = Config.clamp_value(emotional - _get_config_value("emotional_decay_rate", 0.5) * delta)

func update_peak(delta: float) -> void:
	var difference := absf(physical - emotional)
	var minimum_active_threshold: float = float(_get_config_value("minimum_active_threshold", 20.0))
	var both_active: bool = physical >= minimum_active_threshold and emotional >= minimum_active_threshold
	var zero_value_count := 0
	if physical <= 0.0:
		zero_value_count += 1
	if emotional <= 0.0:
		zero_value_count += 1

	var peak_rate := _get_peak_rate(difference, both_active)
	peak_rate -= float(_get_config_value("peak_zero_value_extra_loss_rate", 3.0)) * zero_value_count

	peak = Config.clamp_value(peak + peak_rate * delta)
	if peak > 0.0:
		peak_has_activated = true

func _get_peak_rate(difference: float, both_active: bool) -> float:
	var peak_balance_best_diff: float = float(_get_config_value("peak_balance_best_diff", 5.0))
	var peak_balance_ok_diff: float = float(_get_config_value("peak_balance_ok_diff", 15.0))
	var peak_balance_fail_diff: float = float(_get_config_value("peak_balance_fail_diff", 30.0))
	var peak_loss_rate_imbalanced: float = float(_get_config_value("peak_loss_rate_imbalanced", 2.0))

	if difference <= peak_balance_ok_diff:
		if not both_active:
			return 0.0
		var balance_factor := _get_positive_balance_factor(
			difference,
			peak_balance_best_diff,
			peak_balance_ok_diff
		)
		var level := clampf(minf(physical, emotional) / Config.MAX_VALUE, 0.0, 1.0)
		var level_factor := level * level
		var max_positive_rate: float = float(_get_config_value(
			"max_positive_peak_gain_rate",
			Config.MAX_POSITIVE_PEAK_GAIN_RATE
		))
		return max_positive_rate * balance_factor * level_factor
	if difference <= peak_balance_fail_diff:
		var fail_t := inverse_lerp(peak_balance_ok_diff, peak_balance_fail_diff, difference)
		return lerpf(0.0, -peak_loss_rate_imbalanced, fail_t)
	return -peak_loss_rate_imbalanced

func _get_positive_balance_factor(
		difference: float,
		peak_balance_best_diff: float,
		peak_balance_ok_diff: float
) -> float:
	if difference <= peak_balance_best_diff:
		var best_t := difference / maxf(peak_balance_best_diff, 0.001)
		return lerpf(1.0, POSITIVE_BALANCE_FACTOR_AT_BEST_THRESHOLD, best_t)
	var ok_t := inverse_lerp(peak_balance_best_diff, peak_balance_ok_diff, difference)
	return lerpf(POSITIVE_BALANCE_FACTOR_AT_BEST_THRESHOLD, 0.0, ok_t)

func get_emotion_state() -> String:
	var average := (physical + emotional) * 0.5
	if average <= 10.0:
		return "SAD"
	if average <= 25.0:
		return "UNEASY"
	if average <= 45.0:
		return "CALM"
	if average <= 65.0:
		return "ENGAGED"
	return "EXCITED"

func _get_config_value(property_name: String, fallback: Variant) -> Variant:
	if phase_config != null:
		return phase_config.get(property_name)
	return fallback

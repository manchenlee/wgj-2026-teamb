class_name ArousalModel
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var physical: float = Config.INITIAL_PHYSICAL
var emotional: float = Config.INITIAL_EMOTIONAL
var peak: float = Config.INITIAL_PEAK
var physical_activity_grace_remaining: float = 0.0
var emotional_activity_grace_remaining: float = 0.0
var peak_has_activated: bool = false

func reset() -> void:
	physical = Config.INITIAL_PHYSICAL
	emotional = Config.INITIAL_EMOTIONAL
	peak = Config.INITIAL_PEAK
	physical_activity_grace_remaining = 0.0
	emotional_activity_grace_remaining = 0.0
	peak_has_activated = peak > 0.0

func apply_physical(delta_value: float) -> void:
	physical = Config.clamp_value(physical + delta_value)

func apply_emotional(delta_value: float) -> void:
	emotional = Config.clamp_value(emotional + delta_value)

func refresh_physical_activity() -> void:
	physical_activity_grace_remaining = Config.PHYSICAL_ACTIVITY_GRACE_SECONDS

func refresh_emotional_activity() -> void:
	emotional_activity_grace_remaining = Config.EMOTIONAL_ACTIVITY_GRACE_SECONDS

func apply_decay(delta: float) -> void:
	physical_activity_grace_remaining = maxf(physical_activity_grace_remaining - delta, 0.0)
	emotional_activity_grace_remaining = maxf(emotional_activity_grace_remaining - delta, 0.0)

	if physical_activity_grace_remaining <= 0.0:
		physical = Config.clamp_value(physical - Config.PHYSICAL_DECAY_PER_SECOND * delta)
	if emotional_activity_grace_remaining <= 0.0:
		emotional = Config.clamp_value(emotional - Config.EMOTIONAL_DECAY_PER_SECOND * delta)

func update_peak(delta: float) -> void:
	var difference := absf(physical - emotional)
	var both_active := physical >= Config.MINIMUM_ACTIVE_THRESHOLD and emotional >= Config.MINIMUM_ACTIVE_THRESHOLD
	var zero_value_count := 0
	if physical <= 0.0:
		zero_value_count += 1
	if emotional <= 0.0:
		zero_value_count += 1

	var peak_rate := _get_peak_rate_from_difference(difference)
	if not both_active and peak_rate > 0.0:
		peak_rate = 0.0
	if peak_rate < 0.0:
		peak_rate -= Config.PEAK_ZERO_VALUE_EXTRA_LOSS_RATE * zero_value_count

	if peak_rate >= 0.0:
		peak = Config.clamp_value(peak + peak_rate * delta)
	else:
		peak = Config.clamp_value(peak + peak_rate * delta)
	if peak > 0.0:
		peak_has_activated = true

func _get_peak_rate_from_difference(difference: float) -> float:
	if difference <= Config.PEAK_BALANCE_BEST_DIFF:
		var best_t := difference / maxf(Config.PEAK_BALANCE_BEST_DIFF, 0.001)
		return lerpf(Config.PEAK_GAIN_RATE_MAX, Config.PEAK_GAIN_RATE_MIN, best_t)
	if difference <= Config.PEAK_BALANCE_OK_DIFF:
		var ok_t := inverse_lerp(
			Config.PEAK_BALANCE_BEST_DIFF,
			Config.PEAK_BALANCE_OK_DIFF,
			difference
		)
		return lerpf(Config.PEAK_GAIN_RATE_MIN, 0.0, ok_t)
	if difference <= Config.PEAK_BALANCE_FAIL_DIFF:
		var fail_t := inverse_lerp(
			Config.PEAK_BALANCE_OK_DIFF,
			Config.PEAK_BALANCE_FAIL_DIFF,
			difference
		)
		return lerpf(0.0, -Config.PEAK_LOSS_RATE_IMBALANCED, fail_t)
	return -Config.PEAK_LOSS_RATE_IMBALANCED

func get_emotion_state() -> String:
	var average := (physical + emotional) * 0.5
	if average <= 15.0:
		return "SAD"
	if average <= 35.0:
		return "UNEASY"
	if average <= 60.0:
		return "CALM"
	if average <= 80.0:
		return "ENGAGED"
	return "EXCITED"

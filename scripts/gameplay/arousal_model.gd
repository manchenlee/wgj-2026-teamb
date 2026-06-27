class_name ArousalModel
extends RefCounted

const Config := preload("res://scripts/core/game_config.gd")

var physical: float = Config.INITIAL_PHYSICAL
var emotional: float = Config.INITIAL_EMOTIONAL
var peak: float = Config.INITIAL_PEAK

func reset() -> void:
	physical = Config.INITIAL_PHYSICAL
	emotional = Config.INITIAL_EMOTIONAL
	peak = Config.INITIAL_PEAK

func apply_physical(delta_value: float) -> void:
	physical = Config.clamp_value(physical + delta_value)

func apply_emotional(delta_value: float) -> void:
	emotional = Config.clamp_value(emotional + delta_value)

func apply_decay(delta: float) -> void:
	var decay_amount := Config.NATURAL_DECAY_PER_SECOND * delta
	physical = Config.clamp_value(physical - decay_amount)
	emotional = Config.clamp_value(emotional - decay_amount)

func update_peak(delta: float) -> void:
	var difference := absf(physical - emotional)
	var both_active := physical >= Config.MINIMUM_ACTIVE_THRESHOLD and emotional >= Config.MINIMUM_ACTIVE_THRESHOLD
	var is_balanced := difference <= Config.BALANCE_TOLERANCE

	# Peak rises only when both values are active and close enough together.
	if both_active and is_balanced:
		var balance_ratio := 1.0 - (difference / maxf(Config.BALANCE_TOLERANCE, 1.0))
		peak = Config.clamp_value(peak + Config.PEAK_GAIN_RATE * balance_ratio * delta)
	else:
		peak = Config.clamp_value(peak - Config.PEAK_LOSS_RATE * delta)

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

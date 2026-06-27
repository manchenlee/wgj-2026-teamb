class_name EndingEvaluator
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

static func evaluate(model) -> String:
	if model.peak >= Config.MAX_VALUE:
		return Config.SUCCESS_ENDING
	if model.peak_has_activated and model.peak <= 0.0:
		return Config.PEAK_DEPLETION_FAILURE_ENDING
	if model.physical >= Config.MAX_VALUE and model.emotional < Config.MINIMUM_ACTIVE_THRESHOLD:
		return Config.PHYSICAL_IMBALANCE_FAILURE_ENDING
	if model.emotional >= Config.MAX_VALUE and model.physical < Config.MINIMUM_ACTIVE_THRESHOLD:
		return Config.EMOTIONAL_IMBALANCE_FAILURE_ENDING
	return ""

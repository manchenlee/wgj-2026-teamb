class_name EndingEvaluator
extends RefCounted

const Config := preload("res://scripts/core/game_config.gd")

static func evaluate(model) -> String:
	if model.peak >= Config.MAX_VALUE:
		return Config.SUCCESS_ENDING
	if model.physical <= 0.0:
		return Config.PHYSICAL_FAILURE_ENDING
	if model.emotional <= 0.0:
		return Config.EMOTIONAL_FAILURE_ENDING
	return ""

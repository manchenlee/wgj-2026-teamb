class_name EndingEvaluator
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

static func evaluate(model) -> String:
	# Match the integer scores shown by StatusHUD.update_values().
	var physical_score: int = int(round(Config.clamp_value(model.physical)))
	var emotional_score: int = int(round(Config.clamp_value(model.emotional)))
	var difference: int = absi(physical_score - emotional_score)

	if physical_score == 0 and emotional_score == 0:
		return Config.PEAK_DEPLETION_FAILURE_ENDING
	if (physical_score == 100 or emotional_score == 100) and difference <= 10:
		return Config.SUCCESS_ENDING
	if physical_score == 100 and physical_score - emotional_score > 30:
		return Config.PHYSICAL_IMBALANCE_FAILURE_ENDING
	if emotional_score == 100 and emotional_score - physical_score > 30:
		return Config.EMOTIONAL_IMBALANCE_FAILURE_ENDING
	return ""

class_name EndingEvaluator
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

static func evaluate(
		model,
		phase_config = null,
		use_physical_for_depletion_failure: bool = Config.USE_PHYSICAL_FOR_DEPLETION_FAILURE
) -> String:
	var success_condition := {"type": "peak_at_or_above", "value": Config.MAX_VALUE}
	var failure_thresholds := {
		"peak_depletion_requires_activation": true,
		"physical_cap": Config.MAX_VALUE,
		"physical_counterpart_below": 70.0,
		"emotional_cap": Config.MAX_VALUE,
		"emotional_counterpart_below": 70.0
	}
	if phase_config != null:
		success_condition = phase_config.success_condition
		failure_thresholds = phase_config.failure_thresholds

	if str(success_condition.get("type", "")) == "peak_at_or_above" and model.peak >= float(success_condition.get("value", Config.MAX_VALUE)):
		return Config.SUCCESS_ENDING
	var depletion_failure: bool = model.physical <= 0.0 if use_physical_for_depletion_failure else (
		bool(failure_thresholds.get("peak_depletion_requires_activation", true))
		and model.peak_has_activated
		and model.peak <= 0.0
	)
	if depletion_failure:
		return Config.PEAK_DEPLETION_FAILURE_ENDING
	if model.physical >= float(failure_thresholds.get("physical_cap", Config.MAX_VALUE)) and model.emotional < float(failure_thresholds.get("physical_counterpart_below", 70.0)):
		return Config.PHYSICAL_IMBALANCE_FAILURE_ENDING
	if model.emotional >= float(failure_thresholds.get("emotional_cap", Config.MAX_VALUE)) and model.physical < float(failure_thresholds.get("emotional_counterpart_below", 70.0)):
		return Config.EMOTIONAL_IMBALANCE_FAILURE_ENDING
	return ""

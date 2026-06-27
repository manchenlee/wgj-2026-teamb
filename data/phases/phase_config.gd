class_name PhaseConfig
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var phase_id: String
var starting_physical_value: float
var starting_emotional_value: float
var starting_peak_value: float
var physical_decay_rate: float
var emotional_decay_rate: float
var physical_activity_grace_seconds: float
var emotional_activity_grace_seconds: float

# Interaction Spot (Physical Arousal) — new system
var spot_lifetime: float
var spot_required_scrub_distance: float
var spot_valid_motion_threshold: float
var spot_max_delta_per_event: float
var spot_physical_gain_per_px: float
var spot_completion_bonus: float
var spot_expiry_penalty_ignored: float
var spot_expiry_penalty_partial: float
var spot_radius: float
var spot_spawn_delay_min: float
var spot_spawn_delay_max: float
var spot_max_active_count: int

# LEGACY: Direction-sequence physical interaction (disabled, retained for rollback)
var direction_sequence_length_min: int
var direction_sequence_length_max: int
var direction_prompt_time_limit: float
var next_prompt_reveal_delay: float
var prompt_spawn_delay_min: float
var prompt_spawn_delay_max: float
var direction_reward_values: Dictionary
var direction_penalty_values: Dictionary
var choice_reward_values: Dictionary
var choice_penalty_values: Dictionary
var choice_timeout_seconds: float
var feedback_message_interval_min: float
var feedback_message_interval_max: float
var feedback_physical_low_threshold: float
var feedback_emotional_low_threshold: float
var feedback_emotional_high_threshold: float
var minimum_active_threshold: float
var overall_medium_threshold: float
var overall_high_threshold: float
var overall_peak_threshold: float
var peak_balance_best_diff: float
var peak_balance_ok_diff: float
var peak_balance_fail_diff: float
var peak_gain_rate_max: float
var peak_gain_rate_min: float
var peak_loss_rate_imbalanced: float
var peak_zero_value_extra_loss_rate: float
var success_condition: Dictionary
var failure_thresholds: Dictionary
var dialogue_data_source: String
var character_profile
var overlay_animation_set: Dictionary
var prompt_anchor_profile_id: String
var transition_feedback_text: String

func _init(values: Dictionary = {}) -> void:
	phase_id = String(values.get("phase_id", "phase"))
	starting_physical_value = float(values.get("starting_physical_value", 40.0))
	starting_emotional_value = float(values.get("starting_emotional_value", 40.0))
	starting_peak_value = float(values.get("starting_peak_value", 0.0))
	physical_decay_rate = float(values.get("physical_decay_rate", 2.0))
	emotional_decay_rate = float(values.get("emotional_decay_rate", 0.5))
	physical_activity_grace_seconds = float(values.get("physical_activity_grace_seconds", 1.4))
	emotional_activity_grace_seconds = float(values.get("emotional_activity_grace_seconds", 2.8))

	# Interaction Spot (Physical Arousal) — new system
	# Defaults reference GameConfig constants so changing GameConfig.gd takes effect immediately.
	spot_lifetime = float(values.get("spot_lifetime", Config.SPOT_LIFETIME))
	spot_required_scrub_distance = float(values.get("spot_required_scrub_distance", Config.SPOT_REQUIRED_SCRUB_DISTANCE))
	spot_valid_motion_threshold = float(values.get("spot_valid_motion_threshold", Config.SPOT_VALID_MOTION_THRESHOLD))
	spot_max_delta_per_event = float(values.get("spot_max_delta_per_event", Config.SPOT_MAX_DELTA_PER_EVENT))
	spot_physical_gain_per_px = float(values.get("spot_physical_gain_per_px", Config.SPOT_PHYSICAL_GAIN_PER_PX))
	spot_completion_bonus = float(values.get("spot_completion_bonus", Config.SPOT_COMPLETION_BONUS))
	spot_expiry_penalty_ignored = float(values.get("spot_expiry_penalty_ignored", Config.SPOT_EXPIRY_PENALTY_IGNORED))
	spot_expiry_penalty_partial = float(values.get("spot_expiry_penalty_partial", Config.SPOT_EXPIRY_PENALTY_PARTIAL))
	spot_radius = float(values.get("spot_radius", Config.SPOT_RADIUS))
	spot_spawn_delay_min = float(values.get("spot_spawn_delay_min", Config.SPOT_SPAWN_DELAY_MIN))
	spot_spawn_delay_max = float(values.get("spot_spawn_delay_max", Config.SPOT_SPAWN_DELAY_MAX))
	spot_max_active_count = int(values.get("spot_max_active_count", Config.SPOT_MAX_ACTIVE_COUNT))

	# LEGACY: direction-sequence fields — disabled, retained for rollback
	direction_sequence_length_min = int(values.get("direction_sequence_length_min", 3))
	direction_sequence_length_max = int(values.get("direction_sequence_length_max", 4))
	direction_prompt_time_limit = float(values.get("direction_prompt_time_limit", 2.4))
	next_prompt_reveal_delay = float(values.get("next_prompt_reveal_delay", 0.9))
	prompt_spawn_delay_min = float(values.get("prompt_spawn_delay_min", 1.1))
	prompt_spawn_delay_max = float(values.get("prompt_spawn_delay_max", 1.5))
	direction_reward_values = values.get("direction_reward_values", {}).duplicate(true)
	direction_penalty_values = values.get("direction_penalty_values", {}).duplicate(true)
	choice_reward_values = values.get("choice_reward_values", {}).duplicate(true)
	choice_penalty_values = values.get("choice_penalty_values", {}).duplicate(true)
	choice_timeout_seconds = float(values.get("choice_timeout_seconds", 5.0))
	feedback_message_interval_min = float(values.get("feedback_message_interval_min", 2.0))
	feedback_message_interval_max = float(values.get("feedback_message_interval_max", 4.0))
	feedback_physical_low_threshold = float(values.get("feedback_physical_low_threshold", 30.0))
	feedback_emotional_low_threshold = float(values.get("feedback_emotional_low_threshold", 30.0))
	feedback_emotional_high_threshold = float(values.get("feedback_emotional_high_threshold", 60.0))
	minimum_active_threshold = float(values.get("minimum_active_threshold", 20.0))
	overall_medium_threshold = float(values.get("overall_medium_threshold", minimum_active_threshold))
	overall_high_threshold = float(values.get("overall_high_threshold", feedback_emotional_high_threshold))
	overall_peak_threshold = float(values.get("overall_peak_threshold", 100.0))
	peak_balance_best_diff = float(values.get("peak_balance_best_diff", 5.0))
	peak_balance_ok_diff = float(values.get("peak_balance_ok_diff", 15.0))
	peak_balance_fail_diff = float(values.get("peak_balance_fail_diff", 30.0))
	peak_gain_rate_max = float(values.get("peak_gain_rate_max", 5.0))
	peak_gain_rate_min = float(values.get("peak_gain_rate_min", 1.0))
	peak_loss_rate_imbalanced = float(values.get("peak_loss_rate_imbalanced", 2.0))
	peak_zero_value_extra_loss_rate = float(values.get("peak_zero_value_extra_loss_rate", 3.0))
	success_condition = values.get("success_condition", {"type": "peak_at_or_above", "value": overall_peak_threshold}).duplicate(true)
	failure_thresholds = values.get(
		"failure_thresholds",
		{
			"peak_depletion_requires_activation": true,
			"physical_cap": 100.0,
			"physical_counterpart_below": minimum_active_threshold,
			"emotional_cap": 100.0,
			"emotional_counterpart_below": minimum_active_threshold
		}
	).duplicate(true)
	dialogue_data_source = String(values.get("dialogue_data_source", ""))
	character_profile = values.get("character_profile", null)
	overlay_animation_set = values.get("overlay_animation_set", {}).duplicate(true)
	prompt_anchor_profile_id = String(values.get("prompt_anchor_profile_id", phase_id))
	transition_feedback_text = String(values.get("transition_feedback_text", ""))

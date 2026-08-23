extends PhaseConfig

func _init() -> void:
	super._init(
		{
			"phase_id": "phase_1",
			"starting_physical_value": 40.0,
			"starting_emotional_value": 40.0,
			"starting_peak_value": 0.0,
			"physical_decay_rate": 2.0,
			"emotional_decay_rate": 0.5,
			"physical_activity_grace_seconds": 1.4,
			"emotional_activity_grace_seconds": 2.8,
			# Interaction Spot — values reference GameConfig so editing GameConfig.gd takes effect immediately.
			"click_note_lifetime":          Config.CLICK_NOTE_LIFETIME,
			"slide_checkpoint_time_limit":  Config.SLIDE_CHECKPOINT_TIME_LIMIT,
			"rub_note_lifetime":            Config.RUB_NOTE_LIFETIME,
			"spot_required_checkpoint_count": Config.SPOT_REQUIRED_CHECKPOINT_COUNT,
			"spot_checkpoint_radius":       Config.SPOT_CHECKPOINT_RADIUS,
			"spot_checkpoint_spacing":      Config.SPOT_CHECKPOINT_SPACING,
			"spot_progress_gain_total":     Config.SPOT_PROGRESS_GAIN_TOTAL,
			"spot_completion_bonus":        Config.SPOT_COMPLETION_BONUS,
			"spot_expiry_penalty_ignored":  Config.SPOT_EXPIRY_PENALTY_IGNORED,
			"spot_expiry_penalty_partial":  Config.SPOT_EXPIRY_PENALTY_PARTIAL,
			"spot_spawn_delay_min":         Config.SPOT_SPAWN_DELAY_MIN,
			"spot_spawn_delay_max":         Config.SPOT_SPAWN_DELAY_MAX,
			"spot_max_active_count":        Config.SPOT_MAX_ACTIVE_COUNT,
			"click_note_weight":            Config.CLICK_NOTE_WEIGHT,
			"slide_note_weight":            Config.SLIDE_NOTE_WEIGHT,
			"rub_note_weight":              Config.RUB_NOTE_WEIGHT,
			# LEGACY: direction-sequence (disabled, retained for rollback)
			"direction_sequence_length_min": 3,
			"direction_sequence_length_max": 4,
			"direction_prompt_time_limit": 2.4,
			"next_prompt_reveal_delay": 0.9,
			"prompt_spawn_delay_min": 1.1,
			"prompt_spawn_delay_max": 1.5,
			"direction_reward_values": {
				"correct_input": 1.0,
				"sequence_complete_bonus": 5.0
			},
			"direction_penalty_values": {
				"wrong_input": 2.0
			},
			"choice_reward_values": {
				"good": 10.0,
				"neutral": 3.0
			},
			"choice_penalty_values": {
				"bad": 5.0
			},
			"choice_timeout_seconds": 5.0,
			"feedback_message_interval_min": 2.0,
			"feedback_message_interval_max": 4.0,
			"feedback_physical_low_threshold": 38.0,
			"feedback_physical_high_threshold": 45.0,
			"feedback_emotional_low_threshold": 38.0,
			"feedback_emotional_high_threshold": 52.0,
			"minimum_active_threshold": 20.0,
			"overall_medium_threshold": 15.0,
			"overall_high_threshold": 45.0,
			"overall_peak_threshold": 100.0,
			"peak_balance_best_diff": 5.0,
			"peak_balance_ok_diff": 15.0,
			"peak_balance_fail_diff": 30.0,
			"max_positive_peak_gain_rate": Config.MAX_POSITIVE_PEAK_GAIN_RATE,
			"peak_loss_rate_imbalanced": 2.0,
			"peak_zero_value_extra_loss_rate": 3.0,
			"success_condition": {
				"type": "peak_at_or_above",
				"value": 100.0
			},
			"failure_thresholds": {
				"peak_depletion_requires_activation": true,
				"physical_cap": 100.0,
				"physical_counterpart_below": 20.0,
				"emotional_cap": 100.0,
				"emotional_counterpart_below": 20.0
			},
			"psychological_dialogue_data_source": "res://assets/dialogue/feedback.json",
			"physiological_dialogue_data_source": "res://assets/dialogue/physiological_feedback.json"
		}
	)

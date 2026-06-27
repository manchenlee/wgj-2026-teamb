extends PhaseConfig

const Phase2CharacterProfile := preload("res://data/character_profiles/phase_2_character_profile.gd")

func _init() -> void:
	var profile = Phase2CharacterProfile.new()
	# TODO: Replace Phase 2 placeholder values and dialogue source with final tuning/content.
	super._init(
		{
			"phase_id": "phase_2",
			"starting_physical_value": 40.0,
			"starting_emotional_value": 40.0,
			"starting_peak_value": 0.0,
			"physical_decay_rate": 2.0,
			"emotional_decay_rate": 0.5,
			"physical_activity_grace_seconds": 1.4,
			"emotional_activity_grace_seconds": 2.8,
			# Interaction Spot (Physical Arousal) — new system
			"spot_lifetime": 7.0,
			"spot_required_scrub_distance": 400.0,
			"spot_valid_motion_threshold": 3.0,
			"spot_max_delta_per_event": 24.0,
			"spot_physical_gain_per_px": 0.04,
			"spot_completion_bonus": 12.0,
			"spot_expiry_penalty_ignored": 5.0,
			"spot_expiry_penalty_partial": 2.0,
			"spot_radius": 52.0,
			"spot_spawn_delay_min": 1.8,
			"spot_spawn_delay_max": 3.2,
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
			"feedback_physical_low_threshold": 30.0,
			"feedback_emotional_low_threshold": 30.0,
			"feedback_emotional_high_threshold": 60.0,
			"minimum_active_threshold": 20.0,
			"overall_medium_threshold": 20.0,
			"overall_high_threshold": 60.0,
			"overall_peak_threshold": 100.0,
			"peak_balance_best_diff": 5.0,
			"peak_balance_ok_diff": 15.0,
			"peak_balance_fail_diff": 30.0,
			"peak_gain_rate_max": 5.0,
			"peak_gain_rate_min": 1.0,
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
			"dialogue_data_source": "res://assets/dialogue/feedback.json",
			"character_profile": profile,
			"overlay_animation_set": profile.overlay_animation_set,
			"prompt_anchor_profile_id": profile.profile_id,
			"transition_feedback_text": "Phase 2 clear."
		}
	)

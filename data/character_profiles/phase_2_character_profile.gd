extends PhaseCharacterProfile

const PHASE_2_ROOT := "res://assets/art/character/phase2/"

func _init() -> void:
	var phase_2_base_portrait := "%sperson_bgc.png" % PHASE_2_ROOT
	super._init(
		"phase_2_profile",
		{
			"draft": phase_2_base_portrait,
			"overall_init": phase_2_base_portrait,
			"overall_low": phase_2_base_portrait,
			"overall_medium": phase_2_base_portrait,
			"overall_high": phase_2_base_portrait,
			"physic_high_mental_low": phase_2_base_portrait,
			"physic_low_mental_high": phase_2_base_portrait
		},
		{
			"physic_high_mental_low_gameover": phase_2_base_portrait,
			"physic_low_mental_high_gameover": phase_2_base_portrait
		},
		{
			"penis1": [
				"%spenis1_1.png" % PHASE_2_ROOT,
				"%spenis1_2.png" % PHASE_2_ROOT
			]
		},
		{
			"HeadLeft": Rect2(160.0, 100.0, 80.0, 80.0),
			"HeadRight": Rect2(280.0, 130.0, 80.0, 80.0),
			"Chest": Rect2(110.0, 250.0, 250.0, 270.0),
			"LeftArm": Rect2(80.0, 0.0, 70.0, 182.0),
			"RightArm": Rect2(400.0, 150.0, 250.0, 140.0),
			"Waist": Rect2(220.0, 530.0, 120.0, 220.0),
			"LeftLeg": Rect2(-100.0, 350.0, 182.0, 350.0),
			"RightLeg": Rect2(370.0, 370.0, 182.0, 350.0)
		},
		Rect2(0.214, 0.296, 0.487, 0.319)
	)

func get_layer_texture_paths() -> Dictionary:
	return {
		"phase_2_background": "%sperson_bgc.png" % PHASE_2_ROOT,
		"phase_2_flush": "%sflush.png" % PHASE_2_ROOT,
		"phase_2_gameover_overlay": "%spenis2.png" % PHASE_2_ROOT
	}

func get_face_texture_paths() -> Dictionary:
	return {
		"overall_init": "%sface_init.png" % PHASE_2_ROOT,
		"overall_low": "%sface_init.png" % PHASE_2_ROOT,
		"overall_medium": "%sface_medium.png" % PHASE_2_ROOT,
		"overall_high": "%sface_high.png" % PHASE_2_ROOT
	}

func get_overlay_idle_playback_config() -> Dictionary:
	return {
		"frame_2_duration": 0.18,
		"idle_ratio_min": 2,
		"idle_ratio_max": 6,
		"initial_delay_max": 0.12
	}

func get_face_state_key(overall_value: float, medium_threshold: float, high_threshold: float) -> String:
	if overall_value >= high_threshold:
		return "overall_high"
	if overall_value >= medium_threshold:
		return "overall_medium"
	return "overall_init"

func get_breathing_target_layer_id() -> String:
	return "phase_2_background"

func get_gameover_overlay_texture_path(_ending_type: String = "") -> String:
	return "%spenis2.png" % PHASE_2_ROOT

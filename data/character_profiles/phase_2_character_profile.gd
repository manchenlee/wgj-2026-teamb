extends PhaseCharacterProfile

func _init() -> void:
	# TODO: Replace the shared placeholder states below with dedicated Phase 2 state art
	# once separate low/medium/high and gameover variants are exported.
	var phase_2_base_portrait := "res://assets/art/character/phase2/person.png"
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
			"tentacle4": [
				"res://assets/art/character/phase1/tentacle4_1.png",
				"res://assets/art/character/phase1/tentacle4_2.png"
			],
			"tentacle2": [
				"res://assets/art/character/phase1/tentacle2_1.png",
				"res://assets/art/character/phase1/tentacle2_2.png"
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

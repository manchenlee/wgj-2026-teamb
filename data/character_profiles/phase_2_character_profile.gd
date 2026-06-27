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
			"HeadLeft": Rect2(94.0, 22.0, 148.0, 130.0),
			"HeadRight": Rect2(318.0, 40.0, 142.0, 126.0),
			"Chest": Rect2(156.0, 296.0, 224.0, 212.0),
			"LeftArm": Rect2(26.0, 370.0, 138.0, 182.0),
			"RightArm": Rect2(390.0, 354.0, 130.0, 194.0),
			"Waist": Rect2(174.0, 590.0, 180.0, 156.0),
			"LeftLeg": Rect2(44.0, 734.0, 182.0, 114.0),
			"RightLeg": Rect2(276.0, 704.0, 182.0, 124.0)
		},
		Rect2(0.31, 0.46, 0.31, 0.33)
	)

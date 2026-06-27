extends PhaseCharacterProfile

func _init() -> void:
	# TODO: Replace the placeholder Phase 1 art reuse below with dedicated Phase 2 assets.
	super._init(
		"phase_2_profile",
		{
			"draft": "res://assets/art/character/draft.png",
			"overall_init": "res://assets/art/character/phase1/overall_low.png",
			"overall_low": "res://assets/art/character/phase1/overall_medium.png",
			"overall_medium": "res://assets/art/character/phase1/overall_high.png",
			"overall_high": "res://assets/art/character/phase1/overall_high.png",
			"physic_high_mental_low": "res://assets/art/character/phase1/physic_high_mental_low.png.png",
			"physic_low_mental_high": "res://assets/art/character/phase1/physic_low_mental_high.png"
		},
		{
			"physic_high_mental_low_gameover": "res://assets/art/character/phase1/physic_high_mental_low_gameover.png",
			"physic_low_mental_high_gameover": "res://assets/art/character/phase1/physic_low_mental_high_gameover.png"
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

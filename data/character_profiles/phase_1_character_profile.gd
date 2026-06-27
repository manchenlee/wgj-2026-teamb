extends PhaseCharacterProfile

func _init() -> void:
	super._init(
		"phase_1_profile",
		{
			"draft": "res://assets/art/character/draft.png",
			"overall_init": "res://assets/art/character/phase1/overall_init.png",
			"overall_low": "res://assets/art/character/phase1/overall_low.png",
			"overall_medium": "res://assets/art/character/phase1/overall_medium.png",
			"overall_high": "res://assets/art/character/phase1/overall_high.png",
			"physic_high_mental_low": "res://assets/art/character/phase1/physic_high_mental_low.png.png",
			"physic_low_mental_high": "res://assets/art/character/phase1/physic_low_mental_high.png"
		},
		{
			"physic_high_mental_low_gameover": "res://assets/art/character/phase1/physic_high_mental_low_gameover.png",
			"physic_low_mental_high_gameover": "res://assets/art/character/phase1/physic_low_mental_high_gameover.png"
		},
		{
			"tentacle1": [
				"res://assets/art/character/phase1/tentacle1_1.png",
				"res://assets/art/character/phase1/tentacle1_2.png"
			],
			"tentacle2": [
				"res://assets/art/character/phase1/tentacle2_1.png",
				"res://assets/art/character/phase1/tentacle2_2.png"
			],
			"tentacle3": [
				"res://assets/art/character/phase1/tentacle3_1.png",
				"res://assets/art/character/phase1/tentacle3_2.png"
			],
			"tentacle4": [
				"res://assets/art/character/phase1/tentacle4_1.png",
				"res://assets/art/character/phase1/tentacle4_2.png"
			]
		},
		{
			"HeadLeft": Rect2(140.0, 10.0, 140.0, 134.0),
			"HeadRight": Rect2(280.0, 10.0, 140.0, 134.0),
			"Chest": Rect2(180.0, 351.0, 214.0, 220.0),
			"LeftArm": Rect2(14.0, 407.0, 159.0, 142.0),
			"RightArm": Rect2(406.0, 407.0, 109.0, 237.0),
			"Waist": Rect2(205.0, 618.0, 130.0, 174.0),
			"LeftLeg": Rect2(0.0, 756.0, 232.0, 98.0),
			"RightLeg": Rect2(287.0, 752.0, 203.0, 98.0)
		},
		Rect2(0.34, 0.5, 0.28, 0.35)
	)


func get_interaction_spot_anchor_ids() -> Array[String]:
	return [
		"HeadAnchor",
		"ShoulderLeftAnchor",
		"ShoulderRightAnchor",
		"ArmLeftAnchor",
		"ArmRightAnchor"
	]

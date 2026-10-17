extends PhaseCharacterProfile

const CURRENT_PORTRAIT := "res://assets/art/character/phase2/complete.png"

func _init() -> void:
	super._init(
		"phase_1_profile",
		{
			"draft": CURRENT_PORTRAIT,
			"overall_init": CURRENT_PORTRAIT,
			"overall_low": CURRENT_PORTRAIT,
			"overall_medium": CURRENT_PORTRAIT,
			"overall_high": CURRENT_PORTRAIT,
			"physic_high_mental_low": CURRENT_PORTRAIT,
			"physic_low_mental_high": CURRENT_PORTRAIT
		},
		{
			"physic_high_mental_low_gameover": CURRENT_PORTRAIT,
			"physic_low_mental_high_gameover": CURRENT_PORTRAIT
		},
		{},
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
		{
			"HeadLeft": Rect2(220.0, 96.0, 86.0, 96.0),
			"HeadRight": Rect2(308.0, 104.0, 86.0, 104.0),
			"Chest": Rect2(210.0, 320.0, 170.0, 170.0),
			"LeftArm": Rect2(100.0, 396.0, 112.0, 130.0),
			"RightArm": Rect2(392.0, 386.0, 98.0, 150.0),
			"Waist": Rect2(216.0, 556.0, 132.0, 150.0),
			"LeftLeg": Rect2(112.0, 714.0, 150.0, 112.0),
			"RightLeg": Rect2(304.0, 712.0, 150.0, 112.0)
		},
		Rect2(0.34, 0.5, 0.28, 0.35),
		Vector2(0.403963, 0.5),
		0.0,
		{
			0: {ExpressionState.NEUTRAL: {"base_state_key": "overall_init"}},
			1: {ExpressionState.NEUTRAL: {"base_state_key": "overall_init"}},
			2: {ExpressionState.NEUTRAL: {"base_state_key": "overall_init"}},
		}
	)

class_name PoseCharacterProfile
extends PhaseCharacterProfile

const PROMPT_ANCHOR_LAYOUT := {
	"HeadLeft": Rect2(160.0, 100.0, 80.0, 80.0),
	"HeadRight": Rect2(280.0, 130.0, 80.0, 80.0),
	"Chest": Rect2(110.0, 250.0, 250.0, 270.0),
	"LeftArm": Rect2(80.0, 0.0, 70.0, 182.0),
	"RightArm": Rect2(400.0, 150.0, 250.0, 140.0),
	"Waist": Rect2(220.0, 530.0, 120.0, 220.0),
	"LeftLeg": Rect2(-100.0, 350.0, 182.0, 350.0),
	"RightLeg": Rect2(370.0, 370.0, 182.0, 350.0),
}
const INTERACTION_SPOT_ANCHOR_LAYOUT := {
	"HeadLeft": Rect2(176.0, 112.0, 82.0, 82.0),
	"HeadRight": Rect2(278.0, 138.0, 86.0, 86.0),
	"Chest": Rect2(156.0, 276.0, 166.0, 190.0),
	"LeftArm": Rect2(94.0, 70.0, 78.0, 122.0),
	"RightArm": Rect2(398.0, 166.0, 156.0, 104.0),
	"Waist": Rect2(220.0, 520.0, 120.0, 174.0),
	"LeftLeg": Rect2(18.0, 418.0, 116.0, 210.0),
	"RightLeg": Rect2(380.0, 428.0, 116.0, 210.0),
}
const BREATHING_REGIONS := {
	"sitting": Rect2(0.46, 0.30, 0.23, 0.24),
	"standing": Rect2(0.39, 0.33, 0.22, 0.22),
	"prone": Rect2(0.24, 0.42, 0.33, 0.23),
	"lying": Rect2(0.28, 0.27, 0.25, 0.25),
}

var presentation_phase: int = 1
var pose_name: String = "sitting"

func _init(phase: int = 1) -> void:
	presentation_phase = clampi(phase, 1, 5)
	match presentation_phase:
		3:
			pose_name = "lying"
		4:
			pose_name = "prone"
		5:
			pose_name = "standing"
		_:
			pose_name = "sitting"
	var root := "res://assets/art/character/%s/" % pose_name
	var expressions := {
		ExpressionState.NEUTRAL: {"base_state_key": "overall_init", "face_state_key": "face_neutral"},
		ExpressionState.POSITIVE: {"base_state_key": "overall_init", "face_state_key": "face_positive"},
		ExpressionState.PSYCHOLOGICAL_POSITIVE: {"base_state_key": "overall_init", "face_state_key": "face_psychological_positive"},
		ExpressionState.NEGATIVE: {"base_state_key": "overall_init", "face_state_key": "face_negative"},
	}
	var mappings: Dictionary = {}
	for band in range(5):
		mappings[band] = expressions.duplicate(true)
	super._init(
		"phase_%d_profile" % presentation_phase,
		{"draft": root + "complete.png", "overall_init": root + "complete.png"},
		{}, {},
		PROMPT_ANCHOR_LAYOUT,
		INTERACTION_SPOT_ANCHOR_LAYOUT,
		BREATHING_REGIONS[pose_name],
		Vector2(0.5, 0.5), 0.0,
		mappings
	)

func get_face_texture_paths() -> Dictionary:
	var root := "res://assets/art/character/%s/" % pose_name
	return {
		"face_neutral": root + "face_neutral.png",
		"face_positive": root + "face_positive.png",
		"face_psychological_positive": root + "face_psychological_positive.png",
		"face_negative": root + "face_negative.png",
	}

func get_tail_frame_paths() -> Array[String]:
	var root := "res://assets/art/character/%s/" % pose_name
	return [root + "tail_1.png", root + "tail_2.png", root + "tail_3.png"]

func get_tentacle_part_paths() -> Array:
	var paths: Array = []
	var part_count := 5 if pose_name == "prone" else 4
	for part in range(1, part_count + 1):
		var frames: Array[String] = []
		for frame in range(1, 4):
			frames.append("res://assets/art/tentacles/%s/part_%d_%d.png" % [pose_name, part, frame])
		paths.append(frames)
	return paths

func get_tail_tentacle_paths() -> Array:
	var paths: Array = []
	if pose_name == "sitting":
		for stage in range(1, 4):
			var frames: Array[String] = []
			for frame in range(1, 4):
				frames.append("res://assets/art/tentacles/sitting/tail_%d_%d.png" % [stage, frame])
			paths.append(frames)
	elif pose_name == "standing":
		for side in ["left", "center", "right"]:
			var frames: Array[String] = []
			for frame in range(1, 4):
				frames.append("res://assets/art/tentacles/standing/tail_%s_%d.png" % [side, frame])
			paths.append(frames)
	return paths

func get_interaction_mask_path() -> String:
	return "res://assets/art/character/%s/interaction_mask.png" % pose_name

func get_shooting_tail_path() -> String:
	if pose_name == "standing":
		return "res://assets/art/character/standing/tail_shooting.png"
	return ""

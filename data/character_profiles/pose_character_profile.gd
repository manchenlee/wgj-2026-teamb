class_name PoseCharacterProfile
extends PhaseCharacterProfile

# Phase 1 deliberately references the Phase 2 sitting art until its final art exists.
const LEGACY_LAYOUT := preload("res://data/character_profiles/phase_2_character_profile.gd")
const BREATHING_REGIONS := {
	1: Rect2(0.46, 0.30, 0.23, 0.24),
	2: Rect2(0.46, 0.30, 0.23, 0.24),
	3: Rect2(0.39, 0.33, 0.22, 0.22),
	4: Rect2(0.24, 0.42, 0.33, 0.23),
	5: Rect2(0.28, 0.27, 0.25, 0.25),
}

var presentation_phase: int = 1
var asset_phase: int = 2

func _init(phase: int = 1) -> void:
	presentation_phase = clampi(phase, 1, 5)
	asset_phase = maxi(2, presentation_phase)
	var root := "res://assets/art/character/phase%d/" % asset_phase
	var layout = LEGACY_LAYOUT.new()
	var expressions := {
		ExpressionState.NEUTRAL: {"base_state_key": "overall_init", "face_state_key": "face_neutral"},
		ExpressionState.POSITIVE: {"base_state_key": "overall_init", "face_state_key": "face_positive"},
		ExpressionState.NEGATIVE: {"base_state_key": "overall_init", "face_state_key": "face_negative"},
	}
	var mappings: Dictionary = {}
	for band in range(5):
		mappings[band] = expressions.duplicate(true)
	super._init(
		"phase_%d_profile" % presentation_phase,
		{"draft": root + "complete.png", "overall_init": root + "complete.png"},
		{}, {},
		layout.prompt_anchor_layout,
		layout.interaction_spot_anchor_layout,
		BREATHING_REGIONS[presentation_phase],
		Vector2(0.5, 0.5), 0.0,
		mappings
	)

func get_face_texture_paths() -> Dictionary:
	var root := "res://assets/art/character/phase%d/" % asset_phase
	return {
		"face_neutral": root + "face_neutral.png",
		"face_positive": root + "face_positive.png",
		"face_negative": root + "face_negative.png",
	}

func get_tail_frame_paths() -> Array[String]:
	var root := "res://assets/art/character/phase%d/" % asset_phase
	return [root + "tail_1.png", root + "tail_2.png", root + "tail_3.png"]

func get_interaction_mask_path() -> String:
	return "res://assets/art/character/phase%d/interaction_mask.png" % asset_phase

func get_shooting_tail_path() -> String:
	if asset_phase == 3:
		return "res://assets/art/character/phase3/tail_shooting.png"
	return ""

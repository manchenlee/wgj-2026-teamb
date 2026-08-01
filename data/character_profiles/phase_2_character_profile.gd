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
			# --- Phase 2 Group 1 (already implemented) ---
			"penis1": [
				"%spenis1_1.png" % PHASE_2_ROOT,
				"%spenis1_2.png" % PHASE_2_ROOT
			],

			# --- Phase 2 Group 2: animated tentacle tracks ---
			"tentacle5": [
				"%stentacle5_1.png" % PHASE_2_ROOT,
				"%stentacle5_2.png" % PHASE_2_ROOT
			],
			"tentacle6": [
				"%stentacle6_1.png" % PHASE_2_ROOT,
				"%stentacle6_2.png" % PHASE_2_ROOT
			],
			"tentacle8": [
				"%stentacle8_1.png" % PHASE_2_ROOT,
				"%stentacle8_2.png" % PHASE_2_ROOT
			],
			"tentacle9": [
				"%stentacle9_1.png" % PHASE_2_ROOT,
				"%stentacle9_2.png" % PHASE_2_ROOT
			],
			"tentacle11": [
				"%stentacle11_1.png" % PHASE_2_ROOT,
				"%stentacle11_2.png" % PHASE_2_ROOT
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
		{
			"HeadLeft": Rect2(176.0, 112.0, 82.0, 82.0),
			"HeadRight": Rect2(278.0, 138.0, 86.0, 86.0),
			"Chest": Rect2(156.0, 276.0, 166.0, 190.0),
			"LeftArm": Rect2(94.0, 70.0, 78.0, 122.0),
			"RightArm": Rect2(398.0, 166.0, 156.0, 104.0),
			"Waist": Rect2(220.0, 520.0, 120.0, 174.0),
			"LeftLeg": Rect2(18.0, 418.0, 116.0, 210.0),
			"RightLeg": Rect2(380.0, 428.0, 116.0, 210.0)
		},
		Rect2(0.214, 0.296, 0.487, 0.319),
		Vector2(0.403963, 0.5),
		0.0
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


# ---------------------------------------------------------------------------
# Phase 2 extended overlay profile
#
# Layer z-index order (low = further back, high = in front):
#
#   Phase 2 background / person layers  → managed by GameSessionController
#   (z_index values on those nodes: Phase2BackgroundLayer=1, BackgroundPlaceholder=2)
#
#   OverlayAnimator node itself sits at z_index=3 in BackgroundAnchor.
#   Children of OverlayAnimator inherit position from parent but their own
#   z_index is relative to the OverlayAnimator node unless z_as_relative=false.
#   All children here use z_as_relative=false so the values are absolute.
#
#   Desired Phase 2 render order (back to front):
#     3  — tentacle7 static and tentacle10 static
#          (kept behind the stable hub/front overlay layer)
#     4  — tentacle5, tentacle6, tentacle8, tentacle9, tentacle11 animated tracks
#          (TwoFrameOverlayAnimator._create_track uses no explicit z_index so
#           they stack in child order — adequate because they overlap as art)
#     6  — hole companion overlay (tied to tentacle10, sits above it)
#     7  — Phase2FlushLayer   (managed externally, z=4 on BackgroundAnchor node)
#     8  — Phase2FaceLayer    (managed externally, z=5 on BackgroundAnchor node)
#
# Note: Phase2FlushLayer (z=4) and Phase2FaceLayer (z=5) are direct children of
# BackgroundAnchor and sit above OverlayAnimator (z=3) unconditionally, so the
# exact z_index values inside OverlayAnimator only need to be self-consistent.
# ---------------------------------------------------------------------------
func get_phase2_overlay_profile_config() -> Dictionary:
	return {
		# --- Static full-canvas overlays ---
		# Exposed here so z-index can be adjusted without touching animation logic.
		"static_overlays": [
			{
				# tentacle7: appears behind the animated tentacles
				"texture_path": "%stentacle7.png" % PHASE_2_ROOT,
				"z_index": 3
			},
			{
				# tentacle10: kept below the stable hub/front overlay layer
				"texture_path": "%stentacle10.png" % PHASE_2_ROOT,
				"z_index": 3
			}
		],

		# --- Companion overlay: hole animation linked to tentacle10 ---
		"companion": {
			"linked_motion_id": "tentacle10",
			"frame_1_idle_path":   null,                               # transparent during frame-1 idle
			"frame_2_idle_path":   "%shole_idle.png" % PHASE_2_ROOT,   # visible during frame-2 idle
			"frame_1_active_path": "%shole_using.png" % PHASE_2_ROOT,  # visible during burst frame-1
			"frame_2_active_path": "%shole_idle.png" % PHASE_2_ROOT,   # visible during burst frame-2
			"z_index": 6
		}
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

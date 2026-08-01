class_name PhaseCharacterProfile
extends RefCounted

var profile_id: String
var base_state_textures: Dictionary
var gameover_state_textures: Dictionary
var overlay_animation_set: Dictionary
var prompt_anchor_layout: Dictionary
var interaction_spot_anchor_layout: Dictionary
var breathing_region_rect: Rect2
# Texture-local normalized focus point used for horizontal character alignment.
var character_visual_focus_normalized: Vector2
# Source-pixel inset from the texture bottom to the visible subject bottom edge.
var character_visual_bottom_inset_pixels: float

func _init(
	profile_id_value: String = "",
	base_state_textures_value: Dictionary = {},
	gameover_state_textures_value: Dictionary = {},
	overlay_animation_set_value: Dictionary = {},
	prompt_anchor_layout_value: Dictionary = {},
	interaction_spot_anchor_layout_value: Dictionary = {},
	breathing_region_rect_value: Rect2 = Rect2(0.34, 0.5, 0.28, 0.35),
	character_visual_focus_normalized_value: Vector2 = Vector2(0.5, 0.5),
	character_visual_bottom_inset_pixels_value: float = 0.0
) -> void:
	profile_id = profile_id_value
	base_state_textures = base_state_textures_value.duplicate(true)
	gameover_state_textures = gameover_state_textures_value.duplicate(true)
	overlay_animation_set = overlay_animation_set_value.duplicate(true)
	prompt_anchor_layout = prompt_anchor_layout_value.duplicate(true)
	interaction_spot_anchor_layout = interaction_spot_anchor_layout_value.duplicate(true)
	if interaction_spot_anchor_layout.is_empty():
		interaction_spot_anchor_layout = prompt_anchor_layout.duplicate(true)
	breathing_region_rect = breathing_region_rect_value
	character_visual_focus_normalized = character_visual_focus_normalized_value
	character_visual_bottom_inset_pixels = character_visual_bottom_inset_pixels_value

func get_character_visual_bottom_normalized(texture_size: Vector2) -> float:
	if texture_size.y <= 0.0:
		return 1.0
	return clamp((texture_size.y - character_visual_bottom_inset_pixels) / texture_size.y, 0.0, 1.0)

func get_all_texture_paths() -> Dictionary:
	var merged := base_state_textures.duplicate(true)
	for state_name_variant in gameover_state_textures.keys():
		var state_name := String(state_name_variant)
		merged[state_name] = gameover_state_textures[state_name]
	return merged

func get_texture_path(state_name: String) -> String:
	if gameover_state_textures.has(state_name):
		return String(gameover_state_textures[state_name])
	return String(base_state_textures.get(state_name, ""))

func get_anchor_layout_ids() -> Array[String]:
	var ids: Array[String] = []
	for anchor_id_variant in prompt_anchor_layout.keys():
		ids.append(String(anchor_id_variant))
	ids.sort()
	return ids

func get_interaction_spot_anchor_ids() -> Array[String]:
	var ids: Array[String] = []
	for anchor_id_variant in interaction_spot_anchor_layout.keys():
		ids.append(String(anchor_id_variant))
	ids.sort()
	return ids

func get_layer_texture_paths() -> Dictionary:
	return {}

func get_face_texture_paths() -> Dictionary:
	return {}

func get_overlay_idle_playback_config() -> Dictionary:
	return {}

func get_face_state_key(_overall_value: float, _medium_threshold: float, _high_threshold: float) -> String:
	return ""

func get_breathing_target_layer_id() -> String:
	return "base"

func get_gameover_overlay_texture_path(_ending_type: String = "") -> String:
	return ""

# Override in subclasses to supply Phase 2 extended overlay profile.
# Returns a Dictionary with optional keys:
#   "static_overlays" : Array of { "texture_path": String, "z_index": int }
#   "companion"       : Dictionary (hole companion config — see phase_2_character_profile.gd)
# Returns an empty dict by default (no Phase 2 extended overlays).
func get_phase2_overlay_profile_config() -> Dictionary:
	return {}

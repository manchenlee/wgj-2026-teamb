@tool
class_name PromptAnchorRegion
extends Control

const PREVIEW_LAYER_NAME := "Phase2AnchorPreviewLayer"

var _debug_bounds_visible := false

func apply_profile(profile) -> void:
	if profile == null:
		return

	set_debug_bounds_visible(false)
	var prompt_anchor_layout: Dictionary = profile.get("prompt_anchor_layout")
	for anchor_id_variant in prompt_anchor_layout.keys():
		var anchor_id := StringName(str(anchor_id_variant))
		var anchor_rect := prompt_anchor_layout[anchor_id_variant] as Rect2
		var anchor_node := _get_anchor_node(anchor_id)
		if anchor_node == null:
			push_warning("Prompt anchor node '%s' is missing from GameScreen." % String(anchor_id))
			continue
		anchor_node.position = anchor_rect.position
		anchor_node.size = anchor_rect.size
		anchor_node.visible = _debug_bounds_visible

func get_available_anchor_ids() -> Array[String]:
	var anchor_ids: Array[String] = []
	for child in get_children():
		if _is_gameplay_anchor(child):
			anchor_ids.append(String(child.name))
	anchor_ids.sort()
	return anchor_ids

func get_anchor_global_center(anchor_id: StringName, fallback_global_center: Vector2) -> Vector2:
	var anchor_node := _get_anchor_node(anchor_id)
	if anchor_node == null:
		push_warning("Missing prompt anchor '%s' in active phase profile." % String(anchor_id))
		return fallback_global_center
	return anchor_node.get_global_rect().get_center()

func get_region_global_rect() -> Rect2:
	return get_global_rect()

func set_anchor_rect(anchor_id: StringName, rect: Rect2) -> void:
	var anchor_node := _get_anchor_node(anchor_id)
	if anchor_node == null:
		return
	anchor_node.position = rect.position
	anchor_node.size = rect.size
	anchor_node.visible = false

func set_debug_bounds_visible(debug_visible: bool) -> void:
	_debug_bounds_visible = debug_visible
	for child in get_children():
		if _is_gameplay_anchor(child):
			child.visible = debug_visible

func _get_anchor_node(anchor_id: StringName) -> Control:
	var node := get_node_or_null(NodePath(String(anchor_id))) as Control
	if node == null or String(node.name) == PREVIEW_LAYER_NAME:
		return null
	return node

func _is_gameplay_anchor(node: Node) -> bool:
	return node is Control and String(node.name) != PREVIEW_LAYER_NAME

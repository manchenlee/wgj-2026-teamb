class_name ChoicePanel
extends Control

signal choice_selected(choice_quality: String, choice_text: String)

const CHOICE_ENABLED_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const CHOICE_DISABLED_MODULATE := Color(0.42, 0.42, 0.42, 1.0)
const BUTTON_WIDTH := 300.0
const BUTTON_MIN_HEIGHT := 146.0
const BUTTON_TEXT_MARGIN_LEFT := 14.0
const BUTTON_TEXT_MARGIN_TOP := 12.0
const BUTTON_TEXT_MARGIN_RIGHT := 14.0
const BUTTON_TEXT_MARGIN_BOTTOM := 10.0
const REQUIRED_ANCHORS_PER_SIDE := 4

@export var use_fixed_choice_anchor_seed: bool = false
@export var choice_anchor_seed: int = 1

var choice_button_1: TextureButton = null
var choice_button_2: TextureButton = null
var choice_label_1: Label = null
var choice_label_2: Label = null

var _choice_data: Array[Dictionary] = []
var _left_choice_anchors: Array[Control] = []
var _right_choice_anchors: Array[Control] = []
var _selected_left_anchor_index: int = -1
var _selected_right_anchor_index: int = -1
var _previous_left_anchor_index: int = -1
var _previous_right_anchor_index: int = -1
var _placement_version: int = 0
var _rng := RandomNumberGenerator.new()
var _missing_nodes_warning_printed: bool = false
var _anchor_warning_printed: bool = false
var _buttons_connected: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_anchor_rng()
	if not _bind_choice_nodes():
		return
	clear_choices()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		refresh_choice_anchor_positions()

func set_choice_anchor_groups(left_anchors: Array[Control], right_anchors: Array[Control]) -> void:
	_left_choice_anchors = left_anchors.duplicate()
	_right_choice_anchors = right_anchors.duplicate()
	_warn_if_anchor_groups_are_incomplete()
	refresh_choice_anchor_positions()

func show_choices(choices: Variant) -> void:
	if not _bind_choice_nodes():
		return
	_placement_version += 1
	var placement_version := _placement_version
	_choice_data = _normalize_choices(choices)
	_apply_choice_to_button(choice_button_1, choice_label_1, 0, true)
	_apply_choice_to_button(choice_button_2, choice_label_2, 1, true)
	_select_choice_anchor_pair()
	visible = true
	await get_tree().process_frame
	if placement_version != _placement_version:
		return
	_refresh_button_sizes()
	refresh_choice_anchor_positions()
	_apply_button_visibility_after_positioning()

func clear_choices() -> void:
	if not _bind_choice_nodes():
		return
	_placement_version += 1
	visible = true
	_choice_data.clear()
	_selected_left_anchor_index = -1
	_selected_right_anchor_index = -1
	_apply_disabled_choice_button(choice_button_1, choice_label_1)
	_apply_disabled_choice_button(choice_button_2, choice_label_2)

func emit_choice_by_index(index: int) -> void:
	_emit_choice(index)

func refresh_choice_anchor_positions() -> void:
	if not _bind_choice_nodes():
		return
	_refresh_button_sizes()
	if _selected_left_anchor_index >= 0 and _selected_left_anchor_index < _left_choice_anchors.size():
		_attach_left_button_to_anchor(choice_button_1, _left_choice_anchors[_selected_left_anchor_index])
	if _selected_right_anchor_index >= 0 and _selected_right_anchor_index < _right_choice_anchors.size():
		_attach_right_button_to_anchor(choice_button_2, _right_choice_anchors[_selected_right_anchor_index])

func _bind_choice_nodes() -> bool:
	if choice_button_1 != null and choice_button_2 != null and choice_label_1 != null and choice_label_2 != null:
		return true
	choice_button_1 = get_node_or_null("ChoiceButton1") as TextureButton
	choice_button_2 = get_node_or_null("ChoiceButton2") as TextureButton
	choice_label_1 = get_node_or_null("ChoiceButton1/Label") as Label
	choice_label_2 = get_node_or_null("ChoiceButton2/Label") as Label
	if choice_button_1 != null and choice_button_2 != null and choice_label_1 != null and choice_label_2 != null:
		_connect_buttons_once()
		return true
	if not _missing_nodes_warning_printed:
		_missing_nodes_warning_printed = true
		push_error("ChoicePanel: expected ChoiceButton1, ChoiceButton2, and their Label children.")
	return false

func _connect_buttons_once() -> void:
	if _buttons_connected:
		return
	_buttons_connected = true
	choice_button_1.pressed.connect(func() -> void: _emit_choice(0))
	choice_button_2.pressed.connect(func() -> void: _emit_choice(1))

func _apply_choice_to_button(button: TextureButton, label: Label, index: int, defer_visibility: bool = false) -> void:
	if button == null or label == null:
		return
	if index >= _choice_data.size():
		_apply_disabled_choice_button(button, label)
		label.text = ""
		return

	var choice := _choice_data[index]
	button.visible = not defer_visibility
	button.disabled = false
	label.text = str(choice.get("text", "")).strip_edges()
	_set_choice_button_enabled_state(button, true)
	_resize_choice_button(button, label)

func _apply_disabled_choice_button(button: TextureButton, label: Label) -> void:
	if button == null or label == null:
		return
	button.visible = false
	button.disabled = true
	label.text = ""
	_set_choice_button_enabled_state(button, false)
	_resize_choice_button(button, label)

func _set_choice_button_enabled_state(button: TextureButton, enabled: bool) -> void:
	if button == null:
		return
	button.modulate = CHOICE_ENABLED_MODULATE if enabled else CHOICE_DISABLED_MODULATE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	var fallback_rect := button.get_node_or_null("FallbackBubble") as ColorRect
	if fallback_rect != null:
		fallback_rect.color = Color(0.82, 0.26, 0.45, 0.96) if enabled else Color(0.42, 0.42, 0.42, 0.96)

func _emit_choice(index: int) -> void:
	if index >= _choice_data.size():
		return
	var choice := _choice_data[index]
	choice_selected.emit(str(choice.get("id", "")), str(choice.get("text", "")))

func _normalize_choices(choices: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if typeof(choices) == TYPE_ARRAY:
		for choice_variant in choices as Array:
			if typeof(choice_variant) != TYPE_DICTIONARY:
				continue
			var choice := choice_variant as Dictionary
			var choice_id := str(choice.get("id", ""))
			var choice_text := str(choice.get("text", ""))
			if choice_id.is_empty() or choice_text.is_empty() or choice_id == "neutral":
				continue
			normalized.append({"id": choice_id, "text": choice_text})
			if normalized.size() == 2:
				break
	elif typeof(choices) == TYPE_DICTIONARY:
		for choice_id_variant in ["good", "bad"]:
			if not choices.has(choice_id_variant):
				continue
			var choice_text := str(choices.get(choice_id_variant, ""))
			if choice_text.is_empty():
				continue
			normalized.append({"id": String(choice_id_variant), "text": choice_text})
	return normalized

func _init_anchor_rng() -> void:
	if use_fixed_choice_anchor_seed:
		_rng.seed = choice_anchor_seed
	else:
		_rng.randomize()

func _select_choice_anchor_pair() -> void:
	_selected_left_anchor_index = _select_anchor_index(_left_choice_anchors.size(), _previous_left_anchor_index)
	_selected_right_anchor_index = _select_anchor_index(_right_choice_anchors.size(), _previous_right_anchor_index)
	_previous_left_anchor_index = _selected_left_anchor_index
	_previous_right_anchor_index = _selected_right_anchor_index

func _select_anchor_index(anchor_count: int, previous_index: int) -> int:
	if anchor_count <= 0:
		return -1
	if anchor_count == 1:
		return 0
	var selected_index := _rng.randi_range(0, anchor_count - 1)
	if selected_index == previous_index:
		selected_index = (selected_index + 1 + _rng.randi_range(0, anchor_count - 2)) % anchor_count
	return selected_index

func _refresh_button_sizes() -> void:
	_resize_choice_button(choice_button_1, choice_label_1)
	_resize_choice_button(choice_button_2, choice_label_2)

func _resize_choice_button(button: TextureButton, label: Label) -> void:
	if button == null or label == null:
		return
	label.custom_minimum_size.x = BUTTON_WIDTH - BUTTON_TEXT_MARGIN_LEFT - BUTTON_TEXT_MARGIN_RIGHT
	label.position = Vector2(BUTTON_TEXT_MARGIN_LEFT, BUTTON_TEXT_MARGIN_TOP)
	label.size.x = label.custom_minimum_size.x
	label.update_minimum_size()
	var label_minimum := label.get_combined_minimum_size()
	var button_height := maxf(
		BUTTON_MIN_HEIGHT,
		label_minimum.y + BUTTON_TEXT_MARGIN_TOP + BUTTON_TEXT_MARGIN_BOTTOM
	)
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, button_height)
	button.size = Vector2(BUTTON_WIDTH, button_height)
	label.size = Vector2(
		BUTTON_WIDTH - BUTTON_TEXT_MARGIN_LEFT - BUTTON_TEXT_MARGIN_RIGHT,
		button_height - BUTTON_TEXT_MARGIN_TOP - BUTTON_TEXT_MARGIN_BOTTOM
	)

func _attach_left_button_to_anchor(button: TextureButton, anchor: Control) -> void:
	if button == null or anchor == null:
		return
	var marker_position := _anchor_center_in_panel_space(anchor)
	button.position = marker_position - Vector2(button.size.x, button.size.y * 0.5)

func _attach_right_button_to_anchor(button: TextureButton, anchor: Control) -> void:
	if button == null or anchor == null:
		return
	var marker_position := _anchor_center_in_panel_space(anchor)
	button.position = marker_position - Vector2(0.0, button.size.y * 0.5)

func _anchor_center_in_panel_space(anchor: Control) -> Vector2:
	var anchor_global_center := anchor.get_global_rect().get_center()
	return get_global_transform_with_canvas().affine_inverse() * anchor_global_center

func _apply_button_visibility_after_positioning() -> void:
	if choice_button_1 != null:
		choice_button_1.visible = _choice_data.size() > 0 and _selected_left_anchor_index >= 0
	if choice_button_2 != null:
		choice_button_2.visible = _choice_data.size() > 1 and _selected_right_anchor_index >= 0

func _warn_if_anchor_groups_are_incomplete() -> void:
	if _anchor_warning_printed:
		return
	if _left_choice_anchors.size() == REQUIRED_ANCHORS_PER_SIDE and _right_choice_anchors.size() == REQUIRED_ANCHORS_PER_SIDE:
		return
	_anchor_warning_printed = true
	push_warning(
		"ChoicePanel: expected exactly %d left and %d right choice anchors, got %d left and %d right." % [
			REQUIRED_ANCHORS_PER_SIDE,
			REQUIRED_ANCHORS_PER_SIDE,
			_left_choice_anchors.size(),
			_right_choice_anchors.size()
		]
	)

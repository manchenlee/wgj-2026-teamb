extends Control

signal choice_selected(choice_quality: String, choice_text: String)

const Config := preload("res://scripts/gameplay/GameConfig.gd")

const PLAYER_BUBBLE_PATH := "res://assets/art/ui/text.png"
const CHARACTER_BUBBLE_PATH := "res://assets/art/ui/text2.png"
const CHOICE_BUBBLE_PATH := "res://assets/art/ui/text bubble.png"

const BUBBLE_SCALE := 0.5
const CHOICE_BUBBLE_SCALE := 1.0
const VIEWPORT_PADDING_LEFT := 12.0
const VIEWPORT_PADDING_RIGHT := 0.0
const VIEWPORT_PADDING_VERTICAL := 14.0
const LATEST_MESSAGE_TOP_RATIO := 0.90
const MESSAGE_GAP := 20.0
const MESSAGE_TEXT_MARGIN_LEFT := 34.0
const MESSAGE_TEXT_MARGIN_TOP := 24.0
const MESSAGE_TEXT_MARGIN_RIGHT := 38.0
const MESSAGE_TEXT_MARGIN_BOTTOM := 22.0
const MESSAGE_TEXT_MAX_CHARS := 30
const CHOICE_TEXT_MARGIN_LEFT := 14.0
const CHOICE_TEXT_MARGIN_TOP := 12.0
const CHOICE_TEXT_MARGIN_RIGHT := 14.0
const CHOICE_TEXT_MARGIN_BOTTOM := 10.0
const CHOICE_TEXT_MAX_CHARS := 64
const MESSAGE_FONT_SIZE := 24
const CHOICE_FONT_SIZE := 24
const FALLBACK_MESSAGE_SIZE := Vector2(520.0, 132.0)
const FALLBACK_CHOICE_SIZE := Vector2(300.0, 146.0)
const MAX_VISIBLE_MESSAGES := 5

@onready var conversation_content: Control = $ConversationContent
@onready var choice_area: Control = $"../BottomHUD/ChoiceArea"
@onready var choice_button_1: TextureButton = $"../BottomHUD/ChoiceArea/ChoiceButton1"
@onready var choice_button_2: TextureButton = $"../BottomHUD/ChoiceArea/ChoiceButton2"
@onready var choice_label_1: Label = $"../BottomHUD/ChoiceArea/ChoiceButton1/Label"
@onready var choice_label_2: Label = $"../BottomHUD/ChoiceArea/ChoiceButton2/Label"

var _message_nodes: Array[Control] = []
var _warning_keys: Dictionary = {}
var _choice_data: Array[Dictionary] = []
var _player_bubble_texture: Texture2D
var _character_bubble_texture: Texture2D
var _choice_bubble_texture: Texture2D

func _ready() -> void:
	clip_contents = true
	conversation_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_load_textures()
	_configure_choice_button(choice_button_1, choice_label_1)
	_configure_choice_button(choice_button_2, choice_label_2)
	choice_button_1.pressed.connect(func() -> void: _emit_choice(0))
	choice_button_2.pressed.connect(func() -> void: _emit_choice(1))
	hide_choices()
	_sync_content_rect()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_sync_content_rect()
		_relayout_messages(false)

func show_choices(choices: Variant) -> void:
	_choice_data = _normalize_choices(choices)
	_apply_choice_to_button(choice_button_1, choice_label_1, _choice_data, 0)
	_apply_choice_to_button(choice_button_2, choice_label_2, _choice_data, 1)
	choice_area.visible = true

func hide_choices() -> void:
	choice_area.visible = false
	for button in [choice_button_1, choice_button_2]:
		button.visible = false
		button.disabled = true

func show_prompt(_text_value: String) -> void:
	pass

func hide_prompt() -> void:
	pass

func clear_history() -> void:
	for message_node in _message_nodes:
		message_node.queue_free()
	_message_nodes.clear()
	hide_choices()

func append_history(line: String, speaker_type: String = "companion") -> void:
	var message_node := _create_message_bubble(line, speaker_type)
	conversation_content.add_child(message_node)
	_message_nodes.append(message_node)
	_relayout_messages(true)

func set_choice_timeout_progress(_progress: float) -> void:
	pass


func emit_choice_by_index(index: int) -> void:
	## Called by GameSessionController to trigger a choice via keyboard input.
	## ConversationViewport does not process keyboard events directly.
	if not choice_area.visible:
		return
	_emit_choice(index)

func _sync_content_rect() -> void:
	conversation_content.position = Vector2.ZERO

func _load_textures() -> void:
	_player_bubble_texture = _load_texture_or_warn(PLAYER_BUBBLE_PATH, "player_bubble")
	_character_bubble_texture = _load_texture_or_warn(CHARACTER_BUBBLE_PATH, "character_bubble")
	_choice_bubble_texture = _load_texture_or_warn(CHOICE_BUBBLE_PATH, "choice_bubble")

func _load_texture_or_warn(path: String, warning_key: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	_warn_once(warning_key, "UI texture missing or failed to load: %s. Using fallback presentation." % path)
	return null

func _warn_once(warning_key: String, message: String) -> void:
	if _warning_keys.has(warning_key):
		return
	_warning_keys[warning_key] = true
	push_warning(message)

func _create_message_bubble(line: String, speaker_type: String) -> Control:
	var is_player := speaker_type == "player"
	var texture := _player_bubble_texture if is_player else _character_bubble_texture
	var source_bubble_size := _get_texture_size(texture, FALLBACK_MESSAGE_SIZE)
	var bubble_size := source_bubble_size * BUBBLE_SCALE
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = bubble_size
	root.size = bubble_size
	root.set_meta("speaker_type", speaker_type)
	root.set_meta("align_side", "right" if is_player else "left")

	if texture != null:
		var bubble_texture := TextureRect.new()
		bubble_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble_texture.texture = texture
		bubble_texture.position = Vector2.ZERO
		bubble_texture.size = source_bubble_size
		bubble_texture.scale = Vector2.ONE * BUBBLE_SCALE
		root.add_child(bubble_texture)
	else:
		var fallback_panel := ColorRect.new()
		fallback_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback_panel.color = Color(0.83, 0.73, 0.42, 0.92) if not is_player else Color(0.66, 0.2, 0.38, 0.92)
		fallback_panel.position = Vector2.ZERO
		fallback_panel.size = bubble_size
		root.add_child(fallback_panel)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", MESSAGE_FONT_SIZE)
	label.set_meta("_ui_font_scale_applied", true)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.text = _clamp_text(line, MESSAGE_TEXT_MAX_CHARS)
	label.position = Vector2(MESSAGE_TEXT_MARGIN_LEFT, MESSAGE_TEXT_MARGIN_TOP) * BUBBLE_SCALE
	label.size = Vector2(
		bubble_size.x - (MESSAGE_TEXT_MARGIN_LEFT + MESSAGE_TEXT_MARGIN_RIGHT) * BUBBLE_SCALE,
		bubble_size.y - (MESSAGE_TEXT_MARGIN_TOP + MESSAGE_TEXT_MARGIN_BOTTOM) * BUBBLE_SCALE
	)
	root.add_child(label)

	return root

func _configure_choice_button(button: TextureButton, label: Label) -> void:
	var source_bubble_size := _get_texture_size(_choice_bubble_texture, FALLBACK_CHOICE_SIZE)
	var bubble_size := source_bubble_size * CHOICE_BUBBLE_SCALE
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.custom_minimum_size = bubble_size
	button.size = bubble_size
	button.texture_normal = _choice_bubble_texture
	button.texture_hover = _choice_bubble_texture
	button.texture_pressed = _choice_bubble_texture
	button.texture_disabled = _choice_bubble_texture
	button.modulate = Color.WHITE
	if _choice_bubble_texture == null:
		var fallback_rect := button.get_node_or_null("FallbackBubble") as ColorRect
		if fallback_rect == null:
			fallback_rect = ColorRect.new()
			fallback_rect.name = "FallbackBubble"
			fallback_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fallback_rect.color = Color(0.82, 0.26, 0.45, 0.96)
			fallback_rect.position = Vector2.ZERO
			fallback_rect.size = bubble_size
			button.add_child(fallback_rect)
			button.move_child(fallback_rect, 0)
	else:
		var fallback_rect := button.get_node_or_null("FallbackBubble")
		if fallback_rect != null:
			fallback_rect.queue_free()

	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
	label.set_meta("_ui_font_scale_applied", true)
	label.add_theme_color_override("font_color", Color(0.99, 0.94, 0.94, 1.0))
	label.position = Vector2(CHOICE_TEXT_MARGIN_LEFT, CHOICE_TEXT_MARGIN_TOP) * CHOICE_BUBBLE_SCALE
	label.size = Vector2(
		bubble_size.x - (CHOICE_TEXT_MARGIN_LEFT + CHOICE_TEXT_MARGIN_RIGHT) * CHOICE_BUBBLE_SCALE,
		bubble_size.y - (CHOICE_TEXT_MARGIN_TOP + CHOICE_TEXT_MARGIN_BOTTOM) * CHOICE_BUBBLE_SCALE
	)

func _apply_choice_to_button(button: TextureButton, label: Label, choices: Array[Dictionary], index: int) -> void:
	if index >= choices.size():
		button.visible = false
		button.disabled = true
		label.text = ""
		return

	var choice := choices[index]
	button.visible = true
	button.disabled = false
	button.set_meta("choice_id", str(choice.get("id", "")))
	button.set_meta("choice_text", str(choice.get("text", "")))
	label.text = _clamp_text(str(choice.get("text", "")), CHOICE_TEXT_MAX_CHARS)

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

func _relayout_messages(animated: bool) -> void:
	if _message_nodes.is_empty():
		return

	var latest_message := _message_nodes[_message_nodes.size() - 1]
	var latest_message_top := clampf(
		size.y * LATEST_MESSAGE_TOP_RATIO,
		VIEWPORT_PADDING_VERTICAL,
		maxf(
			VIEWPORT_PADDING_VERTICAL,
			size.y - VIEWPORT_PADDING_VERTICAL - latest_message.size.y
		)
	)
	var bottom_y := latest_message_top + latest_message.size.y
	var tween := create_tween() if animated else null
	if tween != null:
		tween.set_parallel(true)

	for index in range(_message_nodes.size() - 1, -1, -1):
		var message_node := _message_nodes[index]
		if index != _message_nodes.size() - 1:
			bottom_y -= message_node.size.y
		var align_side := str(message_node.get_meta("align_side", "left"))
		var target_x: float = VIEWPORT_PADDING_LEFT if align_side == "left" else maxf(VIEWPORT_PADDING_LEFT, size.x - VIEWPORT_PADDING_RIGHT - message_node.size.x)
		var target_position := Vector2(target_x, bottom_y - message_node.size.y)
		if tween != null:
			tween.tween_property(message_node, "position", target_position, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			message_node.position = target_position
		bottom_y -= MESSAGE_GAP

	_prune_old_messages()

func _prune_old_messages() -> void:
	while _message_nodes.size() > MAX_VISIBLE_MESSAGES:
		var message_node := _message_nodes[0]
		if message_node.position.y + message_node.size.y >= 0.0:
			break
		_message_nodes.remove_at(0)
		message_node.queue_free()

	while _message_nodes.size() > MAX_VISIBLE_MESSAGES + 1:
		var oldest := _message_nodes[0]
		_message_nodes.remove_at(0)
		oldest.queue_free()

func _get_texture_size(texture: Texture2D, fallback_size: Vector2) -> Vector2:
	if texture == null:
		return fallback_size
	return Vector2(texture.get_width(), texture.get_height())

func _clamp_text(text_value: String, max_chars: int) -> String:
	var cleaned := text_value.strip_edges()
	if cleaned.length() <= max_chars:
		return cleaned
	return "%s..." % cleaned.substr(0, max_chars - 3).rstrip(" .,!?")

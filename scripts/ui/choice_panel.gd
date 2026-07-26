class_name ChoicePanel
extends Control

signal choice_selected(choice_quality: String, choice_text: String)

const CHOICE_TEXT_MAX_CHARS := 64
const CHOICE_ENABLED_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const CHOICE_DISABLED_MODULATE := Color(0.42, 0.42, 0.42, 1.0)

@onready var choice_button_1: TextureButton = $ChoiceButton1
@onready var choice_button_2: TextureButton = $ChoiceButton2
@onready var choice_label_1: Label = $ChoiceButton1/Label
@onready var choice_label_2: Label = $ChoiceButton2/Label

var _choice_data: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	choice_button_1.pressed.connect(func() -> void: _emit_choice(0))
	choice_button_2.pressed.connect(func() -> void: _emit_choice(1))
	clear_choices()

func show_choices(choices: Variant) -> void:
	_choice_data = _normalize_choices(choices)
	_apply_choice_to_button(choice_button_1, choice_label_1, 0)
	_apply_choice_to_button(choice_button_2, choice_label_2, 1)
	visible = true

func clear_choices() -> void:
	visible = true
	_choice_data.clear()
	_apply_disabled_choice_button(choice_button_1, choice_label_1)
	_apply_disabled_choice_button(choice_button_2, choice_label_2)

func _apply_choice_to_button(button: TextureButton, label: Label, index: int) -> void:
	if index >= _choice_data.size():
		_apply_disabled_choice_button(button, label)
		label.text = ""
		return

	var choice := _choice_data[index]
	button.visible = true
	button.disabled = false
	label.text = _clamp_text(str(choice.get("text", "")), CHOICE_TEXT_MAX_CHARS)
	_set_choice_button_enabled_state(button, true)

func _apply_disabled_choice_button(button: TextureButton, label: Label) -> void:
	button.visible = true
	button.disabled = true
	label.text = ""
	_set_choice_button_enabled_state(button, false)

func _set_choice_button_enabled_state(button: TextureButton, enabled: bool) -> void:
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

func _clamp_text(text_value: String, max_chars: int) -> String:
	var cleaned := text_value.strip_edges()
	if cleaned.length() <= max_chars:
		return cleaned
	return "%s..." % cleaned.substr(0, max_chars - 3).rstrip(" .,!?")

@tool
class_name CurrentSpeechBubble
extends Control

signal advance_requested()

@export var max_width: float = 420.0:
	set(value):
		max_width = maxf(value, 120.0)
		_refresh_layout()
@export var minimum_bubble_size: Vector2 = Vector2(180.0, 72.0):
	set(value):
		minimum_bubble_size = value
		_refresh_layout()
@export var text_margins: Vector4 = Vector4(24.0, 16.0, 28.0, 18.0):
	set(value):
		text_margins = value
		_refresh_layout()

@onready var margin_container: MarginContainer = $MarginContainer
@onready var text_label: Label = $MarginContainer/TextLabel
@onready var speaker_label: Label = $SpeakerLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_layout()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		accept_event()
		advance_requested.emit()

func set_dialogue_text(text_value: String) -> void:
	if not is_node_ready():
		return
	text_label.text = text_value.strip_edges()
	_refresh_layout()

func set_speaker_text(speaker_text: String) -> void:
	if is_node_ready():
		speaker_label.text = speaker_text
		speaker_label.visible = not speaker_text.is_empty()

func resolve_size() -> Vector2:
	if not is_node_ready():
		return size
	_refresh_layout()
	return size

func _refresh_layout() -> void:
	if not is_node_ready():
		return
	var horizontal_margin := text_margins.x + text_margins.z
	var vertical_margin := text_margins.y + text_margins.w
	var label_width := maxf(1.0, max_width - horizontal_margin)

	margin_container.add_theme_constant_override("margin_left", int(round(text_margins.x)))
	margin_container.add_theme_constant_override("margin_top", int(round(text_margins.y)))
	margin_container.add_theme_constant_override("margin_right", int(round(text_margins.z)))
	margin_container.add_theme_constant_override("margin_bottom", int(round(text_margins.w)))

	text_label.custom_minimum_size.x = label_width
	text_label.size.x = label_width
	text_label.update_minimum_size()

	var resolved_size := Vector2(
		maxf(minimum_bubble_size.x, max_width),
		minimum_bubble_size.y
	)
	custom_minimum_size = resolved_size
	size = resolved_size

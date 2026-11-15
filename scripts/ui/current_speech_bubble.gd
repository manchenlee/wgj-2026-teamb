@tool
class_name CurrentSpeechBubble
extends Control

signal advance_requested()

const STREAM_CHARACTERS_PER_SECOND := 40.0

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

var _stream_progress: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	_refresh_layout()

func _process(delta: float) -> void:
	_stream_progress += delta * STREAM_CHARACTERS_PER_SECOND
	text_label.visible_characters = mini(int(_stream_progress), text_label.get_total_character_count())
	if not is_streaming():
		finish_dialogue_stream()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		accept_event()
		advance_requested.emit()

func set_dialogue_text(text_value: String) -> void:
	if not is_node_ready():
		return
	text_label.text = text_value.strip_edges()
	_stream_progress = 0.0
	text_label.visible_characters = 0 if not text_label.text.is_empty() else -1
	set_process(not text_label.text.is_empty())
	_refresh_layout()

func is_streaming() -> bool:
	return is_node_ready() and text_label.visible_characters >= 0 \
			and text_label.visible_characters < text_label.get_total_character_count()

func finish_dialogue_stream() -> void:
	if not is_node_ready():
		return
	text_label.visible_characters = -1
	set_process(false)

func get_stream_duration() -> float:
	if not is_node_ready():
		return 0.0
	return float(text_label.get_total_character_count()) / STREAM_CHARACTERS_PER_SECOND

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

extends Control

const CHARACTER_SPEAKER_TYPES := {
	"companion": true,
	"system": true
}
const VIEWPORT_SAFE_MARGIN := 16.0
const TOP_SAFE_MARGIN := 88.0

@onready var current_speech_bubble: CurrentSpeechBubble = $CurrentSpeechBubble

var _history: Array[Dictionary] = []
var _speech_bubble_anchor: Control = null
var _active_character_line: String = ""
var _active_line_version: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	if current_speech_bubble != null:
		current_speech_bubble.visible = false
		current_speech_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_position_active_bubble()

func set_speech_bubble_anchor(anchor: Control) -> void:
	_speech_bubble_anchor = anchor
	_position_active_bubble()

func refresh_active_dialogue_position() -> void:
	_position_active_bubble()

func show_prompt(_text_value: String) -> void:
	pass

func hide_prompt() -> void:
	pass

func clear_history() -> void:
	_history.clear()
	_active_character_line = ""
	_active_line_version += 1
	if current_speech_bubble != null:
		current_speech_bubble.visible = false

func append_history(line: String, speaker_type: String = "companion") -> void:
	var cleaned_line := line.strip_edges()
	_history.append({
		"line": cleaned_line,
		"speaker_type": speaker_type
	})
	if _is_character_speaker(speaker_type):
		_show_current_character_line(cleaned_line)

func restore_current_character_line(line: String) -> void:
	_show_current_character_line(line.strip_edges())

func set_choice_timeout_progress(_progress: float) -> void:
	pass

func get_dialogue_history() -> Array[Dictionary]:
	return _history.duplicate(true)

func get_active_dialogue_global_rect() -> Rect2:
	if current_speech_bubble == null or not current_speech_bubble.visible:
		return Rect2()
	return current_speech_bubble.get_global_rect()

func _show_current_character_line(line: String) -> void:
	_active_character_line = line
	_active_line_version += 1
	var line_version := _active_line_version
	if current_speech_bubble == null:
		return
	if line.is_empty():
		current_speech_bubble.visible = false
		return
	current_speech_bubble.set_dialogue_text(line)
	await get_tree().process_frame
	if line_version != _active_line_version:
		return
	_position_active_bubble()
	current_speech_bubble.visible = true

func _position_active_bubble() -> void:
	if current_speech_bubble == null or _speech_bubble_anchor == null or _active_character_line.is_empty():
		return
	current_speech_bubble.resolve_size()
	var anchor_global_position := _speech_bubble_anchor.get_global_rect().get_center()
	var local_anchor_position := get_global_transform_with_canvas().affine_inverse() * anchor_global_position

	# The editor marker represents the bubble's preferred bottom-right corner.
	var target_position := local_anchor_position - current_speech_bubble.size
	var safe_rect := Rect2(
		Vector2(VIEWPORT_SAFE_MARGIN, TOP_SAFE_MARGIN),
		Vector2(
			maxf(0.0, size.x - VIEWPORT_SAFE_MARGIN * 2.0),
			maxf(0.0, size.y - TOP_SAFE_MARGIN - VIEWPORT_SAFE_MARGIN)
		)
	)
	var max_position := safe_rect.end - current_speech_bubble.size
	max_position.x = maxf(safe_rect.position.x, max_position.x)
	max_position.y = maxf(safe_rect.position.y, max_position.y)
	current_speech_bubble.position = Vector2(
		clampf(target_position.x, safe_rect.position.x, max_position.x),
		clampf(target_position.y, safe_rect.position.y, max_position.y)
	)

func _is_character_speaker(speaker_type: String) -> bool:
	return CHARACTER_SPEAKER_TYPES.has(speaker_type)

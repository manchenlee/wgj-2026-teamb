class_name CharacterPresenter
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var character_placeholder: TextureRect = $CharacterVisualAnchor/CharacterPlaceholder
@onready var emotion_state_label: Label = $TopLabelStack/EmotionStateLabel
@onready var reaction_label: Label = $TopLabelStack/ReactionLabel
@onready var prompt_layer: Control = $PromptLayer
@onready var prompt_feedback_label: Label = $PromptLayer/PromptFeedbackLabel
@onready var prompt_timer_line: Line2D = $PromptLayer/PromptTimerLine

var _default_scale := Vector2.ONE
var _prompt_nodes: Dictionary = {}
var _prompt_offsets: Dictionary = {}
var _current_prompt_id: int = -1
var _prompt_time_progress: float = 1.0

func _ready() -> void:
	_default_scale = character_placeholder.scale
	emotion_state_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	reaction_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	prompt_feedback_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	prompt_feedback_label.add_theme_font_size_override("font_size", 24)
	prompt_timer_line.width = Config.ARROW_PROMPT_RING_WIDTH
	prompt_timer_line.default_color = Color(0.24, 0.24, 0.28, 0.82)
	prompt_timer_line.closed = false
	prompt_timer_line.visible = false
	update_emotion_state("CALM")
	_set_reaction("...")
	clear_direction_prompts()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_refresh_prompt_layout()

func show_correct_reaction() -> void:
	_set_reaction("!")
	_pulse(Color(0.85, 0.24, 0.24, 1.0), 1.08)

func show_mistake_reaction() -> void:
	_set_reaction("?")
	_pulse(Color(0.35, 0.45, 0.85, 1.0), 0.92)

func show_ignored_reaction() -> void:
	_set_reaction("...")
	_pulse(Color(0.55, 0.55, 0.62, 1.0), 0.96)

func show_choice_reaction(choice_quality: String) -> void:
	match choice_quality:
		"good":
			_set_reaction("Yay!")
			_pulse(Color(0.9, 0.74, 0.2, 1.0), 1.05)
		"neutral":
			_set_reaction("...")
			_pulse(Color(0.7, 0.7, 0.7, 1.0), 1.0)
		"bad":
			_set_reaction("Hm.")
			_pulse(Color(0.45, 0.45, 0.55, 1.0), 0.95)

func update_emotion_state(state: String) -> void:
	emotion_state_label.text = "State: %s" % state
	var color := Color(0.7, 0.7, 0.7, 1.0)
	match state:
		"SAD":
			color = Color(0.35, 0.45, 0.85, 1.0)
		"UNEASY":
			color = Color(0.58, 0.58, 0.75, 1.0)
		"CALM":
			color = Color(0.6, 0.7, 0.7, 1.0)
		"ENGAGED":
			color = Color(0.9, 0.55, 0.3, 1.0)
		"EXCITED":
			color = Color(0.92, 0.22, 0.22, 1.0)
	_apply_style(character_placeholder, color)

func show_direction_prompt(prompt_id: int, direction: String, anchor_offset: Vector2) -> void:
	_prompt_offsets[prompt_id] = anchor_offset
	var prompt_label := _ensure_prompt_label(prompt_id)
	prompt_label.text = _to_arrow(direction)
	prompt_label.visible = true
	prompt_label.scale = Vector2.ONE
	prompt_label.modulate = Color(0.9, 0.9, 0.95, 0.0)
	_refresh_prompt_layout()

	var tween := create_tween()
	tween.tween_property(prompt_label, "modulate:a", 0.46, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func set_current_prompt(prompt_id: int) -> void:
	_current_prompt_id = prompt_id
	for key in _prompt_nodes.keys():
		var prompt_label: Label = _prompt_nodes[key]
		prompt_label.modulate.a = 1.0 if int(key) == _current_prompt_id else 0.46
	_prompt_time_progress = 1.0
	_update_prompt_timer_ring()

func set_prompt_time_progress(progress: float) -> void:
	_prompt_time_progress = clampf(progress, 0.0, 1.0)
	var current_label := _get_current_prompt_label()
	if current_label != null and current_label.visible:
		current_label.modulate.a = lerpf(0.22, 1.0, _prompt_time_progress)
	_update_prompt_timer_ring()

func remove_direction_prompt(prompt_id: int) -> void:
	if not _prompt_nodes.has(prompt_id):
		return
	var prompt_label: Label = _prompt_nodes[prompt_id]
	prompt_label.queue_free()
	_prompt_nodes.erase(prompt_id)
	_prompt_offsets.erase(prompt_id)
	if _current_prompt_id == prompt_id:
		_current_prompt_id = -1
	_update_prompt_timer_ring()

func clear_direction_prompts() -> void:
	for prompt_label in _prompt_nodes.values():
		prompt_label.queue_free()
	_prompt_nodes.clear()
	_prompt_offsets.clear()
	_current_prompt_id = -1
	_prompt_time_progress = 0.0
	_update_prompt_timer_ring()

func show_prompt_feedback(text_value: String, color: Color, display_duration: float) -> void:
	prompt_feedback_label.text = text_value
	prompt_feedback_label.visible = true
	prompt_feedback_label.modulate = Color(color.r, color.g, color.b, 0.0)
	_position_feedback_label()
	var start_y := prompt_feedback_label.position.y

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(prompt_feedback_label, "modulate:a", 1.0, 0.1)
	tween.tween_property(prompt_feedback_label, "position:y", start_y - 12.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(display_duration)
	tween.set_parallel(true)
	tween.tween_property(prompt_feedback_label, "modulate:a", 0.0, 0.18)
	tween.tween_property(prompt_feedback_label, "position:y", start_y - 22.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: prompt_feedback_label.visible = false)

func _set_reaction(text_value: String) -> void:
	reaction_label.text = "Reaction: %s" % text_value

func _pulse(color: Color, scale_multiplier: float) -> void:
	_apply_style(character_placeholder, color)
	var tween := create_tween()
	tween.tween_property(character_placeholder, "scale", _default_scale * scale_multiplier, 0.12)
	tween.tween_property(character_placeholder, "scale", _default_scale, 0.18)

func _apply_style(_texture_rect: TextureRect, _color: Color) -> void:
	return

func _refresh_prompt_layout() -> void:
	if prompt_feedback_label == null:
		return
	var character_rect := _get_character_rect_local()
	for key in _prompt_nodes.keys():
		var prompt_label: Label = _prompt_nodes[key]
		var prompt_offset: Vector2 = _prompt_offsets.get(key, Vector2.ZERO)
		var prompt_size := prompt_label.size
		var desired_center := character_rect.get_center() + prompt_offset
		var half_size := prompt_size * 0.5
		var min_x := character_rect.position.x + half_size.x + Config.ARROW_PROMPT_EDGE_MARGIN
		var max_x := character_rect.end.x - half_size.x - Config.ARROW_PROMPT_EDGE_MARGIN
		var min_y := character_rect.position.y + half_size.y + Config.ARROW_PROMPT_EDGE_MARGIN
		var max_y := character_rect.end.y - half_size.y - Config.ARROW_PROMPT_EDGE_MARGIN
		var clamped_center := Vector2(
			clampf(desired_center.x, min_x, max_x),
			clampf(desired_center.y, min_y, max_y)
		)
		prompt_label.position = clamped_center - half_size
	_update_prompt_timer_ring()
	if prompt_feedback_label.visible:
		_position_feedback_label()

func _position_feedback_label() -> void:
	var center := _get_feedback_anchor_center()
	var feedback_size := prompt_feedback_label.get_combined_minimum_size()
	prompt_feedback_label.position = center + Vector2(0.0, -74.0) - (feedback_size * 0.5)

func _get_character_center_local() -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * character_placeholder.get_global_rect().get_center()

func _get_character_rect_local() -> Rect2:
	var global_rect := character_placeholder.get_global_rect()
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_rect.position
	return Rect2(local_position, global_rect.size)

func _get_feedback_anchor_center() -> Vector2:
	var current_label := _get_current_prompt_label()
	if current_label == null:
		return _get_character_center_local()
	return current_label.position + (current_label.get_combined_minimum_size() * 0.5)

func _ensure_prompt_label(prompt_id: int) -> Label:
	if _prompt_nodes.has(prompt_id):
		return _prompt_nodes[prompt_id]
	var prompt_label := Label.new()
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.visible = false
	prompt_label.text = "↑"
	prompt_label.custom_minimum_size = Config.ARROW_PROMPT_BOX_SIZE
	prompt_label.size = Config.ARROW_PROMPT_BOX_SIZE
	prompt_label.pivot_offset = Config.ARROW_PROMPT_BOX_SIZE * 0.5
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", Config.ARROW_PROMPT_FONT_SIZE)
	prompt_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.14, 1.0))
	prompt_layer.add_child(prompt_label)
	_prompt_nodes[prompt_id] = prompt_label
	return prompt_label

func _get_current_prompt_label() -> Label:
	if not _prompt_nodes.has(_current_prompt_id):
		return null
	return _prompt_nodes[_current_prompt_id]

func _update_prompt_timer_ring() -> void:
	var current_label := _get_current_prompt_label()
	if current_label == null or not current_label.visible:
		prompt_timer_line.visible = false
		prompt_timer_line.clear_points()
		return

	var center := current_label.position + (current_label.size * 0.5)
	var radius := Config.ARROW_PROMPT_RING_RADIUS
	var steps := 48
	var points: Array[Vector2] = []
	var start_angle := -PI * 0.5
	var end_angle := start_angle + (TAU * _prompt_time_progress)
	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var angle := lerpf(start_angle, end_angle, t)
		points.append(center + Vector2.RIGHT.rotated(angle) * radius)
	prompt_timer_line.points = points
	prompt_timer_line.visible = points.size() >= 2 and _prompt_time_progress > 0.0

func _to_arrow(direction: String) -> String:
	match direction:
		"Left":
			return "←"
		"Right":
			return "→"
		"Up":
			return "↑"
		"Down":
			return "↓"
		_:
			return "?"

class_name CharacterPresenter
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var character_placeholder: Panel = $CharacterVisualAnchor/CharacterPlaceholder
@onready var emotion_state_label: Label = $TopLabelStack/EmotionStateLabel
@onready var reaction_label: Label = $TopLabelStack/ReactionLabel
@onready var direction_prompt_label: Label = $PromptLayer/DirectionPromptLabel
@onready var prompt_feedback_label: Label = $PromptLayer/PromptFeedbackLabel

var _default_scale := Vector2.ONE
var _current_prompt_offset := Vector2.ZERO
var _prompt_time_progress: float = 1.0

func _ready() -> void:
	_default_scale = character_placeholder.scale
	direction_prompt_label.add_theme_font_size_override("font_size", Config.ARROW_PROMPT_FONT_SIZE)
	prompt_feedback_label.add_theme_font_size_override("font_size", 24)
	update_emotion_state("CALM")
	_set_reaction("...")
	clear_direction_prompt()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_refresh_prompt_layout()

func _draw() -> void:
	if not direction_prompt_label.visible:
		return
	var prompt_size := direction_prompt_label.get_combined_minimum_size()
	var prompt_center := direction_prompt_label.position + (prompt_size * 0.5)
	var radius: float = maxf(prompt_size.x, prompt_size.y) * 0.52
	var start_angle := -PI * 0.5
	var end_angle := start_angle + (TAU * _prompt_time_progress)
	draw_arc(
		prompt_center,
		radius,
		start_angle,
		end_angle,
		48,
		Color(1.0, 0.94, 0.68, 0.72),
		3.0,
		true
	)

func show_correct_reaction() -> void:
	_set_reaction("!")
	_pulse(Color(0.85, 0.24, 0.24, 1.0), 1.08)

func show_mistake_reaction() -> void:
	_set_reaction("?")
	_pulse(Color(0.35, 0.45, 0.85, 1.0), 0.92)

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

func show_direction_prompt(direction: String, anchor_offset: Vector2) -> void:
	_current_prompt_offset = anchor_offset
	_prompt_time_progress = 1.0
	direction_prompt_label.text = _to_arrow(direction)
	direction_prompt_label.visible = true
	direction_prompt_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	direction_prompt_label.scale = Vector2(0.82, 0.82)
	_refresh_prompt_layout()
	queue_redraw()

	var tween := create_tween()
	tween.tween_property(direction_prompt_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_prompt_time_progress(progress: float) -> void:
	_prompt_time_progress = clampf(progress, 0.0, 1.0)
	if direction_prompt_label.visible:
		direction_prompt_label.modulate.a = lerpf(0.22, 1.0, _prompt_time_progress)
	queue_redraw()

func clear_direction_prompt() -> void:
	direction_prompt_label.visible = false
	direction_prompt_label.text = ""
	_current_prompt_offset = Vector2.ZERO
	_prompt_time_progress = 0.0
	queue_redraw()

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

func _apply_style(panel: Panel, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	panel.add_theme_stylebox_override("panel", style)

func _refresh_prompt_layout() -> void:
	if direction_prompt_label == null or prompt_feedback_label == null:
		return
	if direction_prompt_label.visible:
		var center := _get_character_center_local()
		var prompt_size := direction_prompt_label.get_combined_minimum_size()
		direction_prompt_label.position = center + _current_prompt_offset - (prompt_size * 0.5)
	if prompt_feedback_label.visible:
		_position_feedback_label()

func _position_feedback_label() -> void:
	var center := _get_character_center_local()
	var feedback_size := prompt_feedback_label.get_combined_minimum_size()
	prompt_feedback_label.position = center + _current_prompt_offset + Vector2(0.0, -74.0) - (feedback_size * 0.5)

func _get_character_center_local() -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * character_placeholder.get_global_rect().get_center()

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

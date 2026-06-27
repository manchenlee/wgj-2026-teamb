class_name CharacterPresenter
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var character_placeholder: TextureRect = $CharacterVisualAnchor/CharacterPlaceholder
@onready var emotion_state_label: Label = $TopLabelStack/EmotionStateLabel
@onready var reaction_label: Label = $TopLabelStack/ReactionLabel
@onready var prompt_layer: Control = $PromptLayer
@onready var prompt_feedback_label: Label = $PromptLayer/PromptFeedbackLabel

var _default_scale := Vector2.ONE

func _ready() -> void:
	_default_scale = character_placeholder.scale
	emotion_state_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	reaction_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	prompt_feedback_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	prompt_feedback_label.add_theme_font_size_override("font_size", Config.PROMPT_FEEDBACK_FONT_SIZE)
	update_emotion_state("CALM")
	_set_reaction("...")


# ---------------------------------------------------------------------------
# Reactions
# ---------------------------------------------------------------------------

func show_correct_reaction() -> void:
	_set_reaction("!")
	_pulse(Color(0.85, 0.24, 0.24, 1.0), 1.08)


func show_mistake_reaction() -> void:
	_set_reaction("?")
	_pulse(Color(0.35, 0.45, 0.85, 1.0), 0.92)


func show_ignored_reaction() -> void:
	_set_reaction("...")
	_pulse(Color(0.55, 0.55, 0.62, 1.0), 0.96)


func show_spot_reaction(strength: String) -> void:
	match strength:
		"strong":
			_set_reaction("~♥")
			_pulse(Color(0.95, 0.45, 0.2, 1.0), 1.1)
		"mild":
			_set_reaction("...")
			_pulse(Color(0.55, 0.55, 0.62, 1.0), 0.95)
		_:
			_set_reaction("~")
			_pulse(Color(0.85, 0.65, 0.3, 1.0), 1.02)


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


# ---------------------------------------------------------------------------
# Emotion state
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Feedback label (used for spot gain/penalty floating text)
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _set_reaction(text_value: String) -> void:
	reaction_label.text = "Reaction: %s" % text_value


func _pulse(color: Color, scale_multiplier: float) -> void:
	_apply_style(character_placeholder, color)
	var tween := create_tween()
	tween.tween_property(character_placeholder, "scale", _default_scale * scale_multiplier, 0.12)
	tween.tween_property(character_placeholder, "scale", _default_scale, 0.18)


func _apply_style(_texture_rect: TextureRect, _color: Color) -> void:
	return


func _position_feedback_label() -> void:
	var center := _get_character_center_local()
	var feedback_size := prompt_feedback_label.get_combined_minimum_size()
	prompt_feedback_label.position = center + Vector2(0.0, -74.0) - (feedback_size * 0.5)


func _get_character_center_local() -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * character_placeholder.get_global_rect().get_center()


func _get_character_rect_local() -> Rect2:
	var global_rect := character_placeholder.get_global_rect()
	var local_position := get_global_transform_with_canvas().affine_inverse() * global_rect.position
	return Rect2(local_position, global_rect.size)

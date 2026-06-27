class_name CharacterPresenter
extends Control

@onready var character_placeholder: Panel = $CharacterVisualAnchor/CharacterPlaceholder
@onready var emotion_state_label: Label = $EmotionStateLabel
@onready var reaction_label: Label = $ReactionLabel

var _default_scale := Vector2.ONE

func _ready() -> void:
	_default_scale = character_placeholder.scale
	update_emotion_state("CALM")
	_set_reaction("...")

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


class_name CentralArousalVisualization
extends Control

const Config := preload("res://scripts/core/game_config.gd")

@onready var physical_circle: Panel = $PhysicalCirclePlaceholder
@onready var emotional_circle: Panel = $EmotionalCirclePlaceholder
@onready var peak_indicator: Label = $PeakIndicator

func _ready() -> void:
	_apply_circle_style(physical_circle, Color(0.95, 0.18, 0.18, 0.42))
	_apply_circle_style(emotional_circle, Color(0.95, 0.84, 0.18, 0.42))
	set_values(Config.INITIAL_PHYSICAL, Config.INITIAL_EMOTIONAL, Config.INITIAL_PEAK)

func set_values(physical: float, emotional: float, peak: float) -> void:
	var physical_scale := lerpf(0.45, 1.0, physical / Config.MAX_VALUE)
	var emotional_scale := lerpf(0.45, 1.0, emotional / Config.MAX_VALUE)

	physical_circle.scale = Vector2.ONE * physical_scale
	emotional_circle.scale = Vector2.ONE * emotional_scale
	physical_circle.position = Vector2(110.0, 90.0)
	emotional_circle.position = Vector2(190.0, 110.0)
	peak_indicator.text = "Peak %d" % int(round(peak))
	peak_indicator.modulate = Color(1.0, 1.0, 1.0, lerpf(0.45, 1.0, peak / Config.MAX_VALUE))

func _apply_circle_style(panel: Panel, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 220
	style.corner_radius_top_right = 220
	style.corner_radius_bottom_left = 220
	style.corner_radius_bottom_right = 220
	panel.add_theme_stylebox_override("panel", style)

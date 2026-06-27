class_name CentralArousalVisualization
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@export_node_path("Control") var character_placeholder_path: NodePath

@onready var peak_indicator: Label = $PeakIndicator

var physical_value: float = Config.INITIAL_PHYSICAL
var emotional_value: float = Config.INITIAL_EMOTIONAL
var peak_value: float = Config.INITIAL_PEAK
var pulse_time: float = 0.0
var character_placeholder: Control

func _ready() -> void:
	if not character_placeholder_path.is_empty():
		character_placeholder = get_node_or_null(character_placeholder_path)
	set_values(Config.INITIAL_PHYSICAL, Config.INITIAL_EMOTIONAL, Config.INITIAL_PEAK)

func _process(delta: float) -> void:
	pulse_time += delta
	queue_redraw()
	_sync_peak_indicator()

func set_values(physical: float, emotional: float, peak: float) -> void:
	physical_value = Config.clamp_value(physical)
	emotional_value = Config.clamp_value(emotional)
	peak_value = Config.clamp_value(peak)
	peak_indicator.text = "Peak %d" % int(round(peak))
	peak_indicator.modulate = Color(0.12, 0.12, 0.16, lerpf(0.55, 1.0, peak_value / Config.MAX_VALUE))
	queue_redraw()
	_sync_peak_indicator()

func _draw() -> void:
	if character_placeholder == null:
		return

	var center := _get_character_center()
	var pulse := sin(pulse_time * 2.6) * 2.0
	var physical_ratio := physical_value / Config.MAX_VALUE
	var emotional_ratio := emotional_value / Config.MAX_VALUE
	var physical_radius := lerpf(Config.CIRCLE_RADIUS_MIN, Config.CIRCLE_RADIUS_MAX, physical_ratio) + pulse
	var emotional_radius := lerpf(Config.CIRCLE_RADIUS_MIN, Config.CIRCLE_RADIUS_MAX, emotional_ratio) - pulse
	var physical_width := lerpf(Config.CIRCLE_STROKE_MIN, Config.CIRCLE_STROKE_MAX, physical_ratio)
	var emotional_width := lerpf(Config.CIRCLE_STROKE_MIN, Config.CIRCLE_STROKE_MAX, emotional_ratio)
	var physical_color := Color(0.94, 0.18, 0.18, lerpf(0.5, 0.95, physical_ratio))
	var emotional_color := Color(0.95, 0.84, 0.18, lerpf(0.45, 0.9, emotional_ratio))

	draw_arc(center, physical_radius, 0.0, TAU, 96, physical_color, physical_width, true)
	draw_arc(center, emotional_radius, 0.0, TAU, 96, emotional_color, emotional_width, true)

func _get_character_center() -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * character_placeholder.get_global_rect().get_center()

func _sync_peak_indicator() -> void:
	if character_placeholder == null:
		return
	var center := _get_character_center()
	peak_indicator.position = center + Vector2(-40.0, Config.PEAK_LABEL_OFFSET_Y)

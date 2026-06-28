class_name CentralArousalVisualization
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const PHYSICAL_RING_TEXTURE := preload("res://assets/art/ui/circle_red.png")
const EMOTIONAL_RING_TEXTURE := preload("res://assets/art/ui/circle_yellow.png")
const MAX_RING_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const MAX_RING_DASH_COUNT := 48
const MAX_RING_DASH_RATIO := 0.55

@export_node_path("Control") var character_placeholder_path: NodePath

@onready var peak_indicator: Label = $PeakIndicator

var physical_value: float = Config.INITIAL_PHYSICAL
var emotional_value: float = Config.INITIAL_EMOTIONAL
var peak_value: float = Config.INITIAL_PEAK
var pulse_time: float = 0.0
var character_placeholder: Control
var physical_ring: TextureRect
var emotional_ring: TextureRect

func _ready() -> void:
	if not character_placeholder_path.is_empty():
		character_placeholder = get_node_or_null(character_placeholder_path)
	physical_ring = _ensure_ring_sprite("PhysicalRing", PHYSICAL_RING_TEXTURE, 1)
	emotional_ring = _ensure_ring_sprite("EmotionalRing", EMOTIONAL_RING_TEXTURE, 2)
	set_values(Config.INITIAL_PHYSICAL, Config.INITIAL_EMOTIONAL, Config.INITIAL_PEAK)
	_sync_circle_sprites()

func _process(delta: float) -> void:
	pulse_time += delta
	_sync_circle_sprites()
	_sync_peak_indicator()
	queue_redraw()

func set_values(physical: float, emotional: float, peak: float) -> void:
	physical_value = Config.clamp_value(physical)
	emotional_value = Config.clamp_value(emotional)
	peak_value = Config.clamp_value(peak)
	peak_indicator.text = "Peak %d" % int(round(peak))
	peak_indicator.modulate = Color(0.12, 0.12, 0.16, lerpf(0.55, 1.0, peak_value / Config.MAX_VALUE))
	_sync_circle_sprites()
	_sync_peak_indicator()
	queue_redraw()

func _draw() -> void:
	_draw_max_ring_outline()

func _get_character_center() -> Vector2:
	if character_placeholder != null and character_placeholder.visible:
		return get_global_transform_with_canvas().affine_inverse() * character_placeholder.get_global_rect().get_center()
	return size * Config.CIRCLE_CENTER_RATIO

func _sync_peak_indicator() -> void:
	var center := _get_character_center()
	peak_indicator.position = center + Vector2(Config.PEAK_LABEL_OFFSET_X, Config.PEAK_LABEL_OFFSET_Y)

func _draw_max_ring_outline() -> void:
	var center := _get_character_center()
	var radius := Config.CIRCLE_RADIUS_MAX
	var line_width := Config.CIRCLE_STROKE_MAX
	var full_turn := TAU
	var dash_angle := full_turn / float(MAX_RING_DASH_COUNT)
	var visible_angle := dash_angle * MAX_RING_DASH_RATIO

	for index in range(MAX_RING_DASH_COUNT):
		var start_angle := dash_angle * index
		draw_arc(center, radius, start_angle, start_angle + visible_angle, 8, MAX_RING_OUTLINE_COLOR, line_width, true)

func _ensure_ring_sprite(node_name: String, texture: Texture2D, z_order: int) -> TextureRect:
	var ring := get_node_or_null(node_name) as TextureRect
	if ring == null:
		ring = TextureRect.new()
		ring.name = node_name
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(ring)
	ring.texture = texture
	# z_as_relative = false so the ring uses a global z_index directly.
	# Rings must sit above the background (z=0) but below the character
	# image BackgroundPlaceholder (z=2, z_as_relative=false), so we use
	# global z = 0 and 1 (mapped from the incoming z_order of 1 and 2).
	ring.z_as_relative = false
	ring.z_index = z_order - 1  # z_order 1 → global 0, z_order 2 → global 1
	return ring

func _sync_circle_sprites() -> void:
	if physical_ring == null or emotional_ring == null:
		return
	var center := _get_character_center()
	var pulse := sin(pulse_time * 2.6) * 2.0
	var physical_ratio := physical_value / Config.MAX_VALUE
	var emotional_ratio := emotional_value / Config.MAX_VALUE
	var physical_radius := lerpf(Config.CIRCLE_RADIUS_MIN, Config.CIRCLE_RADIUS_MAX, physical_ratio) + pulse
	var emotional_radius := lerpf(Config.CIRCLE_RADIUS_MIN, Config.CIRCLE_RADIUS_MAX, emotional_ratio) - pulse
	_sync_ring_sprite(
		physical_ring,
		center,
		physical_radius,
		Color(1.0, 1.0, 1.0, lerpf(0.5, 0.95, physical_ratio))
	)
	_sync_ring_sprite(
		emotional_ring,
		center,
		emotional_radius,
		Color(1.0, 1.0, 1.0, lerpf(0.45, 0.9, emotional_ratio))
	)

func _sync_ring_sprite(ring: TextureRect, center: Vector2, radius: float, color: Color) -> void:
	var diameter := radius * 2.0
	ring.size = Vector2.ONE * diameter
	ring.position = center - (ring.size * 0.5)
	ring.modulate = color

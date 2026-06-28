class_name CharacterPresenter
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const DIRECTION_TEXTURE_PATH := "res://assets/art/ui/direction.png"
const METALLIC_SHEEN_SHADER := preload("res://scripts/ui/metallic_sheen_2d.gdshader")
const DIRECTION_ALPHA_THRESHOLD := 0.02
const DIRECTION_CROP_MARGIN := 0
const DIRECTION_ICON_PADDING := 12.0
const TIMER_RING_TEXTURE_SIZE := 256
const TIMER_RING_BASE_PHASE_STEP := 0.73
const TIMER_RING_COLOR := Color(0.83, 0.73, 0.42, 1.0)
const SUCCESS_NOTE_GLYPHS := ["♪", "♫"]
const SUCCESS_NOTE_COUNT := 3
const SUCCESS_NOTE_RISE_DISTANCE := 52.0
const SUCCESS_NOTE_LIFETIME := 0.72

@onready var character_placeholder: TextureRect = $CharacterVisualAnchor/CharacterPlaceholder
@onready var prompt_layer: Control = $PromptLayer
@onready var prompt_feedback_label: Label = $PromptLayer/PromptFeedbackLabel

@export_group("Direction Metallic Shader")
@export var base_color: Color = Color(0.83, 0.73, 0.42, 1.0):
	set(value):
		base_color = value
		_update_prompt_shader_parameters()
@export var metal_color: Color = Color(0.97, 0.91, 0.72, 1.0):
	set(value):
		metal_color = value
		_update_prompt_shader_parameters()
@export_range(0.0, 2.0, 0.01) var shine_speed: float = 0.12:
	set(value):
		shine_speed = value
		_update_prompt_shader_parameters()
@export_range(0.02, 0.6, 0.01) var shine_width: float = 0.22:
	set(value):
		shine_width = value
		_update_prompt_shader_parameters()
@export_range(0.0, 2.0, 0.01) var shine_strength: float = 0.52:
	set(value):
		shine_strength = value
		_update_prompt_shader_parameters()
@export_range(0.0, 2.0, 0.01) var edge_strength: float = 0.22:
	set(value):
		edge_strength = value
		_update_prompt_shader_parameters()
@export_range(0.0, 6.28318, 0.01) var phase_offset: float = 0.0:
	set(value):
		phase_offset = value
		_update_prompt_shader_parameters()
@export var debug_metallic_prompt_effect: bool = false:
	set(value):
		debug_metallic_prompt_effect = value
		_update_prompt_shader_parameters()
@export_range(0.0, 4.0, 0.05) var debug_boost_amount: float = 2.2:
	set(value):
		debug_boost_amount = value
		_update_prompt_shader_parameters()

var _default_scale := Vector2.ONE
var _prompt_nodes: Dictionary = {}
var _prompt_positions: Dictionary = {}
var _prompt_timer_rings: Dictionary = {}
var _prompt_time_progresses: Dictionary = {}
var _prompt_phase_offsets: Dictionary = {}
var _prompt_ring_progress_cache: Dictionary = {}
var _current_prompt_id: int = -1
var _prompt_bounds_rect := Rect2()
var _direction_texture: Texture2D
var _direction_texture_warning_emitted := false

func _get_direction_texture() -> Texture2D:
	if _direction_texture != null:
		return _direction_texture

	if ResourceLoader.exists(DIRECTION_TEXTURE_PATH):
		var imported_texture := load(DIRECTION_TEXTURE_PATH) as Texture2D
		if imported_texture != null:
			var imported_image := imported_texture.get_image()
			if imported_image != null and not imported_image.is_empty():
				_direction_texture = ImageTexture.create_from_image(_prepare_direction_image(imported_image))
				return _direction_texture

	var absolute_path := ProjectSettings.globalize_path(DIRECTION_TEXTURE_PATH)
	if FileAccess.file_exists(absolute_path):
		var image := Image.load_from_file(absolute_path)
		if image != null and not image.is_empty():
			_direction_texture = ImageTexture.create_from_image(_prepare_direction_image(image))
			return _direction_texture

	if not _direction_texture_warning_emitted:
		_direction_texture_warning_emitted = true
		push_warning(
			"Direction arrow texture failed to load from %s. Falling back to generated arrow." % DIRECTION_TEXTURE_PATH
		)
	_direction_texture = _create_fallback_direction_texture()
	return _direction_texture

func _prepare_direction_image(source_image: Image) -> Image:
	var image := source_image.duplicate()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var crop_rect := _find_direction_alpha_bounds(image)
	if crop_rect.size.x <= 0 or crop_rect.size.y <= 0:
		return image

	var cropped: Image = image.get_region(crop_rect)
	for y in range(cropped.get_height()):
		for x in range(cropped.get_width()):
			var pixel := cropped.get_pixel(x, y)
			if pixel.a <= DIRECTION_ALPHA_THRESHOLD:
				cropped.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			else:
				cropped.set_pixel(x, y, Color(1.0, 1.0, 1.0, pixel.a))
	return cropped

func _find_direction_alpha_bounds(image: Image) -> Rect2i:
	var width := image.get_width()
	var height := image.get_height()
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1

	for y in range(height):
		for x in range(width):
			if image.get_pixel(x, y).a > DIRECTION_ALPHA_THRESHOLD:
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	if max_x < min_x or max_y < min_y:
		return Rect2i()

	min_x = max(0, min_x - DIRECTION_CROP_MARGIN)
	min_y = max(0, min_y - DIRECTION_CROP_MARGIN)
	max_x = min(width - 1, max_x + DIRECTION_CROP_MARGIN)
	max_y = min(height - 1, max_y + DIRECTION_CROP_MARGIN)
	return Rect2i(min_x, min_y, (max_x - min_x) + 1, (max_y - min_y) + 1)

func _create_fallback_direction_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var color := Color.WHITE

	for y in range(22, 56):
		for x in range(28, 36):
			image.set_pixel(x, y, color)

	for row in range(18):
		var start_x := 32 - row
		var end_x := 32 + row
		for x in range(start_x, end_x + 1):
			image.set_pixel(x, 4 + row, color)

	return ImageTexture.create_from_image(image)

func _ready() -> void:
	_default_scale = character_placeholder.scale
	prompt_feedback_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	prompt_feedback_label.add_theme_font_size_override("font_size", Config.PROMPT_FEEDBACK_FONT_SIZE)
	update_emotion_state("CALM")
	clear_direction_prompts()
	_update_prompt_shader_parameters()


# ---------------------------------------------------------------------------
# Reactions
# ---------------------------------------------------------------------------

func show_correct_reaction() -> void:
	_set_reaction("!")
	_pulse(Color(0.85, 0.24, 0.24, 1.0), 1.08)

func show_success_note_burst(prompt_id: int) -> void:
	var origin := _get_success_note_origin(prompt_id)
	for note_index in range(SUCCESS_NOTE_COUNT):
		_spawn_success_note_particle(origin, note_index)

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

func show_direction_prompt(prompt_id: int, direction: String, anchor_position: Vector2) -> void:
	_prompt_positions[prompt_id] = anchor_position
	var prompt_icon := _ensure_prompt_icon(prompt_id)
	prompt_icon.rotation = _direction_rotation(direction)
	prompt_icon.visible = true
	prompt_icon.scale = Vector2.ONE
	prompt_icon.modulate = Color(0.9, 0.9, 0.95, 1.0)
	_prompt_time_progresses[prompt_id] = 1.0
	_refresh_prompt_layout()

func set_current_prompt(prompt_id: int) -> void:
	_current_prompt_id = prompt_id
	for key in _prompt_nodes.keys():
		var prompt_icon: TextureRect = _prompt_nodes[key]
		prompt_icon.modulate.a = 1.0

func set_prompt_time_progresses(progress_by_prompt_id: Dictionary) -> void:
	_prompt_time_progresses.clear()
	for prompt_id_variant in progress_by_prompt_id.keys():
		var prompt_id := int(prompt_id_variant)
		_prompt_time_progresses[prompt_id] = clampf(float(progress_by_prompt_id[prompt_id_variant]), 0.0, 1.0)
	for key in _prompt_nodes.keys():
		var prompt_icon: TextureRect = _prompt_nodes[key]
		prompt_icon.modulate.a = 1.0
	_update_prompt_timer_rings()

func remove_direction_prompt(prompt_id: int) -> void:
	if not _prompt_nodes.has(prompt_id):
		return
	var prompt_icon: TextureRect = _prompt_nodes[prompt_id]
	prompt_icon.queue_free()
	_prompt_nodes.erase(prompt_id)
	_prompt_positions.erase(prompt_id)
	if _prompt_timer_rings.has(prompt_id):
		var prompt_timer_ring: TextureRect = _prompt_timer_rings[prompt_id]
		prompt_timer_ring.queue_free()
		_prompt_timer_rings.erase(prompt_id)
	_prompt_time_progresses.erase(prompt_id)
	_prompt_phase_offsets.erase(prompt_id)
	_prompt_ring_progress_cache.erase(prompt_id)
	if _current_prompt_id == prompt_id:
		_current_prompt_id = -1
	_update_prompt_timer_rings()

func clear_direction_prompts() -> void:
	for prompt_icon in _prompt_nodes.values():
		prompt_icon.queue_free()
	for prompt_timer_ring in _prompt_timer_rings.values():
		prompt_timer_ring.queue_free()
	_prompt_nodes.clear()
	_prompt_positions.clear()
	_prompt_timer_rings.clear()
	_prompt_time_progresses.clear()
	_prompt_phase_offsets.clear()
	_prompt_ring_progress_cache.clear()
	_current_prompt_id = -1
	_update_prompt_timer_rings()

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

func _set_reaction(_text_value: String) -> void:
	return


func _pulse(color: Color, scale_multiplier: float) -> void:
	_apply_style(character_placeholder, color)
	var tween := create_tween()
	tween.tween_property(character_placeholder, "scale", _default_scale * scale_multiplier, 0.12)
	tween.tween_property(character_placeholder, "scale", _default_scale, 0.18)


func _apply_style(_texture_rect: TextureRect, _color: Color) -> void:
	return

func _spawn_success_note_particle(origin: Vector2, note_index: int) -> void:
	var note := Label.new()
	note.text = SUCCESS_NOTE_GLYPHS[note_index % SUCCESS_NOTE_GLYPHS.size()]
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.z_index = 3
	note.pivot_offset = Vector2(12.0, 12.0)
	note.position = origin + Vector2(randf_range(-22.0, 22.0), randf_range(-12.0, 10.0))
	note.rotation = deg_to_rad(randf_range(-16.0, 16.0))
	note.scale = Vector2.ONE * randf_range(0.82, 1.08)
	note.modulate = Color(1.0, 0.97, 0.68, 0.0)
	note.add_theme_font_size_override("font_size", 26 + (note_index * 2))
	note.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72, 1.0))
	note.add_theme_color_override("font_outline_color", Color(1.0, 0.82, 0.28, 0.85))
	note.add_theme_constant_override("outline_size", 4)
	prompt_layer.add_child(note)

	var end_position := note.position + Vector2(randf_range(-12.0, 12.0), -SUCCESS_NOTE_RISE_DISTANCE - randf_range(0.0, 18.0))
	var tween := note.create_tween()
	tween.set_parallel(true)
	tween.tween_property(note, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "position", end_position, SUCCESS_NOTE_LIFETIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "scale", note.scale * 1.18, SUCCESS_NOTE_LIFETIME * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "modulate:a", 0.0, SUCCESS_NOTE_LIFETIME).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(note.queue_free)

func _get_success_note_origin(prompt_id: int) -> Vector2:
	var prompt_icon := _prompt_nodes.get(prompt_id) as TextureRect
	if prompt_icon != null and prompt_icon.visible:
		return prompt_icon.position + (prompt_icon.size * 0.5) + Vector2(0.0, -8.0)
	return _get_feedback_anchor_center()

func _refresh_prompt_layout() -> void:
	if prompt_feedback_label == null:
		return
	var bounds_rect := _get_prompt_bounds_rect()
	for key in _prompt_nodes.keys():
		var prompt_icon: TextureRect = _prompt_nodes[key]
		var prompt_position: Vector2 = _prompt_positions.get(key, bounds_rect.get_center())
		var prompt_size := prompt_icon.size
		var desired_center := prompt_position
		var half_size := prompt_size * 0.5
		var min_x := bounds_rect.position.x + half_size.x + Config.ARROW_PROMPT_EDGE_MARGIN
		var max_x := bounds_rect.end.x - half_size.x - Config.ARROW_PROMPT_EDGE_MARGIN
		var min_y := bounds_rect.position.y + half_size.y + Config.ARROW_PROMPT_EDGE_MARGIN
		var max_y := bounds_rect.end.y - half_size.y - Config.ARROW_PROMPT_EDGE_MARGIN
		var clamped_center := Vector2(
			clampf(desired_center.x, min_x, max_x),
			clampf(desired_center.y, min_y, max_y)
		)
		prompt_icon.position = clamped_center - half_size
	_update_prompt_timer_rings()
	if prompt_feedback_label.visible:
		_position_feedback_label()

func _position_feedback_label() -> void:
	var center := _get_character_center_local()
	var feedback_size := prompt_feedback_label.get_combined_minimum_size()
	prompt_feedback_label.position = center + Vector2(0.0, Config.FEEDBACK_LABEL_OFFSET_Y) - (feedback_size * 0.5)


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
	return current_label.position + (current_label.size * 0.5)

func _get_prompt_bounds_rect() -> Rect2:
	if _prompt_bounds_rect.size.length_squared() > 0.0:
		return _prompt_bounds_rect
	return _get_character_rect_local()

func _get_prompt_icon_size() -> Vector2:
	return Vector2(
		maxf(24.0, Config.ARROW_PROMPT_BOX_SIZE.x - (DIRECTION_ICON_PADDING * 2.0)),
		maxf(24.0, Config.ARROW_PROMPT_BOX_SIZE.y - (DIRECTION_ICON_PADDING * 2.0))
	)

func _ensure_prompt_icon(prompt_id: int) -> TextureRect:
	if _prompt_nodes.has(prompt_id):
		return _prompt_nodes[prompt_id]
	var prompt_icon := TextureRect.new()
	var prompt_icon_size := _get_prompt_icon_size()
	prompt_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_icon.visible = false
	prompt_icon.texture = _get_direction_texture()
	prompt_icon.custom_minimum_size = prompt_icon_size
	prompt_icon.size = prompt_icon_size
	prompt_icon.pivot_offset = prompt_icon_size * 0.5
	prompt_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prompt_icon.material = _create_prompt_shader_material(_get_prompt_phase_offset(prompt_id), false)
	prompt_layer.add_child(prompt_icon)
	_prompt_nodes[prompt_id] = prompt_icon
	_ensure_prompt_timer_ring(prompt_id)
	return prompt_icon

func _get_current_prompt_label() -> TextureRect:
	if not _prompt_nodes.has(_current_prompt_id):
		return null
	return _prompt_nodes[_current_prompt_id]

func _ensure_prompt_timer_ring(prompt_id: int) -> TextureRect:
	if _prompt_timer_rings.has(prompt_id):
		return _prompt_timer_rings[prompt_id]
	var timer_ring := TextureRect.new()
	var radius := Config.ARROW_PROMPT_RING_RADIUS
	var diameter := (radius * 2.0) + Config.ARROW_PROMPT_RING_WIDTH
	var ring_size := Vector2.ONE * diameter
	timer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_ring.visible = false
	timer_ring.texture = _build_timer_ring_texture(1.0)
	timer_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	timer_ring.stretch_mode = TextureRect.STRETCH_SCALE
	timer_ring.custom_minimum_size = ring_size
	timer_ring.size = ring_size
	timer_ring.pivot_offset = ring_size * 0.5
	timer_ring.z_index = 0
	timer_ring.modulate = TIMER_RING_COLOR
	timer_ring.material = _create_prompt_shader_material(_get_prompt_phase_offset(prompt_id) + TIMER_RING_BASE_PHASE_STEP, false)
	prompt_layer.add_child(timer_ring)
	_prompt_timer_rings[prompt_id] = timer_ring
	return timer_ring

func _update_prompt_timer_rings() -> void:
	for prompt_id_variant in _prompt_nodes.keys():
		var prompt_id := int(prompt_id_variant)
		var prompt_icon: TextureRect = _prompt_nodes[prompt_id]
		var timer_ring := _ensure_prompt_timer_ring(prompt_id)
		var progress := float(_prompt_time_progresses.get(prompt_id, 0.0))
		if not prompt_icon.visible or progress <= 0.0:
			timer_ring.visible = false
			continue
		var center := prompt_icon.position + (prompt_icon.size * 0.5)
		timer_ring.position = center - (timer_ring.size * 0.5)
		var cached_progress := float(_prompt_ring_progress_cache.get(prompt_id, -1.0))
		if absf(cached_progress - progress) > 0.0005:
			timer_ring.texture = _build_timer_ring_texture(progress)
			_prompt_ring_progress_cache[prompt_id] = progress
		timer_ring.visible = true

func _get_prompt_phase_offset(prompt_id: int) -> float:
	if not _prompt_phase_offsets.has(prompt_id):
		_prompt_phase_offsets[prompt_id] = fposmod(phase_offset + (float(prompt_id) * 1.61803398875), TAU)
	return float(_prompt_phase_offsets[prompt_id])

func _create_prompt_shader_material(material_phase_offset: float, use_arc_mask: bool) -> ShaderMaterial:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = METALLIC_SHEEN_SHADER
	_apply_shader_parameters(shader_material, material_phase_offset, use_arc_mask)
	shader_material.set_shader_parameter("arc_progress", 1.0)
	return shader_material

func _update_prompt_shader_parameters() -> void:
	_prompt_phase_offsets.clear()
	for prompt_id_variant in _prompt_nodes.keys():
		var prompt_id := int(prompt_id_variant)
		var prompt_icon := _prompt_nodes[prompt_id] as TextureRect
		if prompt_icon != null:
			var icon_material := prompt_icon.material as ShaderMaterial
			if icon_material != null and icon_material.shader == METALLIC_SHEEN_SHADER:
				_apply_shader_parameters(icon_material, _get_prompt_phase_offset(prompt_id), false)
		var prompt_ring := _prompt_timer_rings.get(prompt_id) as TextureRect
		if prompt_ring != null:
			var ring_material := prompt_ring.material as ShaderMaterial
			if ring_material != null and ring_material.shader == METALLIC_SHEEN_SHADER:
				_apply_shader_parameters(ring_material, _get_prompt_phase_offset(prompt_id) + TIMER_RING_BASE_PHASE_STEP, false)

func _apply_shader_parameters(shader_material: ShaderMaterial, material_phase_offset: float, use_arc_mask: bool) -> void:
	shader_material.set_shader_parameter("base_color", base_color)
	shader_material.set_shader_parameter("metal_color", metal_color)
	shader_material.set_shader_parameter("shine_speed", shine_speed)
	shader_material.set_shader_parameter("shine_width", shine_width)
	shader_material.set_shader_parameter("shine_strength", shine_strength)
	shader_material.set_shader_parameter("edge_strength", edge_strength)
	shader_material.set_shader_parameter("phase_offset", fposmod(material_phase_offset, TAU))
	shader_material.set_shader_parameter("use_arc_mask", 1.0 if use_arc_mask else 0.0)
	shader_material.set_shader_parameter("debug_boost", debug_boost_amount if debug_metallic_prompt_effect else 0.0)

func _build_timer_ring_texture(progress: float) -> Texture2D:
	var image := Image.create(TIMER_RING_TEXTURE_SIZE, TIMER_RING_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(TIMER_RING_TEXTURE_SIZE, TIMER_RING_TEXTURE_SIZE) * 0.5
	var outer_radius := (float(TIMER_RING_TEXTURE_SIZE) * 0.5) - 1.0
	var display_outer_radius := Config.ARROW_PROMPT_RING_RADIUS + (Config.ARROW_PROMPT_RING_WIDTH * 0.5)
	var ring_half_width := maxf(
		((Config.ARROW_PROMPT_RING_WIDTH * 0.5) / maxf(display_outer_radius, 1.0)) * outer_radius,
		1.0
	)
	var inner_radius := maxf(outer_radius - (ring_half_width * 2.0), 0.0)
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var max_angle := clamped_progress * TAU
	for y in range(TIMER_RING_TEXTURE_SIZE):
		for x in range(TIMER_RING_TEXTURE_SIZE):
			var sample_position := Vector2(x + 0.5, y + 0.5)
			var distance := center.distance_to(sample_position)
			if distance < inner_radius or distance > outer_radius:
				continue
			var centered := sample_position - center
			var angle := atan2(centered.x, -centered.y)
			if angle < 0.0:
				angle += TAU
			if angle <= max_angle:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)

func _direction_rotation(direction: String) -> float:
	match direction:
		"Left":
			return -PI * 0.5
		"Right":
			return PI * 0.5
		"Up":
			return 0.0
		"Down":
			return PI
		_:
			return 0.0

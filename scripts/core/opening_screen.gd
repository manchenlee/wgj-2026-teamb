extends Control

signal continue_pressed

const OPENING_DATA_PATH := "res://assets/dialogue/opening.json"
const DEFAULT_BACKGROUND_PATH := "res://assets/curtain.jpg"
const DEFAULT_NEXT_TEXT := "NEXT"
const FINISH_TEXT := "START"
const DEFAULT_SPEAKER := "旁白"

@onready var background: TextureRect = $Background
@onready var backdrop_tint: ColorRect = $BackdropTint
@onready var chapter_label: Label = $SafeArea/RootLayout/TopRow/ChapterLabel
@onready var character_stage: Control = $CharacterStage
@onready var character_glow_root: Control = $CharacterStage/CharacterPivot/GlowRoot
@onready var character_root: Control = $CharacterStage/CharacterPivot/CharacterRoot
@onready var speaker_label: Label = $SafeArea/RootLayout/DialogueBox/DialogueLayout/SpeakerPanel/SpeakerLabel
@onready var dialogue_label: RichTextLabel = $SafeArea/RootLayout/DialogueBox/DialogueLayout/DialogueLabel
@onready var hint_label: Label = $SafeArea/RootLayout/DialogueBox/DialogueLayout/FooterRow/HintLabel
@onready var next_button: Button = $SafeArea/RootLayout/DialogueBox/DialogueLayout/FooterRow/NextButton

var _entries: Array = []
var _current_entry_index := -1
var _base_sprite: TextureRect
var _base_glow_sprite: TextureRect
var _layer_sprites: Dictionary = {}
var _layer_glow_sprites: Dictionary = {}
var _background_texture_cache: Dictionary = {}
var _character_texture_cache: Dictionary = {}
var _shake_tween: Tween
var _glow_tween: Tween
var _pivot_rest_position := Vector2.ZERO
var _current_character_offset := Vector2.ZERO
var _current_character_scale := Vector2.ONE

func _ready() -> void:
	_base_sprite = _create_stage_sprite("base")
	_base_glow_sprite = _create_stage_sprite("base_glow", true)
	next_button.pressed.connect(_advance_script)
	resized.connect(_layout_character_stage)
	_load_opening_script()
	_layout_character_stage()
	_advance_script()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ui_accept"):
		advance_input_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not next_button.get_global_rect().has_point(event.position):
			advance_input_handled()

func advance_input_handled() -> void:
	get_viewport().set_input_as_handled()
	_advance_script()

func _advance_script() -> void:
	if _entries.is_empty():
		continue_pressed.emit()
		return

	var next_index := _current_entry_index + 1
	if next_index >= _entries.size():
		continue_pressed.emit()
		return

	_current_entry_index = next_index
	var entry_variant: Variant = _entries[_current_entry_index]
	if entry_variant is Dictionary:
		var entry: Dictionary = entry_variant
		_apply_entry(entry)

func _load_opening_script() -> void:
	_entries.clear()
	if not FileAccess.file_exists(OPENING_DATA_PATH):
		push_warning("Opening dialogue file not found: %s" % OPENING_DATA_PATH)
		return

	var raw_text := FileAccess.get_file_as_string(OPENING_DATA_PATH)
	if raw_text.is_empty():
		push_warning("Opening dialogue file is empty: %s" % OPENING_DATA_PATH)
		return

	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		push_warning("Opening dialogue file has invalid JSON structure: %s" % OPENING_DATA_PATH)
		return

	var root: Dictionary = parsed
	var chapter: String = str(root.get("chapter", "序章"))
	chapter_label.text = chapter
	var steps: Variant = root.get("steps", [])
	if not (steps is Array):
		push_warning("Opening dialogue steps field is not an array: %s" % OPENING_DATA_PATH)
		return

	_entries = (steps as Array).duplicate(true)

func _apply_entry(entry: Dictionary) -> void:
	_apply_background(str(entry.get("background", DEFAULT_BACKGROUND_PATH)))
	_apply_backdrop_tint(entry.get("backdrop_tint", null))
	_apply_character(entry.get("character", {}))
	_apply_dialogue(entry)
	_apply_effects(entry.get("effects", []))
	_update_next_button_text()

func _apply_background(path: String) -> void:
	var texture := _load_texture(path, _background_texture_cache)
	if texture != null:
		background.texture = texture

func _apply_backdrop_tint(tint_value: Variant) -> void:
	if tint_value == null:
		backdrop_tint.color = Color(0.05, 0.03, 0.05, 0.36)
		return
	backdrop_tint.color = _parse_color(tint_value, Color(0.05, 0.03, 0.05, 0.36))

func _apply_dialogue(entry: Dictionary) -> void:
	speaker_label.text = str(entry.get("speaker", DEFAULT_SPEAKER))
	dialogue_label.clear()
	dialogue_label.append_text(str(entry.get("text", "")))
	hint_label.text = str(entry.get("hint", "點擊、Enter 或按鈕繼續"))

func _apply_character(character_data_variant: Variant) -> void:
	if not (character_data_variant is Dictionary):
		return

	var character_data: Dictionary = character_data_variant
	var visible := bool(character_data.get("visible", true))
	character_stage.visible = visible
	if not visible:
		return

	_reset_effect_state()
	_apply_base_character(str(character_data.get("base", "")))
	if bool(character_data.get("clear_layers", false)):
		_clear_all_layers()
	_current_character_offset = _parse_vector2(character_data.get("offset", Vector2.ZERO), Vector2.ZERO)
	_current_character_scale = _parse_vector2(character_data.get("scale", Vector2.ONE), Vector2.ONE)
	character_root.position = _pivot_rest_position + _current_character_offset
	character_root.scale = _current_character_scale
	character_glow_root.position = _pivot_rest_position + _current_character_offset
	character_glow_root.scale = _current_character_scale
	_apply_layers(character_data.get("layers", []))

func _apply_base_character(path: String) -> void:
	if path.is_empty():
		return
	var texture := _load_texture(path, _character_texture_cache)
	if texture == null:
		return
	_configure_sprite(_base_sprite, texture, Vector2.ZERO, Vector2.ONE, Color.WHITE, 0)
	_configure_sprite(_base_glow_sprite, texture, Vector2.ZERO, Vector2.ONE, Color.WHITE, 0)

func _apply_layers(layers_variant: Variant) -> void:
	if not (layers_variant is Array):
		return

	for layer_variant in layers_variant:
		if not (layer_variant is Dictionary):
			continue
		var layer: Dictionary = layer_variant
		var layer_id := str(layer.get("id", "layer_%s" % _layer_sprites.size()))
		var action := str(layer.get("action", "set"))
		if action == "remove":
			_remove_layer(layer_id)
			continue
		if action == "clear":
			_clear_all_layers()
			continue
		var path := str(layer.get("path", ""))
		if path.is_empty():
			continue
		var texture := _load_texture(path, _character_texture_cache)
		if texture == null:
			continue
		var sprite := _ensure_layer_sprite(layer_id, false)
		var glow_sprite := _ensure_layer_sprite(layer_id, true)
		var offset := _parse_vector2(layer.get("offset", Vector2.ZERO), Vector2.ZERO)
		var scale_value := _parse_vector2(layer.get("scale", Vector2.ONE), Vector2.ONE)
		var modulate := _parse_color(layer.get("modulate", Color.WHITE), Color.WHITE)
		var z_index := int(layer.get("z_index", 0))
		_configure_sprite(sprite, texture, offset, scale_value, modulate, z_index)
		_configure_sprite(glow_sprite, texture, offset, scale_value, modulate, z_index)

func _apply_effects(effects_variant: Variant) -> void:
	if not (effects_variant is Array):
		return
	for effect_variant in effects_variant:
		if effect_variant is String:
			_apply_effect({"type": effect_variant})
		elif effect_variant is Dictionary:
			_apply_effect(effect_variant)

func _apply_effect(effect_data: Dictionary) -> void:
	var effect_type := str(effect_data.get("type", "")).to_lower()
	match effect_type:
		"shake":
			_play_shake_effect(
				float(effect_data.get("duration", 0.4)),
				float(effect_data.get("strength", 18.0)),
				int(effect_data.get("loops", 4))
			)
		"glow":
			_play_glow_effect(
				float(effect_data.get("duration", 0.8)),
				float(effect_data.get("strength", 0.75)),
				_parse_color(effect_data.get("color", "#fff1c9"), Color(1.0, 0.95, 0.79, 1.0))
			)
		"flash":
			_play_flash_effect(
				float(effect_data.get("duration", 0.18)),
				_parse_color(effect_data.get("color", "#fff8ea"), Color(1.0, 0.97, 0.92, 1.0))
			)

func _play_shake_effect(duration: float, strength: float, loops: int) -> void:
	if _shake_tween != null and _shake_tween.is_running():
		_shake_tween.kill()
	var rest_position := _pivot_rest_position + _current_character_offset
	character_root.position = rest_position
	character_glow_root.position = rest_position
	_shake_tween = create_tween()
	_shake_tween.set_parallel(false)
	var segment_duration := maxf(duration / max(loops * 2, 1), 0.03)
	for loop_index in range(max(loops, 1)):
		var offset := Vector2(strength if loop_index % 2 == 0 else -strength, 0.0)
		_shake_tween.tween_property(character_root, "position", rest_position + offset, segment_duration)
		_shake_tween.parallel().tween_property(character_glow_root, "position", rest_position + offset, segment_duration)
		_shake_tween.tween_property(character_root, "position", rest_position, segment_duration)
		_shake_tween.parallel().tween_property(character_glow_root, "position", rest_position, segment_duration)

func _play_glow_effect(duration: float, strength: float, glow_color: Color) -> void:
	if _glow_tween != null and _glow_tween.is_running():
		_glow_tween.kill()
	for node in _layer_glow_sprites.values():
		if node is TextureRect:
			node.modulate = glow_color
	_base_glow_sprite.modulate = glow_color
	character_glow_root.modulate.a = 0.0
	character_glow_root.scale = _current_character_scale
	_glow_tween = create_tween()
	_glow_tween.set_parallel(true)
	_glow_tween.tween_property(character_glow_root, "modulate:a", clampf(strength, 0.0, 1.0), duration * 0.4)
	_glow_tween.tween_property(character_glow_root, "scale", _current_character_scale * 1.04, duration * 0.4)
	_glow_tween.chain().tween_property(character_glow_root, "modulate:a", 0.0, duration * 0.6)
	_glow_tween.parallel().tween_property(character_glow_root, "scale", _current_character_scale, duration * 0.6)

func _play_flash_effect(duration: float, flash_color: Color) -> void:
	var flash_rect := ColorRect.new()
	flash_rect.color = flash_color
	flash_rect.modulate.a = 0.0
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash_rect)
	move_child(flash_rect, get_child_count() - 1)
	var tween := create_tween()
	tween.tween_property(flash_rect, "modulate:a", 0.82, duration * 0.35)
	tween.tween_property(flash_rect, "modulate:a", 0.0, duration * 0.65)
	tween.tween_callback(flash_rect.queue_free)

func _reset_effect_state() -> void:
	if _shake_tween != null and _shake_tween.is_running():
		_shake_tween.kill()
	if _glow_tween != null and _glow_tween.is_running():
		_glow_tween.kill()
	character_root.position = _pivot_rest_position + _current_character_offset
	character_glow_root.position = _pivot_rest_position + _current_character_offset
	character_glow_root.modulate.a = 0.0
	character_glow_root.scale = _current_character_scale

func _update_next_button_text() -> void:
	if _current_entry_index >= _entries.size() - 1:
		next_button.text = FINISH_TEXT
	else:
		next_button.text = DEFAULT_NEXT_TEXT

func _layout_character_stage() -> void:
	if not is_node_ready():
		return
	var stage_height := maxf(size.y * 0.62, 420.0)
	character_stage.custom_minimum_size.y = stage_height
	_pivot_rest_position = Vector2(0.0, 20.0)
	character_root.position = _pivot_rest_position + _current_character_offset
	character_glow_root.position = _pivot_rest_position + _current_character_offset

func _create_stage_sprite(node_name: String, is_glow: bool = false) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.name = node_name
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.anchor_left = 0.5
	sprite.anchor_top = 0.5
	sprite.anchor_right = 0.5
	sprite.anchor_bottom = 0.5
	sprite.offset_left = -260.0
	sprite.offset_top = -340.0
	sprite.offset_right = 260.0
	sprite.offset_bottom = 340.0
	sprite.visible = not is_glow
	var parent := character_glow_root if is_glow else character_root
	parent.add_child(sprite)
	if is_glow:
		sprite.visible = true
		sprite.modulate.a = 0.0
	return sprite

func _ensure_layer_sprite(layer_id: String, is_glow: bool) -> TextureRect:
	var source := _layer_glow_sprites if is_glow else _layer_sprites
	if source.has(layer_id):
		return source[layer_id]
	var sprite := _create_stage_sprite(layer_id, is_glow)
	source[layer_id] = sprite
	return sprite

func _remove_layer(layer_id: String) -> void:
	if _layer_sprites.has(layer_id):
		(_layer_sprites[layer_id] as TextureRect).queue_free()
		_layer_sprites.erase(layer_id)
	if _layer_glow_sprites.has(layer_id):
		(_layer_glow_sprites[layer_id] as TextureRect).queue_free()
		_layer_glow_sprites.erase(layer_id)

func _clear_all_layers() -> void:
	for node in _layer_sprites.values():
		if node is TextureRect:
			node.queue_free()
	for node in _layer_glow_sprites.values():
		if node is TextureRect:
			node.queue_free()
	_layer_sprites.clear()
	_layer_glow_sprites.clear()

func _configure_sprite(
	sprite: TextureRect,
	texture: Texture2D,
	offset: Vector2,
	scale_value: Vector2,
	modulate: Color,
	z_index: int
) -> void:
	sprite.texture = texture
	sprite.position = offset
	sprite.scale = scale_value
	sprite.modulate = modulate
	sprite.z_index = z_index

func _load_texture(path: String, cache: Dictionary) -> Texture2D:
	if path.is_empty():
		return null
	if cache.has(path):
		return cache[path]
	if not ResourceLoader.exists(path):
		push_warning("Texture resource not found: %s" % path)
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		cache[path] = texture
	return texture

func _parse_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback

func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		var color_string := String(value)
		if color_string.is_valid_html_color():
			return Color.from_string(color_string, fallback)
	if value is Array and value.size() >= 3:
		var alpha := float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	if value is Dictionary:
		return Color(
			float(value.get("r", fallback.r)),
			float(value.get("g", fallback.g)),
			float(value.get("b", fallback.b)),
			float(value.get("a", fallback.a))
		)
	return fallback

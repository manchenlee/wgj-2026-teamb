class_name LocalizedMeshBreathing
extends Node

const BREATHING_SHADER := preload("res://scripts/ui/localized_mesh_breathing.gdshader")

@export var chest_region_rect: Rect2 = Rect2(0.34, 0.17, 0.28, 0.23):
	set(value):
		chest_region_rect = value
		_update_material_parameters()
@export_range(0.0, 0.05, 0.0005) var inhale_strength: float = 0.01:
	set(value):
		inhale_strength = value
		_update_material_parameters()
@export_range(1.0, 10.0, 0.05) var cycle_duration: float = 4.4
@export_range(0.0, 2.0, 0.05) var timing_variation: float = 0.35
@export_range(0.01, 0.5, 0.01) var edge_softness: float = 0.18:
	set(value):
		edge_softness = value
		_update_material_parameters()
@export_range(0.0, 1.0, 0.01) var chest_vertical_bias: float = 0.2:
	set(value):
		chest_vertical_bias = value
		_update_material_parameters()
@export var debug_breathing: bool = false:
	set(value):
		debug_breathing = value
		_update_material_parameters()
@export_range(1.0, 8.0, 0.1) var debug_inhale_multiplier: float = 5.0:
	set(value):
		debug_inhale_multiplier = value
		_update_material_parameters()
@export_range(0.5, 3.0, 0.05) var debug_cycle_duration: float = 1.5
@export_range(0.0, 0.3, 0.01) var debug_mask_tint_strength: float = 0.08:
	set(value):
		debug_mask_tint_strength = value
		_update_material_parameters()

@export_range(0.0, 1.0, 0.001) var breath_amount: float:
	get:
		return _breath_amount
	set(value):
		_breath_amount = clampf(value, 0.0, 1.0)
		_update_material_parameters()

var _rng := RandomNumberGenerator.new()
var _breathing_tween: Tween
var _breathing_active: bool = false
var _breath_amount: float = 0.0
var _base_target: TextureRect
var _overlay_targets: Array[TextureRect] = []

func _ready() -> void:
	_rng.randomize()
	_update_material_parameters()

func bind_targets(base_target: TextureRect, overlay_targets: Array) -> void:
	_base_target = base_target
	_overlay_targets.clear()
	for overlay_target in overlay_targets:
		if overlay_target is TextureRect:
			_overlay_targets.append(overlay_target)
	_apply_materials()

func is_debug_breathing_enabled() -> bool:
	return debug_breathing

func start_breathing() -> void:
	if _get_targets().is_empty():
		return
	_breathing_active = true
	_kill_breathing_tween()
	breath_amount = 0.0
	_queue_breath_cycle()

func stop_breathing() -> void:
	_breathing_active = false
	_kill_breathing_tween()
	breath_amount = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_kill_breathing_tween()

func _queue_breath_cycle() -> void:
	if not _breathing_active or _get_targets().is_empty():
		return
	var half_cycle_duration := _get_half_cycle_duration()
	_breathing_tween = create_tween()
	_breathing_tween.set_trans(Tween.TRANS_SINE)
	_breathing_tween.set_ease(Tween.EASE_IN_OUT)
	_breathing_tween.finished.connect(_on_breath_cycle_finished)
	_breathing_tween.tween_property(self, "breath_amount", 1.0, half_cycle_duration)
	_breathing_tween.tween_property(self, "breath_amount", 0.0, half_cycle_duration)

func _on_breath_cycle_finished() -> void:
	_breathing_tween = null
	if not _breathing_active:
		return
	_queue_breath_cycle()

func _apply_materials() -> void:
	for target in _get_targets():
		var shader_material := target.material as ShaderMaterial
		if shader_material == null or shader_material.shader != BREATHING_SHADER:
			shader_material = ShaderMaterial.new()
			shader_material.shader = BREATHING_SHADER
			target.material = shader_material
	_update_material_parameters()

func _get_targets() -> Array[TextureRect]:
	var targets: Array[TextureRect] = []
	if is_instance_valid(_base_target):
		targets.append(_base_target)
	for overlay_target in _overlay_targets:
		if is_instance_valid(overlay_target):
			targets.append(overlay_target)
	return targets

func _get_half_cycle_duration() -> float:
	var target_cycle_duration := debug_cycle_duration if debug_breathing else cycle_duration
	var applied_timing_variation := 0.0 if debug_breathing else timing_variation
	var full_cycle := target_cycle_duration + _rng.randf_range(-applied_timing_variation, applied_timing_variation)
	return maxf(full_cycle * 0.5, 0.1)

func _update_material_parameters() -> void:
	var effective_inhale_strength := inhale_strength * (debug_inhale_multiplier if debug_breathing else 1.0)
	var debug_tint_strength := debug_mask_tint_strength if debug_breathing else 0.0
	for target in _get_targets():
		var shader_material := target.material as ShaderMaterial
		if shader_material == null:
			continue
		shader_material.set_shader_parameter(
			"chest_region_rect",
			Vector4(chest_region_rect.position.x, chest_region_rect.position.y, chest_region_rect.size.x, chest_region_rect.size.y)
		)
		shader_material.set_shader_parameter("inhale_strength", effective_inhale_strength)
		shader_material.set_shader_parameter("edge_softness", edge_softness)
		shader_material.set_shader_parameter("chest_vertical_bias", chest_vertical_bias)
		shader_material.set_shader_parameter("breath_amount", _breath_amount)
		shader_material.set_shader_parameter("debug_tint_strength", debug_tint_strength)

func _kill_breathing_tween() -> void:
	if _breathing_tween != null:
		_breathing_tween.kill()
		_breathing_tween = null

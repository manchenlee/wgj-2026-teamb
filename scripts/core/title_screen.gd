extends Control

signal start_pressed
signal skip_pressed
signal debug_requested

@onready var _start_button_root: Control = $StartButtonRoot
@onready var _start_button: Button = $StartButtonRoot/StartButton
@onready var _logo: TextureRect = $Logo
@onready var _debug_hotspot: Button = $BottomBar/DebugHotspot
@onready var _background: TextureRect = $Background
@onready var _cover_overlay: TextureRect = $CoverOverlay
@onready var _skip_button: TextureButton = $SkipButton

const _COVER_1 := preload("res://assets/cover_1.png")
const _COVER_2 := preload("res://assets/cover_2.png")
const _COVER_3 := preload("res://assets/cover_3.png")

var _hover_tween: Tween
var _transitioning := false
var _start_button_base_scale := Vector2.ONE

func _reset_start_button_visual(reset_alpha: bool = false) -> void:
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null

	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_parallel(true)
	tween.tween_property(_start_button_root, "scale", _start_button_base_scale, 0.15)
	if reset_alpha:
		tween.tween_property(_start_button_root, "modulate", Color.WHITE, 0.15)
	else:
		var current_modulate := _start_button_root.modulate
		tween.tween_property(
			_start_button_root,
			"modulate",
			Color(1.0, 1.0, 1.0, current_modulate.a),
			0.15
		)

func _ready() -> void:
	_debug_hotspot.pressed.connect(func() -> void: debug_requested.emit())
	_start_button.mouse_entered.connect(_on_button_mouse_entered)
	_start_button.mouse_exited.connect(_on_button_mouse_exited)
	_start_button.pressed.connect(_play_cover_transition)
	_skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	_start_button_base_scale = _start_button_root.scale
	_start_button_root.pivot_offset = _start_button_root.size * 0.5

	_background.visible = true
	_background.modulate.a = 1.0
	_cover_overlay.visible = false
	_cover_overlay.modulate.a = 0.0
	_skip_button.visible = false
	_skip_button.modulate.a = 0.0
	_animate_in()

func _animate_in() -> void:
	_logo.modulate.a = 0.0
	_start_button_root.modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_logo, "modulate:a", 1.0, 0.8)
	tween.parallel().tween_property(_start_button_root, "modulate:a", 1.0, 0.8)

func _on_button_mouse_entered() -> void:
	if _transitioning:
		return
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_SINE).set_parallel(true)
	_hover_tween.tween_property(_start_button_root, "scale", _start_button_base_scale * 1.04, 0.15)
	_hover_tween.tween_property(_start_button_root, "modulate", Color(1.08, 1.08, 1.08, 1.0), 0.15)

func _on_button_mouse_exited() -> void:
	_reset_start_button_visual(true)

func _play_cover_transition() -> void:
	if _transitioning:
		return
	_transitioning = true
	_start_button.disabled = true
	_reset_start_button_visual(false)

	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_logo, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(_start_button_root, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		_skip_button.visible = true
	)
	tween.tween_property(_skip_button, "modulate:a", 1.0, 0.3)
	tween.tween_callback(func() -> void: _begin_cover_crossfade(_COVER_1))
	tween.tween_property(_cover_overlay, "modulate:a", 1.0, 0.5)
	tween.tween_callback(func() -> void: _commit_cover_crossfade())
	tween.tween_interval(0.3)
	tween.tween_callback(func() -> void: _begin_cover_crossfade(_COVER_2))
	tween.tween_property(_cover_overlay, "modulate:a", 1.0, 0.5)
	tween.tween_callback(func() -> void: _commit_cover_crossfade())
	tween.tween_interval(0.3)
	tween.tween_callback(func() -> void: _begin_cover_crossfade(_COVER_3))
	tween.tween_property(_cover_overlay, "modulate:a", 1.0, 0.5)
	tween.tween_callback(func() -> void: _commit_cover_crossfade())
	tween.tween_interval(0.3)
	tween.tween_callback(func() -> void: start_pressed.emit())

func _begin_cover_crossfade(next_texture: Texture2D) -> void:
	_cover_overlay.texture = next_texture
	_cover_overlay.visible = true
	_cover_overlay.modulate.a = 0.0

func _commit_cover_crossfade() -> void:
	_background.texture = _cover_overlay.texture
	_cover_overlay.modulate.a = 0.0
	_cover_overlay.visible = false

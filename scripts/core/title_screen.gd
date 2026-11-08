extends Control

signal start_pressed
signal skip_pressed
signal debug_requested

@onready var _start_button_root: Control = $StartButtonRoot
@onready var _start_button: Button = $StartButtonRoot/StartButton
@onready var _logo: TextureRect = $Logo
@onready var _debug_hotspot: Button = $BottomBar/DebugHotspot
@onready var _background: TextureRect = $Background
@onready var _hover_cover: TextureRect = $HoverCover
@onready var _skip_button: TextureButton = $SkipButton

const COVER_FRAME_SECONDS: float = 1.0 / 8.0
const _COVER_1 := preload("res://assets/art/screens/title/cover_1.png")
const _COVER_2 := preload("res://assets/art/screens/title/cover_2.png")
const _COVER_3 := preload("res://assets/art/screens/title/cover_3.png")

var _hover_tween: Tween
var _hover_cover_tween: Tween
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
	_hover_cover.visible = false
	_hover_cover.modulate.a = 0.0
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
	_fade_hover_cover(1.0)

func _on_button_mouse_exited() -> void:
	if _transitioning:
		return
	_reset_start_button_visual(true)
	_fade_hover_cover(0.0)

func _fade_hover_cover(target_alpha: float) -> void:
	if _hover_cover_tween:
		_hover_cover_tween.kill()
	_hover_cover.visible = true
	_hover_cover_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_hover_cover_tween.tween_property(_hover_cover, "modulate:a", target_alpha, 0.25)
	if is_zero_approx(target_alpha):
		_hover_cover_tween.tween_callback(func() -> void: _hover_cover.visible = false)

func _play_cover_transition() -> void:
	if _transitioning:
		return
	_transitioning = true
	_start_button.disabled = true
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null
	if _hover_cover_tween:
		_hover_cover_tween.kill()
		_hover_cover_tween = null
	_hover_cover.visible = false
	_start_button_root.visible = false
	_start_button_root.modulate.a = 0.0
	_start_button_root.scale = _start_button_base_scale
	_logo.visible = false
	_background.texture = _hover_cover.texture

	var tween := create_tween()
	tween.tween_interval(COVER_FRAME_SECONDS)
	tween.tween_callback(func() -> void: _background.texture = _COVER_1)
	tween.tween_interval(COVER_FRAME_SECONDS)
	tween.tween_callback(func() -> void: _background.texture = _COVER_2)
	tween.tween_interval(COVER_FRAME_SECONDS)
	tween.tween_callback(func() -> void: _background.texture = _COVER_3)
	tween.tween_interval(COVER_FRAME_SECONDS)
	tween.tween_callback(func() -> void: start_pressed.emit())

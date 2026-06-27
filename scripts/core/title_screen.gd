extends Control

signal start_pressed
signal debug_requested

@onready var _start_button: TextureButton = $StartButton
@onready var _debug_hotspot: Button = $BottomBar/DebugHotspot
@onready var _background: TextureRect = $Background

func _ready() -> void:
	_start_button.pressed.connect(func() -> void: start_pressed.emit())
	_debug_hotspot.pressed.connect(func() -> void: debug_requested.emit())

	_background.visible = true

	# 按鈕用原始尺寸，縮放到畫面寬度的 30%
	_start_button.ignore_texture_size = false
	_start_button.scale = Vector2(1.0, 1.0)

	_animate_in()

func _process(_delta: float) -> void:
	# 按鈕大小根據畫面寬度動態調整，保持 30% 寬
	var target_width := size.x * 0.30
	var img_width := 992.0
	var s := target_width / img_width
	_start_button.scale = Vector2(s, s)

	# 右側中央偏下（水平 58%，垂直 80%）
	var btn_size := Vector2(992.0, 498.0) * _start_button.scale
	_start_button.position = Vector2(
		size.x * 0.58,
		size.y * 0.60 - btn_size.y * 0.5
	)

func _animate_in() -> void:
	_start_button.modulate.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_start_button, "modulate:a", 1.0, 0.8)

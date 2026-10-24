extends Control

@export var button_text := "Skip"

@onready var _label: Label = $SkipLabel
@onready var _button: Button = $Button

var _hover_tween: Tween
var _base_scale := Vector2.ONE

func _ready() -> void:
	_label.text = button_text
	_base_scale = scale
	pivot_offset = size * 0.5
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	_animate_hover(_base_scale * 1.04, Color(1.08, 1.08, 1.08, 1.0))

func _on_mouse_exited() -> void:
	_animate_hover(_base_scale, Color.WHITE)

func _animate_hover(target_scale: Vector2, target_modulate: Color) -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_SINE).set_parallel(true)
	_hover_tween.tween_property(self, "scale", target_scale, 0.15)
	_hover_tween.tween_property(self, "modulate", target_modulate, 0.15)

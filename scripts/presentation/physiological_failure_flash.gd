class_name PhysiologicalFailureFlash
extends ColorRect

@export_range(0.0, 1.0, 0.01) var peak_alpha: float = 0.32
@export_range(0.01, 1.0, 0.01) var fade_in_duration: float = 0.08
@export_range(0.01, 1.0, 0.01) var fade_out_duration: float = 0.18

var _flash_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(color.r, color.g, color.b, 0.0)
	visible = false


func play_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	color = Color(color.r, color.g, color.b, 0.0)
	visible = true

	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "color:a", peak_alpha, fade_in_duration) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(self, "color:a", 0.0, fade_out_duration) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_IN)
	_flash_tween.tween_callback(_on_flash_finished)


func clear_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	color = Color(color.r, color.g, color.b, 0.0)
	visible = false


func _on_flash_finished() -> void:
	color = Color(color.r, color.g, color.b, 0.0)
	visible = false

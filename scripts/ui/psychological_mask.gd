class_name PsychologicalMask
extends TextureRect

const FADE_DURATION: float = 0.65

var _fade_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func set_psychological_active(active: bool) -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	var target_fade := 1.0 if active else 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", target_fade, FADE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

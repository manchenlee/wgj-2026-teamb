class_name PsychologicalVignette
extends ColorRect

const VIGNETTE_SHADER := preload("res://scripts/ui/psychological_vignette.gdshader")
const FADE_DURATION: float = 0.65

var _fade_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = VIGNETTE_SHADER
	vignette_material.set_shader_parameter("fade", 0.0)
	material = vignette_material


func set_psychological_active(active: bool) -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	var target_fade := 1.0 if active else 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(material, "shader_parameter/fade", target_fade, FADE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

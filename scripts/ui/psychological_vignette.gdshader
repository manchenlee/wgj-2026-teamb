shader_type canvas_item;

uniform float fade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// A broad oval keeps the center clear while the corners bloom softly.
	vec2 centered_uv = (UV - vec2(0.5)) * vec2(1.35, 1.0);
	float edge = smoothstep(0.36, 0.79, length(centered_uv));
	COLOR = vec4(1.0, 1.0, 1.0, edge * 0.72 * fade);
}

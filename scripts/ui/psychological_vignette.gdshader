shader_type canvas_item;

uniform float fade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Match the reference's violet upper edge and wine-red lower corners.
	vec2 centered_uv = (UV - vec2(0.5)) * vec2(1.35, 1.0);
	float edge = smoothstep(0.36, 0.79, length(centered_uv));
	float corner = smoothstep(0.58, 0.88, length(centered_uv));
	float opacity = min(0.82, edge * 0.55 + corner * 0.25);
	vec3 upper_color = vec3(0.075, 0.035, 0.11);
	vec3 lower_color = vec3(0.16, 0.025, 0.045);
	vec3 vignette_color = mix(upper_color, lower_color, smoothstep(0.1, 0.95, UV.y));
	COLOR = vec4(vignette_color, opacity * fade);
}

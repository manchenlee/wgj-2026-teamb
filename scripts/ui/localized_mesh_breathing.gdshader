shader_type canvas_item;

uniform vec4 chest_region_rect = vec4(0.34, 0.17, 0.28, 0.23);
uniform float inhale_strength : hint_range(0.0, 0.1) = 0.03;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.18;
uniform float chest_vertical_bias : hint_range(0.0, 1.0) = 0.2;
uniform float breath_amount : hint_range(0.0, 1.0) = 0.0;
uniform float debug_tint_strength : hint_range(0.0, 0.3) = 0.0;

float edge_fade(float value, float softness) {
	return smoothstep(0.0, softness, value) * smoothstep(0.0, softness, 1.0 - value);
}

void fragment() {
	vec2 uv = UV;
	vec4 sampled_color = texture(TEXTURE, uv);
	vec2 region_position = chest_region_rect.xy;
	vec2 region_size = chest_region_rect.zw;
	vec2 local_uv = (uv - region_position) / region_size;

	if (local_uv.x >= 0.0 && local_uv.x <= 1.0 && local_uv.y >= 0.0 && local_uv.y <= 1.0) {
		float edge_mask = edge_fade(local_uv.x, edge_softness) * edge_fade(local_uv.y, edge_softness);
		vec2 centered_uv = local_uv - vec2(0.5, 0.54);
		vec2 ellipse_scale = vec2(0.82, 1.1);
		float radial_distance = length(centered_uv / ellipse_scale);
		float radial_mask = 1.0 - smoothstep(0.18, 0.98, radial_distance);
		float mask = edge_mask * radial_mask;

		vec2 outward = centered_uv;
		float vertical_bias = mix(0.7, 1.15, 1.0 - clamp(local_uv.y + chest_vertical_bias * 0.35, 0.0, 1.0));
		vec2 displacement = vec2(
			outward.x * region_size.x,
			outward.y * region_size.y * vertical_bias
		) * inhale_strength * breath_amount * mask;
		vec2 sample_uv = uv - displacement;
		sampled_color = texture(TEXTURE, sample_uv);
		if (debug_tint_strength > 0.0) {
			vec3 debug_tint = mix(sampled_color.rgb, vec3(0.95, 0.75, 0.18), debug_tint_strength * mask);
			sampled_color.rgb = debug_tint;
		}
	}

	COLOR = sampled_color;
}

shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.83, 0.73, 0.42, 1.0);
uniform vec4 metal_color : source_color = vec4(0.97, 0.91, 0.72, 1.0);
uniform float shine_speed : hint_range(0.0, 2.0) = 0.12;
uniform float shine_width : hint_range(0.02, 0.6) = 0.22;
uniform float shine_strength : hint_range(0.0, 2.0) = 0.52;
uniform float edge_strength : hint_range(0.0, 2.0) = 0.22;
uniform float phase_offset : hint_range(0.0, 6.28318) = 0.0;

uniform float arc_progress : hint_range(0.0, 1.0) = 1.0;
uniform float use_arc_mask : hint_range(0.0, 1.0) = 0.0;
uniform float debug_boost : hint_range(0.0, 4.0) = 0.0;

float wrapped_band_distance(float value, float center) {
	float distance = abs(value - center);
	return min(distance, 1.0 - distance);
}

float sample_texture_alpha(vec4 sample_color) {
	return sample_color.a;
}

float edge_mask_from_samples(float alpha, float left, float right, float up, float down) {
	float gradient = abs(alpha - left) + abs(alpha - right) + abs(alpha - up) + abs(alpha - down);
	return clamp(gradient * 0.6, 0.0, 1.0);
}

float arc_mask(vec2 uv) {
	if (use_arc_mask < 0.5) {
		return 1.0;
	}
	vec2 centered = uv - vec2(0.5);
	float angle = atan(centered.x, -centered.y);
	float normalized = fract((angle / 6.28318530718) + 1.0);
	float feather = 0.01;
	return 1.0 - smoothstep(arc_progress, arc_progress + feather, normalized);
}

void fragment() {
	vec4 source_sample = texture(TEXTURE, UV);
	float source_alpha = source_sample.a;
	vec4 input_color = COLOR;
	float alpha = source_alpha * arc_mask(UV);
	if (alpha <= 0.0001) {
		COLOR = vec4(0.0);
	} else {
		float sweep = fract(dot(UV, normalize(vec2(1.0, -1.0))) - (TIME * shine_speed) + (phase_offset / 6.28318530718));
		float width = max(shine_width, 0.001);
		float band = 1.0 - smoothstep(0.0, width, wrapped_band_distance(sweep, 0.5));
		vec2 pixel = TEXTURE_PIXEL_SIZE;
		float left = sample_texture_alpha(texture(TEXTURE, UV - vec2(pixel.x, 0.0)));
		float right = sample_texture_alpha(texture(TEXTURE, UV + vec2(pixel.x, 0.0)));
		float up = sample_texture_alpha(texture(TEXTURE, UV - vec2(0.0, pixel.y)));
		float down = sample_texture_alpha(texture(TEXTURE, UV + vec2(0.0, pixel.y)));
		float edge = edge_mask_from_samples(source_alpha, left, right, up, down);
		float effect_multiplier = 1.0 + debug_boost;
		float sheen = band * shine_strength * effect_multiplier;
		float edge_highlight = edge * edge_strength * effect_multiplier;
		vec3 base_rgb = base_color.rgb;
		vec3 outline_rgb = mix(base_rgb * 0.28, vec3(0.16, 0.08, 0.02), 0.82);
		float input_alpha_factor = clamp(input_color.a / max(source_alpha, 0.0001), 0.0, 1.0);
		vec3 lit_rgb = base_rgb + (metal_color.rgb * sheen);
		vec3 result_rgb = mix(lit_rgb, outline_rgb, clamp(edge * 0.94, 0.0, 1.0));
		result_rgb += metal_color.rgb * edge_highlight * 0.28;

		COLOR = vec4(result_rgb, alpha * base_color.a * input_alpha_factor);
	}
}

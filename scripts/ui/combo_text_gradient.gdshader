shader_type canvas_item;

uniform vec4 gradient_top : source_color = vec4(0.98, 0.62, 0.29, 1.0);
uniform vec4 gradient_bottom : source_color = vec4(0.67, 0.20, 0.055, 1.0);
uniform float gradient_height = 90.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	vec4 vertex_color = COLOR;
	vec4 glyph_sample = texture(TEXTURE, UV);
	float alpha = glyph_sample.a * vertex_color.a;
	bool is_outline = vertex_color.r > 0.9 && vertex_color.g > 0.9 && vertex_color.b > 0.8;
	if (is_outline) {
		COLOR = vec4(vertex_color.rgb, alpha);
	} else {
		float gradient_mix = smoothstep(0.08, 0.92, clamp(local_y / gradient_height, 0.0, 1.0));
		COLOR = vec4(mix(gradient_top.rgb, gradient_bottom.rgb, gradient_mix), alpha);
	}
}

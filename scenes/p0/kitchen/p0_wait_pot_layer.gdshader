shader_type canvas_item;
// The wait pot's layer (SGODOT-449): its world is drawn into a half-float target (SubViewport.use_hdr_2d, for a
// smooth alpha — the Mobile renderer's default transparent target keeps 4 levels of it) in linear light and
// premultiplied (over the clear black); shown here in the 2D canvas's sRGB, premultiplied, so its white steam stays
// white rather than greyed a second time (黄忠 on 449 d971ef94).
render_mode blend_premul_alpha;

vec3 to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 straight = c.a > 0.0001 ? c.rgb / c.a : vec3(0.0);
	COLOR = vec4(to_srgb(straight) * c.a, c.a);
}

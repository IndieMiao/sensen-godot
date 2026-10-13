shader_type canvas_item;
// CityRow's art (MAP-8): mode 0 as it is; 1 a one-colour glyph in `tint`; 2 the art at saturation 0 (a city never
// visited, 安其拉 279 a5a99803).
uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	if (mode == 1) {
		COLOR = vec4(tint.rgb, t.a * tint.a);
	} else if (mode == 2) {
		float g = dot(t.rgb, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(vec3(g), t.a);
	} else {
		COLOR = t;
	}
}

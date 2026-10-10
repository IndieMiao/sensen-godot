// A placement square on a bed (284 v2 §2, 不知火舞 on #261): `fill` across it, and an `edge` of `edge_m` metres round
// it when the edge has any alpha — about 2 px at 36 px a cell on the 0.9 m square.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 fill : source_color = vec4(0.55, 0.78, 0.95, 0.55);
uniform vec4 edge : source_color = vec4(0.0);
uniform float size_m = 0.9;
uniform float edge_m = 0.036;

void fragment() {
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)) * size_m;
	bool on_edge = edge.a > 0.0 && d < edge_m;
	vec4 c = on_edge ? edge : fill;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}

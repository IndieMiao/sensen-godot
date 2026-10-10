// Placement grid (284 v2 §2, 不知火舞): white cell lines on the ground within `radius` of `centre`, 50% at the centre
// fading to 0 at the radius. Cells are `cell` metres, `origin` one cell's centre, so the lines fall on cell edges.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float cell = 0.65;
uniform vec2 origin = vec2(0.0);
uniform vec2 centre = vec2(0.0);
uniform float radius = 1.95;
uniform float line_m = 0.018;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = (world.xz - origin) / cell + 0.5;   // cell edges at whole numbers
	vec2 e = min(fract(q), 1.0 - fract(q)) * cell;
	float line = 1.0 - step(line_m, min(e.x, e.y));
	float fade = clamp(1.0 - length(world.xz - centre) / radius, 0.0, 1.0);
	ALBEDO = vec3(1.0);
	ALPHA = line * 0.5 * fade;
}

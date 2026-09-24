shader_type spatial;
// Fountain spray: translucent white-cyan column with streaks falling down, bright rim.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

uniform vec4 core : source_color = vec4(0.62, 0.86, 0.97, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying float height_t;

void vertex() {
	height_t = UV.y;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float streak = sin(UV.x * 40.0 + sin(UV.y * 6.0)) * 0.5 + 0.5;
	float flow = sin((UV.y * 14.0 + TIME * 5.0) + UV.x * 12.0) * 0.5 + 0.5;
	vec3 col = mix(core.rgb, edge.rgb, clamp(fres + streak * flow * 0.45 + (1.0 - UV.y) * 0.25, 0.0, 1.0));
	ALBEDO = col;
	EMISSION = col * 0.25;
	ALPHA = clamp(0.72 + fres * 0.28 - UV.y * 0.1, 0.0, 1.0);
}

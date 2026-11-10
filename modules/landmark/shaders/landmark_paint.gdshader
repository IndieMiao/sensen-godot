shader_type spatial;
// Opaque baked vertex paint (linear, with baked AO) shared by all landmark meshes; fades into haze
// beyond the play area so the scene border dissolves instead of ending abruptly.
render_mode diffuse_burley, specular_schlick_ggx;

// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform vec4 haze : source_color = vec4(0.89, 0.92, 0.91, 1.0);
uniform vec4 play_rect = vec4(-12.0, 12.0, -10.0, 10.5);
uniform float fade = 5.0;
uniform float haze_strength = 1.0;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 ox = max(vec2(play_rect.x - world.x, world.x - play_rect.y), vec2(0.0));
	float d = max(max(ox.x, ox.y), max(world.z - play_rect.w, 0.0));
	// Distance haze follows depth below the hilltop (the valley), not northward distance:
	// the nearby western hill keeps its colour like the design.
	d = max(d, smoothstep(-4.0, -9.0, world.y) * fade);
	// Soft sky light: upward faces read lighter, like the design's sunlit canopy tops.
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	vec3 col = COLOR.rgb * (1.02 + 0.06 * clamp(up, 0.0, 1.0));
	float mist = smoothstep(0.0, fade, d) * haze_strength;
	ALBEDO = col * (1.0 - mist);
	EMISSION = src_linear4(haze).rgb * mist;
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
	ALBEDO = albedo_out(ALBEDO);
	EMISSION = albedo_out(EMISSION);
}

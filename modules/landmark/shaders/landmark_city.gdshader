shader_type spatial;
// Far valley buildings use baked face tint and aerial perspective, avoiding
// high-contrast sun/shadow bands that compete with the playable hilltop.
render_mode unshaded, cull_back;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform vec4 scene_haze : source_color = vec4(0.89,0.92,0.91,1.0);
uniform vec4 atmosphere : source_color = vec4(0.73,0.83,0.88,1.0);
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL,0.0)).xyz);
	float face = 0.84 + max(n.y,0.0)*0.14 + max(-n.x,0.0)*0.06;
	float mist = clamp(0.12 + (-world.z-15.0)*0.016,0.12,0.46);
	float edge = max(smoothstep(20.0,26.0,world.x),smoothstep(24.0,34.0,-world.z));
	ALBEDO = mix(mix(COLOR.rgb * face, src_linear4(atmosphere).rgb,mist),src_linear4(scene_haze).rgb,edge);
	ALBEDO = albedo_out(ALBEDO);
}

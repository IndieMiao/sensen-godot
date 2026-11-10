shader_type spatial;
render_mode cull_disabled;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
varying vec3 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float bend = max(VERTEX.y - 0.08, 0.0);
    VERTEX.x += sin(TIME * 1.3 + world.x * 2.1 + world.z) * bend * 0.024;
    VERTEX.z += cos(TIME * 1.1 + world.x + world.z * 1.6) * bend * 0.018;
}
void fragment() {
    float vein = 1.0 - smoothstep(0.03, 0.12, abs(UV.x - 0.5));
    ALBEDO = COLOR.rgb * (0.82 + UV.y * 0.22 + vein * 0.12);
    BACKLIGHT = COLOR.rgb * 0.20;
    ROUGHNESS = 0.76;
    SPECULAR = 0.15;
	ALBEDO = albedo_out(ALBEDO);
}

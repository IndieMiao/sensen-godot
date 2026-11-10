shader_type spatial;
render_mode cull_back;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_strength = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec3 painted = mix(COLOR.rgb, src_linear4(tint).rgb, clamp(UV2.x * tint_strength, 0.0, 1.0));
	ALBEDO = mix(painted, vec3(1.0, 0.96, 0.85), flash);
	ROUGHNESS = 0.8;
	SPECULAR = 0.18;
	ALBEDO = albedo_out(ALBEDO);
}

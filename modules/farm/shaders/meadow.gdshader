shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform sampler2D meadow_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 clearing_color : source_color = vec4(0.60, 0.74, 0.37, 1.0);
uniform float woodland_start = 7.1;
varying vec2 world_uv;

void vertex() {
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec3 paint = src_linear4(texture(meadow_texture, world_uv * 0.075)).rgb;
	paint = mix(src_linear4(clearing_color).rgb, paint, 0.50);
	float grain = src_linear4(texture(meadow_texture, world_uv * 0.73 + vec2(0.31, 0.17))).g;
	// Cooler, mottled grass beyond the clearing gives the woodland its own depth.
	float woodland = smoothstep(woodland_start, woodland_start + 4.5, -world_uv.y + (grain - 0.45) * 1.2);
	vec3 woodland_tint = mix(vec3(1.0), vec3(0.50, 0.72, 0.76), woodland);
	ALBEDO = paint * (0.94 + grain * 0.12) * woodland_tint;
	ROUGHNESS = 1.0;
	ALBEDO = albedo_out(ALBEDO);
}

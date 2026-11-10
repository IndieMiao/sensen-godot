shader_type spatial;
render_mode diffuse_burley, specular_disabled;
// GLES (SGODOT-458): the linear vertex colour and its grain worked out in linear, handed over as GLES wants it.
#include "res://modules/render/gles_colour.gdshaderinc"

uniform sampler2D meadow_texture : source_color, repeat_enable, filter_linear_mipmap;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float grain = src_linear(texture(meadow_texture, world_position * 1.8).rgb).g;
	ALBEDO = albedo_out(COLOR.rgb * (0.60 + grain * 0.80));
	ROUGHNESS = 1.0;
}

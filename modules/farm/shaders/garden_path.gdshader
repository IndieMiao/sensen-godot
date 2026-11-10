shader_type spatial;
render_mode diffuse_burley, specular_disabled;
// GLES (SGODOT-458): the linear vertex colour and its grain worked out in linear, handed over as GLES wants it.
#include "res://modules/render/gles_colour.gdshaderinc"

uniform sampler2D meadow_texture : source_color, repeat_enable, filter_linear_mipmap;
varying vec2 local_position;
varying vec2 world_position;

void vertex() {
	local_position = VERTEX.xz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float grain = src_linear(texture(meadow_texture, world_position * 1.3).rgb).g;
	vec2 corner = abs(local_position) - vec2(0.575);
	float edge = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - 0.06;
	ALBEDO = albedo_out(COLOR.rgb * (0.85 + grain * 0.3));
	ROUGHNESS = 1.0;
	// A single ground-level transparent surface feathers only the outer few cm.
	ALPHA = 1.0 - smoothstep(-0.03, -0.003, edge + (grain - 0.5) * 0.009);
}

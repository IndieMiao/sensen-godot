shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://modules/render/gles_colour.gdshaderinc"

uniform sampler2D grain : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	ALBEDO = albedo_out(src_linear(texture(grain, UV).rgb) * COLOR.rgb);
	ROUGHNESS = 0.89;
	SPECULAR = 0.27;
}

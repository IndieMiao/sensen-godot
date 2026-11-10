shader_type spatial;
// SGODOT-458 (周瑜's spec): what a StandardMaterial3D with vertex_color_use_as_albedo draws — its linear vertex colour (and
// a MultiMesh's instance colour, in COLOR as there) times the albedo tint, with roughness, specular and metallic — for
// Compatibility (GLES3) only: there the material's own shader reads the linear colour as sRGB, a second decode, every
// such piece darker and more saturated than on Mobile. GlesAlbedo swaps it in; the RD renderers never see it.
// The render modes are a StandardMaterial3D's own (blend mix, opaque depth, back faces culled, Burley, Schlick-GGX).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://modules/render/gles_colour.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_specular : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = albedo_out(src_linear(albedo.rgb) * COLOR.rgb);
	ROUGHNESS = roughness;
	SPECULAR = metallic_specular;
	METALLIC = metallic;
}

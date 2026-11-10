shader_type spatial;
// The mine's underground backdrop (SGODOT-257; assets/mine/backdrop/README.md): opaque, unlit, no shadows. The vertex
// colour's RGB is a grey weight read as is (no second sRGB decode); UV2.x fades from the floor's tint (0) to the void
// background (1). No ALPHA: the fade is a colour mix.
render_mode unshaded, shadows_disabled, fog_disabled;
// GLES (SGODOT-458): the tints to linear first, the mix handed over as GLES wants it.
#include "res://modules/render/gles_colour.gdshaderinc"

uniform vec3 floor_tint : source_color = vec3(0.39686275, 0.2027451, 0.1445098);
uniform vec3 void_tint : source_color = vec3(0.14117647, 0.12941176, 0.14509804);
// 355 (contract-efg §10.1): a type's own relief (assets/mine/types/<type>/backdrop.glb) marks its ore veins in UV2.y,
// shown in their vertex colour, not the floor's tint; 1 only for those — the old relief's UV2.y is all 1.0 and would
// lose its tint everywhere.
uniform float vein_mask = 0.0;

void fragment() {
	vec3 rock = mix(COLOR.rgb * src_linear(floor_tint), COLOR.rgb, clamp(UV2.y, 0.0, 1.0) * vein_mask);
	ALBEDO = albedo_out(mix(rock, src_linear(void_tint), clamp(UV2.x, 0.0, 1.0)));
}

shader_type spatial;
// The mine's underground backdrop (SGODOT-257; assets/mine/backdrop/README.md): opaque, unlit, no shadows. The vertex
// colour's RGB is a grey weight read as is (no second sRGB decode); UV2.x fades from the floor's tint (0) to the void
// background (1). No ALPHA: the fade is a colour mix.
render_mode unshaded, shadows_disabled, fog_disabled;

uniform vec3 floor_tint : source_color = vec3(0.39686275, 0.2027451, 0.1445098);
uniform vec3 void_tint : source_color = vec3(0.14117647, 0.12941176, 0.14509804);

void fragment() {
	ALBEDO = mix(COLOR.rgb * floor_tint, void_tint, clamp(UV2.x, 0.0, 1.0));
}

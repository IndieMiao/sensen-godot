shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_strength = 0.0;
uniform float flash = 0.0;
void fragment() {
	vec3 painted = mix(COLOR.rgb, tint.rgb, clamp(UV2.x * tint_strength, 0.0, 1.0));
	ALBEDO = mix(painted, vec3(1.0, 0.96, 0.85), flash);
	ROUGHNESS = 0.8;
	SPECULAR = 0.18;
}

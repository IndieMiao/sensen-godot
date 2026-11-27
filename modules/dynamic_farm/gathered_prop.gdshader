// A gathered tree or rock until it grows back (C-60): the same model and pose, its vertex
// colours (linear, like FarmArt.material) washed out and darkened so it reads as picked over.
// `amount` 0 → 1 is MS-08's fade into that grey (C-185 §3.2, C-211); 1 for every one drawn at rest.
shader_type spatial;

uniform float desaturate : hint_range(0.0, 1.0) = 0.8;
uniform float dim : hint_range(0.0, 1.0) = 0.62;
uniform vec3 tint : source_color = vec3(0.92, 0.86, 0.76);
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float luma = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 picked = mix(COLOR.rgb, vec3(luma), desaturate) * tint * dim;
	ALBEDO = mix(COLOR.rgb, picked, amount);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}

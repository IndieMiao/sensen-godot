shader_type canvas_item;
// Soft fog over the map (P0 travel, plan v2 §11.7, SGODOT-275): a grey veil everywhere except round explored cities.
// holes: xy = centre in the layer's pixels, z = radius in pixels; the first `count` are used. A hole's edge feathers
// over `feather` of its radius so a city's colour fades into the fog instead of ending on a hard circle.

const int MAX_HOLES = 64;
uniform vec4 holes[MAX_HOLES];
uniform int count = 0;
uniform vec4 fog_color : source_color = vec4(0.62, 0.65, 0.68, 0.42);
uniform float feather = 0.35;
uniform vec2 size = vec2(360.0, 800.0);

void fragment() {
	vec2 p = UV * size;
	float clear = 0.0;
	for (int i = 0; i < MAX_HOLES; i++) {
		if (i >= count) break;
		vec4 h = holes[i];
		float d = distance(p, h.xy);
		float edge = max(1.0, h.z * feather);
		clear = max(clear, 1.0 - smoothstep(h.z - edge, h.z, d));
	}
	COLOR = vec4(fog_color.rgb, fog_color.a * (1.0 - clear));
}

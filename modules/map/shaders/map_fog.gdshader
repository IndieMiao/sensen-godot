shader_type canvas_item;
// Soft fog over the map (P0 travel, plan v2 §11.7, SGODOT-275): a grey veil everywhere except round explored cities.
// holes: xy = centre in the layer's pixels, z = radius in pixels; the first `count` are used. A hole's edge feathers
// over `feather` screen pixels (不知火舞 on #227: a fixed 24 px, not a share of the radius, which blurs at country zoom).

const int MAX_HOLES = 64;
uniform vec4 holes[MAX_HOLES];
uniform int count = 0;
uniform vec4 fog_color : source_color = vec4(0.365, 0.416, 0.384, 0.40);   // MapFogLayer.FOG (#5D6A62 at 40 %)
uniform float feather = 24.0;
uniform vec2 size = vec2(360.0, 800.0);

void fragment() {
	vec2 p = UV * size;
	float clear = 0.0;
	for (int i = 0; i < MAX_HOLES; i++) {
		if (i >= count) break;
		vec4 h = holes[i];
		float d = distance(p, h.xy);
		float edge = min(feather, max(1.0, h.z));
		clear = max(clear, 1.0 - smoothstep(h.z - edge, h.z, d));
	}
	COLOR = vec4(fog_color.rgb, fog_color.a * (1.0 - clear));
}

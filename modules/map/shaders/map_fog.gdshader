shader_type canvas_item;
// Soft fog over the map (P0 travel, plan v2 §11.7, SGODOT-275): a grey veil everywhere except round explored cities.
// A hole's edge is a conic about its centre (MapFogLayer.conic_of): Q(v) = a x² + 2b xy + c y² + 2d x + 2e y − 1, below 0
// inside — a circle on a flat map, an ellipse on a tilted one (SGODOT-298). holes: xy = centre in the layer's pixels,
// z = a, w = b; shapes: x = c, y = d, z = e, w = the hole's smallest radius (px). The first `count` are used. A hole's
// edge feathers over `feather` screen pixels (不知火舞 on #227: a fixed 24 px, not a share of the radius, which blurs at
// country zoom), measured to first order (Q / |∇Q|).

const int MAX_HOLES = 64;
uniform vec4 holes[MAX_HOLES];
uniform vec4 shapes[MAX_HOLES];
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
		vec4 k = shapes[i];
		vec2 v = p - h.xy;
		float q = h.z * v.x * v.x + 2.0 * h.w * v.x * v.y + k.x * v.y * v.y + 2.0 * k.y * v.x + 2.0 * k.z * v.y - 1.0;
		vec2 g = 2.0 * vec2(h.z * v.x + h.w * v.y + k.y, h.w * v.x + k.x * v.y + k.z);
		float d = q / max(length(g), 1e-12);
		float edge = min(feather, max(1.0, k.w));
		clear = max(clear, 1.0 - smoothstep(-edge, 0.0, d));
	}
	COLOR = vec4(fog_color.rgb, fog_color.a * (1.0 - clear));
}

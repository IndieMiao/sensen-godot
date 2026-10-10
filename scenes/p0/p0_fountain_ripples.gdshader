// A Fountain's water bubbling (q(131): `Bubbles away`, 苏烈; SGODOT-290's model has flat water only): rings that grow
// from a few points on one basin's water and fade, drawn on a quad laid on that water. Sizes are in the model's metres.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float basin = 0.26;                       // the water's radius: nothing past it
uniform float source_r = 0.0;                     // the ring sources' distance from the middle
uniform int sources = 1;                          // how many, evenly round
uniform float reach = 0.22;                       // how far a ring grows
uniform float width = 0.022;                      // a ring's half width
uniform float period = 2.4;                       // seconds a ring takes to grow out
uniform vec4 tint : source_color = vec4(0.93, 0.98, 1.0, 0.65);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * basin;
	if (length(p) > basin - width) discard;
	float a = 0.0;
	for (int s = 0; s < sources; s++) {
		float ang = 6.2831853 * float(s) / float(max(sources, 1));
		vec2 c = source_r * vec2(cos(ang), sin(ang));
		float d = length(p - c);
		for (int k = 0; k < 2; k++) {   // two rings a source, half a period apart
			float t = fract(TIME / period + float(k) * 0.5 + float(s) * 0.37);
			float ring = 1.0 - smoothstep(0.0, width, abs(d - t * reach));
			a = max(a, ring * (1.0 - t) * smoothstep(0.0, 0.12, t));
		}
	}
	if (a <= 0.01) discard;
	ALBEDO = tint.rgb;
	ALPHA = a * tint.a;
}

shader_type spatial;
// Stylized fountain water matching the landmark designs: pale cyan rim to deeper center,
// drifting concentric ripples, soft white foam at the stone edge and twinkling highlights.
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform vec4 shallow : source_color = vec4(0.52, 0.80, 0.94, 1.0);
uniform vec4 deep : source_color = vec4(0.26, 0.62, 0.88, 1.0);
uniform vec4 foam : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform float radius = 0.5;
uniform float ripple_speed = 0.6;

varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float r = length(local) / radius;
	vec3 col = mix(src_linear4(deep).rgb, src_linear4(shallow).rgb, smoothstep(0.05, 0.95, r));
	// Concentric ripples moving outward from the jet.
	float ring = sin((r * 9.0 - TIME * ripple_speed * 3.0) * 3.14159);
	col += vec3(0.10, 0.12, 0.12) * smoothstep(0.55, 1.0, ring) * (1.0 - r * 0.6);
	// Soft caustic mottling.
	vec2 q = local * 7.0 + vec2(TIME * 0.35, -TIME * 0.27);
	float c = sin(q.x) * sin(q.y + sin(q.x * 0.7 + TIME));
	col += vec3(0.05, 0.06, 0.06) * smoothstep(0.4, 1.0, c);
	// Foam band at the basin wall.
	col = mix(col, src_linear4(foam).rgb, smoothstep(0.88, 0.99, r) * 0.7);
	// Sparkles.
	vec2 cell = floor(local * 14.0);
	float s = hash(cell);
	float tw = step(0.93, s) * pow(max(0.0, sin(TIME * 2.5 + s * 30.0)), 12.0);
	col += vec3(tw) * 0.8;
	ALBEDO = col;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
	EMISSION = col * 0.12;
	ALBEDO = albedo_out(ALBEDO);
	EMISSION = albedo_out(EMISSION);
}

shader_type sky;
// Distant cumulus groups in the orthographic backdrop. No floor, shoreline,
// scrolling ripples, reflection plane, sky-driven relighting or extra viewport.
float puff(vec2 p, vec2 center, vec2 size) {
	return length((p - center) / size);
}

vec3 cumulus(vec3 air, vec2 p, float haze) {
	float l = puff(p, vec2(-0.56, 0.09), vec2(0.49, 0.29));
	float m = puff(p, vec2(-0.14, -0.08), vec2(0.52, 0.48));
	float r = puff(p, vec2(0.32, 0.02), vec2(0.46, 0.35));
	float tip = puff(p, vec2(0.67, 0.13), vec2(0.36, 0.21));
	float d = min(min(l, m), min(r, tip));
	// Warm crowns, cool undersides and a little bounced light between the lobes.
	float crown = 1.0 - smoothstep(-0.20, 0.32, p.y + 0.10 * d);
	vec3 cloud = mix(vec3(0.71, 0.77, 0.88), vec3(1.0, 0.97, 0.90), crown);
	return mix(air, cloud, haze * (1.0 - smoothstep(0.87, 1.06, d)));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.63, 0.78, 0.90);
	} else {
		vec2 uv = SCREEN_UV;
		vec3 air = mix(vec3(0.42, 0.67, 0.88), vec3(0.74, 0.84, 0.90), uv.y);
		air = cumulus(air, (uv - vec2(0.21, 0.18)) / vec2(0.38, 0.16), 0.68);
		air = cumulus(air, (uv - vec2(0.90, 0.34)) / vec2(0.48, 0.19), 0.66);
		air = cumulus(air, (uv - vec2(0.01, 0.52)) / vec2(0.57, 0.22), 0.88);
		air = cumulus(air, (uv - vec2(0.71, 0.69)) / vec2(0.39, 0.17), 0.72);
		air = cumulus(air, (uv - vec2(0.07, 0.93)) / vec2(0.63, 0.27), 0.93);
		COLOR = air;
	}
}

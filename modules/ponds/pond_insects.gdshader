shader_type spatial;
// The wild's bees, butterflies and dragonflies (SGODOT-454, PondInsects): one MultiMesh per kind, each instance at its
// anchor (the instance's origin), INSTANCE_CUSTOM = (flight radius m, phase 0–1, colour variant, scale). The flight,
// the turn to face it and the wingbeat are all worked out here from TIME; the CPU does nothing per frame.
// Mesh: forward +Z; UV.x 0 the body, ±1 a wing on that side (hinged on the body's long axis), UV.y 0 a forewing,
// 1 a hindwing; UV2 the wing's own (span out from the hinge, chord back to front) for its outline and markings.
// Colours by part from `palette`, no textures (上官婉儿's spec).
render_mode unshaded, cull_disabled, shadows_disabled;

uniform int kind = 0;   // 0 bee, 1 butterfly, 2 dragonfly
// bee: body, stripe, wing · butterfly: body, wings ×3, markings ×3 · dragonfly: bodies ×2, heads ×2, wing
uniform vec3 palette[8] : source_color;

varying vec3 local;
varying vec2 wing;
varying float side;
varying float variant;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

// The bee's pauses over a flower: time runs at full speed but for a `hold` s dip each `period`, down to `slow` (smooth).
float warped(float t, float period, float hold, float slow) {
	float n = floor(t / period);
	float f = t - n * period;
	float run = period - hold;
	float lost = (1.0 - slow) * 0.5;   // the dip's mean slowdown
	float base = n * (period - lost * hold);
	if (f < run) return base + f;
	float g = f - run;
	return base + run + g - lost * (g - hold / TAU * sin(TAU * g / hold));
}

vec3 bee_path(float u, float r, float seed) {
	float a = u * mix(0.5, 0.8, hash(seed * 7.3)) / r;   // 0.5–0.8 m/s round the loop
	float eight = step(0.5, hash(seed * 3.7));            // a figure eight or an ellipse
	return vec3(r * sin(a), 0.08 * sin(u * 1.7 + seed * 6.0), r * mix(0.6 * cos(a), 0.55 * sin(2.0 * a), eight));
}

vec3 butterfly_path(float t, float r, float seed) {
	float a = t * mix(0.3, 0.5, hash(seed * 5.1)) / r;   // 0.3–0.5 m/s, drifting
	return vec3(r * sin(a), 0.15 * sin(a * 0.9 + seed * 4.0), r * 0.7 * sin(a * 1.3 + seed * 9.0));
}

// The dragonfly's stops round its anchor, the darts between them 2r·sin(1.05) apart (1–1.5 m at its radius).
vec3 stop(float k, float r, float seed) {
	float a = seed * TAU + k * 2.1 + (hash(k + seed * 31.0) - 0.5) * 0.6;
	return vec3(r * cos(a), 0.0, r * sin(a));
}

void vertex() {
	float r = INSTANCE_CUSTOM.x;
	float seed = INSTANCE_CUSTOM.y;
	variant = INSTANCE_CUSTOM.z;
	local = VERTEX;
	wing = UV2;
	side = UV.x;
	float t = TIME + seed * 37.0;
	vec3 at;
	vec3 ahead;
	float beat;     // the wing's angle up from flat, radians
	float yaw;
	if (kind == 0) {
		float u = warped(t, 3.5 + 2.0 * hash(seed * 3.1), 1.4, 0.12);
		at = bee_path(u, r, seed);
		ahead = bee_path(u + 0.05, r, seed) - at;
		beat = radians(20.0) + radians(60.0) * sin(TAU * 11.0 * t);   // 11 Hz: under 12 at 30 fps (spec)
		yaw = atan(ahead.x, ahead.z);
	} else if (kind == 1) {
		at = butterfly_path(t, r, seed);
		ahead = butterfly_path(t + 0.05, r, seed) - at;
		// 3.5 Hz, 0°–75° (spec), spread most of the beat and up only near its top: seen from above a butterfly is its
		// spread wings
		float up = pow(0.5 + 0.5 * sin(TAU * 3.5 * t), 3.0);
		beat = radians(75.0) * up;
		at.y += 0.04 * (0.5 - up);   // the body lifts as the wings come down
		yaw = atan(ahead.x, ahead.z);
	} else {
		float hold = 1.2 + 0.6 * hash(seed * 5.7);   // hovers 1.2–1.8 s
		float dart = 0.85;                            // then darts ~1.5 m/s
		float k = floor(t / (hold + dart));
		float f = t - k * (hold + dart);
		vec3 here = stop(k, r, seed);
		vec3 next = stop(k + 1.0, r, seed);
		vec3 came = here - stop(k - 1.0, r, seed);
		at = mix(here, next, smoothstep(hold, hold + dart, f));
		at.y = 0.04 * sin(t * 2.3 + seed * 5.0);
		// faces where it came from while it hovers, turning its head quickly just before it darts
		float a0 = atan(came.x, came.z);
		float a1 = atan(next.x - here.x, next.z - here.z);
		yaw = a0 + (mod(a1 - a0 + PI, TAU) - PI) * smoothstep(hold - 0.18, hold, f);
		beat = radians(20.0) * sin(TAU * 8.0 * t + UV.y * 1.6);   // 8 Hz; the fore and hind wings out of step
	}
	vec3 v = VERTEX;
	if (side != 0.0) {   // the wing turns up about the body's long axis at its hinge height
		float out_ = v.x * side;
		v.x = side * out_ * cos(beat);
		v.y += out_ * sin(beat);
	}
	v *= INSTANCE_CUSTOM.w;
	float c = cos(yaw);
	float s = sin(yaw);
	VERTEX = vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c) + at;
}

void fragment() {
	vec3 colour;
	float alpha = 1.0;
	int k = int(variant + 0.5);
	if (kind == 0) {
		if (side != 0.0) {
			alpha = step(length((wing - vec2(0.5)) * vec2(2.0, 2.2)), 1.0);
			colour = palette[2];
		} else {   // tail tip black, then yellow / black / yellow / black / yellow to the head
			float l = clamp((local.z + 0.08) / 0.16, 0.0, 1.0);
			float dark = step(l, 0.16) + step(0.36, l) * step(l, 0.48) + step(0.62, l) * step(l, 0.72);
			colour = mix(palette[0], palette[1], clamp(dark, 0.0, 1.0));
		}
	} else if (kind == 1) {
		if (side != 0.0) {   // a forewing lobe ahead, a smaller hindwing lobe behind
			float fore = length((wing - vec2(0.52, 0.66)) / vec2(0.5, 0.36));
			float hind = length((wing - vec2(0.36, 0.26)) / vec2(0.36, 0.28));
			alpha = step(min(fore, hind), 1.0);
			colour = palette[1 + k];
			float mark;
			if (k == 0) mark = step(0.72, wing.x) * step(0.72, wing.y);                 // yellow: an orange tip
			else if (k == 1) mark = step(length(wing - vec2(0.82, 0.8)), 0.09);          // white: a dark dot
			else mark = step(wing.x, 0.3);                                               // lilac: paler by the body
			colour = mix(colour, palette[4 + k], mark);
		} else {
			colour = palette[0];
		}
	} else {
		if (side != 0.0) {
			alpha = step(length((wing - vec2(0.5)) * vec2(2.0, 2.4)), 1.0);
			// the leading edge in the body's colour: the pale wing has an outline on the water (上官婉儿 on #929)
			colour = wing.y > 0.64 ? palette[k] : palette[4];
		} else {
			colour = local.z > 0.105 ? palette[2 + k] : palette[k];   // the head a shade darker
		}
	}
	ALBEDO = colour;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

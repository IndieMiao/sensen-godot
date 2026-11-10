shader_type spatial;
render_mode specular_disabled;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
// The farm's meadow with the woods round it (P0FarmWoods, SGODOT-422 0.3.5; meadow.gdshader is the meadow before them):
// the same painted meadow and its cooler woodland behind the house, plus the wild ground's language at a few ALU —
// big yellow-green / blue-green patches and a faint light wander (value noise: no extra texture, no data texture), the
// floor under the woods outside the fence ring cooler and darker, the shadows blue-green, and in the yard the wild's
// sparse short grass strokes (上官婉儿 11-10: the empty yard and the beds still to open painted, not filled with pieces).
// No per-renderer light here: GLES drops the sun's shadows for every scene instead (SGODOT-456).

uniform sampler2D meadow_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 clearing_color : source_color = vec4(0.60, 0.74, 0.37, 1.0);
uniform float woodland_start = 7.1;
uniform vec4 yard = vec4(0.38, -12.35, 12.95, 1.4);   // the fence ring: x0, z0, x1, z1
uniform vec3 mottle_warm : source_color = vec3(0.639, 0.710, 0.306);   // a3b54e (the wild's dapple_warm)
uniform vec3 mottle_cool : source_color = vec3(0.435, 0.608, 0.322);   // 6f9b52 (dapple_cool)
uniform float mottle = 0.5;
uniform float wander = 0.10;
uniform vec3 floor_tint = vec3(0.74, 0.85, 0.86);
uniform float strokes = 0.13;   // a dark dash darkens by strokes × 2.2, a light one lightens by × 1.4 (the wild's 0.07 is lost on this meadow)
uniform vec3 shadow_tint = vec3(0.0, 0.05, 0.12);
uniform vec3 shadow_cool = vec3(0.0, 0.012, 0.03);
varying vec2 world_uv;
#include "res://modules/render/ground_shade.gdshaderinc"
varying float shade;   // the trees' shade under Compatibility (SGODOT-457)

void vertex() {
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// sin-free hash (Hoskins' hash12): steady on fp32 GPUs far from the origin
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 rot(vec2 p, float a) { return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a)); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 paint = src_linear4(texture(meadow_texture, world_uv * 0.075)).rgb;
	paint = mix(src_linear4(clearing_color).rgb, paint, 0.50);
	float grain = src_linear4(texture(meadow_texture, world_uv * 0.73 + vec2(0.31, 0.17))).g;
	float woodland = smoothstep(woodland_start, woodland_start + 4.5, -world_uv.y + (grain - 0.45) * 1.2);
	vec3 woodland_tint = mix(vec3(1.0), vec3(0.50, 0.72, 0.76), woodland);
	vec3 c = paint * (0.94 + grain * 0.12) * woodland_tint;
	float n = vnoise(world_uv / 6.5 + vec2(3.7, 1.3)) * 0.65 + vnoise(world_uv / 2.4 + vec2(11.0, 7.0)) * 0.35;
	vec3 hue = mix(src_linear(mottle_cool), src_linear(mottle_warm), smoothstep(0.36, 0.64, n));
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	c = mix(c, hue * dot(c, LUMA) / max(dot(hue, LUMA), 0.001), mottle);
	c *= 1.0 + (n - 0.5) * 2.0 * wander;
	vec2 out2 = max(yard.xy - world_uv, world_uv - yard.zw);
	float outside = max(max(out2.x, out2.y), 0.0);
	// little grass strokes (pond_wild_ground's, denser): in 0.37 m cells, turned so no grid shows, one in three a dark
	// dash; and in a second, offset grid one in four a light one — the empty yard reads as grass growing, not flat paint
	float in_yard = 1.0 - smoothstep(0.0, 3.0, outside);
	vec2 cq = rot(world_uv, 0.9) / 0.37;
	vec2 cell = floor(cq);
	vec2 at = fract(cq) - (0.25 + 0.5 * vec2(hash12(cell + 3.0), hash12(cell + 9.0)));
	vec2 dash = rot(at, hash12(cell + 5.0) * 6.283) * vec2(1.0, 4.0) * 0.37;   // ~0.09 m long, ~0.02 m wide
	float stroke = step(0.67, hash12(cell + 17.0)) * (1.0 - smoothstep(0.03, 0.045, length(dash)));
	c *= 1.0 - stroke * strokes * 2.2 * in_yard;
	vec2 lq = rot(world_uv + vec2(0.19, 0.11), 2.3) / 0.41;
	vec2 lcell = floor(lq);
	vec2 lat = fract(lq) - (0.25 + 0.5 * vec2(hash12(lcell + 23.0), hash12(lcell + 29.0)));
	vec2 ldash = rot(lat, hash12(lcell + 31.0) * 6.283) * vec2(1.0, 4.0) * 0.41;
	float light_stroke = step(0.75, hash12(lcell + 37.0)) * (1.0 - smoothstep(0.03, 0.045, length(ldash)));
	c *= 1.0 + light_stroke * strokes * 1.4 * in_yard;
	c *= mix(vec3(1.0), floor_tint, smoothstep(0.2, 4.0, outside + (grain - 0.5) * 0.8));
	shade = ground_shade(world_uv);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	ALBEDO = albedo_out(ALBEDO);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float att = shade_att(ATTENUATION, shade);
	DIFFUSE_LIGHT += ndl * att * LIGHT_COLOR / PI;
	float shadowed = ndl * (1.0 - att);
	DIFFUSE_LIGHT += shadowed * shadow_tint * LIGHT_COLOR / PI;
	SPECULAR_LIGHT += shadowed * shadow_cool;
}

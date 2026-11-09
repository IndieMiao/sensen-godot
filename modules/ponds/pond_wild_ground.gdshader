shader_type spatial;
// SGODOT-422 wild ground (盘古, the user's v7 11-09; pond_wild_ground.gd sets it): flat painted ground — one warm grass,
// one sand, one path colour, soft frayed outlines from distance fields, light from one large soft gradient, faint colour
// wander and grain, a pale soft band at the joins, the trail into the woods; no texture, no facets.
uniform sampler2D water_sdf : filter_linear, repeat_disable;   // metres to the water's edge (<0 in the water)
uniform vec2 sdf_origin = vec2(-6.0, -22.0);
uniform vec2 sdf_extent = vec2(24.0, 28.0);
uniform vec2 path_points[6];
uniform int path_count = 0;
const vec2 SPAWN = vec2(6.125, -1.625);   // the player's spawn (its sand patch)
uniform vec4 walk = vec4(-2.5, -16.0, 14.5, 1.5);   // x0, z0, x1, z1
uniform vec3 grass : source_color = vec3(0.56, 0.69, 0.30);
uniform vec3 grass_far : source_color = vec3(0.47, 0.60, 0.26);
uniform vec3 plateau : source_color = vec3(0.49, 0.62, 0.27);
uniform vec3 sand : source_color = vec3(0.87, 0.78, 0.58);
uniform vec3 wet : source_color = vec3(0.96, 0.91, 0.78);
uniform vec3 path_colour : source_color = vec3(0.84, 0.74, 0.54);
uniform vec3 rock : source_color = vec3(0.71, 0.62, 0.52);
uniform float gradient = 0.10;   // how much the meadow lightens toward the water and darkens toward its rim
uniform float sand_m = 0.55;     // the sand band's width round the water
uniform vec2 centre = vec2(6.0, -8.0);   // the pond's middle
uniform float south_dark = 0.0;
uniform float vignette = 0.0;
uniform vec2 seed_off = vec2(0.0);      // each pond its own noise
uniform float fine_edge = 0.0;
// v6 (the user on v5, 530 / 532): no broken texture — the grass islets in the sand and the terraces' tops keep the meadow's
// own shading; and a softer join — a band of pale soft green between the sand / path and the meadow's present colour
uniform float seam_fix = 0.0;
uniform vec3 soft_grass : source_color = vec3(0.66, 0.74, 0.40);
uniform float soft_m = 1.7;
// v7: the path's end runs on as a narrow trail into the woods (the user: an adventure); 3 points, 0 width = off
uniform vec2 trail_points[3];
uniform float trail_w = 0.0;   // the soft band's width off the sand, metres (the path's is 0.7 of it)
uniform vec2 contact_points[64];      // v5: plants' feet — a small patch ~10 % darker under each
uniform float contact = 0.0;          // v5: small notches and teeth on every edge, ragged islets, no round pads
uniform float big_tone = 0.0;           // v4: a larger layer — sunlit yellow-green, deep blue-green by the water and under trees
uniform vec2 under_trees[8];
uniform float dapple = 0.0;             // low-frequency light / hue wander, ±
uniform vec3 dapple_cool : source_color = vec3(0.45, 0.62, 0.40);   // the blue-green end of the wander
uniform vec3 dapple_warm : source_color = vec3(0.64, 0.71, 0.31);   // the yellow-green end
uniform float detail = 0.0;             // faint small-scale grain, three unrelated scales
uniform float edge_break = 0.0;         // the sand / grass edge broken by this many metres
uniform float path_taper = 0.0;         // the path narrows to its end over its last part
uniform vec3 shadow_tint = vec3(0.0);        // the sunlight a shadow on the grass keeps, per channel: deeper, toward blue-green
uniform vec3 shadow_tint_sand = vec3(0.0);
uniform vec3 shadow_cool = vec3(0.0);        // added straight into the shadow on the grass: blue-green
uniform float sun_k = 1.0;   // the sun's share of this ground's light (gl_compatibility: < 1, PondWildGround.look_for)
uniform vec3 shadow_cool_sand = vec3(0.0);   // ... on the sand: violet blue   // ... and on the sand: a cool, slightly violet beige
varying vec3 world;
varying vec3 world_normal;
varying float sandy;   // 1 on sand / path, 0 on grass: the shadows take their colour by it

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// sin-free hash (Hoskins' hash12): a sin() hash goes flat on fp32 GPUs once p reaches the thousands (the detail's scales)
float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// a crisp but anti-aliased edge where the field d crosses 0 (1 inside)
float fill(float d) { float w = fwidth(d) * 0.75; return 1.0 - smoothstep(-w, w, d); }
float seg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a, ba = b - a; return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)); }
vec2 rot(vec2 p, float a) { return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a)); }
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

void fragment() {
    vec2 p = world.xz;
    vec2 uv = (p - sdf_origin) / sdf_extent;
    float water = texture(water_sdf, clamp(uv, vec2(0.002), vec2(0.998))).r;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) water = max(water, 6.0);
    // out of the walk, metres
    vec2 o = max(max(walk.xy - p, p - walk.zw), vec2(0.0));
    float outside = length(o);
    // the meadow: one green, a large soft gradient — lighter by the water, deeper toward the rim
    // one large radial light: brightest round the pond's middle, falling off over ~16 m (the reference's soft pool)
    float lit = 1.0 - smoothstep(2.0, 13.0, length(p - centre));
    float rim = smoothstep(0.0, 6.0, outside);
    vec3 c = grass * mix(1.0 - gradient * 0.5, 1.0 + gradient * 0.6, lit);   // the dark end light (上官婉儿: not a cloud's shadow)
    c = mix(c, grass_far * (1.0 - gradient * 0.6), rim * 0.7);
    c *= 1.0 - vignette * smoothstep(7.0, 20.0, length(p - centre));
    c *= 1.0 - south_dark * smoothstep(-9.0, 6.0, p.y);   // pressed darker toward the camera's side (the screen's bottom)
    vec2 q = p + seed_off;
    float n1 = noise(rot(q, 0.6) * 0.16) * 0.65 + noise(rot(q, 2.1) * 0.37) * 0.35;   // large soft patches
    float n2 = noise(rot(q, 1.3) * 0.21 + 7.0);
    c *= 1.0 + (n1 - 0.5) * 2.0 * dapple;
    // the hue wanders both ways from the grass: yellow-green patches and blue-green ones, large and soft
    float hue_t = smoothstep(0.25, 0.75, n2);
    vec3 toward = mix(dapple_warm, dapple_cool, hue_t) / max(grass, vec3(0.01));
    c = mix(c, c * toward, abs(hue_t - 0.5) * 2.0 * dapple * 3.5);
    if (big_tone > 0.0) {
        float sun = noise(rot(q, 2.4) * 0.075) * 0.7 + noise(rot(q, 0.2) * 0.13) * 0.3;   // very large, smooth
        float under = 0.0;
        for (int k = 0; k < 8; k++) under = max(under, 1.0 - smoothstep(1.0, 3.2, length(p - under_trees[k])));
        float by_water = 1.0 - smoothstep(sand_m, sand_m + 3.5, water);
        float deep = clamp(max(under, by_water * 0.8), 0.0, 1.0);
        vec3 sunny = c * vec3(1.10, 1.08, 0.86);   // toward yellow-green, lighter
        vec3 teal = c * vec3(0.80, 0.90, 1.02);    // toward blue-green, deeper
        c = mix(c, sunny, smoothstep(0.45, 0.75, sun) * big_tone / 0.13 * (1.0 - deep));
        c = mix(c, teal, deep * big_tone / 0.13);
    }
    float g = noise(rot(q, 0.4) * 3.7) * 0.3 + noise(rot(q, 2.7) * 8.3) * 0.35 + noise(rot(q, 4.9) * 17.9) * 0.35;
    c *= 1.0 + (g - 0.5) * 2.0 * detail;
    // sparse little grass strokes: in 0.37 m cells (rotated, so no grid shows) one in five holds a short dark dash
    vec2 cq = rot(q, 0.9) / 0.37;
    vec2 cell = floor(cq);
    float pick = hash(cell + 17.0);
    vec2 at = fract(cq) - (0.25 + 0.5 * vec2(hash(cell + 3.0), hash(cell + 9.0)));
    vec2 dash = rot(at, hash(cell + 5.0) * 6.283) * vec2(1.0, 4.0) * 0.37;   // ~0.09 m long, ~0.02 m wide
    float stroke = step(0.80, pick) * (1.0 - smoothstep(0.03, 0.045, length(dash)));
    c *= 1.0 - stroke * detail * 2.2 * (1.0 - smoothstep(0.0, 6.0, outside));
    if (contact > 0.0) {
        float touch = 0.0;
        float wobble = (noise(p * 9.0) - 0.5) * 0.06;   // the same for every foot: once, not 64 times a pixel (GLES, 李元芳 on #917)
        for (int k = 0; k < 64; k++) touch = max(touch, 1.0 - smoothstep(0.06, 0.24, length(p - contact_points[k]) + wobble));
        c *= 1.0 - contact * touch;
    }
    // the terraces' tops and their sides (steep: warm rock)
    float up = smoothstep(0.25, 0.45, world.y);
    c = mix(c, mix(plateau, c * (plateau / max(grass, vec3(0.01))), seam_fix), up);   // v6: the top keeps its shading
    float steep = 1.0 - smoothstep(0.80, 0.86, world_normal.y);
    c = mix(c, rock, steep);
    // path and the spawn's patch: one rounded shape
    float d_path = 1e3;
    for (int k = 0; k < path_count - 1; k++) {
        vec2 a = path_points[k], b = path_points[k + 1];
        vec2 pa = p - a, ba = b - a;
        float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float s_along = (float(k) + t) / max(float(path_count - 1), 1.0);   // 0 at the spawn, 1 at the path's end
        float half_w = 0.48 * mix(1.0, 0.18, path_taper * smoothstep(0.45, 1.0, s_along));
        d_path = min(d_path, length(pa - ba * t) - half_w);
    }
    d_path += (noise(p * 1.3) - 0.5) * 0.18 + (noise(rot(p, 0.8) * 4.7) - 0.5) * edge_break * 0.8;
    d_path += ((noise(rot(p, 2.6) * 7.3) - 0.5) * 0.10 + (noise(rot(p, 0.3) * 15.0) - 0.5) * 0.05) * fine_edge;   // the path frays less than the sand
    float d_spawn = length(p - SPAWN) - 0.85;
    if (fine_edge > 0.0) {   // the spawn's sand: lopsided, bitten, run into the path (the user: no deliberate circle)
        vec2 ds = (p - SPAWN) * vec2(0.85, 1.25);
        float ang = atan(ds.y, ds.x);
        d_spawn = length(ds) - (0.72 + 0.28 * sin(ang * 2.0 + 1.3) + 0.16 * sin(ang * 5.0 + 0.4) + (noise(p * 2.3) - 0.5) * 0.45);
    }
    float d_road = smin(d_path, d_spawn, 0.6);
    float trail_out = 0.0;
    if (trail_w > 0.0) {   // v7: narrowing from the path's end into the woods, frayed like the path
        float d_trail = min(seg(p, trail_points[0], trail_points[1]), seg(p, trail_points[1], trail_points[2]));
        float t_along = clamp(length(p - trail_points[0]) / max(length(trail_points[2] - trail_points[0]), 0.01), 0.0, 1.0);
        d_trail -= trail_w * mix(1.0, 0.45, t_along);
        d_trail += (noise(rot(p, 0.8) * 4.7) - 0.5) * 0.14 + (noise(rot(p, 2.6) * 7.3) - 0.5) * 0.08;
        d_road = smin(d_road, d_trail, 0.35);
        trail_out = fill(d_trail) * smoothstep(walk.w - 0.1, walk.w + 1.2, p.y);   // past the walk's edge
    }
    d_road += ((noise(rot(p, 1.4) * 6.1) - 0.5) * 0.08) * fine_edge;
    // v6: the soft band — distances to the sand band and to the path known first, the meadow eased toward pale green by them
    float band = water - (sand_m + (noise(p * 0.55) - 0.5) * 0.5);
    band += ((noise(rot(p, 1.1) * 0.95) - 0.5) * 0.75 + (noise(rot(p, 2.3) * 1.9) - 0.5) * 0.25) * edge_break * 3.2;
    float teeth = (noise(rot(p, 0.5) * 3.9) - 0.5) * 0.30 + (noise(rot(p, 1.9) * 8.7) - 0.5) * 0.14 + (noise(rot(p, 3.3) * 17.0) - 0.5) * 0.06;
    band += teeth * fine_edge;
    if (seam_fix > 0.0) {
        float wob = (noise(rot(p, 0.8) * 0.6 + 5.0) - 0.5) * 0.9;   // the band's width wanders, ~±0.45 m
        float near_sand = 1.0 - smoothstep(0.0, soft_m + wob, max(band, 0.0));
        float near_road = 1.0 - smoothstep(0.0, soft_m * 0.7 + wob * 0.6, max(d_road, 0.0));
        float soft = max(near_sand * near_sand * (3.0 - 2.0 * near_sand), near_road * near_road) * (1.0 - steep) * (1.0 - up);
        c = mix(c, soft_grass * (c / max(grass, vec3(0.01))) * 0.55 + soft_grass * 0.45, soft * 0.8 * seam_fix);
    }
    vec3 meadow = c;   // the ground as it is just outside the sand: the islets take it (v6)
    // v6: a softer edge (the user: the join softer) — still clean, ~0.15 m wide instead of a pixel
    float road_fill = seam_fix > 0.0 ? 1.0 - smoothstep(-0.07, 0.07, d_road) : fill(d_road);
    c = mix(c, path_colour, road_fill * (1.0 - steep));
    c *= 1.0 - 0.14 * trail_out;   // v7.1 (上官婉儿): the trail past the walk a little darker — a path far off, not "walk here"
    // the sand band round the water (band, above: its outline wandering slowly, broken in low chunky steps — bays and
    // tongues 0.3–0.8 m — and v5's 0.1–0.3 m bites and teeth); a pale wet line at the water
    float sand_fill = seam_fix > 0.0 ? 1.0 - smoothstep(-0.08, 0.08, band) : fill(band);
    c = mix(c, sand, sand_fill);
    // sand flecks just outside the edge and grass islets just inside it (the user: the joins too hard)
    // few, larger sand patches just outside the edge and grass islets just inside (clean edges, no speckle)
    float fleck_d = 0.86 - noise(rot(p, 0.7) * 1.55 + 3.0);
    float islet_d = 0.87 - noise(rot(p, 2.2) * 1.45 + 11.0) + (noise(rot(p, 0.9) * 6.7) - 0.5) * 0.22 * fine_edge;
    fleck_d += (noise(rot(p, 2.9) * 7.1) - 0.5) * 0.22 * fine_edge;
    float near_edge = 1.0 - smoothstep(0.2, 0.9, abs(band));
    if (seam_fix > 0.0) {   // v6: whole shapes that shrink away from the edge, not a mask fading out across them (the cut)
        fleck_d += smoothstep(0.2, 0.9, abs(band)) * 0.6;
        islet_d += smoothstep(0.2, 0.9, abs(band)) * 0.6;
        near_edge = 1.0;
    }
    float fleck = fill(fleck_d) * step(0.0, band) * near_edge;
    float islet = fill(islet_d) * step(band, 0.0) * near_edge;
    c = mix(c, sand, fleck * step(0.01, edge_break));
    c = mix(c, mix(grass * 0.95, meadow, seam_fix), islet * step(0.01, edge_break));   // v6: the meadow's own colour, not a flat green
    sandy = clamp(sand_fill - islet + fleck + fill(d_road), 0.0, 1.0);
    c = mix(c, wet, fill(water - 0.10));
    ALBEDO = c;
    ROUGHNESS = 1.0;
    SPECULAR = 0.08;
}

void light() {
    float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI * sun_k;
    // the shadow side coloured by what it falls on (上官婉儿 on v3): grass deeper and blue-green, sand a cool violet beige
    float shadowed = ndl * (1.0 - ATTENUATION);
    DIFFUSE_LIGHT += shadowed * mix(shadow_tint, shadow_tint_sand, sandy) * LIGHT_COLOR / PI * sun_k;   // how dark
    // the cool cast itself goes in un-multiplied by the ground's colour (grass and sand have almost no blue to tint)
    SPECULAR_LIGHT += shadowed * mix(shadow_cool, shadow_cool_sand, sandy);
}

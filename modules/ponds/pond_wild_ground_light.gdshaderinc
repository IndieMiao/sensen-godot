// SGODOT-422 wild ground (盘古): the large smooth light — brighter round the pond's middle, deeper toward the walk's rim,
// a vignette, darker toward the camera's side — as a per-channel factor on the grass. Shared by the full painted ground
// (pond_wild_ground.gdshader) and the baked one (pond_wild_ground_baked.gdshader), which keeps it live: a gradient this
// wide would band in an 8-bit texture.
// WILD_COLOR: the colour hint (spatial shaders: source_color; the bake's canvas shader takes them linear, no hint).
#ifndef WILD_COLOR
#define WILD_COLOR : source_color
#endif
uniform vec4 walk = vec4(-2.5, -16.0, 14.5, 1.5);   // x0, z0, x1, z1
uniform vec3 grass WILD_COLOR = vec3(0.56, 0.69, 0.30);
uniform vec3 grass_far WILD_COLOR = vec3(0.47, 0.60, 0.26);
uniform vec3 plateau WILD_COLOR = vec3(0.49, 0.62, 0.27);
uniform vec3 rock WILD_COLOR = vec3(0.71, 0.62, 0.52);
uniform float gradient = 0.10;   // how much the meadow lightens toward the water and darkens toward its rim
uniform vec2 centre = vec2(6.0, -8.0);   // the pond's middle
uniform float south_dark = 0.0;
uniform float vignette = 0.0;
uniform vec2 seed_off = vec2(0.0);      // each pond its own noise
uniform float detail = 0.0;             // faint small-scale grain, three unrelated scales

// sin-free hash (Hoskins' hash12): a sin() hash goes flat on fp32 GPUs once p reaches the thousands (the detail's scales)
float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec2 rot(vec2 p, float a) { return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a)); }

// out of the walk, metres
float wild_outside(vec2 p) { return length(max(max(walk.xy - p, p - walk.zw), vec2(0.0))); }

// the meadow's light: one large radial pool round the pond's middle (falling off over ~16 m), deeper toward the rim, a
// vignette, pressed darker toward the camera's side (the screen's bottom); the grass's colour times this
vec3 wild_light(vec2 p) {
    float lit = 1.0 - smoothstep(2.0, 13.0, length(p - centre));
    float rim = smoothstep(0.0, 6.0, wild_outside(p));
    vec3 l = vec3(mix(1.0 - gradient * 0.5, 1.0 + gradient * 0.6, lit));   // the dark end light (上官婉儿: not a cloud's shadow)
    l = mix(l, grass_far / max(grass, vec3(0.01)) * (1.0 - gradient * 0.6), rim * 0.7);
    l *= 1.0 - vignette * smoothstep(7.0, 20.0, length(p - centre));
    l *= 1.0 - south_dark * smoothstep(-9.0, 6.0, p.y);
    return l;
}

// the terraces' tops: the meadow's shading in the plateau's colour
vec3 wild_plateau(float up) { return mix(vec3(1.0), plateau / max(grass, vec3(0.01)), up); }

// sparse little grass strokes: in 0.37 m cells (rotated, so no grid shows) one in five holds a short dark dash, ~0.09 ×
// 0.02 m — the grass's factor (a crisp dash at any zoom: done live, not baked)
float wild_stroke(vec2 p) {
    vec2 q = p + seed_off;
    vec2 cq = rot(q, 0.9) / 0.37;
    vec2 cell = floor(cq);
    float pick = hash(cell + 17.0);
    vec2 at = fract(cq) - (0.25 + 0.5 * vec2(hash(cell + 3.0), hash(cell + 9.0)));
    vec2 dash = rot(at, hash(cell + 5.0) * 6.283) * vec2(1.0, 4.0) * 0.37;   // ~0.09 m long, ~0.02 m wide
    float stroke = step(0.80, pick) * (1.0 - smoothstep(0.03, 0.045, length(dash)));
    return 1.0 - stroke * detail * 2.2 * (1.0 - smoothstep(0.0, 6.0, wild_outside(p)));
}

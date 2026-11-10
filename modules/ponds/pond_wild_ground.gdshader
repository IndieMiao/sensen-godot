shader_type spatial;
// SGODOT-422 wild ground (盘古, the user's v7 11-09; pond_wild_ground.gd sets it): flat painted ground — the colour in
// pond_wild_ground_paint.gdshaderinc, its large soft light in pond_wild_ground_light.gdshaderinc. This full shader draws
// the ground until its bake is done (pond_wild_ground_bake.gd: a frame or two on entering, and always headless); then
// the baked one (pond_wild_ground_baked.gdshader) takes over.
#include "res://modules/ponds/pond_wild_ground_paint.gdshaderinc"
uniform vec3 shadow_tint = vec3(0.0);        // the sunlight a shadow on the grass keeps, per channel: deeper, toward blue-green
uniform vec3 shadow_tint_sand = vec3(0.0);
uniform vec3 shadow_cool = vec3(0.0);        // added straight into the shadow on the grass: blue-green
uniform float sun_k = 1.0;   // the sun's share of this ground's light (gl_compatibility: < 1, PondWildGround.look_for)
uniform vec3 shadow_cool_sand = vec3(0.0);   // ... on the sand: a cool, slightly violet beige
varying vec3 world;
varying vec3 world_normal;
varying float sandy;   // 1 on sand / path, 0 on grass: the shadows take their colour by it

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    float up = smoothstep(0.25, 0.45, world.y);
    float steep = 1.0 - smoothstep(0.80, 0.86, world_normal.y);
    vec3 g, k;
    float s;
    wild_paint(world.xz, up, steep, 1.0, g, k, s);
    sandy = s;
    ALBEDO = g * wild_light(world.xz) + k;
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

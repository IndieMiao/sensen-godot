shader_type spatial;
// SGODOT-422 wild ground, baked (盘古; #917's frame rate on GLES): the painted ground read from its bake
// (pond_wild_ground_bake.gd) — a near image over the walk and the farthest view, a coarse one over the rest — with the
// large smooth light (8-bit would band it), the terraces' tops and their rock sides done live, and the same shadows.
#include "res://modules/ponds/pond_wild_ground_light.gdshaderinc"
// sRGB-encoded, decoded here (from_srgb), not by a source_color hint: the bake holds the colour in whatever space this
// renderer's full shader worked in (linear on Mobile / Forward+, as given on Compatibility, which converts neither its
// colour uniforms nor its source_color textures), so it must come back exactly as encoded
uniform sampler2D baked_near : filter_linear_mipmap, repeat_disable;
uniform sampler2D baked_far : filter_linear_mipmap, repeat_disable;
uniform vec4 near_rect = vec4(-6.0, -24.0, 26.0, 37.0);   // x0, z0, width, depth (metres)
uniform vec4 far_rect = vec4(-26.0, -46.0, 66.0, 64.0);
uniform float w_soft = 0.62;   // the meadow's share at the pale band's strongest: below it, the sand's (for the shadows)
uniform vec3 shadow_tint = vec3(0.0);        // the sunlight a shadow on the grass keeps, per channel: deeper, toward blue-green
uniform vec3 shadow_tint_sand = vec3(0.0);
uniform vec3 shadow_cool = vec3(0.0);        // added straight into the shadow on the grass: blue-green
uniform vec3 shadow_cool_sand = vec3(0.0);   // ... on the sand: a cool, slightly violet beige
varying vec3 world;
varying vec3 world_normal;
#include "res://modules/render/ground_shade.gdshaderinc"
varying float shade;   // the trees' shade under Compatibility (ground_shade.gdshaderinc)
varying float sandy;   // 1 on sand / path, 0 on grass: the shadows take their colour by it

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 from_srgb(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }

void fragment() {
    vec2 p = world.xz;
    vec2 un = (p - near_rect.xy) / near_rect.zw;
    vec4 b = texture(baked_far, (p - far_rect.xy) / far_rect.zw);
    vec4 bn = texture(baked_near, un);
    vec2 edge = min(un, 1.0 - un) * near_rect.zw;   // metres in from the near image's edge: eased into the far one over 0.5 m
    b = mix(b, bn, smoothstep(0.0, 0.5, min(edge.x, edge.y)));
    float up = smoothstep(0.25, 0.45, world.y);
    float steep = 1.0 - smoothstep(0.80, 0.86, world_normal.y);
    vec3 c = from_srgb(b.rgb) * mix(vec3(1.0), wild_light(p) * wild_plateau(up) * wild_stroke(p), b.a);
    ALBEDO = mix(c, rock, steep);
    sandy = clamp(1.0 - b.a / w_soft, 0.0, 1.0);
    shade = ground_shade(p);
    ROUGHNESS = 1.0;
    SPECULAR = 0.08;
}

void light() {
    float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    float att = shade_att(ATTENUATION, shade);
    DIFFUSE_LIGHT += ndl * att * LIGHT_COLOR / PI;
    // the shadow side coloured by what it falls on (上官婉儿 on v3): grass deeper and blue-green, sand a cool violet beige
    float shadowed = ndl * (1.0 - att);
    DIFFUSE_LIGHT += shadowed * mix(shadow_tint, shadow_tint_sand, sandy) * LIGHT_COLOR / PI;   // how dark
    // the cool cast itself goes in un-multiplied by the ground's colour (grass and sand have almost no blue to tint)
    SPECULAR_LIGHT += shadowed * mix(shadow_cool, shadow_cool_sand, sandy);
}

// SGODOT-457 (盘古): the trees' shade on the ground under the Compatibility renderer, where no sun casts a shadow
// (SGODOT-456): GroundShade (ground_shade.gd) draws it into shade_mask once; light() takes it as its shadow there, so it
// is coloured as a Metal shadow is. Other renderers: shade_att is the shadow map's own attenuation, untouched.
uniform sampler2D shade_mask : filter_linear, repeat_disable, hint_default_black;
uniform vec4 shade_rect = vec4(0.0, 0.0, 1.0, 1.0);   // x0, z0, width, depth (metres)
uniform float shade_opacity = 1.0;   // the sun's shadow_opacity: a Metal shadow is that deep (the farm's 0.58, the wild's 1)

float ground_shade(vec2 p) {
    vec2 u = (p - shade_rect.xy) / shade_rect.zw;
    if (u.x < 0.0 || u.y < 0.0 || u.x > 1.0 || u.y > 1.0) return 0.0;
    return texture(shade_mask, u).r;
}

float shade_att(float att, float shade) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    return min(att, 1.0 - shade * shade_opacity);
#else
    return att;
#endif
}

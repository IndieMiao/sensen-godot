shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// The accepted meshes and one original RGBA texture are unchanged.
// The texture shapes the outside edge; it never cuts holes in the shore contact.
uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.7;
uniform float cycle_speed_hz : hint_range(0.0, 0.5) = 0.18181818;
uniform float push_distance_m : hint_range(0.0, 0.15) = 0.10;
uniform float edge_noise_m : hint_range(0.0, 0.08) = 0.055;
uniform float edge_softness_m : hint_range(0.02, 0.3) = 0.14;
uniform float edge_margin_m : hint_range(0.0, 0.05) = 0.005;
uniform vec2 end_fade_uv = vec2(0.0);
varying vec2 local_xz;
varying float retreat_m;
void vertex() {
    local_xz = VERTEX.xz;
    // Out -> in -> out, 0.10 m peak-to-peak; no whole-strip alpha pulsing.
    retreat_m = push_distance_m * 0.5 * (1.0 - cos(TIME * 6.28318530718 * cycle_speed_hz));
}
void fragment() {
    // Recover metres per V from the unmodified ribbon, also for the small pile ring.
    vec2 duv_x = dFdx(UV);
    vec2 duv_y = dFdy(UV);
    float determinant = duv_x.x * duv_y.y - duv_x.y * duv_y.x;
    vec2 across = (dFdy(local_xz) * duv_x.x - dFdx(local_xz) * duv_y.x) / determinant;
    float ribbon_m = max(length(across), 0.001);
    float outward_m = (1.0 - UV.y) * ribbon_m;
    // One centre-line sample provides seamless, irregular scallops along U.
    vec4 foam = texture(foam_texture, vec2(UV.x, 0.5));
    float noise = clamp((foam.a - 0.10) * 4.0, 0.0, 1.0);
    float outer_m = ribbon_m - edge_margin_m - edge_noise_m * noise - retreat_m;
    // Keep the narrow pile contact solid even at the most retracted phase.
    float softness_m = min(edge_softness_m, outer_m * 0.65);
    float coverage = 1.0 - smoothstep(outer_m - softness_m, outer_m, outward_m);
    // This 1 cm fade remains buried under the shore or pile contact.
    coverage *= smoothstep(0.0, 0.01, outward_m);
    float cap_a = end_fade_uv.x > 0.0 ? smoothstep(0.0, end_fade_uv.x, UV.x) : 1.0;
    float cap_b = end_fade_uv.y > 0.0 ? smoothstep(0.0, end_fade_uv.y, 1.0 - UV.x) : 1.0;
    ALBEDO = foam.rgb * foam_color.rgb;
    ALPHA = coverage * foam_color.a * intensity * cap_a * cap_b;
}

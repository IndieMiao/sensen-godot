shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;
uniform vec4 sky_top : source_color = vec4(0.61,0.77,0.84,1.0);
uniform vec4 sky_horizon : source_color = vec4(0.85,0.91,0.90,1.0);
void vertex() {
    vec4 far_point=INV_PROJECTION_MATRIX*vec4(0.0,0.0,CLIP_SPACE_FAR,1.0);
    vec4 projected=PROJECTION_MATRIX*vec4(0.0,0.0,far_point.z/far_point.w*0.97,1.0);
    POSITION=vec4(VERTEX.xy,projected.z/projected.w,1.0);
}
void fragment() {
    ALBEDO=mix(sky_top.rgb,sky_horizon.rgb,smoothstep(0.0,0.75,UV.y));
    ALPHA=1.0;
}

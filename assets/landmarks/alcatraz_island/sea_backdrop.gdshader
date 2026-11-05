shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;
uniform vec4 water : source_color = vec4(0.62745,0.72549,0.74118,1.0);
uniform bool false_horizon = true;
// Deliberate false perspective: reveal the separate distant bay through the top water band.
// Foreground opaque geometry keeps normal depth/occlusion; this is never a gameplay plane.
void fragment() {
    ALBEDO = water.rgb;
    ALPHA = false_horizon ? smoothstep(0.12,0.24,SCREEN_UV.y) : 1.0;
}

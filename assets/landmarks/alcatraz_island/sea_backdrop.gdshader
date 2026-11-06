shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;
uniform vec4 water : source_color = vec4(0.26275,0.60784,0.69020,1.0);
uniform vec4 deep_water : source_color = vec4(0.19216,0.51765,0.62353,1.0);
uniform bool false_horizon = true;
varying vec2 sea_world;
void vertex() {
    sea_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
}
// Deliberate false perspective: reveal the separate distant bay through the top water band.
// Foreground opaque geometry keeps normal depth/occlusion; this is never a gameplay plane.
void fragment() {
    float broad = 0.5 + 0.25*sin(sea_world.x*.27+sea_world.y*.19) + 0.25*sin(sea_world.y*.41-sea_world.x*.13);
    float ripple = sin(sea_world.y*1.7 + sea_world.x*.30 + .65*sin(sea_world.x*.24+TIME*.09) + TIME*.15);
    float breakup = smoothstep(-.15,.55,sin(sea_world.x*.73-sea_world.y*.16+TIME*.06));
    float light_ridge = smoothstep(.96,1.0,ripple)*breakup*.018;
    ALBEDO = mix(deep_water.rgb,water.rgb,.35+.40*broad) + vec3(light_ridge);
    ALPHA = false_horizon ? smoothstep(0.12,0.24,SCREEN_UV.y) : 1.0;
}

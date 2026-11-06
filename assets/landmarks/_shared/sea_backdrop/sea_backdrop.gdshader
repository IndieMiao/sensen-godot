shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// Generalized from the accepted Alcatraz background: 0 samples, 1 pass, 5 sines.
uniform vec4 shallow_color : source_color = vec4(0.2627451,0.6078431,0.6901961,1.0);
uniform vec4 deep_color : source_color = vec4(0.1921569,0.5176471,0.6235294,1.0);
uniform vec4 far_color : source_color = vec4(0.4039216,0.6862745,0.7607843,1.0);
uniform float ripple_wavelength_m : hint_range(0.5,20.0) = 3.64;
uniform float color_patch_scale : hint_range(0.1,10.0) = 1.0;
uniform vec2 color_mix_range = vec2(0.35,0.75);
uniform vec2 pattern_origin = vec2(0.0);
uniform float motion_speed : hint_range(0.0,3.0) = 1.0;
uniform float ripple_strength : hint_range(0.0,0.06) = 0.018;
uniform vec2 ripple_threshold = vec2(0.96,1.0);
uniform vec2 far_fade_screen_y = vec2(0.12,0.24);
uniform float far_color_amount : hint_range(0.0,1.0) = 1.0;
// Optional authored shoreline: three world-XZ segments, no scene-depth reads.
// Uniform branch is off for the accepted bay. Coordinates are world metres,
// independent of pattern_origin; repeat a segment for simpler shores.
uniform float shore_shallows_strength : hint_range(0.0,1.0) = 0.0;
uniform vec2 shore_depth_range_m = vec2(0.25,4.0);
uniform vec4 shore_segment_a = vec4(-4.0,0.0,0.0,0.0);
uniform vec4 shore_segment_b = vec4(0.0,0.0,4.0,0.0);
uniform vec4 shore_segment_c = vec4(4.0,0.0,8.0,0.0);
// Optional Alcatraz-style reveal of a separately authored far background.
// The bay/lake presets are self-contained and keep alpha=1 everywhere.
uniform bool reveal_far_background = false;
varying vec2 sea_world;
void vertex() {
    sea_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz - pattern_origin;
}
float shore_distance_squared(vec2 p, vec4 segment) {
    vec2 along = segment.zw - segment.xy;
    vec2 offset = p - segment.xy;
    float t = clamp(dot(offset,along) / max(dot(along,along),0.0001),0.0,1.0);
    vec2 delta = offset - along*t;
    return dot(delta,delta);
}
void fragment() {
    vec2 broad_p = sea_world / max(color_patch_scale,0.001);
    vec2 wave_p = sea_world * (3.64 / max(ripple_wavelength_m,0.001));
    float time = TIME * motion_speed;
    float broad = 0.5 + 0.25*sin(broad_p.x*.27+broad_p.y*.19) + 0.25*sin(broad_p.y*.41-broad_p.x*.13);
    float ripple = sin(wave_p.y*1.7 + wave_p.x*.30 + .65*sin(wave_p.x*.24+time*.09) + time*.15);
    float breakup = smoothstep(-.15,.55,sin(wave_p.x*.73-wave_p.y*.16+time*.06));
    float light_ridge = smoothstep(ripple_threshold.x,max(ripple_threshold.y,ripple_threshold.x+0.001),ripple)*breakup*ripple_strength;
    float shallow_mix = mix(color_mix_range.x,color_mix_range.y,broad);
    if (shore_shallows_strength > 0.0) {
        vec2 shore_world = sea_world + pattern_origin;
        float distance_squared = min(shore_distance_squared(shore_world,shore_segment_a),
            min(shore_distance_squared(shore_world,shore_segment_b),shore_distance_squared(shore_world,shore_segment_c)));
        vec2 depth_range = max(shore_depth_range_m,vec2(0.0));
        float near_shore = 1.0 - smoothstep(depth_range.x*depth_range.x,
            max(depth_range.y*depth_range.y,depth_range.x*depth_range.x+0.0001),distance_squared);
        shallow_mix = mix(shallow_mix,1.0,near_shore*shore_shallows_strength);
    }
    vec3 water = mix(deep_color.rgb,shallow_color.rgb,shallow_mix) + vec3(light_ridge);
    float near_amount = smoothstep(far_fade_screen_y.x,max(far_fade_screen_y.y,far_fade_screen_y.x+0.001),SCREEN_UV.y);
    ALBEDO = mix(water,far_color.rgb,(1.0-near_amount)*far_color_amount);
    ALPHA = reveal_far_background ? near_amount : 1.0;
}

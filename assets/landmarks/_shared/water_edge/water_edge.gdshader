shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// One RGBA read, as in #824. No screen/depth texture or second foam layer.
uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.8;
uniform float cycle_speed_hz : hint_range(0.0, 0.5) = 0.25;
uniform float drift_uv : hint_range(0.0, 0.05) = 0.018;
uniform float breath_amount : hint_range(0.0, 0.10) = 0.06;
// Zero at modular joins; optional terminal materials fade free ends.
uniform vec2 end_fade_uv = vec2(0.0);
varying float along_shift;
varying float breath;
void vertex() {
    float wave = sin(TIME * 6.28318530718 * cycle_speed_hz);
    along_shift = drift_uv * wave;
    breath = 1.0 - breath_amount * 0.5 * (1.0 - cos(TIME * 6.28318530718 * cycle_speed_hz));
}
void fragment() {
    vec4 foam = texture(foam_texture, vec2(UV.x + along_shift, UV.y));
    float cap_a = end_fade_uv.x > 0.0 ? smoothstep(0.0, end_fade_uv.x, UV.x) : 1.0;
    float cap_b = end_fade_uv.y > 0.0 ? smoothstep(0.0, end_fade_uv.y, 1.0 - UV.x) : 1.0;
    ALBEDO = foam.rgb * foam_color.rgb;
    ALPHA = foam.a * foam_color.a * intensity * breath * cap_a * cap_b;
}

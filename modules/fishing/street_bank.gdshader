shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D grass_detail : source_color, repeat_enable, filter_linear_mipmap;
uniform vec3 grass_color : source_color = vec3(0.722, 0.847, 0.627);
varying vec2 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
    vec3 grass = texture(grass_detail, world * 1.1).rgb;
    float soil = 1.0 - smoothstep(0.03, 0.30, UV.y);
    vec3 bank = mix(grass * 1.25, vec3(0.22, 0.25, 0.12), soil * 0.70);
    ALBEDO = mix(bank, grass_color, smoothstep(0.18, 1.0, UV.y));
    ROUGHNESS = 1.0;
}

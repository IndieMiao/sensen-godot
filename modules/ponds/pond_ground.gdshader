shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
uniform sampler2D grass_detail : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D surface_flow : repeat_enable, filter_linear_mipmap;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world.xz;
    float variation = sin(p.x * 0.9 + sin(p.y * 0.7)) * sin(p.y * 0.65) * 0.5 + 0.5;
    vec3 grass = mix(vec3(0.33, 0.46, 0.105), vec3(0.53, 0.63, 0.21), variation);
    vec3 detail = texture(grass_detail, p * 0.34).rgb;
    float grain = texture(surface_flow, p * 3.0).b;
    grass *= 0.78 + dot(detail, vec3(0.333)) * 1.2 + grain * 0.20;
    float path = (1.0 - smoothstep(0.65, 1.35, abs(p.x - 6.05))) * smoothstep(-3.1, -2.2, p.y);
    vec3 soil = vec3(0.69, 0.63, 0.45);
    float edge = smoothstep(0.0, 4.0, max(abs(p.x - 6.0) - 6.0, abs(p.y + 8.0) - 8.0));
    ALBEDO = mix(mix(grass, soil, path * 0.35), grass * 1.025, edge);
    ROUGHNESS = 0.94;
}

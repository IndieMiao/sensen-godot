shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
float grain(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world.xz;
    float variation = sin(p.x * 0.9 + sin(p.y * 0.7)) * sin(p.y * 0.65) * 0.5 + 0.5;
    vec3 grass = mix(vec3(0.38, 0.49, 0.25), vec3(0.60, 0.67, 0.39), variation);
    float path = (1.0 - smoothstep(0.65, 1.35, abs(p.x - 6.05))) * smoothstep(-3.1, -2.2, p.y);
    vec3 soil = vec3(0.69, 0.63, 0.45);
    float edge = smoothstep(0.0, 4.0, max(abs(p.x - 6.0) - 6.0, abs(p.y + 8.0) - 8.0));
    ALBEDO = mix(mix(grass, soil, path * 0.78), vec3(0.61, 0.67, 0.48), edge) + (grain(floor(p * 105.0)) - 0.5) * 0.025;
    ROUGHNESS = 0.94;
}

shader_type spatial;
render_mode cull_disabled;
uniform sampler2D stone_detail : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D surface_flow : repeat_enable, filter_linear_mipmap;
varying vec3 world;
varying vec3 world_normal;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 weights = pow(abs(world_normal), vec3(4.0));
    weights /= max(weights.x + weights.y + weights.z, 0.001);
    vec3 mineral = texture(stone_detail, world.yz * 1.7).rgb * weights.x
                 + texture(stone_detail, world.xz * 1.7).rgb * weights.y
                 + texture(stone_detail, world.xy * 1.7).rgb * weights.z;
    float grain = texture(surface_flow, world.xz * 1.7 + world.y * vec2(0.7, 0.3)).b;
    float wet = 1.0 - smoothstep(0.07, 0.19, world.y);
    float moss = smoothstep(0.49, 0.64, grain) * smoothstep(0.02, 0.60, world_normal.y) * 0.23;
    vec3 stone = mineral * mix(vec3(0.80), COLOR.rgb, 0.35) * (OUTPUT_IS_SRGB ? 1.10 : 2.8);
    stone = mix(stone, vec3(0.14, 0.20, 0.055) * (0.75 + grain * 0.3), moss);
    ALBEDO = stone * mix(1.0, 0.49, wet);
    ROUGHNESS = mix(0.9, 0.26, wet);
    SPECULAR = mix(0.18, 0.38, wet);
}

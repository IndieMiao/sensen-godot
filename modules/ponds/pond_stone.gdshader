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
    weights /= max(dot(weights, vec3(1.0)), 0.001);
    vec3 mineral = texture(stone_detail, world.yz * 1.6).rgb * weights.x
                 + texture(stone_detail, world.xz * 1.6).rgb * weights.y
                 + texture(stone_detail, world.xy * 1.6).rgb * weights.z;
    float detail = dot(mineral, vec3(0.3333));
    float wet = 1.0 - smoothstep(0.055, 0.15, world.y);
    // Vertex paint is linear on both backends. No renderer-specific exposure gain.
    ALBEDO = COLOR.rgb * (0.72 + detail * 1.18) * mix(1.0, 0.74, wet);
    ROUGHNESS = mix(0.88, 0.43, wet);
    SPECULAR = 0.22;
}

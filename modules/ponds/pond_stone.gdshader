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
    // Fine mineral relief follows the real curved/cut surface in world space.
    vec3 n = normalize(world_normal);
    vec3 dx = dFdx(world);
    vec3 dy = dFdy(world);
    vec3 rx = cross(dy, n);
    vec3 ry = cross(n, dx);
    float determinant = dot(dx, rx);
    vec3 gradient = (rx * dFdx(detail) + ry * dFdy(detail)) / max(abs(determinant), 0.000001) * sign(determinant);
    NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(n - gradient * 0.055));
    float wet = 1.0 - smoothstep(0.055, 0.15, world.y);
    // Vertex paint is linear on both backends. No renderer-specific exposure gain.
    float mottling = texture(surface_flow, world.xz * 1.9 + world.yy * 0.7).b;
    ALBEDO = COLOR.rgb * (0.85 + detail * 0.40 + (mottling - 0.5) * 0.10) * mix(1.0, 0.76, wet);
    ROUGHNESS = mix(0.94, 0.67, wet);
    SPECULAR = 0.15;
}

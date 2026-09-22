shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    VERTEX.y += sin(TIME * 1.1 + world.x * 1.8 + world.z * 2.2) * 0.003;
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float radius = length(p);
    float angle = atan(p.y, p.x);
    float veins = pow(max(0.0, cos(angle * 12.0 + sin(radius * 6.0) * 0.5)), 22.0);
    float edge = smoothstep(0.87, 1.0, radius);
    vec3 color = COLOR.rgb * (0.74 + radius * 0.26 + veins * 0.09);
    ALBEDO = mix(color, color * vec3(1.14, 1.05, 0.65), edge * 0.6);
    ROUGHNESS = 0.38;
    SPECULAR = 0.3;
}

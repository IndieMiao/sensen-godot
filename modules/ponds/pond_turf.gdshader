shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    VERTEX.x += sin(TIME * 1.2 + world.x * 2.0 + world.z) * max(VERTEX.y,0.0) * 0.03;
}
void fragment() {
    ALBEDO = mix(COLOR.rgb, vec3(0.36,0.49,0.11), 0.55);
    BACKLIGHT = vec3(0.17,0.23,0.045);
    ROUGHNESS = 0.94;
    SPECULAR = 0.12;
}

shader_type spatial;
render_mode cull_disabled;
// GLES (SGODOT-458): the linear vertex colour and its grain worked out in linear, handed over as GLES wants it.
#include "res://modules/render/gles_colour.gdshaderinc"
varying vec3 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    VERTEX.y += sin(TIME * 0.9 + world.x * 1.8 + world.z * 2.2) * 0.003;
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    float angle = atan(p.y, p.x);
    float vein = pow(max(cos(angle * 9.0 + sin(r * 4.0) * 0.24), 0.0), 32.0);
    float central_dimple = 1.0 - smoothstep(0.025, 0.10, r);
    float grain = sin(world.x * 171.0) * sin(world.z * 139.0) * 0.009;
    ALBEDO = albedo_out(COLOR.rgb * (0.98 + vein * 0.035 - central_dimple * 0.10 + grain));
    ROUGHNESS = 0.74;
    SPECULAR = 0.14;
}

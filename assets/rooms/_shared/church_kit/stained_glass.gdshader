shader_type spatial;
render_mode cull_disabled;
// One palette texture per church; UV.x indexes a named 8-cell colour group.
uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform float glow_strength : hint_range(0.0,0.3) = 0.12;
void fragment() {
    vec3 paint = texture(palette_texture, vec2(UV.x,0.5)).rgb;
    ALBEDO = paint;
    EMISSION = paint * glow_strength;
    ROUGHNESS = 0.88;
    METALLIC = 0.0;
    SPECULAR = 0.16;
}

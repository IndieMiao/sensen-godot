shader_type spatial;
render_mode cull_disabled;
// SGODOT-422 parameter study. Copied into the isolated project only.
// Palette values are LINEAR RGB. Layout is data, so it has NO source_color hint.
uniform sampler2D meadow_color : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D ground_layout : repeat_disable, filter_linear_mipmap;
uniform vec2 layout_origin = vec2(-4.0, -20.0);
uniform vec2 layout_extent = vec2(20.0, 24.0);
uniform float detail_metres = 4.8;
uniform float detail_strength = 0.55;
uniform vec3 ordinary_grass = vec3(0.35, 0.455, 0.15);
uniform vec3 deep_grass = vec3(0.235, 0.35, 0.105);
uniform vec3 sunlit_grass = vec3(0.49, 0.555, 0.235);
uniform vec3 sand_soil = vec3(0.65, 0.54, 0.355);
uniform vec3 pebble_colour = vec3(0.72, 0.67, 0.53);
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 uv = (world.xz - layout_origin) / layout_extent;
    vec4 m = texture(ground_layout, uv);
    float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
    m *= inside;
    vec3 fine = texture(meadow_color, world.xz / detail_metres).rgb;
    float grain = dot(fine, vec3(0.333333)) / 0.356 - 1.0;
    float ordinary = max(0.0, 1.0 - m.r - m.g);
    vec3 grass = ordinary_grass * ordinary + deep_grass * m.r + sunlit_grass * m.g;
    grass *= 1.0 + grain * detail_strength;
    vec3 soil = sand_soil * (1.0 + grain * 0.08);
    ALBEDO = mix(mix(grass, soil, m.b), pebble_colour, m.a);
    ROUGHNESS = 0.95;
    SPECULAR = 0.12;
}

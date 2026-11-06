shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
uniform sampler2D grass_detail : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D surface_flow : repeat_enable, filter_linear_mipmap;
// SGODOT-422 wild ground (刘备 #791 / #798): the original bindings and fragment are kept as they were; the meadow's
// colour is laid over them only where dry_ground_mask allows, never on the water, the bank stones or under the water.
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
uniform sampler2D dry_ground_mask : repeat_disable, filter_linear;
uniform vec3 dry_channel = vec3(0.0);   // PondScenery sets the shape's; none: the ground as it was
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

    // Ground art overlay, only where the independent dry-ground mask permits.
    vec2 uv = (world.xz - layout_origin) / layout_extent;
    vec4 m = texture(ground_layout, uv);
    float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
    m *= inside;
    vec3 fine = texture(meadow_color, world.xz / detail_metres).rgb;
    float meadow_grain = dot(fine, vec3(0.333333)) / 0.356 - 1.0;
    float ordinary = max(0.0, 1.0 - m.r - m.g);
    vec3 meadow = ordinary_grass * ordinary + deep_grass * m.r + sunlit_grass * m.g;
    meadow *= 1.0 + meadow_grain * detail_strength;
    vec3 dry_soil = sand_soil * (1.0 + meadow_grain * 0.08);
    vec3 dry_colour = mix(mix(meadow, dry_soil, m.b), pebble_colour, m.a);
    // Explicit base level: no distant mip may bleed new colour into the pond.
    float dry = dot(textureLod(dry_ground_mask, uv, 0.0).rgb, dry_channel) * inside;
    ALBEDO = mix(ALBEDO, dry_colour, dry);
    ROUGHNESS = mix(ROUGHNESS, 0.95, dry);
    SPECULAR = mix(0.5, 0.12, dry);
}

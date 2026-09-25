shader_type spatial;
render_mode cull_disabled;

uniform sampler2D pond_shore : filter_linear, repeat_disable;
uniform vec2 pond_extent = vec2(12.0, 16.0);
uniform sampler2D pebble_bed : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D surface_flow : repeat_enable, filter_linear_mipmap;
uniform sampler2D caustics : repeat_enable, filter_linear_mipmap;
uniform sampler2D bank_reflection : filter_linear, repeat_disable;
uniform bool has_bank_reflection = false;
uniform bool polygon_water = true;
uniform vec4 interaction = vec4(0.0);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.80, 0.86);
uniform vec3 deep_color : source_color = vec3(0.015, 0.46, 0.70);
uniform vec3 sun_direction = vec3(-0.391, 0.819, -0.419);
uniform float flow_speed = 1.45;
uniform float depth_absorption = 1.0;
uniform float sparkle_strength = 1.0;
varying vec3 world;

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
    vec2 p = world.xz;
    float shore = texture(pond_shore, vec2(p.x, -p.y) / pond_extent).r * 2.0;
    float broad = texture(surface_flow, p * 0.11).b;
    // Authored bathymetry from the actual shoreline. No screen-depth dependency:
    // the orthographic Mobile and desktop paths use the same optical thickness.
    float shelf = smoothstep(0.0, 1.85, shore);
    float far_bank = smoothstep(3.5, 12.0, -p.y);
    float depth = 0.045 + shelf * (1.10 + far_bank * 1.00 + (broad - 0.5) * 0.28);
    vec2 drift = TIME * flow_speed * vec2(0.018, -0.012);
    vec2 waves_a = texture(surface_flow, p * 0.46 + drift).rg * 2.0 - 1.0;
    vec2 waves_b = texture(surface_flow, p * 0.81 - drift.yx * 0.71).gr * 2.0 - 1.0;
    vec2 slope = (waves_a + waves_b * 0.54) * 0.115;
    vec2 to_float = p - interaction.xy;
    float distance_to_float = length(to_float);
    float envelope = exp(-distance_to_float * 2.4) * smoothstep(0.025, 0.12, distance_to_float) * interaction.w;
    float ring = distance_to_float * 27.0 - TIME * 5.0;
    slope += normalize(to_float + vec2(0.0001)) * cos(ring) * envelope * 0.08;
    vec3 normal_world = normalize(vec3(-slope.x, 1.0, -slope.y));
    NORMAL = normalize(mat3(VIEW_MATRIX) * normal_world);

    vec3 bed_sample = texture(pebble_bed, p * 0.15 + slope * (0.09 + shelf * 0.05)).rgb;
    float mineral = dot(bed_sample, vec3(0.2126, 0.7152, 0.0722));
    vec3 bed = vec3(0.40, 0.57, 0.45) * (0.28 + mineral * 4.2);
    // Beer-Lambert absorption: red disappears first; deeper water loses bed
    // contrast and gains blue in-scattering, as in depth fog.
    vec3 transmission = exp(-depth * depth_absorption * vec3(2.45, 0.82, 0.48));
    vec3 volume = mix(shallow_color, deep_color, smoothstep(0.12, 1.85, depth));
    vec3 color = bed * transmission + volume * (1.0 - transmission);
    color = mix(color, volume, 0.18 + shelf * 0.12);

    vec2 warp = vec2(texture(surface_flow, p * 0.09 + drift * 0.28).b,
                     texture(surface_flow, p * 0.09 - drift * 0.21 + 0.3).b);
    vec2 light_uv = p * 0.35 + warp * 0.13 + drift * 0.32;
    float web_a = texture(caustics, light_uv).r;
    float web_b = texture(caustics, light_uv * 1.17 - drift * 0.61).r;
    float web = web_a * 0.72 + web_b * 0.28;
    color += vec3(0.32, 0.64, 0.58) * web * exp(-depth * 1.3) * 0.68;

    vec3 view_world = normalize(mat3(INV_VIEW_MATRIX) * VIEW);
    float fresnel = pow(1.0 - max(dot(normal_world, view_world), 0.0), 4.0);
    color = mix(color, vec3(0.55, 0.77, 0.89), 0.025 + fresnel * 0.27);
    if (has_bank_reflection) {
        vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + slope * vec2(0.025, 0.014);
        vec4 reflection = texture(bank_reflection, clamp(uv, vec2(0.002), vec2(0.998)));
        float bank = (1.0 - smoothstep(0.4, 1.8, shore)) * 0.10 + fresnel * 0.18;
        color = mix(color, reflection.rgb, reflection.a * bank);
    }
    // Moving wave facets reflect a broad sun. Derivative filtering keeps fine
    // glints from flickering into single-pixel noise on smaller Android screens.
    vec2 fine_wave = texture(surface_flow, p * 0.18 + drift * 0.65).rg * 2.0 - 1.0;
    vec3 facet = normalize(vec3(-(slope.x + fine_wave.x * 0.23), 1.0, -(slope.y + fine_wave.y * 0.23)));
    vec3 half_sun = normalize(view_world + sun_direction);
    float alignment = dot(facet, half_sun);
    float aa = min(max(fwidth(alignment) * 0.35, 0.00012), 0.0012);
    float glint = smoothstep(0.9965 - aa, 0.9996 + aa, alignment);
    float halo = pow(max(alignment, 0.0), 160.0) * 0.10;
    float glint_patch = smoothstep(0.46, 0.68, texture(surface_flow, p * 0.12 - drift * 0.3).b);
    glint *= glint_patch * smoothstep(0.08, 0.38, shore) * sparkle_strength;
    color += max(sin(ring), 0.0) * envelope * vec3(0.16, 0.29, 0.28);
    ALBEDO = color;
    EMISSION = vec3(1.0, 0.97, 0.82) * (glint * 2.8 + halo * glint_patch * sparkle_strength);
    ROUGHNESS = 0.26;
    SPECULAR = 0.35;
}

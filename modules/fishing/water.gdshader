shader_type spatial;
render_mode cull_disabled;

uniform vec4 basin = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool river = false;
uniform vec4 river_a = vec4(0.0);
uniform vec4 river_b = vec4(0.0);
uniform vec4 river_c = vec4(0.0);
uniform float river_half_width = 0.55;
uniform bool geographic_water = false;
uniform sampler2D geographic_mask : filter_linear_mipmap, repeat_disable;
uniform vec2 geographic_extent = vec2(48.0);
uniform vec4 interaction = vec4(0.0);
uniform sampler2D pebble_bed : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D surface_flow : repeat_enable, filter_linear_mipmap;
uniform sampler2D caustics : repeat_enable, filter_linear_mipmap;
uniform sampler2D bank_reflection : filter_linear, repeat_disable;
uniform bool has_bank_reflection = false;
uniform vec3 shallow_color : source_color = vec3(0.24, 0.61, 0.49);
uniform vec3 deep_color : source_color = vec3(0.055, 0.44, 0.43);
uniform vec3 sky_color : source_color = vec3(0.50, 0.69, 0.76);
varying vec3 world;

float segment_distance(vec2 p, vec4 ends) {
    vec2 span = ends.zw - ends.xy;
    float t = clamp(dot(p - ends.xy, span) / max(dot(span, span), 0.0001), 0.0, 1.0);
    return length(p - ends.xy - span * t);
}
float fish_shape(vec2 p, float seed) {
    float time = TIME * (0.095 + seed * 0.012);
    vec2 q = vec2(sin(time + seed * 2.1), cos(time * 0.73 + seed * 1.7));
    vec2 center = basin.xy + q * basin.zw * (0.30 + seed * 0.035);
    vec2 forward = normalize(vec2(cos(time + seed * 2.1) * basin.z, -sin(time * 0.73 + seed * 1.7) * basin.w * 0.73));
    vec2 offset = p - center;
    vec2 body = vec2(dot(offset, forward), dot(offset, vec2(-forward.y, forward.x)));
    body.y += sin(body.x * 18.0 + TIME * 3.0 + seed) * 0.007;
    float silhouette = 1.0 - smoothstep(0.8, 1.15, length(body / vec2(0.21, 0.048)));
    float tail = (1.0 - smoothstep(0.025, 0.04, abs(body.x + 0.23))) * (1.0 - smoothstep(0.015, 0.067, abs(body.y)));
    return max(silhouette, tail * 0.65);
}
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world.xz;
    float normalized_depth = 1.0 - length((p - basin.xy) / basin.zw);
    float shore_distance = normalized_depth * min(basin.z, basin.w);
    if (geographic_water) {
        vec2 uv = vec2(p.x, -p.y) / geographic_extent;
        vec4 mask = texture(geographic_mask, uv);
        if (mask.b < 0.5 || normalized_depth > -0.012) discard;
        // Alpha stores the frozen polygon's distance from shore, including islands.
        shore_distance = max(0.01, mask.a * 1.8);
        normalized_depth = shore_distance / 1.8;
    }
    if (river) {
        float axis_distance = min(segment_distance(p, river_a), min(segment_distance(p, river_b), segment_distance(p, river_c)));
        shore_distance = river_half_width - axis_distance;
        normalized_depth = shore_distance / river_half_width;
    }
    vec2 basin_uv = (p - basin.xy) / basin.zw;
    float broad_noise = texture(surface_flow, p * 0.12).b;
    // A broad shallow shelf faces the bank; depth is asymmetric, never a black central disc.
    float depth_shape = normalized_depth + (broad_noise - 0.5) * 0.20;
    if (!river && !geographic_water) depth_shape -= basin_uv.y * 0.15 + basin_uv.x * 0.05;
    float deep = smoothstep(0.02, 0.95, depth_shape);
    float water_depth = 0.10 + deep * (river ? 0.72 : 1.10);
    vec2 drift = TIME * (river ? vec2(0.001, 0.075) : vec2(0.010, -0.006));
    vec2 a = texture(surface_flow, p * 0.33 + drift).rg * 2.0 - 1.0;
    vec2 b = texture(surface_flow, p * 0.58 - drift.yx * 0.67).gr * 2.0 - 1.0;
    vec2 slope = (a + b * 0.52) * 0.075;
    vec2 to_float = p - interaction.xy;
    float distance_to_float = length(to_float);
    float envelope = exp(-distance_to_float * 2.5) * smoothstep(0.025, 0.12, distance_to_float) * interaction.w;
    float ring_phase = distance_to_float * 23.0 - TIME * 6.0;
    slope += normalize(to_float + vec2(0.0001)) * cos(ring_phase) * envelope * 0.13;
    vec3 water_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
    NORMAL = normalize(mat3(VIEW_MATRIX) * water_normal);

    // A refracted bed is composited in the same opaque pass: stable on mobile, no sorting seams.
    vec2 refracted = p * 0.22 + slope * (0.09 + deep * 0.10);
    vec3 bed = texture(pebble_bed, refracted).rgb;
    vec3 transmission = exp(-water_depth * vec3(1.65, 0.73, 0.58));
    vec3 tint = mix(shallow_color, deep_color, deep);
    vec3 color = bed * transmission + tint * (1.0 - transmission);
    vec2 refracted_light = vec2(texture(surface_flow, p * 0.055 + drift * 0.20).b, texture(surface_flow, p * 0.055 - drift * 0.15 + vec2(0.3)).b);
    vec2 caustic_uv = p * 0.26 + refracted_light * 0.10 + drift * 0.40;
    float light_web = texture(caustics, caustic_uv).r;
    float secondary = texture(caustics, caustic_uv * 0.89 - refracted_light * 0.04 - drift * 0.51).r;
    float sun_web = min(light_web, secondary) * 1.3 + light_web * 0.52 + secondary * 0.15;
    float sun_patch = smoothstep(0.25, 0.65, broad_noise);
    color += vec3(0.31, 0.46, 0.22) * sun_web * mix(0.90, 0.18, deep) * (0.20 + sun_patch * 0.80);
    if (!river && !geographic_water) {
        float fish = max(fish_shape(p + slope * 0.14, 1.0), max(fish_shape(p + slope * 0.14, 2.0), fish_shape(p + slope * 0.14, 3.0)));
        color *= 1.0 - fish * (0.16 + deep * 0.14);
    }
    // Sky streaks and real bank silhouettes occupy patches, leaving clear windows to the bed.
    float fresnel = pow(1.0 - max(dot(normalize(VIEW), NORMAL), 0.0), 2.3);
    float sky_patch = smoothstep(0.38, 0.68, texture(surface_flow, p * vec2(0.17, 0.31) + slope * 0.08 + drift * 0.15).b);
    float reflection_weight = (0.04 + fresnel * 0.32 + sky_patch * 0.15) * smoothstep(0.015, 0.30, shore_distance);
    color = mix(color, sky_color, reflection_weight);
    if (has_bank_reflection) {
        vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + slope * vec2(0.045, 0.020);
        vec4 reflected = texture(bank_reflection, clamp(uv, vec2(0.002), vec2(0.998)));
        color = mix(color, reflected.rgb * vec3(0.57, 0.77, 0.73), reflected.a * (0.24 + fresnel * 0.48) * smoothstep(0.02, 0.35, shore_distance));
    }
    color += max(sin(ring_phase), 0.0) * envelope * vec3(0.14, 0.21, 0.16);
    // Warm wet sediment at the edge, without a bright outline around the basin.
    float margin = 1.0 - smoothstep(0.012, 0.15 + broad_noise * 0.09, shore_distance);
    color = mix(color, bed * vec3(0.72, 0.80, 0.58), margin * 0.55);
    ALBEDO = color;
    ROUGHNESS = mix(0.26, 0.13, smoothstep(0.03, 0.30, shore_distance));
    SPECULAR = 0.48;
}

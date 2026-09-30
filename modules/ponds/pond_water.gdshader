shader_type spatial;
render_mode cull_disabled;

uniform sampler2D pond_shore : filter_linear, repeat_disable;
uniform vec2 pond_extent = vec2(12.0, 16.0);
uniform sampler2D pebble_bed : source_color, repeat_enable, filter_linear_mipmap;
// Pond atlas: refracted mineral bed RGB, optical depth / 2.5 in alpha.
uniform sampler2D basin_bed : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D surface_flow : repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_field : repeat_enable, filter_linear_mipmap;
uniform sampler2D caustics : repeat_enable, filter_linear_mipmap;
uniform sampler2D bank_reflection : filter_linear, repeat_disable;
uniform bool has_bank_reflection = false;
uniform bool polygon_water = true;
uniform vec4 interaction = vec4(0.0);
uniform vec3 shallow_color : source_color = vec3(0.22, 0.89, 0.88);
uniform vec3 middle_color : source_color = vec3(0.125, 0.73, 0.835);
uniform vec3 deep_color : source_color = vec3(0.045, 0.398, 0.60);
uniform vec3 sun_direction = vec3(-0.391, 0.819, -0.419);
uniform float flow_speed = 1.0;
uniform float depth_absorption = 1.0;
uniform float wave_strength : hint_range(0.0, 2.0) = 1.0;
// Normal amplitude is independent of the film / sparkle height thresholds.
uniform float normal_strength : hint_range(0.0, 1.0) = 0.30;
uniform float caustic_depth_falloff : hint_range(0.5, 4.0) = 1.35;
uniform float caustic_scale : hint_range(0.1, 0.5) = 0.22;
uniform float caustic_distortion : hint_range(0.0, 0.25) = 0.13;
uniform float caustic_pan_speed : hint_range(0.0, 2.0) = 0.25;
uniform float caustic_motion_speed : hint_range(0.0, 2.0) = 1.0;
uniform float caustic_softness : hint_range(0.0, 4.0) = 1.2;
uniform float caustic_layer_blend : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_strength : hint_range(0.0, 4.0) = 2.2;
uniform float surface_roughness : hint_range(0.12, 0.45) = 0.31;
uniform float film_cutoff : hint_range(0.25, 0.60) = 0.44;
uniform float film_contrast : hint_range(0.0, 1.0) = 0.30;
uniform float sparkle_cutoff : hint_range(0.65, 0.95) = 0.78;
uniform float shimmer_strength : hint_range(0.0, 24.0) = 4.0;
// Safe interior paths from each actual polygon, rather than a bounding ellipse.
uniform vec4 fish_paths[3];
uniform int lily_count = 0;
uniform vec4 lily_pads[15];
varying vec3 world;
varying float water_sparkle;

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

vec4 reflection_tap(vec2 uv) {
    vec4 reflected = texture(bank_reflection, clamp(uv, vec2(0.002), vec2(0.998)));
    return vec4(reflected.rgb * reflected.a, reflected.a);
}

float fish_shape(vec2 p, vec4 path, float seed, float t) {
    float phase = t * (0.17 + seed * 0.018) + seed * 2.1;
    vec2 center = path.xy + vec2(sin(phase), cos(phase * 0.83)) * path.zw;
    vec2 forward = normalize(vec2(cos(phase) * path.z, -sin(phase * 0.83) * path.w * 0.83) + vec2(0.001));
    vec2 delta = p - center;
    vec2 q = vec2(dot(delta, forward), dot(delta, vec2(-forward.y, forward.x)));
    q.y += sin(q.x * 17.0 - t * 3.2 + seed) * 0.012 * smoothstep(0.04, 0.24, -q.x);
    float body = 1.0 - smoothstep(0.72, 1.2, length(q / vec2(0.17, 0.047)));
    float tail = (1.0 - smoothstep(0.025, 0.042, abs(q.x + 0.18))) * (1.0 - smoothstep(0.022, 0.070, abs(q.y)));
    return max(body, tail * 0.6);
}

void fragment() {
    vec2 p = world.xz;
    vec2 pond_uv = vec2(p.x, -p.y) / pond_extent;
    float shore = texture(pond_shore, pond_uv).r * 2.0;
    float t = TIME * flow_speed;
    // Two differently moving copies create a changing scalar field, following
    // the layered-texture/two-threshold technique in Josh's UE5 breakdown.
    // Shapes grow, join and dissolve; there are no individually moving discs.
    vec4 field_a = texture(ripple_field, p * 0.42 + t * vec2(0.025, -0.015));
    mat2 rotation = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
    vec4 field_b = texture(ripple_field, rotation * p * 0.49 + vec2(0.37, 0.19) + t * vec2(-0.021, 0.027));
    float height = 0.5 + (field_a.r * 0.55 + field_b.r * 0.45 - 0.5) * wave_strength;
    vec2 gradient_a = (field_a.gb * 2.0 - 1.0) * 18.0 * 0.42;
    vec2 gradient_b = transpose(rotation) * ((field_b.gb * 2.0 - 1.0) * 18.0 * 0.49);
    vec2 surface_gradient = gradient_a * 0.55 + gradient_b * 0.45;
    vec2 slope = surface_gradient * 0.055 * wave_strength * normal_strength;
    slope *= smoothstep(0.02, 0.40, shore);
    float threshold_aa = max(fwidth(height) * 1.25, 0.004);
    // A soft film transition avoids flat reflection islands after lowering
    // normal amplitude. Keep the bright-peak threshold independent.
    float film_aa = max(threshold_aa, 0.045);
    float film = clamp((height / film_cutoff) * (1.0 - smoothstep(film_cutoff - film_aa, film_cutoff + film_aa, height)), 0.0, 1.0);
    float peak = smoothstep(sparkle_cutoff - threshold_aa, sparkle_cutoff + 0.035 + threshold_aa, height);
    float soft_edge = smoothstep(sparkle_cutoff - 0.04 - threshold_aa, sparkle_cutoff + threshold_aa, height) * 0.16;
    water_sparkle = (peak + soft_edge) * smoothstep(0.10, 0.55, shore);
    vec2 to_float = p - interaction.xy;
    float distance_to_float = length(to_float);
    float envelope = exp(-distance_to_float * 1.85) * smoothstep(0.04, 0.16, distance_to_float) * interaction.w;
    float ring = distance_to_float * 29.0 - t * 4.2;
    slope += normalize(to_float + vec2(0.0001)) * cos(ring) * envelope * 0.038;
    vec3 normal_world = normalize(vec3(-slope.x, 1.0, -slope.y));
    NORMAL = normalize(mat3(VIEW_MATRIX) * normal_world);

    vec2 refracted = pond_uv + vec2(slope.x, -slope.y) * 0.010 * smoothstep(0.0, 0.4, shore);
    vec4 bed_sample = texture(basin_bed, refracted);
    float depth = bed_sample.a * 2.5;
    vec3 transmission = exp(-depth * depth_absorption * vec3(4.0, 1.05, 0.68));
    vec3 volume = mix(shallow_color, middle_color, smoothstep(0.0, 0.80, depth));
    volume = mix(volume, deep_color, smoothstep(0.85, 2.25, depth));
    // Sunlit neutral minerals transmit cyan/blue light. The old green-grey
    // bed suppressed blue and flattened the shallow-to-deep luminance range.
    vec3 bed = bed_sample.rgb * vec3(1.10, 1.65, 2.15);
    vec3 color = bed * transmission + volume * (1.0 - transmission);
    // Bed-level shadows separate the floating fleshy pads from the clear water.
    float pad_shadow = 0.0;
    for (int i = 0; i < lily_count; i++) {
        vec2 shadow_center = lily_pads[i].xy - sun_direction.xz * depth * 0.55;
        vec2 delta = (p + slope * 0.15 - shadow_center) / lily_pads[i].z;
        pad_shadow = max(pad_shadow, 1.0 - smoothstep(0.62, 1.40, dot(delta, delta)));
    }
    color *= 1.0 - pad_shadow * 0.20;

    // Mobile adaptation of the supplied CausticsProjector: two monochrome
    // samples in this water pass, using the existing atlas depth. Three broad
    // waves provide bounded deformation without an external ocean function.
    // Independently phased broad waves bend the light even with panning off.
    // Unlike translating a smooth noise map, their combined shape changes.
    float caustic_time = t * caustic_motion_speed;
    float bend_a = sin(dot(p, vec2(1.30, 0.80)) + caustic_time * 0.90);
    float bend_b = sin(dot(p, vec2(-0.70, 1.50)) - caustic_time * 1.25);
    float bend_c = sin(dot(p, vec2(0.55, -1.05)) + caustic_time * 1.65 + 0.9);
    vec2 caustic_warp = vec2(bend_a + bend_c * 0.35, bend_b - bend_c * 0.35)
                       * caustic_distortion * wave_strength;
    vec2 light_uv_a = p * caustic_scale + caustic_warp + t * caustic_pan_speed * vec2(0.016, -0.009);
    vec2 light_uv_b = rotation * p * (caustic_scale * 0.93) - caustic_warp * 0.75
                   + vec2(0.37, 0.19) + t * caustic_pan_speed * vec2(-0.013, 0.011);
    // Retain the screen-footprint LOD when zoomed out; an explicit LOD of 0
    // would shimmer in portrait views. Art softness never divides brightness.
    vec2 caustic_size = vec2(textureSize(caustics, 0));
    vec2 dx_a = dFdx(light_uv_a) * caustic_size;
    vec2 dy_a = dFdy(light_uv_a) * caustic_size;
    vec2 dx_b = dFdx(light_uv_b) * caustic_size;
    vec2 dy_b = dFdy(light_uv_b) * caustic_size;
    float footprint = max(max(dot(dx_a, dx_a), dot(dy_a, dy_a)), max(dot(dx_b, dx_b), dot(dy_b, dy_b)));
    float caustic_lod = max(0.5 * log2(max(footprint, 1.0)), caustic_softness + smoothstep(0.25, 1.8, depth) * 0.8);
    float web_a = textureLod(caustics, light_uv_a, caustic_lod).r;
    float web_b = textureLod(caustics, light_uv_b, caustic_lod).r;
    // Broad soft light bands intersect, focus and disappear. Do not retain a
    // dominant single-layer skeleton: that makes the motion read as panning.
    float web = mix(web_a, min(web_a, web_b), caustic_layer_blend);
    color += vec3(0.14, 0.38, 0.36) * web * caustic_strength
           * exp(-depth * caustic_depth_falloff) * smoothstep(0.03, 0.20, shore);
    float fish = 0.0;
    for (int i = 0; i < 3; i++) fish = max(fish, fish_shape(p + slope * 0.22, fish_paths[i], float(i + 1), t));
    color *= 1.0 - fish * 0.23 * smoothstep(0.35, 0.8, shore);

    vec3 view_world = normalize(mat3(INV_VIEW_MATRIX) * VIEW);
    float fresnel = pow(1.0 - max(dot(normal_world, view_world), 0.0), 4.0);
    if (has_bank_reflection) {
        vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + slope * vec2(0.017, 0.011);
        // Filter the small cached capture in premultiplied space, then restore
        // colour. Its unfiltered bright stone silhouettes formed a stepped rim.
        vec2 texel = 1.0 / vec2(textureSize(bank_reflection, 0));
        vec4 reflection = reflection_tap(uv) * 0.40;
        reflection += reflection_tap(uv + vec2(texel.x, 0.0)) * 0.15;
        reflection += reflection_tap(uv - vec2(texel.x, 0.0)) * 0.15;
        reflection += reflection_tap(uv + vec2(0.0, texel.y)) * 0.15;
        reflection += reflection_tap(uv - vec2(0.0, texel.y)) * 0.15;
        float bank = (1.0 - smoothstep(0.10, 0.85, shore)) * 0.03 + fresnel * 0.12;
        color = mix(color, reflection.rgb / max(reflection.a, 0.001), reflection.a * bank);
    }
    color += pow(max(sin(ring), 0.0), 5.0) * envelope * vec3(0.10, 0.22, 0.22);
    float swell = sin(p.x * 3.1 + p.y * 1.3 + t * 0.65) * sin(p.y * 2.4 - t * 0.54);
    color += vec3(0.0, 0.008, 0.011) * swell * smoothstep(0.2, 0.8, depth);
    float far_bank = smoothstep(7.5, 11.7, -p.y + (p.x - 6.0) * 0.18);
    color *= 1.0 - far_bank * (1.0 - smoothstep(0.08, 0.85, shore)) * 0.30;
    ALBEDO = color * 0.88;
    EMISSION = color * 0.12;
    // The lower threshold shapes a soft reflected film; the upper threshold
    // creates isolated, irregular highlights in the light processor below.
    float normal_variance = dot(dFdx(normal_world), dFdx(normal_world)) + dot(dFdy(normal_world), dFdy(normal_world));
    ROUGHNESS = clamp(surface_roughness + (1.0 - 2.0 * film) * 0.03 * film_contrast + normal_variance * 6.0, 0.12, 0.55);
    SPECULAR = 0.35 + (film - 0.5) * 0.10 * film_contrast;
    METALLIC = 0.0;
}

void light() {
    float nl = max(dot(NORMAL, LIGHT), 0.0);
    float nv = max(dot(NORMAL, VIEW), 0.001);
    vec3 half_vector = normalize(LIGHT + VIEW);
    float lh = max(dot(LIGHT, half_vector), 0.0);
    // Preserve the engine's Burley diffuse response for the existing water body.
    float fd90 = 0.5 + 2.0 * ROUGHNESS * lh * lh;
    float diffuse = (1.0 + (fd90 - 1.0) * pow(1.0 - nl, 5.0))
                  * (1.0 + (fd90 - 1.0) * pow(1.0 - nv, 5.0));
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl * diffuse / PI;
    // Josh routes the stylized glints to emission. Here the same kind of mask
    // is light- and view-gated, retaining the user's requirement that real
    // light intensity, direction and shadowing affect the highlights.
    float view_response = pow(max(dot(NORMAL, half_vector), 0.0), 24.0);
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * nl
                    * view_response * water_sparkle * shimmer_strength;
}

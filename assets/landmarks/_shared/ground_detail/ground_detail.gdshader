shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Packed linear DATA, not source_color. Opaque, static, no additional pass.
uniform sampler2D fields : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surfaces : filter_linear_mipmap_anisotropic, repeat_enable;
uniform int finish_kind : hint_enum("Vertex palette", "Grass", "Paving", "Wood", "Sand", "Wet sand") = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float palette_tolerance : hint_range(0.001, 0.1) = 0.012;
uniform vec4 grass_key : source_color = vec4(0.525490, 0.658824, 0.309804, 1.0);
uniform vec4 grass_dark_key : source_color = vec4(0.458824, 0.580392, 0.282353, 1.0);
uniform vec4 grass_light_key : source_color = vec4(0.603922, 0.709804, 0.364706, 1.0);
uniform vec4 paving_key : source_color = vec4(0.874510, 0.796078, 0.654902, 1.0);
uniform vec4 wood_key : source_color = vec4(0.733333, 0.545098, 0.321569, 1.0);
uniform vec4 wood_light_key : source_color = vec4(0.815686, 0.647059, 0.423529, 1.0);
uniform vec4 wood_dark_key : source_color = vec4(0.603922, 0.439216, 0.274510, 1.0);
uniform vec4 sand_key : source_color = vec4(0.831373, 0.752941, 0.588235, 1.0);
uniform vec4 wet_sand_key : source_color = vec4(0.607843, 0.560784, 0.439216, 1.0);

// XZ projection in metres; local projection follows movable/rotated modules.
uniform int coordinate_space : hint_enum("World XZ", "Object XZ") = 0;
uniform vec2 mapping_origin_m = vec2(0.0);
uniform float mapping_rotation_degrees : hint_range(-180.0, 180.0) = 0.0;
uniform vec2 top_normal_range = vec2(0.80, 0.98);
uniform bool height_filter_enabled = false;
uniform vec2 local_height_range_m = vec2(-0.015, 0.015);

uniform vec4 grass_deep_color : source_color = vec4(0.321569, 0.494118, 0.207843, 1.0);
uniform vec4 grass_base_color : source_color = vec4(0.470588, 0.627451, 0.266667, 1.0);
uniform vec4 grass_sun_color : source_color = vec4(0.635294, 0.725490, 0.364706, 1.0);
uniform float grass_patch_repeat_m : hint_range(0.1, 100.0) = 24.0;
uniform float grass_secondary_ratio : hint_range(0.1, 4.0) = 1.618;
uniform vec2 grass_secondary_offset_m = vec2(11.7, -4.3);
uniform float grass_secondary_mix : hint_range(0.0, 1.0) = 0.20;
uniform vec2 grass_deep_transition = vec2(0.41, 0.46);
uniform vec2 grass_sun_transition = vec2(0.54, 0.60);
uniform float grass_detail_repeat_m : hint_range(0.1, 10.0) = 2.0;
uniform float grass_detail_strength : hint_range(0.0, 1.0) = 0.13;
uniform vec4 paving_color : source_color = vec4(0.874510, 0.796078, 0.654902, 1.0);
uniform vec2 paving_repeat_m = vec2(4.0, 4.0);
uniform float paving_joint_strength : hint_range(0.0, 1.0) = 0.16;
uniform float paving_tone_strength : hint_range(0.0, 1.0) = 0.10;
uniform vec4 wood_color : source_color = vec4(0.639216, 0.505882, 0.364706, 1.0);
uniform vec4 wood_light_color : source_color = vec4(0.721569, 0.600000, 0.447059, 1.0);
uniform vec4 wood_dark_color : source_color = vec4(0.474510, 0.372549, 0.278431, 1.0);
uniform vec2 wood_repeat_m = vec2(3.0, 1.0);
uniform float wood_grain_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec2 wood_board_size_m = vec2(1.8, 0.18);
uniform float wood_board_stagger : hint_range(0.0, 1.0) = 0.5;
uniform float wood_joint_width_m : hint_range(0.0, 0.05) = 0.012;
uniform vec4 wood_joint_color : source_color = vec4(0.411765, 0.329412, 0.250980, 1.0);
uniform float wood_board_tone_strength : hint_range(0.0, 0.5) = 0.14;

uniform vec4 sand_color : source_color = vec4(0.831373, 0.752941, 0.588235, 1.0);
uniform vec4 wet_sand_color : source_color = vec4(0.650980, 0.545098, 0.388235, 1.0);
uniform vec4 tide_color : source_color = vec4(0.521569, 0.423529, 0.290196, 1.0);
uniform float sand_macro_repeat_m : hint_range(0.1, 100.0) = 12.0;
uniform float sand_detail_repeat_m : hint_range(0.1, 10.0) = 1.5;
uniform float sand_macro_strength : hint_range(0.0, 1.0) = 0.10;
uniform float sand_grain_strength : hint_range(0.0, 1.0) = 0.10;
uniform bool tide_enabled = true;
uniform vec2 tide_direction = vec2(0.0, 1.0);
uniform float tide_position_m = 0.0;
uniform float tide_transition_m : hint_range(0.01, 4.0) = 0.65;
uniform float tide_breakup_m : hint_range(0.0, 4.0) = 0.35;
uniform float tide_band_offset_m = 0.35;
uniform float tide_band_width_m : hint_range(0.01, 2.0) = 0.23;
uniform float tide_band_strength : hint_range(0.0, 1.0) = 0.22;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.86;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.15;

varying vec2 ground_position;
varying float local_height;
varying float up_facing;

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 p = (coordinate_space == 0 ? world.xz : VERTEX.xz) - mapping_origin_m;
    float a = radians(mapping_rotation_degrees);
    ground_position = vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y);
    local_height = VERTEX.y;
    up_facing = smoothstep(top_normal_range.x, max(top_normal_range.y, top_normal_range.x + 0.0001),
        dot(normalize(MODEL_NORMAL_MATRIX * NORMAL), vec3(0.0, 1.0, 0.0)));
}

bool near_key(vec3 a, vec3 b) { return distance(a, b) < palette_tolerance; }

float board_tone(vec2 id) {
    // Static arithmetic hash: no additional texture or time-dependent noise.
    vec3 h = fract(vec3(id.x, id.y, id.x) * 0.1031);
    h += dot(h, h.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

void fragment() {
    vec3 base = COLOR.rgb;
    vec3 detailed = base;
    vec2 p = ground_position;
    int kind = finish_kind;
    if (kind == 0) {
        if (near_key(base, grass_key.rgb) || near_key(base, grass_dark_key.rgb) || near_key(base, grass_light_key.rgb)) kind = 1;
        else if (near_key(base, paving_key.rgb)) kind = 2;
        else if (near_key(base, wood_key.rgb) || near_key(base, wood_light_key.rgb) || near_key(base, wood_dark_key.rgb)) kind = 3;
        else if (near_key(base, sand_key.rgb)) kind = 4;
        else if (near_key(base, wet_sand_key.rgb)) kind = 5;
    }
    float wet = 0.0;
    if (kind == 1) {
        float broad = texture(fields, p / max(grass_patch_repeat_m, 0.001)).r;
        float second = texture(fields, (p.yx + grass_secondary_offset_m) / max(grass_patch_repeat_m * grass_secondary_ratio, 0.001)).r;
        float patch = mix(broad, second, grass_secondary_mix);
        vec3 grass = mix(grass_deep_color.rgb, grass_base_color.rgb, smoothstep(grass_deep_transition.x, grass_deep_transition.y, patch));
        grass = mix(grass, grass_sun_color.rgb, smoothstep(grass_sun_transition.x, grass_sun_transition.y, patch));
        float leaf = texture(fields, p / max(grass_detail_repeat_m, 0.001)).g;
        detailed = grass * (1.0 + (leaf - 0.5) * grass_detail_strength * 2.0);
    } else if (kind == 2) {
        vec2 stone = texture(surfaces, p / max(paving_repeat_m, vec2(0.001))).rg;
        detailed = paving_color.rgb * (1.0 - stone.r * paving_joint_strength + (stone.g - 0.5) * paving_tone_strength);
    } else if (kind == 3) {
        vec3 wood = wood_color.rgb;
        if (near_key(base, wood_light_key.rgb)) wood = wood_light_color.rgb;
        else if (near_key(base, wood_dark_key.rgb)) wood = wood_dark_color.rgb;
        float grain = texture(surfaces, p / max(wood_repeat_m, vec2(0.001))).b;
        detailed = wood * (1.0 + (grain - 0.5) * wood_grain_strength * 2.0);
        // Metric boards run along projected X. Alternate rows shift the end joints.
        vec2 board_size = max(wood_board_size_m, vec2(0.001));
        float row = floor(p.y / board_size.y);
        vec2 board_uv = vec2(p.x / board_size.x + mod(row, 2.0) * wood_board_stagger, p.y / board_size.y);
        vec2 cell = floor(board_uv);
        vec2 within = fract(board_uv);
        vec2 edge_m = min(within, 1.0 - within) * board_size;
        // Derivatives of continuous position avoid false AA at stagger boundaries.
        vec2 aa = max(fwidth(p) * 0.5, vec2(0.0001));
        vec2 joints = 1.0 - smoothstep(vec2(wood_joint_width_m * 0.5) - aa,
            vec2(wood_joint_width_m * 0.5) + aa, edge_m);
        float seam = wood_joint_width_m > 0.0 ? max(joints.x, joints.y) : 0.0;
        detailed *= 1.0 + (board_tone(cell) - 0.5) * wood_board_tone_strength * 2.0;
        detailed = mix(detailed, wood_joint_color.rgb, seam);
    } else if (kind == 4 || kind == 5) {
        // Two reads, both existing packed channels; no ripple/normal/water sampling.
        float broad = texture(fields, p / max(sand_macro_repeat_m, 0.001)).r;
        float grain = texture(fields, p / max(sand_detail_repeat_m, 0.001)).b;
        float band = 0.0;
        if (kind == 5) {
            vec2 direction = tide_direction / max(length(tide_direction), 0.0001);
            float shore = dot(p, direction) - tide_position_m + (broad - 0.5) * tide_breakup_m * 2.0;
            wet = tide_enabled ? smoothstep(-tide_transition_m * 0.5, tide_transition_m * 0.5, shore) : 1.0;
            band = tide_enabled ? (1.0 - smoothstep(0.0, max(tide_band_width_m, 0.001), abs(shore - tide_band_offset_m))) * tide_band_strength : 0.0;
        }
        detailed = mix(sand_color.rgb, wet_sand_color.rgb, wet);
        detailed = mix(detailed, tide_color.rgb, band);
        detailed *= 1.0 + (broad - 0.5) * sand_macro_strength * 2.0 + (grain - 0.5) * sand_grain_strength * 2.0;
    }
    float coverage = strength * up_facing;
    if (height_filter_enabled && (local_height < local_height_range_m.x || local_height > local_height_range_m.y)) coverage = 0.0;
    ALBEDO = mix(base, detailed, coverage);
    ROUGHNESS = mix(surface_roughness, wet_roughness, wet * coverage);
    SPECULAR = surface_specular;
    METALLIC = 0.0;
}

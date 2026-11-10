shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
// Optional finishes for #792 bf0c31b1. COLOR is the imported LINEAR palette.
// DATA samplers deliberately have no source_color hint. No UV dependency.
uniform sampler2D fields : filter_linear_mipmap, repeat_enable;
uniform sampler2D surfaces : filter_linear_mipmap, repeat_enable;
uniform int finish_kind : hint_enum("Terrain", "Dock boards") = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float palette_tolerance : hint_range(0.001, 0.03) = 0.012;
uniform vec4 garden : source_color = vec4(0.52549, 0.65882, 0.30980, 1.0);
uniform vec4 garden_dark : source_color = vec4(0.45882, 0.58039, 0.28235, 1.0);
uniform vec4 garden_light : source_color = vec4(0.60392, 0.70980, 0.36471, 1.0);
// Grass output colours are independent from the owner's COLOR_0 selection keys.
uniform vec4 grass_deep_color : source_color = vec4(0.45882, 0.58039, 0.28235, 1.0);
uniform vec4 grass_base_color : source_color = vec4(0.52549, 0.65882, 0.30980, 1.0);
uniform vec4 grass_sun_color : source_color = vec4(0.60392, 0.70980, 0.36471, 1.0);
uniform vec4 road : source_color = vec4(0.87451, 0.79608, 0.65490, 1.0);
uniform vec4 wood : source_color = vec4(0.73333, 0.54510, 0.32157, 1.0);
uniform vec4 wood_light : source_color = vec4(0.81569, 0.64706, 0.42353, 1.0);
uniform vec4 wood_dark : source_color = vec4(0.60392, 0.43922, 0.27451, 1.0);
uniform float grass_patch_repeat_m = 24.0;
uniform float grass_detail_repeat_m = 2.0;
uniform float grass_detail_strength = 0.13;
uniform float paving_repeat_m = 4.0;
uniform float paving_joint_strength = 0.16;
uniform float paving_tone_strength = 0.10;
uniform vec2 wood_repeat_m = vec2(3.0, 1.0);
uniform float wood_grain_strength = 0.32;
// Kept identical to the host's original vertex-colour material.
uniform float surface_roughness = 0.94;
uniform float surface_specular = 0.15;

varying vec3 world_position;
varying vec3 object_position;
varying float up_facing;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    object_position = VERTEX;
    up_facing = smoothstep(0.80, 0.98, dot(normalize(MODEL_NORMAL_MATRIX * NORMAL), vec3(0.0, 1.0, 0.0)));
}

bool near_palette(vec3 a, vec3 b) {
    return distance(a, b) < palette_tolerance;
}

void fragment() {
    vec3 base = COLOR.rgb;
    vec3 detailed = base;
    if (finish_kind == 0) {
        bool grass = near_palette(base, src_linear4(garden).rgb) || near_palette(base, src_linear4(garden_dark).rgb) || near_palette(base, src_linear4(garden_light).rgb);
        bool path = near_palette(base, src_linear4(road).rgb);
        if (grass) {
            // Two incommensurate repeats reduce obvious macro repetition across the island.
            float broad = texture(fields, world_position.xz / grass_patch_repeat_m).r;
            float second = texture(fields, (world_position.zx + vec2(11.7, -4.3)) / (grass_patch_repeat_m * 1.618)).r;
            float patch = broad * 0.80 + second * 0.20;
            vec3 grass_color = mix(src_linear4(grass_deep_color).rgb, src_linear4(grass_base_color).rgb, smoothstep(0.41, 0.46, patch));
            grass_color = mix(grass_color, src_linear4(grass_sun_color).rgb, smoothstep(0.54, 0.60, patch));
            float leaf = texture(fields, world_position.xz / grass_detail_repeat_m).g;
            detailed = grass_color * (1.0 + (leaf - 0.5) * grass_detail_strength * 2.0);
        } else if (path) {
            vec2 stone = texture(surfaces, world_position.xz / paving_repeat_m).rg;
            detailed = base * (1.0 - stone.r * paving_joint_strength + (stone.g - 0.5) * paving_tone_strength);
        }
    } else {
        bool board = near_palette(base, src_linear4(wood).rgb) || near_palette(base, src_linear4(wood_light).rgb) || near_palette(base, src_linear4(wood_dark).rgb);
        // Only original deck top faces: do not paint pile caps, piles or side faces.
        if (board && abs(object_position.y) < 0.015) {
            float grain = texture(surfaces, object_position.xz / wood_repeat_m).b;
            detailed = base * (1.0 + (grain - 0.5) * wood_grain_strength * 2.0);
        }
    }
    ALBEDO = mix(base, detailed, strength * up_facing);
    ROUGHNESS = surface_roughness;
    SPECULAR = surface_specular;
    METALLIC = 0.0;
	ALBEDO = albedo_out(ALBEDO);
}

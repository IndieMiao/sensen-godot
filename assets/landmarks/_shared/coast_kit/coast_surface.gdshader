shader_type spatial;
render_mode depth_draw_opaque;

// COLOR.rgb is authored linear vertex paint. COLOR.a is a surface code, never opacity:
// 1/8 base rock, 2/8 light rock, 3/8 shadow rock, 4/8 warm face, 6/8 wettable solid.
uniform int rock_palette : hint_range(0, 1, 1) = 1;
uniform vec4 cold_base : source_color = vec4(0.4666667, 0.4784314, 0.4588235, 1.0);
uniform vec4 cold_light : source_color = vec4(0.5764706, 0.5843137, 0.5450980, 1.0);
uniform vec4 cold_shadow : source_color = vec4(0.3176471, 0.3568627, 0.3490196, 1.0);
uniform vec4 cold_warm_face : source_color = vec4(0.5176471, 0.5294118, 0.4941176, 1.0);
uniform float water_level = 0.15;
uniform float wet_height : hint_range(0.01, 0.5) = 0.25;
uniform float wet_strength : hint_range(0.0, 0.75) = 0.38;

varying flat float surface_code;
varying float world_height;

void vertex() {
    surface_code = floor(COLOR.a * 8.0 + 0.5);
    world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
    vec3 paint = COLOR.rgb;
    if (rock_palette == 1) {
        if (surface_code == 1.0) { paint = cold_base.rgb; }
        else if (surface_code == 2.0) { paint = cold_light.rgb; }
        else if (surface_code == 3.0) { paint = cold_shadow.rgb; }
        else if (surface_code == 4.0) { paint = cold_warm_face.rgb; }
    }
    float wet = 0.0;
    if (surface_code >= 1.0 && surface_code <= 6.0) {
        wet = 1.0 - smoothstep(water_level, water_level + max(wet_height, 0.001), world_height);
    }
    ALBEDO = paint * (1.0 - wet * wet_strength);
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
    SPECULAR = 0.15;
}

shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
// Same camera-facing far-depth projection as the Alcatraz cards.
uniform float depth_fraction : hint_range(0.5,0.999) = 0.96;
uniform vec4 base_color : source_color = vec4(0.90980,0.85490,0.79216,1.0);
uniform vec4 accent_color : source_color = vec4(0.66667,0.74118,0.77647,1.0);
uniform vec4 shadow_color : source_color = vec4(0.62353,0.69412,0.74118,1.0);
uniform vec4 fog_color : source_color = vec4(0.40392,0.68627,0.76078,1.0);
uniform float fog_amount : hint_range(0.0,1.0) = 0.18;
varying vec3 card_color;

void vertex() {
    vec3 center = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0,0.0,0.0,1.0)).xyz;
    vec2 axis_scale = vec2(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz));
    vec4 far_plane = INV_PROJECTION_MATRIX * vec4(0.0,0.0,CLIP_SPACE_FAR,1.0);
    vec3 view_position = vec3(center.xy + VERTEX.xy * axis_scale, far_plane.z / far_plane.w * depth_fraction);
    POSITION = PROJECTION_MATRIX * vec4(view_position,1.0);
    // GLB RGB is palette weight, not sRGB paint. Fog changes colour, not opacity.
    vec3 paint = COLOR.r * src_linear4(base_color).rgb + COLOR.g * src_linear4(accent_color).rgb + COLOR.b * src_linear4(shadow_color).rgb;
    card_color = mix(paint,src_linear4(fog_color).rgb,fog_amount);
}

void fragment() {
    ALBEDO = card_color;
    ALPHA = 1.0;
	ALBEDO = albedo_out(ALBEDO);
}

shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform float depth_fraction = 0.94;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_texture = false;
uniform sampler2D card_texture : source_color, filter_linear_mipmap, repeat_disable;
void vertex() {
    vec3 center = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0,0.0,0.0,1.0)).xyz;
    vec2 axis_scale = vec2(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz));
    vec4 far_plane = INV_PROJECTION_MATRIX * vec4(0.0,0.0,CLIP_SPACE_FAR,1.0);
    vec3 view_position = vec3(center.xy + VERTEX.xy * axis_scale, far_plane.z / far_plane.w * depth_fraction);
    POSITION = PROJECTION_MATRIX * vec4(view_position,1.0);
}
void fragment() {
    vec4 color = COLOR * src_linear4(tint);
    if (use_texture) { color *= src_linear4(texture(card_texture,UV)); }
    ALBEDO = color.rgb;
    ALPHA = color.a;
	ALBEDO = albedo_out(ALBEDO);
}

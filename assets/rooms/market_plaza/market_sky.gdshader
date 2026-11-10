shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;
// GLES (SGODOT-458): source_color inputs to linear where read, ALBEDO / EMISSION handed over as GLES wants them.
#include "res://modules/render/gles_colour.gdshaderinc"
uniform vec4 sky_top : source_color = vec4(0.61,0.77,0.84,1.0);
uniform vec4 sky_horizon : source_color = vec4(0.85,0.91,0.90,1.0);
void vertex() {
    vec4 far_point=INV_PROJECTION_MATRIX*vec4(0.0,0.0,CLIP_SPACE_FAR,1.0);
    vec4 projected=PROJECTION_MATRIX*vec4(0.0,0.0,far_point.z/far_point.w*0.97,1.0);
    POSITION=vec4(VERTEX.xy,projected.z/projected.w,1.0);
}
void fragment() {
    ALBEDO=mix(src_linear4(sky_top).rgb,src_linear4(sky_horizon).rgb,smoothstep(0.0,0.75,UV.y));
    ALPHA=1.0;
	ALBEDO = albedo_out(ALBEDO);
}

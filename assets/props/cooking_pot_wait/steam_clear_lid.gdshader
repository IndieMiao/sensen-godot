shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 steam_colour : source_color = vec4(1.0, 0.97254902, 0.94117647, 1.0);
// Set per Steam instance from the real animated lid and the host camera.
// Default 0 hides steam until that camera is available.
uniform float lid_top_uv = 0.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= scale * mix(0.45, 1.25, smoothstep(0.5, 1.0, INSTANCE_CUSTOM.y));
}

void fragment() {
	float radial = pow(max(0.0, 1.0 - length((UV - vec2(0.5)) * 2.0)), 1.5);
	float above_lid = smoothstep(0.0, 0.003, lid_top_uv - SCREEN_UV.y);
	ALBEDO = steam_colour.rgb;
	ALPHA = min(COLOR.a, 0.35) * radial * above_lid;
}

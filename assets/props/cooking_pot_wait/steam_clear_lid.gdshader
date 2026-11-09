shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 steam_colour : source_color = vec4(1.0, 0.97254902, 0.94117647, 1.0);
uniform sampler2D puff_texture : source_color, filter_linear_mipmap;
//449 host:200x220 logical-pixel SubViewport at(80,110); scales with the layer.
uniform vec2 steam_layer_logical_size = vec2(200.0,220.0);
uniform vec2 steam_layer_logical_origin = vec2(80.0,110.0);
// Set per Steam instance from the real animated lid and the host camera.
// Default 0 hides steam until that camera is available.
uniform float lid_top_uv = 0.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= scale * mix(1.0, 1.52, smoothstep(0.10, 0.78, INSTANCE_CUSTOM.y));
	MODELVIEW_MATRIX[3].x += 0.016 * sin(float(INSTANCE_ID)*2.094395 + INSTANCE_CUSTOM.y*3.2);
}

void fragment() {
	vec4 puff = texture(puff_texture, UV);
	vec2 px = SCREEN_UV * steam_layer_logical_size + steam_layer_logical_origin;
	float upper_fade = smoothstep(120.0, 133.0, px.y);
	float region = smoothstep(130.0, 134.0, px.x) * (1.0-smoothstep(226.0,230.0,px.x))
		* (1.0-smoothstep(191.0,195.0,px.y));
	float ring_cap = mix(0.56,0.38,smoothstep(166.0,170.0,px.y));
	float above_lid = smoothstep(0.0, 0.003, lid_top_uv - SCREEN_UV.y);
	ALBEDO = puff.rgb;
	ALPHA = min(COLOR.a, ring_cap) * puff.a * above_lid * upper_fade * region;
}

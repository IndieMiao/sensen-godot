shader_type spatial;
// Vertex-painted landmark ground with the farm meadow grain; fades into haze past the play area.
render_mode diffuse_burley, specular_disabled;

uniform sampler2D meadow_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 haze : source_color = vec4(0.89, 0.92, 0.91, 1.0);
uniform vec4 play_rect = vec4(-12.0, 12.0, -10.0, 10.5);
uniform float fade = 5.0;
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float grain = texture(meadow_texture, world.xz * 0.55).g;
	float wash = texture(meadow_texture, world.xz * 0.06).r;
	vec3 col = COLOR.rgb * (0.93 + grain * 0.10) * (0.95 + wash * 0.08);
	vec2 outside = max(vec2(play_rect.x - world.x, world.x - play_rect.y), vec2(0.0));
	float d = max(max(outside.x, outside.y), max(world.z - play_rect.w, 0.0));
	d = max(d, smoothstep(-4.0, -9.0, world.y) * fade);
	float mist = smoothstep(0.0, fade, d);
	ALBEDO = col * (1.0 - mist);
	EMISSION = haze.rgb * mist;
	ROUGHNESS = 1.0;
}

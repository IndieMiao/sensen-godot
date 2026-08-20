// 统一 avatar toon shader：近似 Unity DonutAvatar（BaseColor × AO × 双段光照 ramp）
// 一期把 56 种 Unity shader 收敛到这一个；特殊效果二期按需扩展。
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.3;
uniform float shadow_value : hint_range(0.0, 1.0) = 0.85; // 暗部亮度（对应 _Kshadow）
uniform float shadow_softness : hint_range(0.001, 1.0) = 0.1;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	float ao = mix(1.0, texture(ao_tex, UV).r, ao_strength);
	ALBEDO = alb.rgb * ao;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = alb.rgb * (emission_strength + rim * rim_strength);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, shadow_softness, ndl);
	float shade = mix(shadow_value, 1.0, lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * ATTENUATION * shade;
}

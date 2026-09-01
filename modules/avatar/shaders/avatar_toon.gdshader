// 统一 avatar 材质：对齐 Unity DonutAvatar 的 **URP Lit（PBR）** 语义。
//
// 2026-09-01 修正（真机 lookdev 与森森正式版比对后）：
// 一期把 56 种 Unity shader 收敛成一个自定义两段 toon ramp，并按名字把 Unity 的
// PBR 参数硬套到含义无关的 ramp 参数上，结果画面完全没有体积感（硬边平色）。
// 查证原图 Assets/_Gensen/Characters/Materials/DonutAvatar.shadergraph：目标是
// UniversalLitSubTarget，只写 BaseColor / Emission / Smoothness / Metallic /
// Occlusion / NormalTS 这些**标准表面输出**，没有任何自定义光照函数——
// 那种"黏土玩具"的柔和体积来自 Lambert 的自然渐变 + 环境光填充 + 宽高光。
//
// 三处错位（均已修正）：
//   _Ksmooth  是 Smoothness（roughness = 1 - it），不是 ramp 宽度。
//             原先写死 ROUGHNESS=1 / SPECULAR=0，把高光整个掐死。
//   _Kshadow  是 graph 内部的 Lerp 系数，不是"暗部亮度"。原先 0.85 让亮暗只差 15%。
//   AO        按 URP Occlusion 语义只压间接光；原先直接乘进 ALBEDO，连直接光一起压。
//
// 所以这里**不写 light()**，交给引擎标准光照——既是对齐原版，也更简单。
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.3; // Unity _Kao
uniform float smoothness : hint_range(0.0, 1.0) = 0.1; // Unity _Ksmooth
uniform float diffuse_strength : hint_range(0.0, 2.0) = 1.0; // Unity _Kd
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0; // Unity _Ke
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0; // Unity _FresnelHighLight

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	// _Kd（受光）与 _Ke（平光地板）在 Unity 材质里成对出现，且和常常大于 1
	// （body 0.8/0.6、eyes 1/1、水晶发 0.5/0.8）——更像美术在配"受光 vs 平光"的
	// 配比，而不是两个独立的绝对值。1:1 照搬进 Godot 会把总能量顶到 1.4，
	// 皮肤这种浅底色直接裁成纯白、体积感消失（2026-09-01 真机实测）。
	// 这里保住美术选的比例、把总量归一到 ≤1；和本来就 ≤1 的材质不受影响。
	float energy = max(diffuse_strength + emission_strength, 1.0);
	float lit_w = diffuse_strength / energy;
	float flat_w = emission_strength / energy;
	ALBEDO = alb.rgb * lit_w;
	// URP 的 Occlusion 只压间接光。AO_LIGHT_AFFECT=0 就是这个语义。
	AO = mix(1.0, texture(ao_tex, UV).r, ao_strength);
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = clamp(1.0 - smoothness, 0.0, 1.0);
	SPECULAR = 0.5; // URP Lit 非金属反射率 0.04 ≈ Godot SPECULAR 0.5
	METALLIC = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = alb.rgb * (flat_w + rim * rim_strength);
}

class_name AvatarMaterialFactory
extends RefCounted

const SHADER := preload("res://modules/avatar/shaders/avatar_toon.gdshader")
const TEXTURE_KEYS := ["albedo_tex", "ao_tex"]
## 与 avatar_toon.gdshader 的 uniform 名一一对应；由 tools/unity_export/materials.py
## 的 FLOAT_MAP 从 Unity .mat 抽出。2026-09-01 起按 URP Lit 真实语义命名
## （smoothness/diffuse_strength），不再有 shadow_value/shadow_softness——
## 那两个是把 Unity PBR 参数错当成 toon ramp 参数的产物。
const FLOAT_KEYS := ["ao_strength", "smoothness", "diffuse_strength",
	"emission_strength", "rim_strength"]

static func create(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for key in TEXTURE_KEYS:
		if not params.has(key):
			continue
		var v = params[key]
		if v is String:
			v = load(v)
		if v is Texture2D:
			m.set_shader_parameter(key, v)
	for key in FLOAT_KEYS:
		if params.has(key):
			m.set_shader_parameter(key, float(params[key]))
	return m

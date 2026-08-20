class_name AvatarMaterialFactory
extends RefCounted

const SHADER := preload("res://modules/avatar/shaders/avatar_toon.gdshader")
const TEXTURE_KEYS := ["albedo_tex", "ao_tex"]
const FLOAT_KEYS := ["ao_strength", "shadow_value", "shadow_softness", "emission_strength", "rim_strength"]

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

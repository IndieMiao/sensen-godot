class_name MineBackdrop
extends RefCounted
## The P0 mine's underground backdrop (SGODOT-257; asset PR #162 by 刘备, spec and tints 不知火舞): one relief mesh
## shared by floors 1 and 2, made for the mine camera's 43° / 14.5° and placed at the world origin as authored. Each
## floor tints it with its wall colour darkened, fading out to the mine's void background at its outer edge. It casts no
## shadow, takes no GI and has no collision; the mine keeps it out of the camera's framing bounds (scenery / objects).

const SCENE := preload("res://assets/mine/backdrop/mine_backdrop.glb")
const SHADER := preload("res://modules/mining/mine_backdrop.gdshader")
## The mine Environment's background colour (P0Mine), which the backdrop's outer edge fades into.
const VOID := Color("242125")
## Floor tints as the asset was verified with (README): floor 1 #B85E43 darkened 45 % (≈ #653425), floor 2 #A59A77
## darkened 50 % (≈ #534D3C), in sRGB.
const TINTS := {
	1: Color(0.39686275, 0.2027451, 0.1445098),
	2: Color(0.32352941, 0.30196078, 0.23333333),
}

static func tint(floor_n: int) -> Color:
	return TINTS.get(floor_n, TINTS[2])

static func build(floor_n: int) -> Node3D:
	var root: Node3D = SCENE.instantiate()
	root.name = "MineBackdrop"
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("floor_tint", tint(floor_n))
	mat.set_shader_parameter("void_tint", VOID)
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return root

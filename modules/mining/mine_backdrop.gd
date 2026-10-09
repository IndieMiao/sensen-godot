class_name MineBackdrop
extends RefCounted
## The P0 mine's underground backdrop (SGODOT-257; asset PR #162 by 刘备, spec and tints 不知火舞): one relief mesh
## shared by floors 1 and 2, made for the mine camera's 43° / 14.5° and placed at the world origin as authored, slid
## FORWARD_M towards the camera along its view (the same picture, see below). Each
## floor tints it with its wall colour darkened, fading out to the mine's void background at its outer edge. It casts no
## shadow, takes no GI and has no collision; the mine keeps it out of the camera's framing bounds (scenery / objects).

const FarmCamera := preload("res://modules/farm/farm_camera.gd")
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

## How far the relief sits towards the camera along the view (苏烈 on #173, the depth sweep on SGODOT-257): the
## camera's far plane saws with the zoom (FarmCamera.fit_ground_depth rounds it to half metres), and with a pinch
## past 1.4 at the right end it cut the bottom strata by up to 0.64 m. An orthographic picture does not change along
## the view, so this only moves the relief inside far; near stays more than 12 m in front of it.
const FORWARD_M := 1.0

## The mine camera's view axis, from the scene towards the camera (FarmCamera.place: pitch 43°, yaw 14.5°).
static func toward_camera() -> Vector3:
	var pitch := deg_to_rad(FarmCamera.PITCH_DEG)
	var yaw := deg_to_rad(FarmCamera.YAW_DEG)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))

static func tint(floor_n: int) -> Color:
	return TINTS.get(floor_n, TINTS[2])

static func build(floor_n: int) -> Node3D:
	var root: Node3D = SCENE.instantiate()
	root.name = "MineBackdrop"
	root.position = toward_camera() * FORWARD_M
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

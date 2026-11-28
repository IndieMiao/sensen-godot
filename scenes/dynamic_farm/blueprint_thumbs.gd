extends Node
## The blueprint book's pictures (C-228; SEN-C-227 README §3: the building drawn once at the farm's angle, turn 0, kept
## per type): each type gets a small SubViewport of its own world with the building's model (Building.model, as the
## placement's), the farm's 43° / 14.5° orthographic view framing its bounds, a sun and the farm's ambient light. It
## renders once (UPDATE_ONCE) and its texture is reused for every opening of the book while the parcel is up.

const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const CameraRules = preload("res://modules/farm/farm_camera.gd")
## Twice the 92 × 112 paper, so it stays sharp on a phone's density.
const SIZE := Vector2i(184, 224)
## Room left round the building's bounds in the frame.
const MARGIN := 1.12

var _views := {}

## The picture of `type` (footprint `base` unturned, `cell_m` a cell's metres), drawn the first time it is asked for.
func texture(type: String, base: Vector2i, cell_m: float) -> Texture2D:
	if _views.has(type): return (_views[type] as SubViewport).get_texture()
	var view := SubViewport.new()
	view.name = "Thumb_%s" % type
	view.size = SIZE
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	_views[type] = view
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.90, 0.88, 0.84)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color(1.0, 0.905, 0.755)
	sun.light_energy = 1.1
	view.add_child(sun)
	var model := Building.model(type, base, cell_m)
	if model == null: return view.get_texture()
	view.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	view.add_child(camera)
	var box := bounds(model)
	CameraRules.place(camera, box.get_center())
	var inverse := camera.global_transform.affine_inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = inverse * box.get_endpoint(i)
		low = low.min(Vector2(p.x, p.y))
		high = high.max(Vector2(p.x, p.y))
	var aspect := float(SIZE.x) / float(SIZE.y)
	camera.size = maxf(high.x - low.x, (high.y - low.y) * aspect) * MARGIN
	camera.global_position += camera.global_basis * Vector3((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, 0)
	camera.near = 0.05
	camera.far = 60.0
	camera.current = true
	return view.get_texture()

## Every mesh's bounds under `root` (in the tree), in world space.
static func bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: meshes.append(root)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null: continue
		var box := mesh.global_transform * mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)

extends Node
## Reuses world props and their mesh helpers for transparent inventory thumbnails.

const Art = preload("res://modules/farm/farm_art.gd")
const Scenery = preload("res://modules/farm/place_scenery.gd")
const Decorations = preload("res://modules/farm/decoration_layout.gd")
const OUTPUT := "res://assets/ui/farm/items/"
const ITEMS := ["wood", "stone", "fiber", "copper_ore", "rock_salt", "bench", "planter", "lantern", "fountain", "sign", "crate", "hand_tools", "row_tool"]
const METAL := Color("538087")
const BARK := Color("997252")
const COPPER := Color("d39369")

func _enter_tree() -> void:
	Net.booting = true
	Net.booted_once = true

func _ready() -> void:
	call_deferred("_render")

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Inventory rendering requires a graphical renderer")
		get_tree().quit(2)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if directory_error != OK:
		push_error("Cannot create inventory thumbnail directory: %s" % directory_error)
		get_tree().quit(2)
		return
	var viewport := _viewport()
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 100.0
	viewport.add_child(camera)
	camera.current = true
	var failed := false
	for item_id in _item_ids():
		var model := _model(item_id)
		viewport.add_child(model)
		_frame(camera, model)
		for frame in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var source := viewport.get_texture().get_image()
		var occupied := _opaque_bounds(source)
		if occupied.size.x <= 0 or occupied.size.y <= 0:
			push_error("Inventory thumbnail is blank: " + item_id)
			failed = true
		else:
			var pixels := _thumbnail(source, occupied)
			var result := pixels.save_png(OUTPUT + item_id + ".png")
			print("INVENTORY_ITEM_RENDER ", item_id, " source_bounds=", occupied, " size=", pixels.get_size(), " error=", result)
			failed = failed or result != OK
		model.queue_free()
		await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failed else 0)

func _item_ids() -> Array:
	return ITEMS

func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	return viewport

func _frame(camera: Camera3D, model: Node3D) -> void:
	var points: Array[Vector3] = []
	_mesh_corners(model, points)
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	var center := bounds.get_center()
	camera.position = center + Vector3(0.75, 0.65, 1.0).normalized() * 12.0
	camera.look_at(center)
	var projected := AABB(camera.global_transform.affine_inverse() * points[0], Vector3.ZERO)
	for point in points: projected = projected.expand(camera.global_transform.affine_inverse() * point)
	camera.size = maxf(projected.size.x, projected.size.y) * 1.15
	var offset := projected.get_center()
	camera.position += camera.global_basis * Vector3(offset.x, offset.y, 0)

func _mesh_corners(node: Node3D, points: Array[Vector3]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var bounds := (node as MeshInstance3D).get_aabb()
		for index in 8: points.append(node.global_transform * bounds.get_endpoint(index))
	for child in node.get_children():
		if child is Node3D: _mesh_corners(child, points)

func _opaque_bounds(pixels: Image) -> Rect2i:
	var minimum := pixels.get_size()
	var maximum := Vector2i(-1, -1)
	for y in pixels.get_height():
		for x in pixels.get_width():
			if pixels.get_pixel(x, y).a <= 0.02: continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _thumbnail(source: Image, bounds: Rect2i) -> Image:
	var cropped := source.get_region(bounds)
	var factor := 224.0 / maxf(bounds.size.x, bounds.size.y)
	cropped.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_LANCZOS)
	cropped.convert(Image.FORMAT_RGBA8)
	var result := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var origin := Vector2i((256 - cropped.get_width()) / 2, (256 - cropped.get_height()) / 2)
	result.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), origin)
	return result

func _model(item_id: String) -> Node3D:
	if item_id in Decorations.IDS: return Decorations._prop(item_id)
	if item_id == "stone": return _stone_bundle()
	if item_id == "copper_ore": return _copper_ore()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match item_id:
		"wood": _wood(surface)
		"fiber": _reeds(surface)
		"rock_salt": _salt(surface)
		"hand_tools": _hand_tools(surface)
		"row_tool": _row_tool(surface)
	return _mesh(surface, item_id)

func _mesh(surface: SurfaceTool, node_name: String) -> MeshInstance3D:
	surface.index()
	var result := MeshInstance3D.new()
	result.name = node_name.to_pascal_case()
	result.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	result.material_override = material
	return result

func _wood(surface: SurfaceTool) -> void:
	for center in [Vector3(-0.20, 0.18, 0), Vector3(0.20, 0.18, -0.07), Vector3(0, 0.49, -0.035)]:
		var rotation := Basis(Vector3.RIGHT, PI * 0.5)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.18
		cylinder.bottom_radius = 0.18
		cylinder.height = 0.88
		cylinder.radial_segments = 10
		Scenery._append(surface, cylinder, Transform3D(rotation, center), BARK)
		for side in [-1.0, 1.0]:
			cylinder.top_radius = 0.15
			cylinder.bottom_radius = 0.15
			cylinder.height = 0.008
			Scenery._append(surface, cylinder, Transform3D(rotation, center + Vector3(0, 0, side * 0.444)), Scenery.WOOD.lightened(0.23))
			cylinder.top_radius = 0.09
			cylinder.bottom_radius = 0.09
			Scenery._append(surface, cylinder, Transform3D(rotation, center + Vector3(0, 0, side * 0.449)), Scenery.WOOD)
			cylinder.top_radius = 0.055
			cylinder.bottom_radius = 0.055
			Scenery._append(surface, cylinder, Transform3D(rotation, center + Vector3(0, 0, side * 0.453)), Scenery.WOOD.lightened(0.23))

func _stone_bundle() -> Node3D:
	var root := Node3D.new()
	var points := [Vector3(-0.19, 0, 0.12), Vector3(0.22, 0, -0.01), Vector3(0, 0.18, -0.10)]
	for index in points.size():
		var rock := Art.instance("rock", points[index], 2.1 - index * 0.25)
		rock.rotation.y = index * 1.7
		root.add_child(rock)
	return root

func _copper_ore() -> Node3D:
	var root := Node3D.new()
	var rock := Art.instance("rock", Vector3.ZERO, 3.0)
	rock.rotation.y = 1.0
	root.add_child(rock)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spec in [Vector3(-0.30, 0.60, 0.32), Vector3(0.04, 0.86, 0.14), Vector3(0.30, 0.50, 0.36), Vector3(-0.17, 0.83, -0.05)]:
		Scenery._oval(surface, Vector3(0.24, 0.17, 0.17), spec, COPPER, Basis(Vector3.UP, spec.x * 2.0))
		Scenery._oval(surface, Vector3(0.13, 0.06, 0.13), spec + Vector3(0.02, 0.08, 0.01), COPPER.lightened(0.22))
	root.add_child(_mesh(surface, "CopperVeins"))
	return root

func _reeds(surface: SurfaceTool) -> void:
	for index in 9:
		var x := (index % 3 - 1) * 0.085
		var z := (index / 3 - 1) * 0.075
		var base := Vector3(x * 0.7, 0.03, z)
		var top := Vector3(x * 1.8, 0.84 + sin(index * 2.0) * 0.12, z * 1.6)
		Scenery._beam(surface, base, top, 0.037, Scenery.LEAF.lightened(0.08 if index % 2 == 0 else 0.24))
		var leaf_center := base.lerp(top, 0.66) + Vector3(0.08 if index % 2 == 0 else -0.08, 0.03, 0)
		Scenery._oval(surface, Vector3(0.08, 0.31, 0.035), leaf_center, Scenery.LEAF, Basis(Vector3.BACK, -0.6 if index % 2 == 0 else 0.6))
		Scenery._oval(surface, Vector3(0.052, 0.17, 0.052), top, Scenery.WOOD.lightened(0.18))
	for y in [0.27, 0.34]:
		Scenery._box(surface, Vector3(0.27, 0.035, 0.27), Vector3(0, y, 0), Scenery.WOOD)

func _salt(surface: SurfaceTool) -> void:
	var centers := [Vector3(-0.21, 0.17, 0.08), Vector3(0.18, 0.15, 0.10), Vector3(0.02, 0.34, -0.05), Vector3(0.26, 0.08, -0.16)]
	for index in centers.size():
		var size := Vector3.ONE * (0.34 if index < 3 else 0.20)
		var basis := Basis.from_euler(Vector3(0.12 + index * 0.09, index * 0.42, -0.20 + index * 0.19))
		Scenery._box(surface, size, centers[index], Color("e5eee8") if index % 2 == 0 else Color("cbdedb"), basis)
		Scenery._box(surface, size * Vector3(0.74, 0.04, 0.74), centers[index] + basis * Vector3(0, size.y * 0.52, 0), Scenery.PAPER, basis)

func _hand_tools(surface: SurfaceTool) -> void:
	var trowel_basis := Basis(Vector3.BACK, -0.30)
	var rake_basis := Basis(Vector3.BACK, 0.23)
	var trowel_origin := Vector3(-0.18, 0.10, 0.08)
	var rake_origin := Vector3(0.18, 0.10, -0.08)
	for spec in [[trowel_origin, trowel_basis], [rake_origin, rake_basis]]:
		var origin: Vector3 = spec[0]
		var basis: Basis = spec[1]
		Scenery._box(surface, Vector3(0.075, 0.47, 0.075), origin + basis * Vector3(0, 0.57, 0), Scenery.WOOD, basis)
		Scenery._box(surface, Vector3(0.09, 0.10, 0.09), origin + basis * Vector3(0, 0.36, 0), METAL, basis)
	Scenery._oval(surface, Vector3(0.25, 0.38, 0.06), trowel_origin + trowel_basis * Vector3(0, 0.17, 0), METAL.lightened(0.22), trowel_basis)
	Scenery._box(surface, Vector3(0.028, 0.22, 0.018), trowel_origin + trowel_basis * Vector3(0, 0.19, 0.04), METAL.lightened(0.42), trowel_basis)
	Scenery._box(surface, Vector3(0.30, 0.07, 0.07), rake_origin + rake_basis * Vector3(0, 0.26, 0), METAL, rake_basis)
	for x in [-0.12, 0.0, 0.12]:
		Scenery._box(surface, Vector3(0.045, 0.23, 0.06), rake_origin + rake_basis * Vector3(x, 0.12, 0), METAL.lightened(0.20), rake_basis)

func _row_tool(surface: SurfaceTool) -> void:
	Scenery._beam(surface, Vector3(0, 0.22, 0), Vector3(0, 1.06, -0.10), 0.075, Scenery.WOOD)
	Scenery._box(surface, Vector3(0.32, 0.065, 0.085), Vector3(0, 1.05, -0.10), Scenery.GREEN)
	Scenery._box(surface, Vector3(0.70, 0.09, 0.10), Vector3(0, 0.25, 0), METAL)
	Scenery._box(surface, Vector3(0.10, 0.16, 0.12), Vector3(0, 0.34, 0), Scenery.GREEN)
	for x in [-0.27, 0.0, 0.27]:
		Scenery._beam(surface, Vector3(x, 0.24, 0), Vector3(x, 0.06, 0.21), 0.085, METAL.lightened(0.18))
		Scenery._box(surface, Vector3(0.10, 0.045, 0.20), Vector3(x, 0.035, 0.26), METAL.lightened(0.27))

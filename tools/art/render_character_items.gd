extends "res://tools/art/render_inventory_items.gd"

func _item_ids() -> Array:
	return ["copper_pickaxe", "foraging_gloves", "artisan_apron"]

func _model(item_id: String) -> Node3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	match item_id:
		"copper_pickaxe": _pickaxe(surface)
		"foraging_gloves": _gloves(surface)
		"artisan_apron": _apron(surface)
	return _mesh(surface, item_id)

func _pickaxe(surface: SurfaceTool) -> void:
	Scenery._beam(surface, Vector3(-0.12, 0.04, 0), Vector3(0.06, 1.15, 0), 0.085, Scenery.WOOD)
	Scenery._beam(surface, Vector3(-0.12, 0.04, 0), Vector3(-0.08, 0.29, 0), 0.10, Scenery.GREEN)
	Scenery._box(surface, Vector3(0.19, 0.18, 0.16), Vector3(0.04, 1.05, 0), COPPER.darkened(0.15))
	for side in [-1, 1]:
		var center := Vector3(0.04, 1.08, 0)
		var elbow := center + Vector3(side * 0.24, -0.04, 0)
		var tip := center + Vector3(side * 0.52, -0.21, 0)
		Scenery._beam(surface, center, elbow, 0.13, COPPER)
		var tooth := CylinderMesh.new()
		tooth.top_radius = 0.008
		tooth.bottom_radius = 0.085
		tooth.height = elbow.distance_to(tip)
		tooth.radial_segments = 4
		var rotation := Basis(Quaternion(Vector3.UP, (tip - elbow).normalized()))
		Scenery._append(surface, tooth, Transform3D(rotation, (tip + elbow) * 0.5), COPPER.lightened(0.12))

func _gloves(surface: SurfaceTool) -> void:
	for side in [-1, 1]:
		var origin := Vector3(side * 0.24, 0, side * 0.03)
		var basis := Basis(Vector3.BACK, side * -0.12)
		var leather := Color("c7d8a5")
		Scenery._box(surface, Vector3(0.30, 0.18, 0.10), origin + basis * Vector3(0, 0.12, 0), Scenery.GREEN, basis)
		Scenery._oval(surface, Vector3(0.34, 0.35, 0.12), origin + basis * Vector3(0, 0.37, 0), leather, basis)
		for finger in 4:
			var length := 0.25 - absf(finger - 1.5) * 0.025
			var x := (finger - 1.5) * 0.075
			Scenery._oval(surface, Vector3(0.075, length, 0.09), origin + basis * Vector3(x, 0.59, 0), leather, basis)
		var thumb_basis := basis * Basis(Vector3.BACK, side * -0.65)
		Scenery._oval(surface, Vector3(0.11, 0.23, 0.10), origin + basis * Vector3(side * 0.19, 0.37, 0), leather, thumb_basis)
		Scenery._box(surface, Vector3(0.20, 0.10, 0.025), origin + basis * Vector3(0, 0.37, 0.075), leather.darkened(0.12), basis)

func _apron(surface: SurfaceTool) -> void:
	var cloth := Color("658eaa")
	var trim := Color("d8e8eb")
	Scenery._box(surface, Vector3(0.68, 0.50, 0.07), Vector3(0, 0.28, 0), cloth)
	Scenery._box(surface, Vector3(0.44, 0.36, 0.065), Vector3(0, 0.67, 0), cloth)
	Scenery._box(surface, Vector3(0.68, 0.035, 0.075), Vector3(0, 0.035, 0), trim)
	for x in [-0.18, 0.18]:
		Scenery._beam(surface, Vector3(x, 0.80, 0), Vector3(x * 0.65, 1.00, -0.04), 0.055, trim)
	Scenery._beam(surface, Vector3(-0.117, 1, -0.04), Vector3(0.117, 1, -0.04), 0.055, trim)
	Scenery._box(surface, Vector3(0.77, 0.045, 0.08), Vector3(0, 0.49, 0), trim)
	Scenery._box(surface, Vector3(0.40, 0.19, 0.045), Vector3(0, 0.29, 0.06), cloth.darkened(0.13))
	Scenery._box(surface, Vector3(0.41, 0.025, 0.05), Vector3(0, 0.39, 0.065), trim)
	Scenery._box(surface, Vector3(0.02, 0.16, 0.05), Vector3(0, 0.29, 0.067), trim)
	Scenery._beam(surface, Vector3(0.08, 0.38, 0.07), Vector3(0.12, 0.60, 0.07), 0.033, Scenery.WOOD)

extends RefCounted

const Scenery = preload("res://modules/farm/place_scenery.gd")

static func model(id: String) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if id == "trail_boots":
		for side in [-1, 1]:
			var origin := Vector3(side * 0.24, 0, 0)
			Scenery._box(surface, Vector3(0.32, 0.1, 0.62), origin + Vector3(0, 0.06, 0.12), Color("394849"))
			Scenery._oval(surface, Vector3(0.32, 0.28, 0.55), origin + Vector3(0, 0.18, 0.15), Color("6989a0"))
			Scenery._box(surface, Vector3(0.29, 0.48, 0.3), origin + Vector3(0, 0.41, -0.04), Color("6989a0"))
			Scenery._box(surface, Vector3(0.33, 0.08, 0.33), origin + Vector3(0, 0.66, -0.04), Color("d9e2cf"))
			for y in [0.25, 0.34, 0.43]:
				Scenery._box(surface, Vector3(0.2, 0.022, 0.025), origin + Vector3(0, y, 0.13), Color("e5d09b"))
	elif id in ["hand_tools", "row_tool", "copper_pickaxe", "copper_axe"]:
		Scenery._box(surface, Vector3(0.075, 0.85, 0.075), Vector3(0, 0.42, 0), Color("997248"))
		var metal := Color("c99a70") if id.begins_with("copper") else Color("a0b9b7")
		if id == "copper_pickaxe":
			Scenery._beam(surface, Vector3(-0.35, 0.72, 0), Vector3(0.35, 0.72, 0), 0.08, metal)
		elif id == "copper_axe":
			Scenery._box(surface, Vector3(0.34, 0.26, 0.065), Vector3(0.14, 0.72, 0), metal)
		else:
			Scenery._box(surface, Vector3(0.25 if id == "hand_tools" else 0.45, 0.08, 0.2), Vector3(0, 0.72, 0.07), metal)
	else:
		var copper := id in ["copper_sword", "copper_knife"]
		var blade := Color("c99a70") if copper else Color("a0b9b7")
		Scenery._box(surface, Vector3(0.11, 0.25, 0.10), Vector3(0, 0.17, 0), Color("537969"))
		Scenery._box(surface, Vector3(0.17, 0.09, 0.14), Vector3(0, 0.04, 0), Color("d8c499"))
		Scenery._box(surface, Vector3(0.52, 0.09, 0.14), Vector3(0, 0.32, 0), Color("d8c499"))
		var length := 0.46 if id == "copper_knife" else 0.94 if copper else 0.73
		Scenery._box(surface, Vector3(0.16, length, 0.065), Vector3(0, 0.35 + length * 0.5, 0), blade)
		Scenery._box(surface, Vector3(0.035, length, 0.072), Vector3(-0.02, 0.35 + length * 0.5, 0), blade.lightened(0.28))
		var tip := CylinderMesh.new()
		tip.top_radius = 0
		tip.bottom_radius = 0.115
		tip.height = 0.2
		tip.radial_segments = 4
		Scenery._append(surface, tip, Transform3D(Basis.from_scale(Vector3(1, 1, 0.42)), Vector3(0, 0.45 + length, 0)), blade)
	surface.index()
	var result := MeshInstance3D.new()
	result.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.55
	result.material_override = material
	return result

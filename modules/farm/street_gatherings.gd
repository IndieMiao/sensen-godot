class_name StreetGatherings
extends RefCounted

static func build(theme: String, state: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Gathering_" + theme
	var hosted := JourneyGatherings.current(state) == theme
	root.set_meta("hosted", hosted)
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := PlaceScenery
	p._cylinder(s, 3.25, 0.06, Vector3(0, 0.015, 0), p.STONE, Vector3.ONE, 32)
	p._cylinder(s, 3.0, 0.02, Vector3(0, 0.055, 0), Color("b8cfbb"), Vector3.ONE, 32)
	p._box(s, Vector3(1.5, 0.1, 0.95), Vector3(0, 0.9, 0), p.WOOD)
	for x in [-0.58, 0.58]:
		for z in [-0.32, 0.32]: p._box(s, Vector3(0.09, 0.85, 0.09), Vector3(x, 0.45, z), p.GREEN)
	if hosted:
		p._box(s, Vector3(1.52, 0.015, 0.7), Vector3(0, 0.96, 0), p.BLUE if theme == "lantern" else p.PAPER)
		for x in [-0.5, 0.5]:
			p._cylinder(s, 0.18, 0.025, Vector3(x, 0.98, 0.04), p.PAPER)
			if theme == "garden":
				p._cylinder(s, 0.09, 0.13, Vector3(x, 1.05, 0.04), p.CORAL)
				p._cylinder(s, 0.07, 0.005, Vector3(x, 1.119, 0.04), p.WOOD.darkened(0.3))
			else:
				p._plants(s, "L", [Vector3(x, 1.0, 0.04)], 0.22)
				p._oval(s, Vector3(0.09, 0.055, 0.08), Vector3(x + 0.06, 1.05, 0.08), p.CORAL)
	s.index()
	var mesh := MeshInstance3D.new()
	mesh.name = "GatheringTable"
	mesh.mesh = s.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.material_override = material
	root.add_child(mesh)
	if hosted:
		var piece := DecorationLayout._prop(str(JourneyGatherings.themes()[theme].item))
		piece.name = "RetainedPiece"
		piece.position = Vector3(0, 0.97, -0.08)
		piece.scale = Vector3.ONE * 0.7
		root.add_child(piece)
	return root

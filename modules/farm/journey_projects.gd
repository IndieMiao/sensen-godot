class_name JourneyProjects
extends RefCounted

static func discovery_position(id: String) -> Vector3:
	var position: Array = JourneyProgress.data().discoveries[id].position
	return Vector3(float(position[0]), 0.02, float(position[1]))

static func discovery_choices(id: String, state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not JourneyProgress.fact(state, "discovery_" + id): return result
	var choices: Dictionary = JourneyProgress.data().discoveries[id].choices
	for index in choices.size():
		var choice := str(choices.keys()[index])
		var reward: Dictionary = choices[choice]
		if reward.has("requires") and not JourneyProgress.unlocked(state, str(reward.requires)): continue
		result.append({"id": "harvest:%s:%s" % [id, choice], "discovery": id, "choice": choice, "reward": reward,
			"position": discovery_position(id) + Vector3((index - 0.5) * 1.9, 0, -0.2)})
	return result

static func build_discovery(id: String, state: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Discovery_" + id
	root.position = discovery_position(id)
	var restored := JourneyProgress.fact(state, "discovery_" + id)
	var ready := JourneyProgress.discovery_harvest_ready(state, id)
	root.set_meta("restored", restored)
	root.set_meta("harvest_ready", ready)
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := PlaceScenery
	match id:
		"stone_hollow":
			for side in [-1.0, 1.0]:
				p._oval(s, Vector3(0.45, 0.65, 0.6), Vector3(side * 0.4, 0.32, -0.3), p.STONE.darkened(0.2))
			p._box(s, Vector3(1.25, 0.18, 0.6), Vector3(0, 0.68, -0.3), p.STONE)
			if not restored:
				p._beam(s, Vector3(-0.5, 0.1, 0.25), Vector3(0.5, 0.3, 0.2), 0.12, p.WOOD)
		"reed_garden":
			p._planter(s, Vector3(0.15, 0, -0.1), Vector2(1.05, 0.8), p.GREEN if restored else p.STONE)
		"kitchen_garden":
			p._planter(s, Vector3(0, 0, -0.18), Vector2(1.15, 0.7), p.BLUE if restored else p.STONE)
			if restored: p._box(s, Vector3(0.12, 0.02, 0.65), Vector3(0, 0.09, 0.15), p.BLUE.lightened(0.2))
	s.index()
	var mesh := MeshInstance3D.new()
	mesh.mesh = s.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.material_override = material
	root.add_child(mesh)
	if restored:
		var piece := DecorationLayout._prop(str(JourneyProgress.data().discoveries[id].item))
		piece.name = "InstalledPiece"
		piece.position = Vector3(0, 0.77, -0.3) if id == "stone_hollow" else Vector3(0, 0, 0.45)
		piece.scale = Vector3.ONE * (0.9 if id == "stone_hollow" else 0.65)
		root.add_child(piece)
	for choice in discovery_choices(id, state):
		var tray := _harvest_tray(choice.reward, ready)
		tray.name = "Harvest_" + str(choice.choice)
		tray.position = choice.position - root.position
		tray.set_meta("harvest_ready", ready)
		root.add_child(tray)
	return root

static func _harvest_tray(reward: Dictionary, ready: bool) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := PlaceScenery
	p._planter(surface, Vector3.ZERO, Vector2(0.7, 0.6), p.WOOD)
	if ready:
		for material in reward.materials:
			for i in mini(3, int(reward.materials[material])):
				var offset := Vector3(-0.22 + i * 0.22, 0.35, 0)
				match material:
					"stone": p._oval(surface, Vector3(0.25, 0.24, 0.3), offset, p.STONE)
					"wood": p._beam(surface, offset + Vector3(0, 0, -0.22), offset + Vector3(0, 0, 0.22), 0.12, p.WOOD.darkened(0.25))
					"fiber":
						p._beam(surface, offset, offset + Vector3(-0.04, 0.48, 0.07), 0.045, p.LEAF)
		for index in reward.produce.size():
			var crop := str(reward.produce.keys()[index])
			var position := Vector3((index - (reward.produce.size() - 1) * 0.5) * 0.36, 0.52, 0)
			p._plants(surface, crop, [position], 0.6)
			if crop == "C":
				var root := p.CropPlantMesh.build("C_detail", Color(0.95, 0.43, 0.15))
				p._append(surface, root, Transform3D(Basis.from_scale(Vector3.ONE * 0.6), position), Color.WHITE, true)
		for crop in reward.seeds:
			for index in mini(2, int(reward.seeds[crop])):
				var offset := Vector3(-0.15 + index * 0.3, 0.32, 0)
				p._box(surface, Vector3(0.24, 0.05, 0.36), offset, p.PAPER)
				p._oval(surface, Vector3(0.12, 0.025, 0.18), offset + Vector3(0, 0.04, 0), p.LEAF)
	surface.index()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.material_override = material
	return mesh

static func display_position(id: String, slot: int) -> Vector3:
	# The outer edge stays clear of canopies, tables and the courtyard arrangement area.
	return Vector3(3.8 if id == "terrace" else -3.8, 0.02, 0.75 - slot * 0.65)

static func build(id: String, state: Dictionary) -> MeshInstance3D:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stage := JourneyProgress.project_stage(state, id)
	var p := PlaceScenery
	match id:
		"seedbeds":
			for side in [-1.0, 1.0]:
				p._planter(s, Vector3(side * 0.4, 0, 0), Vector2(0.65, 0.95), p.STONE if stage == 0 else p.BLUE)
				if stage > 0:
					p._beam(s, Vector3(side * 0.72, 0, -0.4), Vector3(side * 0.72, 1.55, -0.4), 0.07, p.WOOD)
				if stage > 1:
					p._plants(s, "L", [Vector3(side * 0.4, 0.34, -0.2), Vector3(side * 0.4, 0.34, 0.2)], 0.55)
			if stage > 1:
				p._box(s, Vector3(1.7, 0.05, 1.05), Vector3(0, 1.58, -0.05), p.BLUE.lightened(0.3))
				if not state.journey.exploration.collected.has("seedbeds"):
					p._pot(s, Vector3(0, 0, 0.8), 0.22, p.CORAL)
		"terrace":
			if stage == 0:
				for i in 3: p._box(s, Vector3(1.1, 0.08, 0.15), Vector3(0, 0.09 + i * 0.08, 0), p.WOOD)
			else:
				for side in [-1.0, 1.0]:
					p._beam(s, Vector3(side, 0, -0.5), Vector3(side, 2.4, -0.5), 0.09, p.GREEN)
				for i in 7:
					p._box(s, Vector3(0.32, 0.04, 1.6), Vector3(-0.96 + i * 0.32, 2.42, 0), p.PAPER if i % 2 == 0 else p.CORAL)
				if stage > 1:
					p._box(s, Vector3(0.9, 0.015, 0.7), Vector3(0, 0.92, 0), p.BLUE)
					for x in [-0.3, 0.3]:
						p._cylinder(s, 0.11, 0.12, Vector3(x, 1.0, 0), p.PAPER)
		"waystation":
			p._box(s, Vector3(1.8, 0.08, 1.15), Vector3(0, 0.04, 0), p.SOIL if stage == 0 else p.STONE)
			if stage > 0:
				for side in [-1.0, 1.0]:
					p._box(s, Vector3(0.12, 1.5, 0.12), Vector3(side * 0.78, 0.75, -0.38), p.WOOD)
				p._box(s, Vector3(1.8, 0.1, 0.55), Vector3(0, 1.5, -0.38), p.GREEN)
			if stage > 1:
				for side in [-1.0, 1.0]:
					p._pot(s, Vector3(side * 0.78, 0.9, -0.38), 0.19, p.CORAL)
					p._plants(s, "H", [Vector3(side * 0.78, 1.2, -0.38)], 0.45)
	s.index()
	var mesh := MeshInstance3D.new()
	mesh.name = "Project_" + id
	mesh.mesh = s.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.material_override = material
	var pos: Array = JourneyProgress.data().projects[id].position
	mesh.position = Vector3(float(pos[0]), 0.02, float(pos[1]))
	mesh.set_meta("project_stage", stage)
	return mesh

class_name StreetCommons
extends RefCounted

const PLACES := {"nursery": "nursery", "restorer": "courtyard", "bistro": "bistro"}
const RESIDENTS := {"nursery": "nursery_keeper", "restorer": "restorer", "bistro": "bistro_owner"}
const NAMES := {"nursery": "Nursery walk", "restorer": "Repair corner", "bistro": "Street table"}
const EFFECTS := {"leaves": "Leaf beds", "flowers": "Flower pots", "benches": "Rest corner",
	"baskets": "Harvest stand", "picnic": "Lunch table", "tea": "Tea service"}

static func count(state: Dictionary, effect: String) -> int:
	return clampi(int(state.get("journey", {}).get("contributions", {}).get(effect, 0)), 0, int(JourneyProgress.data().contribution_steps))

static func progress(state: Dictionary, effect: String) -> String:
	return L10n.format_text("%s %d/%d", [EFFECTS.get(effect, L10n.text("Street garden")), count(state, effect), int(JourneyProgress.data().contribution_steps)])

static func available(state: Dictionary, slot: String) -> bool:
	return slot != "bistro" or JourneyProgress.fact(state, "shared_meal")

static func build(slot: String, state: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Common_" + slot
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := PlaceScenery
	p._box(s, Vector3(3.4, 0.08, 2.6), Vector3(0, -0.025, 0), p.STONE)
	match slot:
		"nursery":
			for index in 3:
				var x := (index - 1) * 1.05
				p._planter(s, Vector3(x, 0.04, -0.45), Vector2(0.83, 0.86), p.BLUE)
				if index < count(state, "leaves"): p._plants(s, "L", [Vector3(x, 0.54, -0.45)], 0.8)
				if index < count(state, "flowers"):
					p._pot(s, Vector3(x, 0.04, 0.6), 0.3, p.CORAL)
					p._plants(s, "H", [Vector3(x, 0.62, 0.6)], 0.75)
		"restorer":
			var benches := count(state, "benches")
			if benches > 0: p._bench(s, Vector3(0, 0.04, -0.4), p.CORAL)
			else:
				for index in 3: p._box(s, Vector3(1.8, 0.12, 0.18), Vector3(0, 0.12 + index * 0.12, -0.4), p.WOOD)
			for index in maxi(0, benches - 1):
				p._pot(s, Vector3(-1.25 + index * 2.5, 0.04, -0.65), 0.25, p.BLUE)
				p._plants(s, "H", [Vector3(-1.25 + index * 2.5, 0.58, -0.65)], 0.6)
			for index in count(state, "baskets"):
				var x := (index - 1) * 0.75
				p._planter(s, Vector3(x, 0.04, 0.68), Vector2(0.6, 0.55), p.WOOD)
				p._plants(s, "R", [Vector3(x, 0.55, 0.68)], 0.6)
		"bistro":
			var lunches := count(state, "picnic")
			var teas := count(state, "tea")
			if lunches + teas == 0:
				p._box(s, Vector3(1.8, 0.12, 0.8), Vector3(0, 0.15, 0), p.WOOD)
			else:
				p._box(s, Vector3(1.9, 0.12, 1.2), Vector3(0, 0.88, 0), p.WOOD)
				for x in [-0.75, 0.75]:
					for z in [-0.4, 0.4]: p._box(s, Vector3(0.09, 0.82, 0.09), Vector3(x, 0.41, z), p.GREEN)
				for index in lunches:
					var point := Vector3(-0.45 + index * 0.45, 0.965, -0.25)
					p._cylinder(s, 0.18, 0.05, point, p.PAPER)
					p._plants(s, "L", [point + Vector3(0, 0.05, 0)], 0.23)
				for index in teas:
					p._cylinder(s, 0.1, 0.14, Vector3(-0.4 + index * 0.4, 1.01, 0.3), p.BLUE)
				if teas > 0:
					p._oval(s, Vector3(0.32, 0.24, 0.28), Vector3(0, 1.1, 0), p.CORAL)
	s.index()
	var mesh := MeshInstance3D.new()
	mesh.mesh = s.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	mesh.material_override = material
	root.add_child(mesh)
	return root

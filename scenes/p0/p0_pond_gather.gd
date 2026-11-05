extends Node3D
## Gathering at a pond (SGODOT-410, v4q(11); 后裔's 409: view.gather.pond {pond, shape, points: [{id, slot, kind, name,
## yield, energy, x, z, stand, ready_in}]}, null away from it). Each point a piece on the bank where the server puts it —
## Timber, Stone and Wild Herb from the farm kit's old spot pieces (P0SpotArt's grove, rock pile and herb patch, farm-dev),
## Reeds, Clay, Hardwood and Flax from 上官婉儿's (#782). The nearest one alone has its name
## bar (the item's name; cooling: dimmed, `Ready in 3h 12m`, 不知火舞 on 410); within REACH_M of its stand the main key
## turns to `Gather · 3 Energy` — grey `Ready in …` / `Bag full` (its toast `No room · free a slot first`), amber `Need 3
## Energy` (D2's words) — and back to Cast away from it. The host sends the key's command and plays the gather clip.

const Art = preload("res://modules/farm/farm_art.gd")
const CropMesh = preload("res://modules/farm/crop_plant_mesh.gd")
const P0MaterialLogic := preload("res://modules/p0/p0_material_logic.gd")
const REACH_M := 1.0      # from the point's stand: the key is Gather
const TAG_M := 8.0        # the nearest point within this has its name bar
const CLEAR_M := 1.5      # the bank's trees and bushes keep this far off a point (pond_slots_v2 _doc.scenery_clearance)
## The pieces by kind (上官婉儿, 410 924d6611); the four new ones are farm-kit glbs (Art.instance), the rest are built.
const PIECES := {"wood": "grove", "stone": "rock_pile", "herb": "herb_patch", "reed": "reed_bank", "clay": "clay_pit",
	"hardwood": "hardwood_grove", "flax": "flax_patch"}
const GROVE_TREES := [[Vector3(0.5, 0, -0.35), "tree_1", 0.78], [Vector3(-0.35, 0, 0.2), "tree_2", 0.7], [Vector3(0.55, 0, 0.6), "tree_1", 0.66]]

var pond := ""
var points: Array = []
var nodes := {}   # point id → its piece

## The pond's points as the view has them now (ready_in counted down by P0Logic.project); the pieces built once.
func sync(view: Dictionary) -> void:
	var g = view.get("gather", {}).get("pond", null) if view.get("gather") is Dictionary else null
	points = (g.get("points", []) as Array) if g is Dictionary and g.get("points") is Array else []
	pond = str(g.get("pond", "")) if g is Dictionary else ""
	for p in points:
		if not nodes.has(str(p.id)): nodes[str(p.id)] = _piece(p)

func _piece(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Gather_" + str(p.get("slot", p.id))
	root.position = Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0)))
	add_child(root)
	match str(PIECES.get(str(p.get("kind", "")), "")):
		"grove":
			for t in GROVE_TREES:
				var tree := Art.instance(str(t[1]), t[0], float(t[2]))
				tree.rotation.y = float(t[0].x) * 2.1
				root.add_child(tree)
		"rock_pile": _rocks(root)
		"herb_patch":
			root.add_child(Art.instance("bush", Vector3(0.0, 0, -0.35), 0.62))
			var herb := CropMesh.build("B", CropMesh.LEAF)
			for at in [Vector3(-0.28, 0, 0.12), Vector3(0.24, 0, 0.18), Vector3(0.02, 0, 0.36)]:
				var h := MeshInstance3D.new()
				h.mesh = herb
				h.material_override = Art.material()
				h.position = at
				h.scale = Vector3.ONE * 1.25
				root.add_child(h)
		var asset:
			if asset != "": root.add_child(Art.instance(asset))
	return root

static func _rocks(root: Node3D) -> void:
	for r in [[Vector3(0, 0, 0), 1.55, 0.0], [Vector3(0.38, 0, 0.22), 1.2, 1.7], [Vector3(-0.32, 0, 0.18), 1.05, 3.1],
			[Vector3(0.12, 0, -0.34), 1.3, 4.4], [Vector3(-0.1, 0.18, 0.02), 0.85, 2.2]]:
		var m := Art.instance("rock", r[0], float(r[1]))
		m.rotation.y = float(r[2])
		root.add_child(m)

## Where a point's stand is (where the key turns to Gather), else the point itself.
static func stand_of(p: Dictionary) -> Vector3:
	var s = p.get("stand", null)
	return Vector3(float(s[0]), 0, float(s[1])) if s is Array and s.size() >= 2 else Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0)))

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## The point nearest `at` (by its stand), {} with none.
static func nearest(list: Array, at: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for p in list:
		var d := _flat(stand_of(p), at)
		if d < best_d:
			best_d = d
			best = p
	return best

## The main key at a point within reach (D2's words and order: cooling, then Energy, then the bag).
static func key(view: Dictionary, p: Dictionary, pond_id: String) -> Dictionary:
	var cost := int(p.get("energy", 3))
	var yields: Array = p.get("yield", [])
	var main: Array = yields[0] if not yields.is_empty() else ["", 0]
	var a := {"icon": str(main[0]), "verb": "Gather", "sub": "%d Energy" % cost, "enabled": true, "amber": false,
		"cmd": {"type": "gather", "spot": str(p.get("id", "")), "space": "pond", "place": pond_id}, "need": cost}
	var ready := float(p.get("ready_in", 0))
	if ready > 0.0:
		a.sub = "Ready in %s" % P0Logic.span(ready)
		a.enabled = false
		a.cmd = {}
	elif int(view.get("energy", {}).get("value", 0)) < cost:
		a.sub = "Need %d Energy" % cost
		a.amber = true
		a.cmd = {"type": "energy_card"}
	elif str(main[0]) != "" and P0MaterialLogic.bag_room(view, str(main[0])) < int(main[1]):
		a.sub = "Bag full"
		a.enabled = false
		a.cmd = {}
		a["toast"] = "No room · free a slot first"
	return a

## The name bar of a point: the item's name; cooling, dimmed with `Ready in …` (不知火舞 on 410: `Timber · Ready in 3h 12m`).
static func tag(view: Dictionary, p: Dictionary) -> Dictionary:
	var yields: Array = p.get("yield", [])
	var main := str(yields[0][0]) if not yields.is_empty() else ""
	var ready := float(p.get("ready_in", 0))
	return {"icon": main, "text": P0Logic.item_name(view, main), "fact": "Ready in %s" % P0Logic.span(ready) if ready > 0.0 else "",
		"dimmed": ready > 0.0}

## The points the bank's trees and bushes keep clear of (world xz), for PondScenery.build.
static func clear_points(view: Dictionary) -> Array:
	var g = view.get("gather", {}).get("pond", null) if view.get("gather") is Dictionary else null
	var out: Array = []
	if g is Dictionary and g.get("points") is Array:
		for p in g.points: out.append(Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0))))
	return out

## The point with this id, {} without.
func point(id: String) -> Dictionary:
	for p in points: if str(p.get("id", "")) == id: return p
	return {}

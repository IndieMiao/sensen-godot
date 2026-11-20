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
const PIECE_REACH_M := 1.5   # … or this near the piece itself: a stand on its far side (Pebble Pond's C1, by the water —
                             # 李元芳 on 422) is reached from the front too
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
	var kind := str(PIECES.get(str(p.get("kind", "")), ""))
	if PondScenery.V2 >= 6 and kind in ["grove", "hardwood_grove"]:   # 盘古's 422 v4 sample: the pack's trees, same reads
		_v4_piece(root, kind)
		if PondScenery.V2 >= 7: _feet(root, kind)
		return root
	if PondScenery.V2 >= 7 and kind == "rock_pile":
		_rocks(root)
		_feet(root, kind)
		return root
	match kind:
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
	if PondScenery.V2 in [1, 2, 3]:   # 盘古's 422 v2 sample: the painted ground draws a soft round shadow under each point instead
		for g in root.find_children("*", "GeometryInstance3D", true, false): (g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## v4 (the user 11-09: "树木换掉素材"; 奕星 / 上官婉儿: keep what reads as the point): Timber still three trees in a clump,
## Hardwood still a tree, a stump and a stack of logs — the pack's Tree_19 / Tree_15, Log_05, Log_01 / 02, about the old size.
## Still three in a clump, but opened toward the camera round the stand side (上官婉儿: no crown over the player at the
## stand — farm-dev's grove hid them whole at Fern's C1, (−0.12, −0.72) off the point): two to the right, one behind left.
static var GROVE_V6: String = OS.get_environment("P0_WILD_GROVE") if OS.get_environment("P0_WILD_GROVE") in ["A", "B"] else "A"
const V4_GROVE := [[Vector3(0.85, 0, -0.45), "pg_tree_19_g", 0.44], [Vector3(-0.9, 0, -1.3), "pg_tree_15_g", 0.4], [Vector3(1.15, 0, 0.55), "pg_tree_19_g", 0.42]]   # _g: +10 % saturation
static func _v4_piece(root: Node3D, kind: String) -> void:
	if kind == "grove":
		for t in V4_GROVE:
			# v6 (the user on v5, 530: "这个树换掉" — Fern's Timber, its Tree_19s by the spawn): A three layered pines (they
			# read as timber), B Tree_20; about the old 2.1 m (P0_WILD_GROVE, 上官婉儿 picks)
			var asset := str(t[1])
			var s := float(t[2])
			if PondScenery.V2 >= 8:
				asset = "pg_tree_20_g" if GROVE_V6 == "B" else "pg_pine_01_g"
				s = s / 0.44 * (0.47 if GROVE_V6 == "B" else 0.58)
			var at: Vector3 = t[0]
			if PondScenery.V2 >= 8 and GROVE_V6 == "A" and at.z > 0.0:   # the one nearest the stand: left-back a little, 10 % less (air by the player)
				at += Vector3(-0.25, 0, -0.2)
				s *= 0.9
			var tree := Art.instance(asset, at, s)
			tree.rotation.y = float(t[0].x) * 2.1
			root.add_child(tree)
		return
	# v6: Hardwood's tree no Tree_19 either (上官婉儿: no D near anywhere) — Tree_20, a broadleaf for the hardwood
	var tree := Art.instance("pg_tree_20_g" if PondScenery.V2 >= 8 else "pg_tree_19_g", Vector3(0.1, 0, -0.25), 0.52 if PondScenery.V2 >= 8 else 0.5)
	tree.rotation.y = 0.8
	root.add_child(tree)
	var stump := Art.instance("pg_log_05", Vector3(-0.5, 0, 0.3), 0.28)
	root.add_child(stump)
	for l in [[Vector3(0.35, 0, 0.42), "pg_log_01", 0.0], [Vector3(0.33, 0.13, 0.4), "pg_log_02", 0.25]]:
		var log := Art.instance(str(l[1]), l[0], 0.24)
		log.rotation = Vector3(0, PI * 0.5 + float(l[2]), 0)
		root.add_child(log)

## v5 (the user: grass where things meet the ground, the stones' and trees' feet most): blades round each trunk and round
## the stone pile, none on the stand's side within 0.45 m of it.
static func _feet(root: Node3D, kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(root.name)
	var bases: Array = []
	if kind == "grove":
		for t in V4_GROVE: bases.append([t[0], 0.35])
	elif kind == "hardwood_grove": bases = [[Vector3(0.1, 0, -0.25), 0.4], [Vector3(-0.5, 0, 0.3), 0.3], [Vector3(0.35, 0, 0.42), 0.35]]
	else: bases = [[Vector3.ZERO, 0.6]]
	var blades := ["pg_foot_leafy"]   # mid green, short, round (上官婉儿 on v5)
	var by := {}   # one MultiMesh a blade kind, not a node a blade (上官婉儿: draw calls)
	for b in bases:
		for k in rng.randi_range(4, 6):
			var at: Vector3 = b[0] + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * float(b[1]) * rng.randf_range(0.8, 1.25)
			var kind_b: String = blades[rng.randi() % blades.size()]
			if not by.has(kind_b): by[kind_b] = []
			by[kind_b].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.45, 0.7)), Vector3(at.x, -0.02, at.z)))
	for kind_b in by: root.add_child(Art.batch(kind_b, by[kind_b], false))

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

static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Whether `at` can gather `p`: within REACH_M of its stand, or PIECE_REACH_M of the piece (the server does not ask).
static func in_reach(p: Dictionary, at: Vector3) -> bool:
	if p.is_empty(): return false
	return flat(stand_of(p), at) <= REACH_M or flat(Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0))), at) <= PIECE_REACH_M

## The point nearest `at` (by its stand), {} with none.
static func nearest(list: Array, at: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for p in list:
		var d := flat(stand_of(p), at)
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

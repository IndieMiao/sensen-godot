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

var pond := ""
var points: Array = []
var nodes := {}   # point id → its piece: a Live layer, a Gathered layer, the feet's blades under both
## C67 (SGODOT-417; the user 11-10 bot 682 "C67 ok"): a point cooling shows its gathered look — 410 924d6611: the piece
## hidden, its gathered one shown, back when it is ready, no transition; the name bar, the tap and the stand unchanged;
## the feet's blades stay. Reeds, Clay, Flax and Stone are 黄忠's <kind>_gathered.glb (417, wp-3d-scene 431fb759);
## Timber, Hardwood and Wild Herb are built here from the pack pieces they are made of (上官婉儿 / 不知火舞, 417
## af31871a, a956cb00). Dev (shots): P0_GATHER_COOL = all | kinds or slots, comma-separated, reads those points as
## cooling COOL_MS, in the editor binary only (cool_switch: an exported build ignores it, as P0BlackjackMock).
const COOL_MS := 11520000.0   # 3h 12m: 不知火舞's frame
var _cool := cool_switch(OS.has_feature, OS.get_environment("P0_GATHER_COOL"))
## P0_GATHER_COOL_MS (with the switch): the cooling counted down from the first sync, so a shot sees it grow back.
var _cool_ms := float(OS.get_environment("P0_GATHER_COOL_MS")) if OS.get_environment("P0_GATHER_COOL_MS").is_valid_float() else COOL_MS
var _cool_t0 := -1
var _cooling := {}   # point id → whether its gathered look shows
## A point's look turned (gathered, or grown back) in this sync — once however many turned: what reads the pieces
## (GroundShade.watch: the trees' shade under Compatibility, SGODOT-457) reads them again (周瑜 on #969).
signal looks_changed

static func cool_switch(has_feature: Callable, env: String) -> PackedStringArray:
	return env.split(",", false) if env != "" and bool(has_feature.call("editor")) else PackedStringArray()

## The pond's points as the view has them now (ready_in counted down by P0Logic.project); the pieces built once.
func sync(view: Dictionary) -> void:
	var g = view.get("gather", {}).get("pond", null) if view.get("gather") is Dictionary else null
	points = (g.get("points", []) as Array) if g is Dictionary and g.get("points") is Array else []
	pond = str(g.get("pond", "")) if g is Dictionary else ""
	if not _cool.is_empty():
		if _cool_t0 < 0: _cool_t0 = Time.get_ticks_msec()
		var left := maxf(0.0, _cool_ms - float(Time.get_ticks_msec() - _cool_t0))
		points = points.map(func(p): return cooled(p, _cool, left))
	var turned := false
	for p in points:
		var id := str(p.id)
		var cooling := float(p.get("ready_in", 0)) > 0.0
		if not nodes.has(id): nodes[id] = _piece(p)
		elif bool(_cooling.get(id, false)) != cooling: turned = true
		_cooling[id] = cooling
		show_cooling(nodes[id], cooling)
	if turned: looks_changed.emit()

## The piece as it stands: its gathered look while cooling (the Gathered layer has one for every kind).
static func show_cooling(root: Node3D, cooling: bool) -> void:
	var live := root.get_node_or_null("Live") as Node3D
	var done := root.get_node_or_null("Gathered") as Node3D
	if live == null or done == null or done.get_child_count() == 0: return
	live.visible = not cooling
	done.visible = cooling

## A point the dev switch names, read as cooling `left` (its own ready_in kept when it has one; none left: ready).
static func cooled(p: Dictionary, names: PackedStringArray, left := COOL_MS) -> Dictionary:
	if not ("all" in names or str(p.get("kind", "")) in names or str(p.get("slot", "")) in names): return p
	if float(p.get("ready_in", 0)) > 0.0 or left <= 0.0: return p
	var q := p.duplicate()
	q["ready_in"] = left
	return q

func _piece(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Gather_" + str(p.get("slot", p.id))
	root.position = Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0)))
	add_child(root)
	var kind := str(PIECES.get(str(p.get("kind", "")), ""))
	var live := Node3D.new()
	live.name = "Live"
	root.add_child(live)
	var done := Node3D.new()
	done.name = "Gathered"
	done.visible = false
	root.add_child(done)
	match kind:
		"grove": _grove_gathered(done, stand_of(p) - root.position)
		"hardwood_grove": _hardwood_gathered(done)
		"herb_patch": _herb_gathered(done)
		_: if kind != "": done.add_child(Art.instance(kind + "_gathered"))
	match kind:
		"grove": _grove(live)
		"hardwood_grove": _hardwood(live)
		"rock_pile": _rocks(live)
		"herb_patch":
			live.add_child(Art.instance("bush", Vector3(0.0, 0, -0.35), 0.62))
			var herb := CropMesh.build("B", CropMesh.LEAF)
			for at in [Vector3(-0.28, 0, 0.12), Vector3(0.24, 0, 0.18), Vector3(0.02, 0, 0.36)]:
				var h := MeshInstance3D.new()
				h.mesh = herb
				h.material_override = Art.material()
				h.position = at
				h.scale = Vector3.ONE * 1.25
				live.add_child(h)
		var asset:
			if asset != "": live.add_child(Art.instance(asset))
	if kind in ["grove", "hardwood_grove", "rock_pile"]: _feet(root, kind)
	return root

## Timber (SGODOT-422 v7; the user 11-09: "树木换掉素材", on v5 530: "这个树换掉"): still three trees in a clump — the
## Pandazole pack's layered pines (_g: +10 % saturation, they read as timber), about the old 2.1 m — opened toward the
## camera round the stand side (上官婉儿: no crown over the player at the stand — farm-dev's grove hid them whole at
## Fern's C1, (−0.12, −0.72) off the point): two to the right, one behind left; the one nearest the stand a little
## left-back and 10 % smaller (air by the player).
const GROVE := [[Vector3(0.85, 0, -0.45), 0.44], [Vector3(-0.9, 0, -1.3), 0.4], [Vector3(1.15, 0, 0.55), 0.42]]   # the trunks' spots (their feet's blades too)
static func _grove(root: Node3D) -> void:
	for t in GROVE:
		var s := float(t[1]) / 0.44 * 0.58
		var at: Vector3 = t[0]
		if at.z > 0.0:
			at += Vector3(-0.25, 0, -0.2)
			s *= 0.9
		var tree := Art.instance("wild_pz_pine_01_g", at, s)
		tree.rotation.y = float(t[0].x) * 2.1
		root.add_child(tree)

## Hardwood (SGODOT-422 v7): still a tree, a stump and a stack of logs — the pack's Tree_20 (a broadleaf, _g), Log_05,
## Log_01 / 02, about the old size.
static func _hardwood(root: Node3D) -> void:
	var tree := Art.instance("wild_pz_tree_20_g", Vector3(0.1, 0, -0.25), 0.52)
	tree.rotation.y = 0.8
	root.add_child(tree)
	var stump := Art.instance("wild_pz_log_05", Vector3(-0.5, 0, 0.3), 0.28)
	root.add_child(stump)
	for l in [[Vector3(0.35, 0, 0.42), "wild_pz_log_01", 0.0], [Vector3(0.33, 0.13, 0.4), "wild_pz_log_02", 0.25]]:
		var log := Art.instance(str(l[1]), l[0], 0.24)
		log.rotation = Vector3(0, PI * 0.5 + float(l[2]), 0)
		root.add_child(log)

## Timber gathered (C67, 417 af31871a): the two pines nearest the stand stumps their size (log_05), the farthest left
## standing at 0.4 — well under a pine that can be gathered — two regrowth sprouts; no ground disc.
static func _grove_gathered(root: Node3D, stand: Vector3) -> void:
	var far := 0
	for i in GROVE.size(): if flat(GROVE[i][0], stand) > flat(GROVE[far][0], stand): far = i
	for i in GROVE.size():
		var t: Array = GROVE[i]
		var s := float(t[1]) / 0.44 * 0.58   # as _grove stands them
		var at: Vector3 = t[0]
		if at.z > 0.0:
			at += Vector3(-0.25, 0, -0.2)
			s *= 0.9
		var m := Art.instance("wild_pz_pine_01_g" if i == far else "wild_pz_log_05", at, s * (0.4 if i == far else 0.55))
		m.rotation.y = float(t[0].x) * (2.1 if i == far else 1.3)
		root.add_child(m)
	for at in [Vector3(0.3, 0, 0.05), Vector3(-0.4, 0, -0.75)]: root.add_child(_sprout(at))

## Hardwood gathered (C67): the Tree_20 a stump one size up (log_05 ×0.45) a walnut darker — #8B6842 → #78472F, apart
## from Timber's pale stumps (不知火舞) — the small stump and the log stack as they are, two regrowth sprouts.
static var _walnut: StandardMaterial3D
static func _hardwood_gathered(root: Node3D) -> void:
	if _walnut == null:
		_walnut = Art.material().duplicate() as StandardMaterial3D
		_walnut.albedo_color = Color(0.73, 0.45, 0.52).linear_to_srgb()   # on log_05's vertex colour, linear
	var big := Art.instance("wild_pz_log_05", Vector3(0.1, 0, -0.25), 0.45)
	big.material_override = _walnut
	big.rotation.y = 0.8
	root.add_child(big)
	root.add_child(Art.instance("wild_pz_log_05", Vector3(-0.5, 0, 0.3), 0.28))
	for l in [[Vector3(0.35, 0, 0.42), "wild_pz_log_01", 0.0], [Vector3(0.33, 0.13, 0.4), "wild_pz_log_02", 0.25]]:
		var log := Art.instance(str(l[1]), l[0], 0.24)
		log.rotation = Vector3(0, PI * 0.5 + float(l[2]), 0)
		root.add_child(log)
	for at in [Vector3(-0.2, 0, -0.05), Vector3(0.55, 0, -0.45)]: root.add_child(_sprout(at))

## Wild Herb gathered (C67, 417 a956cb00; 上官婉儿 + 不知火舞): no ground — the piece has none — but one clump: the piece's
## own leaves cut low (0.55 high) and closed in, a shade darker, dark leafy blades at its foot, two sprouts; no bush.
static var _herb_dim: StandardMaterial3D
static var _herb_foot: StandardMaterial3D
static var _herb_cut: ArrayMesh
static func _herb_gathered(root: Node3D) -> void:
	if _herb_dim == null:
		_herb_dim = Art.material().duplicate() as StandardMaterial3D
		_herb_dim.albedo_color = Color(0.8, 0.8, 0.8)
		_herb_foot = Art.material().duplicate() as StandardMaterial3D
		_herb_foot.albedo_color = Color(0.72, 0.72, 0.72)
	var c := Vector3(0.0, 0, 0.15)   # the three herbs' middle
	if _herb_cut == null:   # the three cut herbs one mesh (上官婉儿 on #969: a gathered piece ≤ 6 draws)
		var herb := CropMesh.build("B", CropMesh.LEAF)
		var st := SurfaceTool.new()
		for at in [Vector3(-0.28, 0, 0.12), Vector3(0.24, 0, 0.18), Vector3(0.02, 0, 0.36)]:
			st.append_from(herb, 0, Transform3D(Basis.from_scale(Vector3(1.25 * 0.85, 1.25 * 0.55, 1.25 * 0.85)), c + (at - c) * 0.55))
		_herb_cut = st.commit()
	var cut := MeshInstance3D.new()
	cut.name = "CutHerbs"
	cut.mesh = _herb_cut
	cut.material_override = _herb_dim
	root.add_child(cut)
	var rng := RandomNumberGenerator.new()
	rng.seed = 417
	var blades: Array = []   # dark leafy blades at its foot, one batch as _feet's
	for i in 9:
		var at := c + Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)) * rng.randf_range(0.17, 0.26)
		blades.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.5, 0.7)), Vector3(at.x, -0.02, at.z)))
	var foot := Art.batch("wild_pz_foot_leafy", blades, false)
	foot.material_override = _herb_foot
	foot.set_meta("placed", blades)   # its instances where they stand: a MultiMesh keeps none headless (tests)
	root.add_child(foot)
	for at in [Vector3(-0.32, 0, -0.12), Vector3(0.36, 0, -0.05)]: root.add_child(_sprout(at))

## 417's one regrowth sprout (gathered_417 build.py sprout()): a 0.105 m stem, two oval leaves in a V, #8FA46B — one
## mesh, built once (one draw a sprout).
static var _sprout_mat: StandardMaterial3D
static var _sprout_mesh: ArrayMesh
static func _sprout(at: Vector3) -> MeshInstance3D:
	if _sprout_mesh == null:
		_sprout_mat = StandardMaterial3D.new()
		_sprout_mat.albedo_color = Color("8FA46B")
		_sprout_mat.roughness = 0.9
		var stem := CylinderMesh.new()
		stem.top_radius = 0.010
		stem.bottom_radius = 0.012
		stem.height = 0.105
		stem.radial_segments = 4
		stem.rings = 1
		var leaf := SphereMesh.new()   # 1 m across: scaled to 417's leaf 0.15 × 0.08 × 0.06
		leaf.radial_segments = 6
		leaf.rings = 3
		var st := SurfaceTool.new()
		st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.0525, 0)))
		for side in [-1.0, 1.0]:
			st.append_from(leaf, 0, Transform3D(Basis(Vector3.BACK, side * 0.55) * Basis.from_scale(Vector3(0.15, 0.08, 0.06)), Vector3(side * 0.055, 0.14, 0)))
		_sprout_mesh = st.commit()
	var n := MeshInstance3D.new()
	n.name = "Sprout"
	n.mesh = _sprout_mesh
	n.material_override = _sprout_mat
	n.position = at
	return n

## Grass where things meet the ground (the user on v5: the stones' and trees' feet most): blades round each trunk and
## round the stone pile, one MultiMesh a blade kind (上官婉儿: draw calls).
static func _feet(root: Node3D, kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(root.name)
	var bases: Array = []
	if kind == "grove":
		for t in GROVE: bases.append([t[0], 0.35])
	elif kind == "hardwood_grove": bases = [[Vector3(0.1, 0, -0.25), 0.4], [Vector3(-0.5, 0, 0.3), 0.3], [Vector3(0.35, 0, 0.42), 0.35]]
	else: bases = [[Vector3.ZERO, 0.6]]
	var blades := ["wild_pz_foot_leafy"]   # mid green, short, round (上官婉儿 on v5)
	var by := {}
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
		a.sub = P0Logic.key_ready(ready)   # the round key's ≤ 80 px (q(44)): `3h 12m`, `Ready in 4h`, as a growing plot's
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
## A point's piece on the ground as the camera keeps it off the action keys (上官婉儿 on 475 3bee65ba): the slot's
## footprint (pond_slots: about 1.5 × 1.5 m) to its height — a grove or hardwood TALL_M, the low pieces LOW_M, as their
## marks hang (p0_pond.gather_screen) — its eight corners; and where its icon button centres.
const FOOT_HALF_M := 0.75
const TALL_M := 2.2
const LOW_M := 1.0
static func height_of(p: Dictionary) -> float:
	return TALL_M if str(p.get("kind", "")) in ["wood", "hardwood"] else LOW_M

static func piece_box(p: Dictionary) -> PackedVector3Array:
	var at := Vector3(float(p.get("x", 0)), 0, float(p.get("z", 0)))
	var tall := height_of(p)
	var out := PackedVector3Array()
	for k in 8: out.append(at + Vector3(FOOT_HALF_M if k & 1 else -FOOT_HALF_M, tall if k & 2 else 0.0, FOOT_HALF_M if k & 4 else -FOOT_HALF_M))
	return out

static func icon_at(p: Dictionary) -> Vector3:
	return Vector3(float(p.get("x", 0)), height_of(p), float(p.get("z", 0)))

## The nearest point's mark (SGODOT-475; 不知火舞's gather-compact spec ①, the user bot 682: the tag took too much of the
## screen): its item's icon button, cooling with the part grown back (`progress`, no words: the key's second line and a
## tap say how long); `open` once the player stands at it and it is ready — the button opens to its name strip, the
## item's name alone. A point the view sends without its cooldown (an older server) counts COOLDOWN_H.
const COOLDOWN_H := 4.0
static func mark(view: Dictionary, p: Dictionary, at: Vector3) -> Dictionary:
	var yields: Array = p.get("yield", [])
	var main := str(yields[0][0]) if not yields.is_empty() else ""
	var ready := float(p.get("ready_in", 0))
	return {"icon": main, "text": P0Logic.item_name(view, main), "progress": progress(p),
		"open": ready <= 0.0 and in_reach(p, at)}

## How far a cooling point has grown back, 0..1; -1 when it is ready.
static func progress(p: Dictionary) -> float:
	var ready := float(p.get("ready_in", 0))
	if ready <= 0.0: return -1.0
	var whole := maxf(1.0, float(p.get("cooldown_h", COOLDOWN_H)) * 3_600_000.0)
	return clampf(1.0 - ready / whole, 0.0, 1.0)

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

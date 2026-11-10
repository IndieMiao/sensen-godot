extends Node3D
## The farm ringed by woods (SGODOT-422, 0.3.5; the user 11-09: 「农场也可以做成有林地包围的感觉，树木可以多使用集中类型的松树」,
## the empty grass round the field circled). The wild v7 language (PondWildGround._forest / _clumps) on the farm's own
## ground: pine woods south (the screen's bottom), west, east and behind the farmhouse, denser and darker outward, a
## low wood edge of bushes, stones and logs just outside the fence ring, and small clumps of tufts and flowers on the
## field's beds still to open (gone as they open; the ones next to an open bed already). Nothing here collides and no
## trunk stands in the walk rect: the walk mask and the path grid are the farm's as before.
## Lines of sight: a crown nearer the camera that would cover any point of KEEP on screen (43° pitch, 14.5° yaw; the
## same test as the wild's hides()) comes in smaller — the wood's edge is young trees — or as a bush, or not at all, so
## every bed (open or still to open), the spawn, the exit, the house and its looks (Lv1–Lv15), the facilities and their
## strips stay clear. Only the yard's front strip past the beds may go under the crowns (上官婉儿 11-10 a: Lv1 opens
## with the woods at its foot).
## Deterministic: world coordinates and a fixed seed only — no screen, no device, no save — so a visitor sees the same.

const Art = preload("res://modules/farm/farm_art.gd")
const Fence = preload("res://scenes/p0/p0_fence.gd")
const SEED := 4221109
const RIGHT := Vector2(0.968148, -0.250380)   # the screen's right on the ground (yaw 14.5°)
const DOWN := Vector2(0.250380, 0.968148)     # the screen's down on the ground, toward the camera
## The ground kept in sight: the fence ring (P0Garden.FENCE_RING) and a margin, but at the front only to 0.9 — the beds'
## front row is at z 0.325 (half a cell more: 0.65), the spawn at (6.175, 0.325), the entrance sign at (4.8, 0.575); the
## strip 0.9…1.4 to the front fence is grass the crowns may cover — but for the exit's corner (EXIT below).
const KEEP := Rect2(0.2, -12.55, 12.95, 13.45)
## The farm's exit pin at the yard's front-left corner (C7, P0Garden.MAP_EXIT, #943; its ring 0.38 m, the pin 1.4 m, its strip
## 2.1 m — those stand over KEEP on screen): no trunk within EXIT_R of it and no crown over it or its ring on screen.
## Cleared after the woods are made (_clear_exit), so only the pieces there change and the rest stand as approved.
const EXIT := Vector2(P0Garden.MAP_EXIT.x, P0Garden.MAP_EXIT.z)
const EXIT_R := 1.2   # the ring 0.38 and 0.3 m clear round it (不知火舞 on #943) well inside
## 上官婉儿's rule for the exit's column (443 190fa019): a piece in front of the ring whose x ± its radius meets x EXIT_COL stands far enough
## out that its top clears the ring's front edge on screen with 5 cm to spare — z − h / tan 43° ≥ EXIT_FRONT. It keeps the
## gap the front fence opens there from Lv3 (x 0.38–1.64) a patch of clean grass outside as well.
const EXIT_COL := Vector2(0.2, 1.64)   # 上官婉儿's 0.2–1.4, out to the fence gap's east end (P0Garden.MAP_EXIT_GAP)
const EXIT_FRONT := 1.45
const COT_PITCH := 1.07
## Where the woods stand: outside OUT (the ring and 1 m), inside AREA.
const OUT := Rect2(-0.8, -13.4, 14.8, 15.9)
const AREA := Rect2(-8.0, -22.0, 29.0, 39.0)   # x −8…21, z −22…17: the farthest zoom from any yard point, and the high levels' opening
## Trees batched per kind and side (south, west, east, behind): a side off screen is culled whole, and few draws.

## pines most (上官婉儿: the tiered pine_01 / 03 / 04 in groups, a few Tree_20 round crowns among them)
const NEAR := ["wild_pz_pine_01", "wild_pz_pine_03", "wild_pz_pine_01", "wild_pz_pine_03", "wild_pz_pine_04", "wild_pz_pine_03", "wild_pz_tree_20"]
const FAR := ["wild_pz_pine_03_dk", "wild_pz_pine_03_dk", "wild_pz_pine_03_dk", "wild_pz_pine_01_dk", "wild_pz_tree_20_dk"]   # the 1162-triangle tiered pine sparing out there
## along each near row: a sunlit crown, plain, a deep pine, plain (上官婉儿 on the wild: not one green carpet)
const RHYTHM := [["wild_pz_pine_03_lt", "wild_pz_pine_03_lt", "wild_pz_tree_20_lt"], [], ["wild_pz_pine_03_dk"], []]
const SCALE := {"wild_pz_pine_01": 0.95, "wild_pz_pine_01_dk": 0.95, "wild_pz_pine_03": 0.8, "wild_pz_pine_03_dk": 0.8,
	"wild_pz_pine_03_lt": 0.8, "wild_pz_pine_04": 0.55, "wild_pz_tree_20": 0.8, "wild_pz_tree_20_dk": 0.8, "wild_pz_tree_20_lt": 0.8}
const HEIGHT := {"wild_pz_pine_01": 3.6, "wild_pz_pine_03": 4.7, "wild_pz_pine_04": 7.36, "wild_pz_tree_20": 4.46}
const RADIUS := {"wild_pz_pine_01": 1.52, "wild_pz_pine_03": 1.05, "wild_pz_pine_04": 1.25, "wild_pz_tree_20": 1.6}
const EDGE_BUSHES := ["wild_pz_bush_05", "wild_pz_bush_15", "wild_pz_bush_07", "wild_pz_bush_11"]
const EDGE_STONES := ["wild_pz_rock_13", "wild_pz_rock_22", "wild_pz_rock_29"]
const TUFTS := ["wild_pz_grass_24", "wild_pz_grass_40", "wild_pz_grass_41"]
const FLOWERS := ["wild_pz_flower_20", "wild_pz_flower_23", "wild_pz_flower_26"]
const DARK := Color(0.66, 0.76, 0.80)   # the far wood's tint (cooler, darker), on top of the _dk kinds
## The beds' clumps stay under LOW m (上官婉儿 11-10 b: flat little flowers and grass, no stones): heights at scale 1.
const LOW := 0.14
const LOW_H := {"wild_pz_grass_24": 0.46, "wild_pz_grass_40": 0.2, "wild_pz_grass_41": 0.19, "wild_pz_flower_20": 0.64,
	"wild_pz_flower_23": 0.62, "wild_pz_flower_26": 0.59, "wild_pz_foot_leafy": 0.19, "wild_pz_rosette": 0.0}
## Tall pines on the left of the Lv1 opening, outside the front fence, below the spawn on screen (上官婉儿 11-10: the
## opening's left edge has trees): [asset, x, z] — each as tall as clears KEEP (hides()) from 1.3 down; the woods' own
## trees round them give way (after the rows, so the rows' draws are as before).
const LEFT_PINES := [["wild_pz_pine_01", 5.0, 6.2], ["wild_pz_pine_03", 6.3, 6.6], ["wild_pz_pine_01", 3.4, 5.4]]

var counts := {}          # asset → instances (the plan's numbers)
var trees_placed: Array = []   # [asset, Transform3D] of every tree (tests: the batches hold them on the GPU only)
var _shown := {}          # index into _beds → shown now
var _beds: Array = []     # [bed id, MultiMesh, index, Transform3D] of the clumps on beds still to open
var _bed_key := ""
## The yard growing (v4q(12) ⑤, the user 11-10 bot 655; P0Farm.yard_grown): the few pieces in the way of the yard at
## GIVE_WAY levels, worked out at build — level → [[where, asset, index, from, to]] (where "tree" / "small": in that
## asset's list as built; the woods are not made again, so Lv1–12 stay as approved). yard_level is the level shown.
const GIVE_WAY := [13, 14]
var yard_moves := {}
var yard_level := 0
var _shown_at := {}   # key → where give_way last put it
var _at := {}   # "tree|asset|index" / "small|asset|index" → [MultiMesh, instance, trees_placed index or -1]

func build(bp: FarmBlueprint, seed_value := SEED) -> void:
	name = "FarmWoods"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trees := {}   # asset → [[Transform3D, tint]]
	var small := {}   # asset → [Transform3D]
	_woods(trees, small, rng, seed_value)
	_left_pines(trees)
	_edge(trees, small, rng)
	_clear_exit(trees, small)
	_plan_give_way(trees, small)
	var chunks := {}
	for asset in trees:
		for i in (trees[asset] as Array).size():
			var e: Array = trees[asset][i]
			var o: Vector3 = (e[0] as Transform3D).origin
			var key := "%s|%s" % [asset, _side(Vector2(o.x, o.z))]
			if not chunks.has(key): chunks[key] = []
			chunks[key].append([e, i, trees_placed.size()])
			trees_placed.append([asset, e[0]])
			counts[asset] = int(counts.get(asset, 0)) + 1
	for key in chunks:
		var asset := str(key).get_slice("|", 0)
		var xfs: Array = []
		var tints := PackedColorArray()
		var shade := false
		for c in chunks[key]:
			var e: Array = c[0]
			xfs.append(e[0])
			tints.append(e[1])
			if (e[1] as Color).r > 0.9: shade = true   # only the near trees cast (the far ones' shadows fall off screen)
		var mm := Art.batch(asset, xfs, shade, tints)
		mm.name = "Wood_" + str(key).replace("|", "_")
		add_child(mm)
		for j in chunks[key].size(): _at["tree|%s|%d" % [asset, chunks[key][j][1]]] = [mm.multimesh, j, chunks[key][j][2]]
	for asset in small:
		var mm := Art.batch(asset, small[asset], asset.begins_with("wild_pz_bush") or asset.begins_with("wild_pz_log") or asset == "wild_pz_rock_27")
		mm.name = "Edge_" + asset
		add_child(mm)
		counts[asset] = int(counts.get(asset, 0)) + (small[asset] as Array).size()
		for i in (small[asset] as Array).size(): _at["small|%s|%d" % [asset, i]] = [mm.multimesh, i, -1]
	_bed_clumps(bp, rng)

## Does a crown h m tall, r m round, its trunk at p, cover the kept yard on screen? (43° pitch: a metre up covers
## 0.731 / 0.682 m of ground behind; PondWildGround._forest's hides, against the whole yard instead of a few points.)
static func hides(p: Vector2, h: float, r: float) -> bool:
	var reach := (h * 0.731 + 0.4) / 0.682
	var w := r + 0.4
	var t := 0.0
	while t <= reach:
		for k in 5:
			var q := p - DOWN * t + RIGHT * w * (float(k) / 2.0 - 1.0)
			if KEEP.has_point(q): return true
		t += 0.3
	return false

## Does a piece h m tall, r m round at p break the exit's column rule, or cover the exit's circle on screen (hides()'s
## test, the camera's 14.5° turn and all)?
static func covers_exit(p: Vector2, h: float, r: float) -> bool:
	if p.y > EXIT.y and p.x + r >= EXIT_COL.x and p.x - r <= EXIT_COL.y and p.y - COT_PITCH * h < EXIT_FRONT: return true   # in front of the ring only
	if p.distance_to(EXIT) < EXIT_R: return true
	var reach := (h * 0.731 + 0.4) / 0.682
	var t := 0.0
	while t <= reach:
		for k in 5:
			if (p - DOWN * t + RIGHT * (r + 0.4) * (float(k) / 2.0 - 1.0)).distance_to(EXIT) < EXIT_R: return true
		t += 0.3
	return false

## The exit pin's ground (上官婉儿 11-10: keep the woods round it, no hole): a piece over it comes in one size smaller,
## else moves 0.5–1 m away from the pin, else (a tree) stands as a bush there; a stone or log that cannot move goes; the
## low leafy ground stays. exit_changes says what changed (review shots).
var exit_changes: Array = []
func _clear_exit(trees: Dictionary, small: Dictionary) -> void:
	var placed := func(t: Transform3D, h: float, r: float) -> Transform3D:   # Transform3D() when nothing fits
		var p := Vector2(t.origin.x, t.origin.z)
		var away := (p - EXIT).normalized() if p != EXIT else Vector2.DOWN
		# [size, metres away]: one size smaller where it stands, then moved out as it is, then both
		for c in [[0.92, 0.0], [1.0, 0.5], [1.0, 0.75], [1.0, 1.0], [0.92, 0.5], [0.92, 0.75], [0.92, 1.0]]:
			var k: float = c[0]
			var q: Vector2 = p + away * float(c[1])
			if OUT.has_point(q) or hides(q, h * k, r * k) or covers_exit(q, h * k, r * k): continue
			return Transform3D(t.basis.scaled(Vector3.ONE * k), Vector3(q.x, t.origin.y, q.y))
		return Transform3D()
	for asset in trees:
		var base := str(asset).trim_suffix("_dk").trim_suffix("_lt")
		var kept: Array = []
		for e in trees[asset]:
			var t: Transform3D = e[0]
			var s := t.basis.get_scale().x
			var h := float(HEIGHT[base]) * s
			var r := float(RADIUS[base]) * s
			if not covers_exit(Vector2(t.origin.x, t.origin.z), h, r):
				kept.append(e)
				continue
			var to: Transform3D = placed.call(t, h, r)
			if to != Transform3D():
				kept.append([to] + (e as Array).slice(1))
				exit_changes.append("%s (%.2f, %.2f) → %s" % [asset, t.origin.x, t.origin.z, "smaller" if to.origin == t.origin else "moved to (%.2f, %.2f)%s" % [to.origin.x, to.origin.z, " smaller" if to.basis.get_scale().x < s - 0.001 else ""]])
				continue
			var bush := "wild_pz_bush_05"
			var bt := Transform3D(Basis(Vector3.UP, t.basis.get_euler().y).scaled(Vector3.ONE * 0.9), t.origin)
			var bp: Transform3D = placed.call(bt, 1.05 * 0.9, 0.6 * 0.9)
			if bp != Transform3D():
				if not small.has(bush): small[bush] = []
				small[bush].append(bp)
				exit_changes.append("%s (%.2f, %.2f) → bush at (%.2f, %.2f)" % [asset, t.origin.x, t.origin.z, bp.origin.x, bp.origin.z])
			else:
				exit_changes.append("%s (%.2f, %.2f) → gone" % [asset, t.origin.x, t.origin.z])
		trees[asset] = kept
	for asset in small:
		if str(asset).contains("leafy") or str(asset).contains("grass"): continue
		var kept: Array = []
		for t: Transform3D in small[asset]:
			var h := 1.05 * t.basis.get_scale().y
			var r := 0.6 * t.basis.get_scale().x
			if not covers_exit(Vector2(t.origin.x, t.origin.z), h, r):
				kept.append(t)
				continue
			var to: Transform3D = placed.call(t, h, r)
			if to != Transform3D():
				kept.append(to)
				exit_changes.append("%s (%.2f, %.2f) → (%.2f, %.2f)" % [asset, t.origin.x, t.origin.z, to.origin.x, to.origin.z])
			else:
				exit_changes.append("%s (%.2f, %.2f) → gone" % [asset, t.origin.x, t.origin.z])
		small[asset] = kept

## The yard's rect at a level (P0Garden.yard_at's fence ring), x–z.
static func yard_rect(level: int) -> Rect2:
	var r: Dictionary = P0Garden.yard_at(level).ring
	return Rect2(float(r.west), float(r.back), float(r.east) - float(r.west), float(r.front) - float(r.back))

## Does a round r m at p reach over the rect?
static func over(rect: Rect2, p: Vector2, r: float) -> bool:
	var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	return rect.has_point(p) or p.distance_to(q) < r

## What the yard gains at a level over the one before: the strips of the new rect outside the old (back, front, west,
## east), each as a rect.
static func grown_strips(level: int) -> Array[Rect2]:
	var a := yard_rect(level - 1)
	var b := yard_rect(level)
	var out: Array[Rect2] = []
	if b.position.y < a.position.y: out.append(Rect2(b.position.x, b.position.y, b.size.x, a.position.y - b.position.y))
	if b.end.y > a.end.y: out.append(Rect2(b.position.x, a.end.y, b.size.x, b.end.y - a.end.y))
	if b.position.x < a.position.x: out.append(Rect2(b.position.x, b.position.y, a.position.x - b.position.x, b.size.y))
	if b.end.x > a.end.x: out.append(Rect2(a.end.x, b.position.y, b.end.x - a.end.x, b.size.y))
	return out

## The pieces in the way of what the yard gains at each GIVE_WAY level (a tree's crown, an edge piece's own round over
## the new strip; the low leafy ground stays under the fence as it does now) each move 0.5–1 m away from the yard's
## middle till clear of the whole new yard — moved only, none dropped and none smaller (v2 plan ⑤); a level's moves
## start from the one before's. The woods' own make-up (its seed, the lines of sight) is not touched.
func _plan_give_way(trees: Dictionary, small: Dictionary) -> void:
	var now := {}   # "where|asset|index" → its transform at the level being worked out
	for level in GIVE_WAY:
		var strips := grown_strips(level)
		var yard := yard_rect(level)
		var moves: Array = []
		var fit := func(t: Transform3D, r: float) -> Transform3D:   # Transform3D() when nothing fits
			var p := Vector2(t.origin.x, t.origin.z)
			var away := (p - Vector2(6.6, -5.8)).normalized()
			for m in [0.5, 0.75, 1.0, 1.25, 1.5]:
				var q: Vector2 = p + away * m
				if not over(yard, q, r): return Transform3D(t.basis, Vector3(q.x, t.origin.y, q.y))
			return Transform3D()
		for where in ["tree", "small"]:
			var lists: Dictionary = trees if where == "tree" else small
			for asset in lists:
				if where == "small" and (str(asset).contains("leafy") or str(asset).contains("grass")): continue
				var size := Art.mesh_for(asset).get_aabb().size if where == "small" else Vector3.ZERO
				for i in (lists[asset] as Array).size():
					var key := "%s|%s|%d" % [where, asset, i]
					var built: Transform3D = lists[asset][i][0] if where == "tree" else lists[asset][i]
					var t: Transform3D = now.get(key, built)
					var sc := t.basis.get_scale().x
					var r := float(RADIUS[str(asset).trim_suffix("_dk").trim_suffix("_lt")]) * sc if where == "tree" else maxf(size.x, size.z) * 0.5 * sc
					var p := Vector2(t.origin.x, t.origin.z)
					if not strips.any(func(s: Rect2): return over(s, p, r)): continue
					var to: Transform3D = fit.call(t, r)
					if to == Transform3D():
						push_warning("FarmWoods: %s at (%.2f, %.2f) finds no room off the Lv%d yard" % [asset, p.x, p.y, level])
						continue
					now[key] = to
					moves.append([where, asset, i, built, to])
		yard_moves[level] = moves

## The woods at a Homestead level: the pieces in the way of its yard where they stand from GIVE_WAY's levels up, the
## others as built. animate (the level reached here, P0Farm.yard_grown): a piece that moves pops in at its new place
## with the fence's drop (Fence.POP_S, a little dust), not sliding; else (the farm opened at it) it just stands there.
func give_way(level: int, animate := false) -> void:
	if level == yard_level: return
	yard_level = level
	var want := {}   # key → [as built, where it stands at this level]
	for lv in GIVE_WAY:
		for m in yard_moves.get(lv, []):
			var key := "%s|%s|%d" % [m[0], m[1], m[2]]
			if not want.has(key): want[key] = [m[3], m[3]]
			if level >= lv: want[key][1] = m[4]
	for key in want:
		var at: Array = _at.get(key, [])
		var to: Transform3D = want[key][1]
		if at.is_empty() or shown_at(key, want[key][0]).is_equal_approx(to): continue
		var mm: MultiMesh = at[0]
		var i: int = at[1]
		if int(at[2]) >= 0: trees_placed[at[2]][1] = to
		_shown_at[key] = to
		if not animate:
			mm.set_instance_transform(i, to)
			continue
		mm.set_instance_transform(i, Transform3D(to.basis.scaled(Vector3.ONE * 0.01), to.origin))
		var tw := create_tween()
		tw.tween_method(func(k: float): mm.set_instance_transform(i, Transform3D(to.basis.scaled(Vector3.ONE * k), to.origin)), 0.01, 1.0, Fence.POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Fence.dust(self, to.origin)

## Where a piece that moves for the yard stands now ("tree|asset|index" / "small|asset|index"), or `built` if it has not
## moved (give_way's own record: headless, a MultiMesh keeps no transforms — tests and shots read this).
func shown_at(key: String, built := Transform3D()) -> Transform3D:
	return _shown_at.get(key, built)

static func _hash(i: int, j: int, seed_value: int) -> float:
	return float(hash(Vector3i(i, j, seed_value)) % 10007) / 10006.0

static func _vnoise(p: Vector2, seed_value: int) -> float:   # value noise on a unit grid, 0…1, the same on every device
	var i := floori(p.x)
	var j := floori(p.y)
	var f := p - Vector2(i, j)
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_hash(i, j, seed_value), _hash(i + 1, j, seed_value), u.x), lerpf(_hash(i, j + 1, seed_value), _hash(i + 1, j + 1, seed_value), u.x), u.y)

static func _side(p: Vector2) -> String:
	if p.y > OUT.end.y: return "south"
	if p.y < OUT.position.y: return "back"
	return "west" if p.x < OUT.get_center().x else "east"

static func _depth(p: Vector2) -> float:   # metres outside the ring
	var dx := maxf(OUT.position.x - p.x, p.x - OUT.end.x)
	var dz := maxf(OUT.position.y - p.y, p.y - OUT.end.y)
	return maxf(maxf(dx, dz), 0.0)

func _woods(trees: Dictionary, small: Dictionary, rng: RandomNumberGenerator, seed_value: int) -> void:
	var trunks: Array = []
	var beat := [0]
	var tree := func(p: Vector2) -> void:
		if OUT.has_point(p) or not AREA.has_point(p): return
		if trunks.any(func(o): return o.distance_squared_to(p) < 1.3 * 1.3): return
		var d := _depth(p)
		var list: Array = NEAR if d < 4.5 else FAR
		var asset: String = list[rng.randi() % list.size()]
		if d < 4.5:
			var rh: Array = RHYTHM[beat[0] % RHYTHM.size()]
			beat[0] += 1
			if not rh.is_empty(): asset = rh[rng.randi() % rh.size()]
			if asset == "wild_pz_tree_20_lt": asset = "wild_pz_tree_20"   # 上官婉儿 11-10: no light round crown on the farm (the wild's stay)
		var base := asset.trim_suffix("_dk").trim_suffix("_lt")
		var s: float = float(SCALE.get(asset, 0.8)) * rng.randf_range(0.85, 1.15)
		# the wood's edge comes in young: smaller until the crown clears the yard, a bush below half size
		var k := 1.0
		while k >= 0.45 and hides(p, float(HEIGHT[base]) * s * k, float(RADIUS[base]) * s * k): k -= 0.08
		if k < 0.45:
			var b: String = EDGE_BUSHES[rng.randi() % 3]
			if not hides(p, 1.1, 0.7): _put(small, b, p, rng.randf_range(0.8, 1.1), rng, -0.03)
			elif not hides(p, 0.55, 0.35): _put(small, "wild_pz_bush_11", p, rng.randf_range(0.7, 0.85), rng, -0.03)   # the lowest at the front
			else: _put(small, "wild_pz_foot_leafy", p, rng.randf_range(0.6, 0.85), rng, -0.02)
			return
		var tint := Color.WHITE.lerp(DARK, smoothstep(2.0, 11.0, d))
		if not trees.has(asset): trees[asset] = []
		trees[asset].append([Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s * k), Vector3(p.x, 0, p.y)), tint])
		trunks.append(p)
		if d < 3.0:   # the near trunks rooted in a little leafy ground
			for i in 1: _put(small, "wild_pz_foot_leafy", p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 0.9), rng.randf_range(0.55, 0.85), rng, -0.02)
	# rows across, the gaps closing outward (denser); the near rows first so the far ones fill round them
	var z := AREA.position.y
	var rows: Array = []
	while z < AREA.end.y:
		rows.append(z)
		z += 1.45
	rows.sort_custom(func(a, b): return _depth(Vector2(6.0, a)) < _depth(Vector2(6.0, b)))
	var row_i := 0
	for zr in rows:
		var x := AREA.position.x + rng.randf_range(0.0, 1.0) + (0.9 if row_i % 2 else 0.0)
		row_i += 1
		while x < AREA.end.x:
			var p := Vector2(x + rng.randf_range(-0.4, 0.4), float(zr) + rng.randf_range(-0.45, 0.45))
			var d := _depth(p)
			# a few clearings and gaps near the ring (not a hedge), closed further out
			# in groves: a 5 m noise thins the near rows to clearings between groups, closing outward
			var grove := clampf(0.35 + 1.1 * _vnoise(p / 5.0, seed_value), 0.0, 1.0)
			if d > 0.0 and rng.randf() < lerpf(0.72 * grove + 0.1, 0.97, smoothstep(0.0, 6.0, d)): tree.call(p)
			x += lerpf(2.4, 1.65, smoothstep(0.0, 8.0, d)) + rng.randf_range(-0.2, 0.3)

func _left_pines(trees: Dictionary) -> void:
	for lp in LEFT_PINES:
		var p := Vector2(lp[1], lp[2])
		for asset in trees: trees[asset] = (trees[asset] as Array).filter(func(e): var o: Vector3 = (e[0] as Transform3D).origin; return e.size() > 2 or Vector2(o.x, o.z).distance_to(p) > 1.6)
		var s := 1.3
		while s > 0.5 and hides(p, float(HEIGHT[lp[0]]) * s, float(RADIUS[lp[0]]) * s): s -= 0.05
		if s <= 0.5: continue
		if not trees.has(lp[0]): trees[lp[0]] = []
		trees[lp[0]].append([Transform3D(Basis(Vector3.UP, _hash(int(p.x * 10), int(p.y * 10), SEED) * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0, p.y)), Color.WHITE, true])   # [xf, tint, a left pine]

## The wood's edge just outside the fence ring: a clump of bushes and faceted stones every few metres, leafy ground
## round them, a mossy log or a big stone now and then; low enough near the front not to cover the yard.
func _edge(trees: Dictionary, small: Dictionary, rng: RandomNumberGenerator) -> void:
	var ring := [Vector2(OUT.position.x, OUT.end.y), Vector2(OUT.position.x, OUT.position.y), Vector2(OUT.end.x, OUT.position.y), Vector2(OUT.end.x, OUT.end.y), Vector2(OUT.position.x, OUT.end.y)]
	for side in 4:
		var a: Vector2 = ring[side]
		var b: Vector2 = ring[side + 1]
		var length := a.distance_to(b)
		var t := rng.randf_range(0.3, 1.5)
		while t < length:
			var c := a.lerp(b, t / length)
			c += (c - Vector2(6.6, -5.5)).normalized() * rng.randf_range(0.0, 0.9)
			t += rng.randf_range(2.0, 3.4)
			var pick := rng.randf()
			var h := 1.05
			var asset: String = EDGE_BUSHES[rng.randi() % EDGE_BUSHES.size()]
			if pick > 0.9: asset = ["wild_pz_log_01", "wild_pz_log_02", "wild_pz_rock_27"][rng.randi() % 3]
			elif pick > 0.65: asset = EDGE_STONES[rng.randi() % 3]
			var s := rng.randf_range(0.8, 1.15) if asset.begins_with("wild_pz_bush") else rng.randf_range(0.45, 0.65)
			if asset == "wild_pz_rock_27": s = rng.randf_range(0.5, 0.65)
			if asset.begins_with("wild_pz_log"): s = rng.randf_range(0.8, 1.0)
			while s > 0.3 and hides(c, h * s, 0.6 * s): s -= 0.1
			if s > 0.3: _put(small, asset, c, s, rng, -0.04)
			for i in rng.randi_range(2, 4):
				var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.4, 1.0)
				var low: String = ["wild_pz_foot_leafy", "wild_pz_foot_leafy", "wild_pz_grass_41", "wild_pz_rock_13"][rng.randi() % 4]
				if low == "wild_pz_rock_13" and hides(q, 0.4, 0.3): low = "wild_pz_foot_leafy"
				_put(small, low, q, rng.randf_range(0.3, 0.45) if low == "wild_pz_rock_13" else rng.randf_range(0.55, 0.85), rng, -0.03)

static func _put(to: Dictionary, asset: String, p: Vector2, s: float, rng: RandomNumberGenerator, y := 0.0) -> void:
	if not to.has(asset): to[asset] = []
	to[asset].append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))

## Clumps on the field's beds still to open (the circled empty grass): a tuft heart, flowers with their rosettes,
## leafy blades, dense in the middle, all flattened under LOW; on about a third of the beds. Nothing here collides.
func _bed_clumps(bp: FarmBlueprint, rng: RandomNumberGenerator) -> void:
	var per := {}   # asset → [[bed id, Transform3D]]
	var add := func(bed: int, asset: String, p: Vector2, s: float, y: float) -> void:
		if not per.has(asset): per[asset] = []
		var h: float = LOW_H[asset]
		var sy := minf(s, LOW / h) if h > 0.0 else s
		# blades flattened to LOW, as wide as before; a flower shrunk whole (flattened, its stems read as dark specks)
		var sxz := sy if asset.begins_with("wild_pz_flower") else s
		per[asset].append([bed, Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(sxz, sy, sxz)), Vector3(p.x, y, p.y))])
	for bed in P0Garden.max_plots():
		var at := bp.cell_to_world(P0Garden.cell_of(bed))
		var c := Vector2(at.x, at.z) + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
		if rng.randf() > 0.34: continue
		var flower: String = FLOWERS[rng.randi() % FLOWERS.size()]
		for i in rng.randi_range(1, 2): add.call(bed, TUFTS[rng.randi() % TUFTS.size()], c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.15), rng.randf_range(0.4, 0.55), -0.03)
		for i in rng.randi_range(4, 7):
			var p: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * (0.15 + 0.5 * pow(rng.randf(), 1.6))
			var roll := rng.randf()
			if roll < 0.5: add.call(bed, "wild_pz_foot_leafy", p, rng.randf_range(0.5, 0.75), -0.02)
			elif roll < 0.75:
				add.call(bed, flower, p, rng.randf_range(0.45, 0.6), -0.03)
				add.call(bed, "wild_pz_rosette", p, rng.randf_range(0.3, 0.4), 0.006)
			elif roll < 0.88: add.call(bed, "wild_pz_grass_40", p, rng.randf_range(0.5, 0.65), -0.03)   # no pebbles (上官婉儿 11-10 b)
			else: add.call(bed, "wild_pz_grass_41", p, rng.randf_range(0.45, 0.6), -0.03)
	for asset in per:
		var xfs: Array = []
		for e in per[asset]: xfs.append(e[1])
		var mm := Art.batch(asset, xfs, false)
		mm.name = "BedClump_" + asset
		add_child(mm)
		for i in xfs.size(): _beds.append([int(per[asset][i][0]), mm.multimesh, i, xfs[i]])
		counts["bed:" + asset] = xfs.size()

## The beds open now and Decorate's taken cells: a clump shows on a bed still to open and not next to an open one (the
## beds' surroundings clean), a blade or flower not on a cell a piece stands on (奕星 11-09: Decorate and tapping a bed
## unchanged — nothing here takes a tap or a cell anyway).
func fit(bp: FarmBlueprint, count: int, taken: Array = []) -> void:
	var key := "%d|%s" % [count, str(taken)]
	if key == _bed_key: return
	_bed_key = key
	var open: Array = []
	for id in count: open.append(bp.cell_to_world(P0Garden.cell_of(id)))
	var under := {}
	for c in taken: under[c] = true
	for k in _beds.size():
		var e: Array = _beds[k]
		var bed: int = e[0]
		var at := bp.cell_to_world(P0Garden.cell_of(bed))
		var o: Vector3 = (e[3] as Transform3D).origin
		var show := bed >= count and not open.any(func(q): return (q as Vector3).distance_to(at) < 1.5) and not under.has(bp.world_to_cell(o))
		_shown[k] = show
		(e[1] as MultiMesh).set_instance_transform(e[2], e[3] if show else Transform3D(Basis.from_scale(Vector3.ZERO), (e[3] as Transform3D).origin))

func shown_bed_clumps() -> int:
	return _shown.values().count(true)

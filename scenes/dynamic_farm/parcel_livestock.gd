extends Node3D
## The animals and their drops on the owner's parcel (C-154, the coop; the owner on SEN-C-134#22 q4 and the egg
## pickup recorded on SEN-C-154#7). Presentation only: the save (ParcelFarming's store) says which drops exist, where
## they lie and when they are laid; this node draws them and tells ParcelFarming when the player comes within reach.
##
## Each livestock building gets its animals (FarmLivestock.animal: the art's model and its three clips, walk / peck /
## idle). They wander the yard's open floor, peck and stand about, and step away from a player who comes close; no
## physics, straight walks between free points (a blocked walk just picks another point). A fed animal goes to the
## nearest feeder and pecks; shortly before its product is due it walks to the drop's spot, and at `ready_at` (server
## time) the drop bounces out of it onto the ground (SEN-C-154#145: out of the hen, not up from the ground; the motion
## is FarmLivestock.lay, the drop's size FarmLivestock.drop_scale). Drops already laid when the parcel opens just lie
## there. A drop still in the air is not picked up.
##
## Pickup (the design on SEN-C-154#19): a laid drop within `reach_m` of the player on the ground is reported by
## `update`; `fly` hops it up `hop_m` and arcs it into the player's chest over `flight_s`, shrinking to `shrink`, then
## hides it. ParcelFarming sends `pick_up` and flies the item into the Bag. A drop whose pickup failed stays where it
## is and is not taken again until the player has stepped away and back.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
## Walking and fleeing speeds (cells / s), how near the player makes an animal step away (cells), how far it goes.
const WALK_SPEED := 0.9
const FLEE_SPEED := 2.2
const SHY_CELLS := 1.3
const FLEE_CELLS := 2.2
## An animal sets off for its laying spot this long before the drop is due (ms): long enough to cross the yard round
## a part at its hurried walk (WALK_SPEED * 1.4).
const LAY_LEAD_MS := 6500
## A fed animal pecks at the feeder this long (s).
const FEED_PECK_S := 3.0
## A laid drop grows from this share of its size while it leaves the animal (over the first third of the fall).
const LAY_GROW_FROM := 0.5
## A laid drop leaves this share of the way from the animal's middle toward where it lands (from under her tail).
const LAY_TAIL := 0.25
## Waypoints an animal takes at most on its way to lay (its walks are straight lines round the parts), and new plans
## it makes at most when a step of that walk is blocked.
const LAY_HOPS := 3
## Animals keep time with the drops' ready_at (server time, `now`), not only the engine's frame delta: on a slow frame
## (the emulator renders at 1.5–4 fps) Godot reports at most max_physics_steps_per_frame / physics_ticks_per_second
## (8 / 60 s) and capped scenes report less, so a hen walking by delta fell behind and the egg came due before she
## reached her spot (SEN-C-173). A frame is the longer of `delta` and the time `now` moved, walked in steps of at most
## STEP_S, so she neither falls behind nor takes one long step into a part. A frame longer than MAX_FRAME_S (the app
## was away, the clock was corrected) moves them that long only.
const STEP_S := 1.0 / 30.0
const MAX_FRAME_S := 1.0
## On her way to lay a hen that would arrive late (she set off a slow frame late, or her way round the parts is long)
## hurries, up to FLEE_SPEED, to be beside the spot this long (s) before the drop is due (SEN-C-173); on time she
## keeps her hurried walk (WALK_SPEED * 1.4).
const LAY_SPARE_S := 0.5

var _walk: RefCounted
var _cell_m := 0.8
## Building id -> {state, rule, base, root: Node3D (the building's transform), animals: [..], drops: {id: Node3D}}
var _yards := {}
## Drop ids flying to the player or whose pickup is out, and ids refused until the player steps away.
var _flying := {}
var _held_off := {}
## Drop ids seen unlaid while watching (they pop in when laid) and ids already drawn.
var _expected := {}
## Drop ids still falling out of the animal (not picked up until they lie on the ground).
var _landing := {}
## `now` of the last update (ms), or -1 before the first.
var _last_now := -1
var _pickup := Livestock.pickup()

func setup(walk: RefCounted) -> void:
	_walk = walk
	_cell_m = float(walk.cell_m)
	name = "ParcelLivestock"

## Follows the save: yards for livestock buildings (rebuilt when moved), their animals, and drops laid by `now`.
func sync(farm: Dictionary, rules: Dictionary, now: int) -> void:
	var wanted := {}
	for b: Dictionary in ParcelFarm.buildings_of(farm):
		var rule := ParcelFarm.livestock_of(rules, b)
		if not rule.is_empty() and not Livestock.building_art(str(b.type)).is_empty(): wanted[int(b.id)] = {"state": b, "rule": rule}
	for id: int in _yards.keys():
		if wanted.has(id) and _same_spot(wanted[id].state, _yards[id].state): continue
		(_yards[id].root as Node3D).queue_free()
		_yards.erase(id)
	for id: int in wanted:
		if not _yards.has(id): _build_yard(wanted[id].state, wanted[id].rule)
	var present := {}
	for d: Dictionary in farm.get("drops", []):
		present[int(d.id)] = d
		var yard = _yards.get(int(d.building))
		if yard == null: continue
		yard.pending[int(d.id)] = d
		if int(d.ready_at) > now and not yard.drops.has(int(d.id)):
			if not _expected.has(int(d.id)):
				_expected[int(d.id)] = true
				_send_to_feeder(yard, int(d.animal))
	for yard: Dictionary in _yards.values():
		for id: int in yard.pending.keys():
			if not present.has(id): yard.pending.erase(id)
		for id: int in yard.drops.keys():
			if not present.has(id) and not _flying.has(id):
				(yard.drops[id] as Node3D).queue_free()
				yard.drops.erase(id)
				_landing.erase(id)
	for id: int in _held_off.keys():
		if not present.has(id): _held_off.erase(id)
	for id: int in _expected.keys():
		if not present.has(id): _expected.erase(id)
	_draw_laid(now, false)

static func _same_spot(a: Dictionary, b: Dictionary) -> bool:
	return str(a.type) == str(b.type) and int(a.x) == int(b.x) and int(a.y) == int(b.y) and int(a.rotation) == int(b.rotation) \
		and int(a.width) == int(b.width) and int(a.depth) == int(b.depth)

func _build_yard(b: Dictionary, rule: Dictionary) -> void:
	var type := str(b.type)
	var base := Building.base_of(b)
	var root := Node3D.new()
	root.name = "Yard%d" % int(b.id)
	root.transform = Building.transform(_walk, Building.at_of(b), base, int(b.rotation))
	add_child(root)
	var yard := {"state": b.duplicate(), "rule": rule, "type": type, "base": base, "root": root, "animals": [], "drops": {},
		"pending": {}, "rects": {}, "cells": {}, "feeders": Livestock.feeders(type), "eat": Livestock.eat_points(type),
		"feeder_points": [], "stand_points": [], "cutouts": Building.cutouts_of(b)}
	for cell: Vector2i in ParcelFarm.building_footprint(b): yard.cells[cell] = true
	var stands := Livestock.refill_points(type)
	for i in yard.feeders.size():
		yard.feeder_points.append(root.transform * Livestock.model_point(yard.feeders[i], base, _cell_m))
		yard.stand_points.append(root.transform * Livestock.model_point(stands[i], base, _cell_m) if stands[i] is Vector2 else null)
	var kinds: Array = b.get("animals", rule.animals)
	for i in kinds.size():
		var made := Livestock.animal(str(kinds[i]), _cell_m)
		var radius: float = made.radius
		var a := {"node": made.node, "player": made.player, "clips": made.clips, "radius": radius, "state": "idle", "left": 0.0,
			"target": Vector2.ZERO, "speed": WALK_SPEED, "errand": "", "clip": "", "then": false, "lay_to": {}}
		root.add_child(made.node)
		a.pos = _free_point(yard, radius, Vector2(base) * Vector2(0.3 + 0.2 * i, 0.55), 40)
		_place_animal(yard, a, Vector2.RIGHT.rotated(float(i) * 2.1))
		yard.animals.append(a)
		_rest(a, "idle", 0.5 + 0.6 * i)
	_yards[int(b.id)] = yard

# ------------------------------------------------------------------ frame

## One frame: animals move, due drops pop in, and laid drops now within reach of `player` are returned (ids) for
## ParcelFarming to pick up (none while `paused`).
func update(delta: float, player: Vector3, now: int, paused := false) -> Array:
	var clock_s := float(now - _last_now) / 1000.0 if _last_now >= 0 else 0.0
	_last_now = now
	var frame := clampf(maxf(delta, clock_s), 0.0, MAX_FRAME_S)
	var steps := maxi(1, ceili(frame / STEP_S - 0.001))
	var step := frame / float(steps)
	for yard: Dictionary in _yards.values():
		var local := Livestock.local_point((yard.root as Node3D).transform.affine_inverse() * player, yard.base, _cell_m)
		for k in steps:
			# Each step at its own time within the frame, so a walk to lay starts and ends when it should.
			var at := now - int(float(steps - 1 - k) * step * 1000.0)
			for i in yard.animals.size(): _tick(yard, yard.animals[i], i, step, local, at)
	_draw_laid(now, true)
	var reach: float = _pickup.reach_m
	var out := []
	for yard: Dictionary in _yards.values():
		for id: int in yard.drops:
			var node: Node3D = yard.drops[id]
			if _flying.has(id) or _landing.has(id): continue
			var gap := Vector2(node.global_position.x - player.x, node.global_position.z - player.z).length()
			if _held_off.has(id):
				if gap > reach * 1.6: _held_off.erase(id)
				continue
			if not paused and gap <= reach: out.append(id)
	return out

## Drops laid by `now` get their model (bouncing out of the animal that laid it when `animate`, i.e. laid while the
## player watches).
func _draw_laid(now: int, animate: bool) -> void:
	for yard: Dictionary in _yards.values():
		for id: int in yard.pending:
			var d: Dictionary = yard.pending[id]
			if yard.drops.has(id) or int(d.ready_at) > now: continue
			var node := Livestock.drop_model(str(d.item), _cell_m)
			node.name = "Drop%d" % id
			var spots: Array = yard.rule.spots
			var spot: Vector2 = spots[int(d.spot)] if int(d.spot) < spots.size() else Vector2(yard.base) * 0.5
			node.position = Livestock.model_point(spot, yard.base, _cell_m)
			node.rotation.y = float(id % 7) * 0.9
			(yard.root as Node3D).add_child(node)
			yard.drops[id] = node
			if animate and _expected.has(id): _lay(yard, id, d, node)
			_expected.erase(id)

## The drop leaves the animal that laid it `from_m` up, from under her tail (she turns it to the spot), arcs down onto
## its spot and bounces once (FarmLivestock.lay). From `toss_m` short of the spot when that animal is not beside it
## (fled, or blocked on its way).
func _lay(yard: Dictionary, id: int, d: Dictionary, node: Node3D) -> void:
	var lay := Livestock.lay(str(d.item))
	var land := node.position
	var toss: float = lay.toss_m
	var away := Vector3(0, 0, toss)
	var index := int(d.animal)
	if index >= 0 and index < yard.animals.size():
		var a: Dictionary = yard.animals[index]
		var at := Livestock.model_point(a.pos, yard.base, _cell_m) - land
		at.y = 0.0
		var gap := at.length()
		if gap > toss * 2.0: away = at / gap * toss
		elif gap > 0.01: away = at
		# Her tail to the spot: the drop comes out behind her.
		if not a.state in ["walk", "flee"]: _face(yard, a, Vector2(at.x, at.z))
	var start := land + away * (1.0 - LAY_TAIL) + Vector3(0, float(lay.from_m), 0)
	var rise: float = lay.rise_m
	var bounce: float = lay.bounce_m
	_landing[id] = true
	node.position = start
	node.scale = Vector3.ONE * LAY_GROW_FROM
	var tw := node.create_tween()
	tw.tween_method(func(t: float):
		var p := start.lerp(land, t)
		p.y += 4.0 * rise * t * (1.0 - t)
		node.position = p
		node.scale = Vector3.ONE * lerpf(LAY_GROW_FROM, 1.0, minf(1.0, t * 3.0)), 0.0, 1.0, maxf(0.01, float(lay.fall_s)))
	tw.tween_method(func(t: float): node.position = land + Vector3(0, 4.0 * bounce * t * (1.0 - t), 0), 0.0, 1.0,
		maxf(0.01, float(lay.bounce_s)))
	tw.tween_callback(func():
		node.position = land
		node.scale = Vector3.ONE
		_landing.erase(id))

func _tick(yard: Dictionary, a: Dictionary, index: int, delta: float, player: Vector2, now: int) -> void:
	# Due soon: off to the spot where this animal's next drop lies; once it is laid the errand is over.
	var due = null
	for d: Dictionary in yard.pending.values():
		if int(d.animal) == index and int(d.ready_at) > now and (due == null or int(d.ready_at) < int(due.ready_at)): due = d
	if due == null and a.errand == "lay": a.errand = ""
	if due != null and a.errand != "lay" and int(due.ready_at) - now <= LAY_LEAD_MS:
		var spots: Array = yard.rule.spots
		if int(due.spot) < spots.size():
			a.lay_to = {"spot": spots[int(due.spot)], "toss": float(Livestock.lay(str(due.item)).toss_m) / _cell_m, "hops": 0, "index": index}
			_walk_to_lay(yard, a)
	var shy: bool = a.pos.distance_to(player) < SHY_CELLS
	if shy and a.errand == "" and a.state != "flee":
		var away: Vector2 = (a.pos - player).normalized() if a.pos.distance_to(player) > 0.01 else Vector2.RIGHT
		var best: Vector2 = a.pos
		var best_d := -1.0
		for k in 10:
			var p: Vector2 = _free_point(yard, a.radius, a.pos + away.rotated(randf_range(-1.1, 1.1)) * FLEE_CELLS, 1, 0.6)
			var d: float = p.distance_to(player)
			if d > best_d:
				best_d = d
				best = p
		_go(yard, a, best, FLEE_SPEED, "")
		a.state = "flee"
	if a.errand == "lay" and a.state == "walk" and due != null:
		a.speed = _lay_speed(a, int(due.ready_at) - now)
		if a.player != null: (a.player as AnimationPlayer).speed_scale = 1.6 if a.speed > WALK_SPEED * 1.5 else 1.0
	if a.state in ["walk", "flee"]:
		var to: Vector2 = a.target - a.pos
		var step: float = a.speed * delta
		if to.length() <= step:
			_place_animal(yard, a, to, a.target)
			_arrive(yard, a)
		else:
			var next: Vector2 = a.pos + to.normalized() * step
			if not _open(yard, next, a.radius):
				# On her way to lay: plan again from here instead of giving up (SEN-C-173).
				if a.errand == "lay" and not a.lay_to.is_empty() and int(a.lay_to.get("replans", 0)) < LAY_HOPS:
					a.lay_to.replans = int(a.lay_to.get("replans", 0)) + 1
					_walk_to_lay(yard, a)
					return
				_rest(a, "idle", 0.4)
				a.errand = ""
				a.then = false
			else:
				_place_animal(yard, a, to, next)
		return
	a.left -= delta
	if a.left > 0.0: return
	if a.errand == "lay":
		_rest(a, "idle", 1.0)
		return
	a.errand = ""
	var roll := randf()
	if roll < 0.45:
		_go(yard, a, _free_point(yard, a.radius, a.pos + Vector2(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0)), 12), WALK_SPEED, "")
	elif roll < 0.75: _rest(a, "peck", randf_range(2.0, 3.5))
	else: _rest(a, "idle", randf_range(1.5, 3.0))

## The speed (cells / s) that brings `a` beside her laying spot LAY_SPARE_S before the drop is due in `left_ms`: her
## hurried walk when that is enough, faster up to FLEE_SPEED when she is late. The way left is this leg, and from a
## waypoint (`then`) the line on to the spot.
func _lay_speed(a: Dictionary, left_ms: int) -> float:
	var way: float = a.pos.distance_to(a.target)
	if a.then and not a.lay_to.is_empty(): way += maxf(0.0, (a.target as Vector2).distance_to(a.lay_to.spot) - float(a.lay_to.toss))
	var left_s := float(left_ms) / 1000.0 - LAY_SPARE_S
	var hurried := WALK_SPEED * 1.4
	if left_s <= 0.0: return FLEE_SPEED if way > 0.01 else hurried
	return clampf(way / left_s, hurried, FLEE_SPEED)

func _arrive(yard: Dictionary, a: Dictionary) -> void:
	if a.errand == "lay" and a.then and int(a.lay_to.hops) < LAY_HOPS:
		a.lay_to.hops = int(a.lay_to.hops) + 1
		_walk_to_lay(yard, a)
		return
	match a.errand:
		"feed":
			_rest(a, "peck", FEED_PECK_S)
			a.errand = ""
			var feeder = _nearest_feeder(yard, a.pos)
			if feeder != null: _face(yard, a, feeder - a.pos)
		"lay":
			_rest(a, "idle", 2.0)
			# Her tail to the spot already, so she does not swing round as she lays.
			if not a.lay_to.is_empty(): _face(yard, a, a.pos - (a.lay_to.spot as Vector2))
		_: _rest(a, "idle" if randf() < 0.5 else "peck", randf_range(1.0, 2.5))
	if a.errand != "lay": a.errand = ""

func _send_to_feeder(yard: Dictionary, index: int) -> void:
	if index < 0 or index >= yard.animals.size(): return
	var a: Dictionary = yard.animals[index]
	var feeder = _nearest_feeder(yard, a.pos)
	if feeder == null: return
	# C-202: where the feeder says its animals eat (the barn's cows behind the trough), else beside it on her side.
	var eat = yard.eat[yard.feeders.find(feeder)]
	var want: Vector2 = eat if eat is Vector2 else feeder + (a.pos - feeder).normalized() * 0.55
	_go(yard, a, _free_point(yard, a.radius, want, 12, 0.3), WALK_SPEED * 1.4, "feed")

func _nearest_feeder(yard: Dictionary, from: Vector2) -> Variant:
	var best = null
	for f: Vector2 in yard.feeders:
		if best == null or from.distance_to(f) < from.distance_to(best): best = f
	return best

func _go(_yard: Dictionary, a: Dictionary, target: Vector2, speed: float, errand: String) -> void:
	a.target = target
	a.speed = speed
	a.errand = errand
	a.state = "walk"
	_clip(a, "walk")

func _rest(a: Dictionary, clip: String, seconds: float) -> void:
	a.state = clip
	a.left = seconds
	_clip(a, clip)

func _clip(a: Dictionary, which: String) -> void:
	if a.clip == which or a.player == null: return
	a.clip = which
	var name_ := str(a.clips.get(which, ""))
	var player: AnimationPlayer = a.player
	if player.has_animation(name_): player.play(name_)
	elif player.has_animation(name_ + "-loop"): player.play(name_ + "-loop")
	player.speed_scale = 1.6 if which == "walk" and a.speed > WALK_SPEED * 1.5 else 1.0

func _place_animal(yard: Dictionary, a: Dictionary, heading: Vector2, at = null) -> void:
	if at is Vector2: a.pos = at
	var node: Node3D = a.node
	node.position = Livestock.model_point(a.pos, yard.base, _cell_m)
	_face(yard, a, heading)

func _face(_yard: Dictionary, a: Dictionary, heading: Vector2) -> void:
	if heading.length() < 0.001: return
	# The building's own frame: +x right, +z toward the entry; the pivot looks down −Z.
	(a.node as Node3D).rotation.y = atan2(-heading.x, -heading.y)

## Off to lay beside `a.lay_to.spot`, `toss` (cells) from it: straight to the nearest open point round the spot that it
## can walk to in a line, else to a waypoint (a part's corner, or a random point of the floor) from which one is (or,
## failing that, the one nearest the spot; it plans again there, `then`), else to the open point nearest the first
## try (the drop then leaves `toss_m` short of its spot, see _lay).
func _walk_to_lay(yard: Dictionary, a: Dictionary) -> void:
	var index := int(a.lay_to.index)
	var radius: float = a.radius
	var spot: Vector2 = a.lay_to.spot
	var toss: float = a.lay_to.toss
	var targets := []
	for k in 8:
		var p := spot + Vector2(toss, 0).rotated(float(index) + float(k) * TAU / 8.0)
		if _open(yard, p, radius): targets.append(p)
	# Nearest first, but the side of the spot away from the camera before the others: the drop then falls toward the
	# viewer instead of behind the animal.
	var back := _away_from_camera(yard)
	var cost := func(p: Vector2) -> float: return a.pos.distance_to(p) + (0.0 if (p - spot).dot(back) >= -0.01 else 3.0)
	targets.sort_custom(func(p: Vector2, q: Vector2): return cost.call(p) < cost.call(q))
	a.then = false
	for p: Vector2 in targets:
		if _clear_line(yard, a.pos, p, radius):
			_go(yard, a, p, WALK_SPEED * 1.4, "lay")
			return
	var rects: Dictionary = _rects(yard, radius)
	var floor_rect: Rect2 = rects.floor
	var ways := []
	for r: Rect2 in rects.blocked:
		var g := r.grow(0.05)
		ways.append_array([g.position, Vector2(g.end.x, g.position.y), Vector2(g.position.x, g.end.y), g.end])
	for k in 12: ways.append(Vector2(randf_range(floor_rect.position.x, floor_rect.end.x), randf_range(floor_rect.position.y, floor_rect.end.y)))
	var best = null
	var best_len := INF
	var nearest = null
	var nearest_d := INF
	for w: Vector2 in ways:
		if w.distance_to(a.pos) < 0.05 or not _open(yard, w, radius) or not _clear_line(yard, a.pos, w, radius): continue
		if w.distance_to(spot) < nearest_d:
			nearest_d = w.distance_to(spot)
			nearest = w
		for p: Vector2 in targets:
			var length: float = a.pos.distance_to(w) + w.distance_to(p)
			if length < best_len and _clear_line(yard, w, p, radius):
				best_len = length
				best = w
	var via = best if best != null else nearest
	if via != null and not targets.is_empty():
		_go(yard, a, via, WALK_SPEED * 1.4, "lay")
		a.then = true
		return
	_go(yard, a, _free_point(yard, radius, spot + Vector2(toss, 0).rotated(float(index)), 12, 0.5), WALK_SPEED * 1.4, "lay")

## The direction (building frame, cells) the camera looks along over the ground, or zero without a camera.
func _away_from_camera(yard: Dictionary) -> Vector2:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null: return Vector2.ZERO
	var look: Vector3 = (yard.root as Node3D).global_basis.inverse() * -camera.global_basis.z
	return Vector2(look.x, look.z).normalized()

## The straight walk from `from` to `to` (cells) stays on the open floor: `to` is open and the segment past `from`
## crosses no part (the floor is a rectangle, so both ends on it keep the whole walk on it). A segment clear of a part
## keeps every step of the walk (`_open` per frame) clear of it, even from a point on the part's edge.
func _clear_line(yard: Dictionary, from: Vector2, to: Vector2, radius: float) -> bool:
	if not _open(yard, to, radius): return false
	for r: Rect2 in _rects(yard, radius).blocked:
		if _segment_hits(from, to, r): return false
	return true

## Whether the segment `a`→`b` meets `r` anywhere past its very start (Liang–Barsky clipping).
static func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0001
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var lo: float = r.position[axis] - a[axis]
		var hi: float = r.end[axis] - a[axis]
		if absf(d[axis]) < 1e-9:
			if lo > 0.0 or hi < 0.0: return false
			continue
		var ta: float = lo / d[axis]
		var tb: float = hi / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1: return false
	return true

## A point of the open floor near `want` (cells), else the nearest of `tries` random ones round it, else the floor's
## middle.
func _free_point(yard: Dictionary, radius: float, want: Vector2, tries: int, spread := 1.0) -> Vector2:
	var floor_rect: Rect2 = _rects(yard, radius).floor
	var p := want.clamp(floor_rect.position, floor_rect.end)
	if _open(yard, p, radius): return p
	for k in tries:
		var q := (want + Vector2(randf_range(-spread, spread), randf_range(-spread, spread)) * 1.5).clamp(floor_rect.position, floor_rect.end)
		if _open(yard, q, radius): return q
	return floor_rect.get_center()

func _open(yard: Dictionary, p: Vector2, radius: float) -> bool:
	var rects: Dictionary = _rects(yard, radius)
	if not (rects.floor as Rect2).has_point(p): return false
	for r: Rect2 in rects.blocked:
		if r.has_point(p): return false
	return true

## The open floor and the parts grown by `radius`, worked out once per yard and radius.
func _rects(yard: Dictionary, radius: float) -> Dictionary:
	if not yard.rects.has(radius):
		yard.rects[radius] = {"floor": Livestock.floor_rect(yard.type, yard.base, radius),
			"blocked": Livestock.blocked_rects(yard.type, radius, yard.cutouts)}
	return yard.rects[radius]

# ------------------------------------------------------------------ pickup

## The drop hops up and arcs into the player's chest, shrinking, then hides (the 3D half of the pickup).
func fly(id: int, player: Vector3) -> void:
	var node := _drop_node(id)
	if node == null: return
	_flying[id] = true
	var start := node.global_position
	var top := start + Vector3(0, float(_pickup.hop_m), 0)
	var flight := float(_pickup.flight_s)
	var hop := minf(0.1, flight * 0.3)
	var tw := node.create_tween()
	tw.tween_property(node, "global_position", top, hop).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float):
		var chest := player + Vector3(0, float(_pickup.chest_m), 0)
		var p := top.lerp(chest, t)
		p.y += sin(t * PI) * 0.25
		node.global_position = p
		node.scale = Vector3.ONE * lerpf(1.0, float(_pickup.shrink), t), 0.0, 1.0, flight - hop).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): node.visible = false)

## The pickup's reply: picked drops leave; ones still in the save come back to their spot (`hold`: not taken again
## until the player steps away).
func settle(ids: Array, hold: bool) -> void:
	for id: int in ids:
		_flying.erase(id)
		var node := _drop_node(id)
		if node == null: continue
		for yard: Dictionary in _yards.values():
			if not yard.drops.has(id): continue
			if yard.pending.has(id):
				var spots: Array = yard.rule.spots
				var d: Dictionary = yard.pending[id]
				node.position = Livestock.model_point(spots[int(d.spot)] if int(d.spot) < spots.size() else Vector2(yard.base) * 0.5, yard.base, _cell_m)
				node.scale = Vector3.ONE
				node.visible = true
				if hold: _held_off[id] = true
			else:
				node.queue_free()
				yard.drops.erase(id)

func _drop_node(id: int) -> Node3D:
	for yard: Dictionary in _yards.values():
		if yard.drops.has(id): return yard.drops[id]
	return null

## A drop's screen-independent spot (scene space), or null.
func drop_position(id: int) -> Variant:
	var node := _drop_node(id)
	return node.global_position if node != null else null

# ------------------------------------------------------------------ feeding

## The livestock building whose feeder is nearest `player` within `reach` (m), from its centre or from where the player
## stands to fill it (its `refill`, C-202): {building: state, point: Vector3 (the centre), stand: Vector3 or null}, or {}.
func feeder_near(player: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for yard: Dictionary in _yards.values():
		for i in yard.feeder_points.size():
			var p: Vector3 = yard.feeder_points[i]
			var stand = yard.stand_points[i]
			var d := Vector2(p.x - player.x, p.z - player.z).length()
			if stand is Vector3: d = minf(d, Vector2(stand.x - player.x, stand.z - player.z).length())
			if d <= best_d:
				best_d = d
				best = {"building": yard.state, "point": p, "stand": stand}
	return best

## The cells under livestock buildings (their floor is walked, never farmed).
func covers(cell: Vector2i) -> bool:
	for yard: Dictionary in _yards.values():
		if yard.cells.has(cell): return true
	return false

## For tests and probes: {building id: {animals: [{pos, state, errand}], drops: [ids drawn], landing: [ids in the air]}}.
func snapshot() -> Dictionary:
	var out := {}
	for id: int in _yards:
		var yard: Dictionary = _yards[id]
		out[id] = {"animals": yard.animals.map(func(a): return {"pos": a.pos, "state": a.state, "errand": a.errand,
			"world": (a.node as Node3D).global_position}), "drops": yard.drops.keys(),
			"landing": yard.drops.keys().filter(func(id): return _landing.has(id))}
	return out

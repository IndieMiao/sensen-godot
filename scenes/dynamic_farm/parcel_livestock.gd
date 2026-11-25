extends Node3D
## The animals and their drops on the owner's parcel (C-154, the coop; the owner on SEN-C-134#22 q4 and the egg
## pickup recorded on SEN-C-154#7). Presentation only: the save (ParcelFarming's store) says which drops exist, where
## they lie and when they are laid; this node draws them and tells ParcelFarming when the player comes within reach.
##
## Each livestock building gets its animals (FarmLivestock.animal: the art's model and its three clips, walk / peck /
## idle). They wander the yard's open floor, peck and stand about, and step away from a player who comes close; no
## physics, straight walks between free points (a blocked walk just picks another point). A fed animal goes to the
## nearest feeder and pecks; shortly before its product is due it walks to the drop's spot, and at `ready_at` (server
## time) the drop pops in beside it. Drops already laid when the parcel opens just lie there.
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
## An animal sets off for its laying spot this long before the drop is due (ms).
const LAY_LEAD_MS := 4000
## A fed animal pecks at the feeder this long (s).
const FEED_PECK_S := 3.0
const POP_S := 0.25

var _walk: RefCounted
var _cell_m := 0.8
## Building id -> {state, rule, base, root: Node3D (the building's transform), animals: [..], drops: {id: Node3D}}
var _yards := {}
## Drop ids flying to the player or whose pickup is out, and ids refused until the player steps away.
var _flying := {}
var _held_off := {}
## Drop ids seen unlaid while watching (they pop in when laid) and ids already drawn.
var _expected := {}
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
		"pending": {}, "rects": {}, "cells": {}, "feeders": Livestock.feeders(type), "feeder_points": []}
	for cell: Vector2i in ParcelFarm.building_footprint(b): yard.cells[cell] = true
	for f: Vector2 in yard.feeders: yard.feeder_points.append(root.transform * Livestock.model_point(f, base, _cell_m))
	var kinds: Array = b.get("animals", rule.animals)
	for i in kinds.size():
		var made := Livestock.animal(str(kinds[i]), _cell_m)
		var radius: float = made.radius
		var a := {"node": made.node, "player": made.player, "clips": made.clips, "radius": radius, "state": "idle", "left": 0.0,
			"target": Vector2.ZERO, "speed": WALK_SPEED, "errand": "", "clip": ""}
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
	for yard: Dictionary in _yards.values():
		var local := Livestock.local_point((yard.root as Node3D).transform.affine_inverse() * player, yard.base, _cell_m)
		for i in yard.animals.size(): _tick(yard, yard.animals[i], i, delta, local, now)
	_draw_laid(now, true)
	var reach: float = _pickup.reach_m
	var out := []
	for yard: Dictionary in _yards.values():
		for id: int in yard.drops:
			var node: Node3D = yard.drops[id]
			if _flying.has(id): continue
			var gap := Vector2(node.global_position.x - player.x, node.global_position.z - player.z).length()
			if _held_off.has(id):
				if gap > reach * 1.6: _held_off.erase(id)
				continue
			if not paused and gap <= reach: out.append(id)
	return out

## Drops laid by `now` get their model (popping in when `animate`, i.e. laid while the player watches).
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
			if animate and _expected.has(id):
				node.scale = Vector3.ONE * 0.01
				var tw := node.create_tween()
				tw.tween_property(node, "scale", Vector3.ONE * 1.15, POP_S * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(node, "scale", Vector3.ONE, POP_S * 0.4)
			_expected.erase(id)

func _tick(yard: Dictionary, a: Dictionary, index: int, delta: float, player: Vector2, now: int) -> void:
	# Due soon: off to the spot where this animal's next drop lies; once it is laid the errand is over.
	var due = null
	for d: Dictionary in yard.pending.values():
		if int(d.animal) == index and int(d.ready_at) > now and (due == null or int(d.ready_at) < int(due.ready_at)): due = d
	if due == null and a.errand == "lay": a.errand = ""
	if due != null and a.errand != "lay" and int(due.ready_at) - now <= LAY_LEAD_MS:
		var spots: Array = yard.rule.spots
		if int(due.spot) < spots.size():
			var beside: Vector2 = spots[int(due.spot)] + Vector2(0.35, 0).rotated(float(index))
			_go(yard, a, _free_point(yard, a.radius, beside, 12, 0.5), WALK_SPEED * 1.4, "lay")
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
	if a.state in ["walk", "flee"]:
		var to: Vector2 = a.target - a.pos
		var step: float = a.speed * delta
		if to.length() <= step:
			_place_animal(yard, a, to, a.target)
			_arrive(yard, a)
		else:
			var next: Vector2 = a.pos + to.normalized() * step
			if not _open(yard, next, a.radius):
				_rest(a, "idle", 0.4)
				a.errand = ""
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

func _arrive(yard: Dictionary, a: Dictionary) -> void:
	match a.errand:
		"feed":
			_rest(a, "peck", FEED_PECK_S)
			a.errand = ""
			var feeder = _nearest_feeder(yard, a.pos)
			if feeder != null: _face(yard, a, feeder - a.pos)
		"lay": _rest(a, "idle", 2.0)
		_: _rest(a, "idle" if randf() < 0.5 else "peck", randf_range(1.0, 2.5))
	if a.errand != "lay": a.errand = ""

func _send_to_feeder(yard: Dictionary, index: int) -> void:
	if index < 0 or index >= yard.animals.size(): return
	var a: Dictionary = yard.animals[index]
	var feeder = _nearest_feeder(yard, a.pos)
	if feeder == null: return
	_go(yard, a, _free_point(yard, a.radius, feeder + (a.pos - feeder).normalized() * 0.55, 12, 0.3), WALK_SPEED * 1.4, "feed")

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
		yard.rects[radius] = {"floor": Livestock.floor_rect(yard.type, yard.base, radius), "blocked": Livestock.blocked_rects(yard.type, radius)}
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

## The livestock building whose feeder is nearest `player` within `reach` (m): {building: state, point: Vector3}, or {}.
func feeder_near(player: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for yard: Dictionary in _yards.values():
		for p: Vector3 in yard.feeder_points:
			var d := Vector2(p.x - player.x, p.z - player.z).length()
			if d <= best_d:
				best_d = d
				best = {"building": yard.state, "point": p}
	return best

## The cells under livestock buildings (their floor is walked, never farmed).
func covers(cell: Vector2i) -> bool:
	for yard: Dictionary in _yards.values():
		if yard.cells.has(cell): return true
	return false

## For tests and probes: {building id: {animals: [{pos, state, errand}], drops: [ids drawn]}}.
func snapshot() -> Dictionary:
	var out := {}
	for id: int in _yards:
		var yard: Dictionary = _yards[id]
		out[id] = {"animals": yard.animals.map(func(a): return {"pos": a.pos, "state": a.state, "errand": a.errand,
			"world": (a.node as Node3D).global_position}), "drops": yard.drops.keys()}
	return out

extends SceneTree
## The coop (C-154): the client copy of the rules against the server on the shared cases
## (fixtures/coop_cases.json, also run by server/test/parcels/farm.test.ts), the yard's art file (fence runs with the
## entry open, walls, feeders, the placeholder while SEN-C-155's yard is not in), and ParcelLivestock: hens stay on
## the open floor and step away from the player, a laid egg is reported in reach once, a failed pickup waits until
## the player steps away, an unlaid one appears when due; at about 3 fps the hen still lays from beside the spot
## (SEN-C-173).
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_coop.gd
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
const LivestockScene = preload("res://scenes/dynamic_farm/parcel_livestock.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const T0 := 1795406400000
const BODY := 0.3
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	_rules()
	_cases()
	_saves()
	_layout()
	_walls()
	_entry()
	_keep_clear()
	for path in OS.get_cmdline_user_args():
		_keep_clear_parcel(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_drop_art()
	await _animals()
	await _slow_lay()
	_items()
	print("COOP_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The shipped coop and its livestock rule; malformed ones are refused as the server refuses them.
func _rules() -> void:
	var rules := ParcelFarm.rules()
	var coop: Dictionary = rules.buildings.coop
	_check(coop.width == 7 and coop.depth == 5 and coop.max == 1 and coop.blueprint == "blueprint_coop" and coop.materials == {},
		"coop: 7×5, one per parcel, the coop blueprint only")
	var l: Dictionary = coop.livestock
	_check(l.animals == ["hen_white", "hen_brown", "hen_white"] and l.feed == "crop_carrot" and l.product == "egg" and l.amount == 1 \
		and l.produce_seconds == 120 and l.max_ground == 6 and l.spots.size() >= 6, "coop: three hens, a carrot gives an egg in 120 s, 6 on the ground")
	_check(rules.energy.costs.feed == 1 and rules.economy.sell_prices.egg == 20, "feeding 1 Energy (P0); an egg sells for 20")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(change: Callable) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		change.call(copy.buildings.coop)
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call(func(_c): pass), "rules: the shipped coop parses")
	_check(bad.call(func(c): c.livestock.animals = []), "rules: no animals refused")
	_check(bad.call(func(c): c.livestock.produce_seconds = 0), "rules: no time refused")
	_check(bad.call(func(c): c.livestock.spots = c.livestock.spots.slice(0, 5)), "rules: fewer spots than eggs on the ground refused")
	_check(bad.call(func(c): c.livestock.spots.append([8, 1])), "rules: a spot outside the footprint refused")
	_check(bad.call(func(c): c.materials = {"wood": 0}), "rules: a material of 0 refused")

func _cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/coop_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 15, "coop cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
		var got := {"ok": true, "buildings": r.state.buildings, "drops": r.state.drops, "drop_seq": r.state.drop_seq, "bag": r.state.bag,
			"energy": r.state.energy} if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "coop case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "coop case '%s': the input save is untouched" % c.name)

## Drops and animals survive the save's JSON; a save from before C-154 reads with none and keeps its blueprint.
func _saves() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/coop_cases.json"))
	var fed: Dictionary = {}
	for c: Dictionary in shared.cases:
		if str(c.name).begins_with("three hens"):
			fed = ParcelFarm.apply(rules, ParcelFarm.normalize(c.farm), c.commands, int(c.now)).state
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(fed)))
	_check(not fed.is_empty() and JSON.stringify(reread, "", true) == JSON.stringify(fed, "", true), "saves: drops and hens read back as written")
	var old := {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"blueprint_coop": 1}, "welcomed_at": T0,
		"coins": 12, "sales": 1, "gathered": {}, "blueprints_claimed": {"coop": T0}}
	var read := ParcelFarm.normalize(old)
	_check(read.drops == [] and read.drop_seq == 0 and read.bag == {"blueprint_coop": 1}, "saves: before C-154 no drops, the blueprint kept")
	var odd: Dictionary = JSON.parse_string(JSON.stringify(fed))
	odd.drops.append({"id": "x"})
	odd.drop_seq = 1
	var cleaned := ParcelFarm.normalize(odd)
	_check(cleaned.drops.size() == 3 and cleaned.drop_seq == 3, "saves: a malformed drop is left out; the id counter never goes below the drops")

## The art file: the fence's runs leave the entry open; walls are the runs and the parts; feeders inside.
func _layout() -> void:
	var base := Vector2i(7, 5)
	var runs := Livestock.fence_runs("coop", base)
	_check(runs.size() == 5, "layout: four sides, the front split by the entry (%d runs)" % runs.size())
	var front := runs.filter(func(r): return is_equal_approx(r.from.y, 5.0) and is_equal_approx(r.to.y, 5.0))
	_check(front.size() == 2 and is_equal_approx(front[0].to.x, 5.0) and is_equal_approx(front[1].from.x, 6.0), "layout: the entry is x 5–6 of the front")
	var profiles := Livestock.profiles("coop", base, 0.8)
	_check(profiles.size() == runs.size() + Livestock.parts("coop").size(), "layout: a wall per run and per part")
	var feeders := Livestock.feeders("coop")
	_check(feeders.size() == 2 and feeders.all(func(f: Vector2): return Rect2(Vector2.ZERO, Vector2(base)).has_point(f)), "layout: two feeders inside")
	for spot: Vector2 in ParcelFarm.rules().buildings.coop.livestock.spots:
		var free := true
		for r: Rect2 in Livestock.blocked_rects("coop", 0.05): free = free and not r.has_point(spot)
		_check(free and Livestock.floor_rect("coop", base, 0.05).has_point(spot), "layout: egg spot %s lies on the open floor" % spot)
	var model := Building.model("coop", base, 0.8)
	var scene := str(Livestock.building_art("coop").scene)
	_check(model != null and (ResourceLoader.exists(scene) or model.get_node_or_null("Placeholder") != null),
		"layout: the yard's scene, or a placeholder until it exists")
	model.free()
	_check(Building.kind("coop").name == "Coop" and Building.kind("coop").get("livestock", false), "layout: Build Coop from the art file's name")

## The walls in all four turns: the player (0.3 m) passes the entry, not the fence, and stands on the open floor.
func _walls() -> void:
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var base := Vector2i(7, 5)
	for turns in 4:
		var at := Building.transform(walk, Vector2i(2, 2), base, turns)
		var proxies := Building.proxies(walk, "coop", Vector2i(2, 2), base, turns)
		var blocked := func(local: Vector2) -> bool:
			var p := at * Livestock.model_point(local, base, walk.cell_m)
			return proxies.any(func(x): return x.touches(p, BODY))
		_check(not blocked.call(Vector2(5.5, 5.0)) and not blocked.call(Vector2(5.5, 4.3)) and not blocked.call(Vector2(5.5, 5.6)),
			"walls turned %d: in and out through the entry" % turns)
		_check(blocked.call(Vector2(2.5, 5.0)) and blocked.call(Vector2(3.5, 0.0)) and blocked.call(Vector2(0.0, 2.5)) \
			and blocked.call(Vector2(7.0, 2.5)), "walls turned %d: the fence stops the player" % turns)
		_check(blocked.call(Vector2(4.0, 0.75)) and blocked.call(Vector2(2.5, 3.5)), "walls turned %d: the coop and a feeder stop the player" % turns)
		_check(not blocked.call(Vector2(4.5, 3.2)) and not blocked.call(Vector2(1.5, 4.0)), "walls turned %d: the floor is open" % turns)

## C-154#89 (V-495): in all four turns the player's centre passes the entry `entry_clear_m` (0.4 m) wide, and the
## real walker pushed at a slant from one cell outside the entry, frame by frame at walking speed, gets onto the floor.
## Aimed up to 0.4 m beside the opening's middle; a stick held steeper than about 67° off straight in slides past
## even this opening, the walls before C-154#89 (0.1 m) from about 65°. With `entry_clear_m` 0 every 65° walk and
## every straight push aimed 0.4 m off fails, so the cases do catch a narrow entry.
const ENTRY_DEGREES := [0.0, 20.0, 35.0, 50.0, 60.0, 65.0]
const ENTRY_AIMS := [-0.5, -0.25, 0.0, 0.25, 0.5]

func _entry() -> void:
	var fence: Dictionary = Livestock.building_art("coop").fence
	var shipped = fence.get("entry_clear_m")
	_check(shipped != null and is_equal_approx(Livestock.entry_clear_m("coop"), 0.4), "entry: entry_clear_m 0.4 from the art file")
	var wide := _entry_walks(ENTRY_DEGREES)
	_check(wide.narrowest >= 0.4 - 0.005, "entry: the player's centre passes %.3f m in the narrowest turn (≥ 0.4)" % wide.narrowest)
	_check(wide.failed.is_empty(), "entry: %d walks in, four turns, both sides, up to 65°, all get in (failed %s)" % [wide.total, wide.failed])
	var wide_limit := _entry_limit()
	fence.entry_clear_m = 0.0
	var narrow := _entry_walks(ENTRY_DEGREES)
	var steep: Array = narrow.failed.filter(func(f: String): return f.contains("65°"))
	var off: Array = narrow.failed.filter(func(f: String): return f.contains(" +0° ") and f.ends_with("0.50"))
	var narrow_limit := _entry_limit()
	fence.entry_clear_m = shipped
	_check(narrow.narrowest < 0.15, "entry control: with entry_clear_m 0 the centre passes only %.3f m" % narrow.narrowest)
	_check(steep.size() == 4 * 2 * ENTRY_AIMS.size(), "entry control: with entry_clear_m 0 every 65° walk slides past (%d of 40)" % steep.size())
	_check(off.size() == 4 * 2 * 2, "entry control: with entry_clear_m 0 every straight push aimed 0.4 m off stops at the fence (%d of 16)" % off.size())
	_check(wide_limit > narrow_limit, "entry: the steepest push that gets in, %d° against %d° before" % [wide_limit, narrow_limit])
	print("COOP entry clear=%.2f narrowest=%.3f failed=%d/%d steepest=%d°; clear=0 narrowest=%.3f failed=%d/%d steepest=%d°" % [
		Livestock.entry_clear_m("coop"), wide.narrowest, wide.failed.size(), wide.total, wide_limit, narrow.narrowest,
		narrow.failed.size(), narrow.total, narrow_limit])

## The steepest whole degree at which every straight-aimed push, in all four turns from both sides, still gets in.
func _entry_limit() -> int:
	var limit := 0
	for degrees in range(40, 86):
		if not _entry_walks([float(degrees)], [0.0]).failed.is_empty(): break
		limit = degrees
	return limit

## The coop's walls in the real walker on the synthetic parcel, each turn: the narrowest width (m) the player's centre
## passes along the entry's fence line, and which pushes at `degrees` off straight in, aimed `aims` cells beside the
## opening's middle, fail to reach the floor within six seconds.
func _entry_walks(degrees_list: Array, aims := ENTRY_AIMS) -> Dictionary:
	var data := Data.decode(Fixture.farm())
	var base := Vector2i(7, 5)
	var at := Vector2i(10, 10)
	var narrowest := INF
	var failed := []
	var total := 0
	for turns in 4:
		var walk := Walk.new(data)
		var frame := Building.transform(walk, at, base, turns)
		var back := frame.affine_inverse()
		for proxy in Building.proxies(walk, "coop", at, base, turns): walk.add_prop(proxy)
		var world := func(local: Vector2) -> Vector3: return frame * Livestock.model_point(local, base, walk.cell_m)
		var local := func(p: Vector3) -> Vector2: return Livestock.local_point(back * p, base, walk.cell_m)
		# Across the fence line at the entry: the longest clear stretch of centres.
		var run := 0.0
		var best := 0.0
		var step := 0.0025
		var x := 4.0
		while x <= 7.0:
			run = run + step if walk.clear_position(world.call(Vector2(x, 5.0))) else 0.0
			best = maxf(best, run)
			x += step
		narrowest = minf(narrowest, best * walk.cell_m)
		# The stick held at a slant toward a point of the opening, at 60 frames a second, from one cell out (the
		# entry's kept cell row), clear of the fence.
		for side in [-1.0, 1.0]:
			for degrees: float in degrees_list:
				for aim: float in aims:
					total += 1
					var a := deg_to_rad(degrees)
					var heading := Vector2(side * sin(a), -cos(a))
					var start: Vector2 = Vector2(5.5 + aim, 5.0) - heading / cos(a)
					walk.position = world.call(start)
					var direction: Vector3 = (world.call(start + heading) - world.call(start)).normalized()
					var inside := false
					for _frame in 360:
						walk.move(direction * 3.75 / 60.0)
						var now: Vector2 = local.call(walk.position)
						if now.y < 4.4 and now.x > 0.5 and now.x < 6.5:
							inside = true
							break
					if not inside: failed.append("t%d %+d° aim %+.2f" % [turns, int(side * degrees), aim])
	return {"narrowest": narrowest, "failed": failed, "total": total}

## C-154#54 (V-482): the cell outside the entry and the rear hedge row are the coop's to keep. They turn with the
## model; the coop stands only with them in the core and off buildings and solid obstacles, and no later building
## covers them, whichever comes first. The reviewer's two cases on the synthetic parcel, then the real walker.
func _keep_clear() -> void:
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var base := Vector2i(7, 5)
	var kept := Livestock.keep_clear("coop", base)
	_check(kept.size() == 8 and kept.filter(func(k): return k.walk).map(func(k): return k.cell) == [Vector2i(5, 5)],
		"keep clear: the entry's outside cell (walkable) and the 7 rear cells, from the art file")
	_check(Building.apron("cottage", Vector2i(3, 3), Vector2i(3, 3)).walk.is_empty() and Building.apron_cells("cottage", Vector2i(3, 3), Vector2i(3, 3)).is_empty(),
		"keep clear: the cottage keeps nothing past its footprint")
	for turns in 4:
		var at := Vector2i(4, 4)
		var frame := Building.transform(walk, at, base, turns)
		var a := Building.apron("coop", at, base, turns)
		var same := true
		var i := 0
		for k: Dictionary in kept:
			var want := walk.cell_at(frame * Livestock.model_point(Vector2(k.cell) + Vector2(0.5, 0.5), base, walk.cell_m))
			var got: Vector2i = a.walk[0] if k.walk else a.art[i]
			if not k.walk: i += 1
			same = same and got == want
		var entry := walk.cell_at(frame * Livestock.model_point(Vector2(5.5, 5.4), base, walk.cell_m))
		var footprint := Building.cells(at, base, turns)
		_check(same and a.walk == [entry] and not footprint.has(entry) and a.art.all(func(c): return not footprint.has(c)),
			"keep clear turned %d: the cells turn with the model, the entry's just past its opening" % turns)
	var path := Space.protected_path(data)
	var cottage := Vector2i(3, 3)
	var none := {}
	var walk_of := func(farm: Dictionary) -> Dictionary: return walk.reserved.merged(ParcelFarm.building_cells(farm))
	var coop_ok := func(at: Vector2i, turns: int, farm: Dictionary) -> String:
		return Building.reason(data, at, base, turns, Building.blocked({}, farm), path, walk_of.call(farm), "coop")
	var house_ok := func(at: Vector2i, farm: Dictionary) -> String:
		return Building.reason(data, at, cottage, 0, Building.blocked({}, farm), path, walk_of.call(farm), "cottage")
	# The reviewer's probe: a coop spot fine alone and a cottage fine alone whose footprint covers the coop's entry
	# (its rear row); either one standing refuses the other.
	for which in ["walk", "art"]:
		var found := 0
		var exact := true
		for cell: Dictionary in data.cells:
			if found >= 6: break
			if cell.zone != "core": continue
			var at := Vector2i(cell.x, cell.y)
			for turns in 4:
				if coop_ok.call(at, turns, none) != "": continue
				var target: Vector2i = Building.apron("coop", at, base, turns)[which][0]
				for dy in 3:
					for dx in 3:
						var h := target - Vector2i(dx, dy)
						if house_ok.call(h, none) != "": continue
						var c := {"buildings": [{"id": 1, "type": "coop", "x": at.x, "y": at.y, "width": 7, "depth": 5, "rotation": turns}]}
						var hf := {"buildings": [{"id": 1, "type": "cottage", "x": h.x, "y": h.y, "width": 3, "depth": 3, "rotation": 0}]}
						exact = exact and coop_ok.call(at, turns, hf) == Building.TAKEN and house_ok.call(h, c) == Building.TAKEN
						found += 1
		_check(found > 0 and exact, "keep clear %s: %d coop/cottage pairs over the coop's %s, refused in either order"
			% [which, found, "entry" if which == "walk" else "rear row"])
	# A solid obstacle on the entry or the rear row refuses the coop; a weed or a tilled cell does not.
	var spot = Building.nearest(data, data.spawn, base, {}, path, walk.reserved, 0, "coop")
	_check(spot != null, "keep clear: the synthetic parcel has room for the coop")
	if spot == null: return
	var a0 := Building.apron("coop", spot, base, 0)
	_check(Building.reason(data, spot, base, 0, {}, path, walk.reserved.merged({a0.walk[0]: true}), "coop") == Building.TAKEN
		and Building.reason(data, spot, base, 0, {}, path, walk.reserved.merged({a0.art[3]: true}), "coop") == Building.TAKEN
		and Building.reason(data, spot, base, 0, {a0.walk[0]: true, a0.art[3]: true}, path, walk.reserved, "coop") == "",
		"keep clear: a solid obstacle there refuses the coop; a weed or a tilled cell does not")

## On a real parcel: every coop spot in all four turns keeps its entry and rear row in the core and off solid
## obstacles; with the coop standing, every cottage the placement accepts near the entry leaves its floor reachable
## from spawn by the real walker.
## p-5402049 (r4 only, a 267×3 core; not in r8) has no coop spot, so it reports spots=0 and checks nothing more;
## that is expected (C-193). Whether the current parcels hold the coop is test_building_fit.gd's.
func _keep_clear_parcel(raw: Dictionary) -> void:
	var data := Data.decode(raw)
	if not data.ok: return
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var layout: Array = planned.core_obstacles.layout
	var obstacles := {}
	for item: Dictionary in layout: obstacles[item.cell] = true
	var path := Space.protected_path(data)
	var base := Vector2i(7, 5)
	# The obstacles cleared, as a player does before building; solid ones still standing are judged below.
	var taken := Building.blocked({}, {})
	var walk_blocked: Dictionary = walk.reserved.duplicate()
	var stones := Building.solid(layout, obstacles)
	var exact := true
	var spots := 0
	var reached := true
	var cottages := 0
	for turns in 4:
		var first = null
		for y in range(-1, data.grid_size.y):
			for x in range(-1, data.grid_size.x):
				var at := Vector2i(x, y)
				var why := Building.reason(data, at, base, turns, taken, path, walk_blocked, "coop")
				var kept := Building.apron_cells("coop", at, base, turns)
				var bad := kept.any(func(c): return not data.by_cell.has(c) or data.by_cell[c].zone != "core")
				if bad: exact = exact and why == Building.OUTSIDE
				if why == "":
					spots += 1
					if first == null: first = at
				if why == "" and kept.any(func(c): return stones.has(c)):
					exact = exact and Building.reason(data, at, base, turns, taken, path, walk_blocked.merged(stones), "coop") == Building.TAKEN
		if first == null: continue
		var farm := {"buildings": [{"id": 1, "type": "coop", "x": first.x, "y": first.y, "width": 7, "depth": 5, "rotation": turns}]}
		var entry: Vector2i = Building.apron("coop", first, base, turns).walk[0]
		var floor_at := Building.transform(walk, first, base, turns) * Livestock.model_point(Vector2(4.5, 3.2), base, walk.cell_m)
		var tried := 0
		for dy in range(-3, 2):
			for dx in range(-3, 2):
				if tried >= 3: break
				var h := entry + Vector2i(dx, dy)
				if Building.reason(data, h, Vector2i(3, 3), 0, Building.blocked({}, farm), path,
						walk_blocked.merged(ParcelFarm.building_cells(farm)), "cottage") != "": continue
				tried += 1
				var trial := Walk.new(data)
				trial.reserved = walk.reserved
				trial._proxies_by_cell = walk._proxies_by_cell.duplicate(true)
				for p in Building.proxies(trial, "coop", first, base, turns): trial.add_prop(p)
				for p in Building.proxies(trial, "cottage", h, Vector2i(3, 3), 0): trial.add_prop(p)
				reached = reached and _reaches(trial, floor_at)
		cottages += tried
	_check(exact, "%s: every coop spot keeps its entry and rear row in the core, off solid obstacles" % data.block_id)
	_check(reached, "%s: %d cottages beside the coop's entry leave its floor reachable" % [data.block_id, cottages])
	print("COOP keep_clear parcel=%s spots=%d cottages=%d" % [data.block_id, spots, cottages])

## Flood fill on a 0.2 m lattice from spawn: the player reaches `target` (within one step).
func _reaches(walk: RefCounted, target: Vector3) -> bool:
	var step := 0.2
	var key := func(p: Vector3) -> Vector2i: return Vector2i(roundi(p.x / step), roundi(p.z / step))
	var start: Vector3 = walk.point(walk.data.spawn)
	var goal: Vector2i = key.call(target)
	var seen := {key.call(start): true}
	var queue: Array[Vector3] = [start]
	var i := 0
	while i < queue.size():
		var p := queue[i]
		i += 1
		if Vector2(key.call(p)).distance_to(Vector2(goal)) <= 1.5: return true
		for d in [Vector3(step, 0, 0), Vector3(-step, 0, 0), Vector3(0, 0, step), Vector3(0, 0, -step)]:
			var q: Vector3 = p + d
			var k: Vector2i = key.call(q)
			if seen.has(k): continue
			seen[k] = true
			if walk.clear_position(q): queue.append(q)
	return false

func _animals() -> void:
	# The hens wander at random (randf); a fixed seed keeps the checks below the same on every run.
	seed(154)
	var rules := ParcelFarm.rules()
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var host := LivestockScene.new()
	host.setup(walk)
	root.add_child(host)
	var farm := ParcelFarm.empty_state()
	farm.buildings = [{"id": 1, "type": "coop", "model": "chicken_yard", "x": 2, "y": 2, "width": 7, "depth": 5, "rotation": 1,
		"built_at": T0, "animals": ["hen_white", "hen_brown", "hen_white"]}]
	farm.drops = [{"id": 1, "item": "egg", "amount": 1, "building": 1, "animal": 0, "spot": 2, "ready_at": T0 - 1000},
		{"id": 2, "item": "egg", "amount": 1, "building": 1, "animal": 1, "spot": 5, "ready_at": T0 + 5000}]
	farm.drop_seq = 2
	host.sync(farm, rules, T0)
	var snap: Dictionary = host.snapshot()
	_check(snap.has(1) and snap[1].animals.size() == 3, "animals: three hens in the coop")
	_check(snap[1].drops == [1], "animals: the laid egg lies there, the one not laid yet does not")
	_check(host.covers(Vector2i(2, 2)) and host.covers(Vector2i(6, 8)) and not host.covers(Vector2i(7, 2)), "animals: the turned coop's cells are its floor")
	var egg: Vector3 = host.drop_position(1)
	var far := egg + Vector3(3, 0, 0)
	_check(host.update(0.016, far, T0).is_empty(), "pickup: nothing out of reach")
	_check(host.update(0.016, egg + Vector3(0.5, 0, 0), T0) == [1], "pickup: an egg 0.5 m away is in reach (0.8 m)")
	_check(host.update(0.016, egg + Vector3(0.5, 0, 0), T0, true).is_empty(), "pickup: none while paused (another command out)")
	host.fly(1, egg + Vector3(0.5, 0, 0))
	_check(host.update(0.016, egg, T0).is_empty(), "pickup: a flying egg is not reported again")
	host.settle([1], true)
	_check(host.update(0.016, egg, T0).is_empty(), "pickup: refused, it waits while the player stays")
	host.update(0.016, egg + Vector3(2, 0, 0), T0)
	_check(host.update(0.016, egg, T0) == [1], "pickup: after stepping away and back it is taken again")
	# The hens: ten seconds with the player in the middle; they keep to the open floor and step away from the player.
	var b: Dictionary = farm.buildings[0]
	var frame := Building.transform(walk, Building.at_of(b), Building.base_of(b), 1)
	var middle := frame * Livestock.model_point(Vector2(4.5, 3.0), Vector2i(7, 5), walk.cell_m)
	var inside := true
	for i in 600:
		host.update(1.0 / 60.0, middle, T0 + i * 16)
		for a: Dictionary in host.snapshot()[1].animals:
			var p: Vector2 = a.pos
			inside = inside and Livestock.floor_rect("coop", Vector2i(7, 5), 0.15).grow(0.01).has_point(p)
			for r: Rect2 in Livestock.blocked_rects("coop", 0.15): inside = inside and not r.grow(-0.01).has_point(p)
	_check(inside, "animals: always on the open floor, never in a part")
	var near := 0
	for a: Dictionary in host.snapshot()[1].animals:
		if (a.pos as Vector2).distance_to(Vector2(4.5, 3.0)) < 1.0: near += 1
	_check(near == 0, "animals: none stays within a metre of the player")
	# The second egg is laid at T0 + 5 s: it appears; the hen that laid it went to its spot first.
	host.update(0.016, far, T0 + 6000)
	_check(host.snapshot()[1].drops.has(2), "animals: the egg appears when it is due")
	# Laid while watched (SEN-C-154#145): the hen walks beside the spot, the egg leaves her above the ground, arcs down
	# onto its spot and bounces once; it is not picked up while it is still in the air.
	var lay := Livestock.lay("egg")
	var away := egg + Vector3(30, 0, 30)
	farm.drops.append({"id": 4, "item": "egg", "amount": 1, "building": 1, "animal": 0, "spot": 3, "ready_at": T0 + 12000})
	host.sync(farm, rules, T0 + 6000)
	for i in 375: host.update(1.0 / 60.0, away, T0 + 6000 + i * 16)
	var hen: Vector3 = host.snapshot()[1].animals[0].world
	host.update(0.016, away, T0 + 12000)
	var ground := frame * Livestock.model_point(ParcelFarm.livestock_of(rules, b).spots[3], Vector2i(7, 5), walk.cell_m)
	var leaving: Vector3 = host.drop_position(4)
	_check(host.snapshot()[1].landing.has(4), "lay: the egg is in the air when laid")
	var hen_gap := Vector2(hen.x - ground.x, hen.z - ground.z).length()
	var from_hen := Vector2(leaving.x - hen.x, leaving.z - hen.z).length()
	_check(is_equal_approx(leaving.y - ground.y, lay.from_m) and hen_gap <= lay.toss_m * 2.0 + 0.01
		and absf(from_hen - hen_gap * LivestockScene.LAY_TAIL) < 0.02,
		"lay: it leaves the hen %.2f m up, under her tail (%s, hen %s)" % [lay.from_m, leaving, hen])
	var toss := Vector2(leaving.x - ground.x, leaving.z - ground.z).length()
	_check(toss > 0.05 and toss <= lay.toss_m * 2.0 + 0.01, "lay: the hen laid it beside its spot (%.2f m)" % toss)
	_check(not host.update(0.016, leaving, T0 + 12000).has(4), "lay: an egg in the air is not picked up")
	var peak := -INF
	var bounced := false
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int((lay.fall_s + lay.bounce_s + 0.5) * 1000.0):
		await process_frame
		var at: Vector3 = host.drop_position(4)
		peak = maxf(peak, at.y - ground.y)
		# Over its spot and still off the ground: the bounce after the fall.
		if Vector2(at.x - ground.x, at.z - ground.z).length() < 0.001 and at.y - ground.y > 0.005: bounced = true
		if host.snapshot()[1].landing.is_empty(): break
	var landed: Vector3 = host.drop_position(4)
	_check(host.snapshot()[1].landing.is_empty() and landed.distance_to(ground) < 0.001, "lay: it ends on its spot (%s vs %s)" % [landed, ground])
	_check(peak > lay.from_m, "lay: it arcs up out of the hen before falling (peak %.2f m)" % peak)
	_check(bounced, "lay: it bounces once on its spot")
	_check(host.update(0.016, ground, T0 + 12000).has(4), "lay: once on the ground it is picked up")
	# A new feeding: the hen goes to a feeder.
	farm.drops.append({"id": 3, "item": "egg", "amount": 1, "building": 1, "animal": 2, "spot": 7, "ready_at": T0 + 200000})
	host.sync(farm, rules, T0 + 13000)
	_check(host.snapshot()[1].animals[2].errand == "feed", "animals: a fed hen goes to the feeder")
	var feeder := frame * Livestock.model_point(Livestock.feeders("coop")[0], Vector2i(7, 5), walk.cell_m)
	_check(not host.feeder_near(feeder + Vector3(0.6, 0, 0), 1.1).is_empty() and host.feeder_near(feeder + Vector3(2, 0, 0), 1.1).is_empty(),
		"feeding: the key's feeder within 1.1 m")
	# Gone from the save (picked elsewhere): gone from the ground.
	farm.drops = []
	host.sync(farm, rules, T0 + 14000)
	_check(host.snapshot()[1].drops.is_empty(), "animals: a picked egg leaves the ground")
	host.queue_free()
	await process_frame

## SEN-C-173: frames a third of a second long (about 3 fps, as the emulator renders), for which Godot reports a delta
## of only 8/60 s (max_physics_steps_per_frame / physics_ticks_per_second), while the server clock moves 1/3 s. In each
## turn, a hen on the far side of the yard from the egg's spot, the egg due in LAY_LEAD_MS: she walks the clock's whole
## frame in short steps, keeps to the open floor, is beside the spot when the egg is laid, and the egg leaves her (not
## the air short of the spot). Spots 7, 1 and 2 are where the eggs fell from the air before (C-154#198).
func _slow_lay() -> void:
	seed(173)
	var rules := ParcelFarm.rules()
	var walk := Walk.new(Data.decode(Fixture.farm()))
	var lay := Livestock.lay("egg")
	var base := Vector2i(7, 5)
	var frame_s := 1.0 / 3.0
	var engine_delta := 8.0 / 60.0
	var beside := 0
	var tail := 0
	var laid := 0
	var inside := true
	var moved := true
	for turns in 4:
		var host := LivestockScene.new()
		host.setup(walk)
		root.add_child(host)
		var farm := ParcelFarm.empty_state()
		farm.buildings = [{"id": 1, "type": "coop", "model": "chicken_yard", "x": 2, "y": 2, "width": 7, "depth": 5, "rotation": turns,
			"built_at": T0, "animals": ["hen_white", "hen_brown", "hen_white"]}]
		var b: Dictionary = farm.buildings[0]
		var at := Building.transform(walk, Building.at_of(b), Building.base_of(b), turns)
		var spots: Array = ParcelFarm.livestock_of(rules, b).spots
		var away := at * Livestock.model_point(Vector2(30, 30), base, walk.cell_m)
		var now := T0
		host.sync(farm, rules, now)
		var yard: Dictionary = host._yards[1]
		for k in 3:
			var spot: int = [7, 1, 2][k]
			var hen: Dictionary = yard.animals[k]
			# Across the yard from the spot, standing.
			hen.pos = host._free_point(yard, hen.radius, Vector2(base) - (spots[spot] as Vector2), 40)
			host._rest(hen, "idle", 0.5)
			var id := 10 * turns + k + 1
			farm.drops = [{"id": id, "item": "egg", "amount": 1, "building": 1, "animal": k, "spot": spot, "ready_at": now + LivestockScene.LAY_LEAD_MS}]
			host.sync(farm, rules, now)
			host.update(0.0, away, now)
			var start: Vector2 = hen.pos
			var after_one := Vector2.INF
			while not host.snapshot()[1].drops.has(id) and now < T0 + 600000:
				now += int(frame_s * 1000.0)
				host.update(engine_delta, away, now)
				if after_one == Vector2.INF: after_one = hen.pos
				var p: Vector2 = hen.pos
				inside = inside and Livestock.floor_rect("coop", base, 0.15).grow(0.01).has_point(p)
				for r: Rect2 in Livestock.blocked_rects("coop", 0.15): inside = inside and not r.grow(-0.01).has_point(p)
			# One long frame walks the hen the clock's whole frame (at least her hurried WALK_SPEED * 1.4; faster when she
			# would be late), not the engine's 8/60 s.
			moved = moved and start.distance_to(after_one) >= LivestockScene.WALK_SPEED * 1.4 * frame_s - 0.02
			var snap: Dictionary = host.snapshot()[1]
			if not snap.landing.has(id): continue
			laid += 1
			var ground := at * Livestock.model_point(spots[spot], base, walk.cell_m)
			var world: Vector3 = snap.animals[k].world
			var leaving: Vector3 = host.drop_position(id)
			var hen_gap := Vector2(world.x - ground.x, world.z - ground.z).length()
			if hen_gap <= lay.toss_m * 2.0 + 0.01: beside += 1
			if absf(Vector2(leaving.x - world.x, leaving.z - world.z).length() - hen_gap * LivestockScene.LAY_TAIL) < 0.02: tail += 1
			farm.drops = []
			host.sync(farm, rules, now)
		host.queue_free()
		await process_frame
	_check(laid == 12, "slow frames: all 12 eggs laid while watched (%d)" % laid)
	_check(moved, "slow frames: a third of a second on the clock walks the hen a third of a second's way, not the 8/60 s delta")
	_check(inside, "slow frames: the hens keep to the open floor, never in a part")
	_check(beside == 12, "slow frames: the hen is beside the spot when it lays, four turns × spots 7, 1, 2 (%d/12)" % beside)
	_check(tail == 12, "slow frames: the egg leaves the hen, from under her tail (%d/12)" % tail)

func _drop_art() -> void:
	# The egg is drawn bigger than life (SEN-C-154#145: 1.6x, PM C-154#146); the size sits on the model, not the holder.
	_check(is_equal_approx(Livestock.drop_scale("egg"), 1.6) and is_equal_approx(Livestock.drop_scale("no_such_item"), 1.0),
		"drop art: the egg is 1.6x its model, other drops 1x")
	var egg := Livestock.drop_model("egg", 0.8)
	_check(egg.scale == Vector3.ONE and (egg.get_child(0) as Node3D).scale.is_equal_approx(Vector3.ONE * 0.8 * 1.6),
		"drop art: the egg model is scaled, its holder is not")
	egg.free()
	var lay := Livestock.lay("egg")
	_check(lay.keys() == Livestock.LAY_DEFAULTS.keys() and lay.fall_s > 0.0 and lay.toss_m > 0.0 and lay.from_m > 0.0,
		"drop art: the egg's laying motion is configured")
	_check(Livestock.lay("no_such_item") == Livestock.LAY_DEFAULTS, "drop art: a drop without one lays by the defaults")

func _items() -> void:
	# Loaded here, not preloaded: it reads P0's content through autoloads that exist only once the tree runs.
	var ParcelItems = load("res://modules/dynamic_farm/parcel_items.gd")
	_check(ParcelItems.name_of("egg") == "Egg", "items: the Egg is named")
	var icon: Texture2D = ParcelItems.icon_of("egg")
	_check(icon != null and icon.get_width() == 96, "items: the Egg has its own icon")

## Whole floats to ints, all the way down (JSON reads numbers as floats).
func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v): return int(v)
	if v is Dictionary:
		var out := {}
		for k in v: out[k] = _ints(v[k])
		return out
	if v is Array: return v.map(_ints)
	return v

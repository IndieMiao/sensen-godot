extends SceneTree
## The sheep pen (C-182, 0.4.6): the client copy of the rules against the server on the shared cases
## (fixtures/sheep_pen_cases.json, also run by server/test/parcels/farm.test.ts: the blueprint after 15 delivered requests
## at farm level 3 for 1,200 coins, SEN-Q-282), the pen's art on SEN-C-180's final 6×6 scene (sheep_pen.tscn, owner
## SEN-C-180#99, layout C-180#107: the gate x 1–2 of the front, the hay feeder at (0.5, 2.5) filled from (1.5, 2.5) and
## eaten at from (0.5, 3.5), each part where the scene puts it), placing it on a parcel in all four turns, the Build key's
## material gap and the feed key's reason (three Wild Herbs), and ParcelLivestock with four sheep: they keep to the open
## floor, wool given while away lies there, wool due appears, a fed sheep goes to the feeder, a laid one is reported in reach.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_sheep_pen.gd [-- <parcel.json>...]
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
const BASE := Vector2i(6, 6)
const SCENE := "res://assets/dynamic_farm/sheep_pen/sheep_pen.tscn"
const CASES := "res://tests/dynamic_farm/fixtures/sheep_pen_cases.json"
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
	_scene_matches()
	_walls()
	_entry()
	_placement()
	for path in OS.get_cmdline_user_args():
		_fit_parcel(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_models()
	_items()
	_keys()
	await _animals()
	print("SHEEP_PEN_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The shipped pen, its livestock rule and Scott's price and unlock; malformed ones are refused as the server refuses them.
func _rules() -> void:
	var rules := ParcelFarm.rules()
	var pen: Dictionary = rules.buildings.sheep_pen
	_check(pen.width == 6 and pen.depth == 6 and pen.get("cutouts", []) == [] and pen.max == 1 and pen.blueprint == "blueprint_sheep_pen"
		and pen.materials == {"wood": 15, "stone": 15}, "pen: 6×6, one per parcel, its blueprint and 15 Timber + 15 Stone")
	var l: Dictionary = pen.livestock
	_check(l.animals == ["sheep", "sheep", "sheep", "sheep"] and l.feed == "wild_herb" and l.feed_amount == 3 and l.product == "wool"
		and l.amount == 1 and l.produce_seconds == 1800 and l.max_ground == 4 and l.spots.size() >= 4,
		"pen: four sheep, 3 Wild Herbs give a wool in 30 min, 4 on the ground (SEN-Q-282)")
	_check(rules.economy.blueprints.sheep_pen == {"item": "blueprint_sheep_pen", "amount": 1, "min_sales": 0, "min_level": 3, "min_requests": 15,
		"coins": 1200}, "Scott: the sheep pen blueprint 1,200 coins after 15 delivered requests at farm level 3 (SEN-Q-282)")
	_check(rules.economy.blueprints.barn.min_requests == 0 and rules.economy.blueprints.coop.min_requests == 0,
		"the barn's and the coop's blueprints ask for no requests")
	_check(rules.economy.sell_prices.wool == 30 and rules.energy.costs.feed == 1, "wool sells for 30; feeding 1 Energy")
	_check(rules.requests.templates.wool_bundle == {"item": "wool", "building": "sheep_pen"}, "the board asks for wool once a sheep pen stands")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(change: Callable) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		change.call(copy)
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call(func(_c): pass), "rules: the shipped pen parses")
	_check(bad.call(func(c): c.buildings.sheep_pen.livestock.spots.append([6.5, 1])), "rules: a spot outside the 6×6 footprint refused")
	var requests := func(n) -> Dictionary:
		var copy: Dictionary = raw.duplicate(true)
		copy.economy.blueprints.sheep_pen.min_requests = n
		return ParcelFarm.parse_rules(copy).economy.blueprints
	_check(not requests.call(-1).has("sheep_pen") and not requests.call(100001).has("sheep_pen") and not requests.call(1.5).has("sheep_pen")
		and requests.call(0).sheep_pen.min_requests == 0 and requests.call(100000).sheep_pen.min_requests == 100000,
		"rules: a request count out of 0–100000 is left out, as the server refuses it")

func _cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	_check(shared is Dictionary and shared.cases.size() >= 30, "pen cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
		var got := {"ok": true, "buildings": r.state.buildings, "drops": r.state.drops, "drop_seq": r.state.drop_seq, "bag": r.state.bag,
			"energy": r.state.energy, "coins": r.state.coins, "blueprints_claimed": r.state.blueprints_claimed,
			"requests_done": r.state.requests_done} if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "pen case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "pen case '%s': the input save is untouched" % c.name)

## Wool and sheep survive the save's JSON; a request delivered in the same batch opens the blueprint (the 15th).
func _saves() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	var fed: Dictionary = {}
	for c: Dictionary in shared.cases:
		if str(c.name).begins_with("four sheep"): fed = ParcelFarm.apply(rules, ParcelFarm.normalize(c.farm), c.commands, int(c.now)).state
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(fed)))
	_check(not fed.is_empty() and fed.drops.size() == 4 and JSON.stringify(reread, "", true) == JSON.stringify(fed, "", true),
		"saves: the wool on its way and the sheep read back as written")
	var farm := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": T0,
		"coins": 1300, "level": 3, "requests_done": 14})
	var board := ParcelFarm.view(rules, farm, T0)
	var req: Dictionary = board.board.slots[0].req
	board.bag[req.item] = int(req.qty)
	var out := ParcelFarm.apply(rules, board, [{"type": "deliver_request", "request": int(req.id)}, {"type": "claim_blueprint", "blueprint": "sheep_pen"}], T0 + 1000)
	_check(out.ok and out.state.requests_done == 15 and out.state.bag.get("blueprint_sheep_pen") == 1,
		"saves: the 15th delivered request opens the blueprint in the same batch")
	var early := ParcelFarm.apply(rules, board, [{"type": "claim_blueprint", "blueprint": "sheep_pen"}], T0 + 1000)
	_check(not early.ok and early.code == "CONDITION_NOT_MET" and early.detail == {"requests_done": 14, "min_requests": 15}, "saves: at 14 it does not")

## The art file: the fence leaves the gate open; walls are the runs and the parts; the feeder, its fill and eat points
## and the wool spots inside.
func _layout() -> void:
	var runs := Livestock.fence_runs("sheep_pen", BASE)
	_check(runs.size() == 5, "layout: four sides, the front split by the gate (%d runs)" % runs.size())
	var front := runs.filter(func(r): return is_equal_approx(r.from.y, 6.0) and is_equal_approx(r.to.y, 6.0))
	_check(front.size() == 2 and is_equal_approx(front[0].from.x, 0.0) and is_equal_approx(front[0].to.x, 1.0) and front[0].open_to
		and is_equal_approx(front[1].from.x, 2.0) and is_equal_approx(front[1].to.x, 6.0) and front[1].open_from, "layout: the gate is x 1–2 of the front")
	_check(Livestock.profiles("sheep_pen", BASE, 0.8).size() == runs.size() + Livestock.parts("sheep_pen").size(), "layout: a wall per run and per part")
	_check(Livestock.feeders("sheep_pen") == [Vector2(0.5, 2.5)], "layout: one feeder, the hay feeder at (0.5, 2.5)")
	_check(Livestock.refill_points("sheep_pen") == [Vector2(1.5, 2.5)] and Livestock.eat_points("sheep_pen") == [Vector2(0.5, 3.5)],
		"layout: filled from (1.5, 2.5), the sheep eat at (0.5, 3.5) (C-182#13)")
	var art := Livestock.building_art("sheep_pen")
	_check(art.entry == [1.5, 6.0], "layout: the entry is the gate's middle (1.5, 6)")
	var kept := Livestock.keep_clear("sheep_pen", BASE)
	_check(kept.size() == 1 and kept[0].walk and kept[0].cell == Vector2i(1, 6), "layout: the cell outside the gate (1.5, 6.5) is kept walkable")
	var sheep := float(Livestock.animal_art("sheep").radius)
	var open_at := func(p: Vector2, radius: float) -> bool:
		var open := Livestock.floor_rect("sheep_pen", BASE, radius).has_point(p)
		for r: Rect2 in Livestock.blocked_rects("sheep_pen", radius): open = open and not r.has_point(p)
		return open
	_check(open_at.call(Vector2(0.5, 3.5), sheep), "layout: a sheep fits where it eats")
	_check(open_at.call(Vector2(1.5, 2.5), 0.3 / 0.8), "layout: the player fits where the feeder is filled from")
	var toss := float(Livestock.lay("wool").toss_m) / 0.8
	for spot: Vector2 in ParcelFarm.rules().buildings.sheep_pen.livestock.spots:
		var free: bool = open_at.call(spot, 0.05)
		# A sheep has somewhere to stand beside it to give the wool (the eight points ParcelLivestock tries).
		var stands := 0
		for k in 8:
			if open_at.call(spot + Vector2(toss, 0).rotated(float(k) * TAU / 8.0), sheep): stands += 1
		_check(free and stands > 0, "layout: wool spot %s on the open floor, a sheep can stand beside it (%d)" % [spot, stands])
	var model := Building.model("sheep_pen", BASE, 0.8)
	_check(model != null and str(art.scene) == SCENE and ResourceLoader.exists(SCENE) and model.get_node_or_null("Placeholder") == null,
		"layout: the pen is SEN-C-180's scene")
	model.free()
	_check(Building.kind("sheep_pen").name == "Sheep Pen" and Building.kind("sheep_pen").get("livestock", false), "layout: Build Sheep Pen from the art file's name")

## The rules and the art file say what SEN-C-180's scene says: its 6×6 footprint, the gate (entry), the cell kept clear, the
## feeder's centre, where it is filled (refill) and eaten at (eat), and each part's model where the scene puts it, its size
## the model's measured bounds (the gate leaf turned with its node).
func _scene_matches() -> void:
	var pen: Node3D = (load(SCENE) as PackedScene).instantiate()
	var art := Livestock.building_art("sheep_pen")
	var feeder: Dictionary = Livestock.parts("sheep_pen").filter(func(p): return p.feeder)[0]
	_check(pen.get_meta("footprint_cells") == BASE and pen.get_meta("entry") == Vector2(art.entry[0], art.entry[1])
		and pen.get_meta("keep_clear_cell") == Vector2i(1, 6) and pen.get_meta("refill") == feeder.refill and pen.get_meta("eat") == feeder.eat,
		"scene: 6×6, the gate (1.5, 6), (1, 6) kept clear, filled from (1.5, 2.5), eaten at (0.5, 3.5)")
	_check(is_equal_approx(float(pen.get_meta("gate_clear_u")), 2.0 - 1.0 - float(art.fence.thickness)), "scene: 0.875 between the gate posts")
	var nodes := {"shelter": ["SheepShelter"], "water_trough": ["LongWaterTrough"], "feeder": ["HayFeeder"], "bale": ["BoundBaleA", "BoundBaleB"],
		"gate_leaf": ["OpenGate"]}
	var used := {}
	for p: Dictionary in Livestock.parts("sheep_pen"):
		var found := false
		for name: String in nodes.get(p.id, []):
			if used.has(name): continue
			var node: Node3D = pen.get_node(name)
			var bounds := AABB()
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				var box: AABB = (node.transform * _local_to(node, mesh)) * mesh.get_aabb()
				bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
			var size := Vector2(bounds.size.x, bounds.size.z)
			var mid := Vector2(bounds.get_center().x, bounds.get_center().z)
			var model_ok: bool = p.model.is_empty() or str(node.scene_file_path) == p.model
			if mid.distance_to(p.center) < 0.03 and absf(size.x - p.size.x) < 0.03 and absf(size.y - p.size.y) < 0.03 and model_ok:
				used[name] = true
				found = true
				break
		_check(found, "scene: %s at %s, %s is a node of the scene with that model and bounds" % [p.id, p.center, p.size])
	_check(used.size() == 6, "scene: every part matched one node (%s)" % [used.keys()])
	pen.free()

## The transform from `child`'s frame to `ancestor`'s, outside the tree.
static func _local_to(ancestor: Node3D, child: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = child
	while n != ancestor and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## The walls in all four turns: the player (0.3 m) passes the gate, not the fence or the parts, and stands on the floor
## and where the feeder is filled from.
func _walls() -> void:
	var walk := Walk.new(Data.decode(Fixture.farm()))
	for turns in 4:
		var at := Building.transform(walk, Vector2i(2, 2), BASE, turns)
		var proxies := Building.proxies(walk, "sheep_pen", Vector2i(2, 2), BASE, turns)
		var blocked := func(local: Vector2) -> bool:
			var p := at * Livestock.model_point(local, BASE, walk.cell_m)
			return proxies.any(func(x): return x.touches(p, BODY))
		_check(not blocked.call(Vector2(1.5, 6.0)) and not blocked.call(Vector2(1.5, 5.3)) and not blocked.call(Vector2(1.5, 6.6)),
			"walls turned %d: in and out through the gate" % turns)
		_check(blocked.call(Vector2(3.5, 6.0)) and blocked.call(Vector2(0.4, 6.0)) and blocked.call(Vector2(3.0, 0.0)) and blocked.call(Vector2(0.0, 4.0))
			and blocked.call(Vector2(6.0, 4.0)), "walls turned %d: the fence stops the player" % turns)
		_check(blocked.call(Vector2(4.5, 1.0)) and blocked.call(Vector2(0.5, 1.0)) and blocked.call(Vector2(0.5, 2.5)) and blocked.call(Vector2(4.5, 2.5))
			and blocked.call(Vector2(5.46, 2.5)) and blocked.call(Vector2(1.02, 5.5)),
			"walls turned %d: the shelter, the water trough, the hay feeder, the bales and the open gate leaf stop the player" % turns)
		_check(not blocked.call(Vector2(3.0, 4.0)) and not blocked.call(Vector2(1.5, 2.5)) and not blocked.call(Vector2(2.0, 1.0)),
			"walls turned %d: the floor is open, beside the feeder and behind it too" % turns)

## The real walker pushed straight in, and at a slant, from one cell outside the gate gets onto the floor in each turn.
func _entry() -> void:
	var data := Data.decode(Fixture.farm())
	var at := Vector2i(10, 10)
	var failed := []
	var total := 0
	for turns in 4:
		var walk := Walk.new(data)
		var frame := Building.transform(walk, at, BASE, turns)
		var back := frame.affine_inverse()
		for proxy in Building.proxies(walk, "sheep_pen", at, BASE, turns): walk.add_prop(proxy)
		var world := func(local: Vector2) -> Vector3: return frame * Livestock.model_point(local, BASE, walk.cell_m)
		for degrees: float in [0.0, 30.0, 50.0]:
			for side in [-1.0, 1.0]:
				for aim: float in [-0.2, 0.0, 0.2]:
					total += 1
					var a := deg_to_rad(degrees)
					var heading := Vector2(side * sin(a), -cos(a))
					var start: Vector2 = Vector2(1.5 + aim, 6.0) - heading / cos(a)
					walk.position = world.call(start)
					var direction: Vector3 = (world.call(start + heading) - world.call(start)).normalized()
					var inside := false
					for _frame in 360:
						walk.move(direction * 3.75 / 60.0)
						var now := Livestock.local_point(back * walk.position, BASE, walk.cell_m)
						if now.y < 5.3 and now.x > 0.0 and now.x < 6.0:
							inside = true
							break
					if not inside: failed.append("t%d %+d° aim %+.2f" % [turns, int(side * degrees), aim])
	_check(failed.is_empty(), "entry: %d walks in, four turns, up to 50°, all get in (failed %s)" % [total, failed])

## On the synthetic parcel the pen finds a spot in each turn, its kept gate cell clear; a solid obstacle on that cell
## refuses it.
func _placement() -> void:
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var path := Space.protected_path(data)
	for turns in 4:
		var spot = Building.nearest(data, data.spawn, BASE, {}, path, walk.reserved, turns, "sheep_pen")
		_check(spot != null and Building.reason(data, spot, BASE, turns, {}, path, walk.reserved, "sheep_pen") == "",
			"placement turned %d: the pen fits the parcel's core" % turns)
		if spot == null: continue
		var kept: Array = Building.apron("sheep_pen", spot, BASE, turns).walk
		var footprint := Building.cells(spot, BASE, turns)
		_check(footprint.size() == 36 and kept.size() == 1 and not footprint.has(kept[0])
			and Building.reason(data, spot, BASE, turns, {}, path, walk.reserved.merged({kept[0]: true}), "sheep_pen") == Building.TAKEN,
			"placement turned %d: 36 cells; a solid obstacle on the cell outside the gate refuses it" % turns)
		# The kept cell is the one the gate opens onto, turned with the building.
		var frame := Building.transform(walk, spot, BASE, turns)
		_check(walk.cell_at(frame * Livestock.model_point(Vector2(1.5, 6.5), BASE, walk.cell_m)) == kept[0],
			"placement turned %d: the kept cell %s is outside the model's gate" % [turns, kept[0]])

## On a real parcel (the pinned r4 fixtures), every pen spot the placement accepts in each turn keeps its gate cell in
## the core and off solid obstacles, and a solid obstacle there refuses it. How many spots each turn has is printed, not
## asserted: a small yard may have none (SEN-C-193).
func _fit_parcel(raw: Dictionary) -> void:
	var data := Data.decode(raw)
	if not data.ok: return
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var layout: Array = planned.core_obstacles.layout
	var obstacles := {}
	for item: Dictionary in layout: obstacles[item.cell] = true
	var path := Space.protected_path(data)
	var taken := Building.blocked({}, {})
	var stones := Building.solid(layout, obstacles)
	var exact := true
	var counts := []
	for turns in 4:
		var spots := 0
		for y in range(-1, data.grid_size.y):
			for x in range(-1, data.grid_size.x):
				var at := Vector2i(x, y)
				var why := Building.reason(data, at, BASE, turns, taken, path, walk.reserved, "sheep_pen")
				var kept := Building.apron_cells("sheep_pen", at, BASE, turns)
				if kept.any(func(c): return not data.by_cell.has(c) or data.by_cell[c].zone != "core"):
					exact = exact and why == Building.OUTSIDE
				if why != "": continue
				spots += 1
				if kept.any(func(c): return stones.has(c)):
					exact = exact and Building.reason(data, at, BASE, turns, taken, path, walk.reserved.merged(stones), "sheep_pen") == Building.TAKEN
		counts.append(spots)
	_check(exact, "%s: every pen spot keeps its gate cell in the core, off solid obstacles" % data.block_id)
	print("SHEEP_PEN fit parcel=%s pen_spots=%s" % [data.block_id, counts])

## SEN-C-180's sheep (three clips, scaled once by cell_m, facing +Z) and wool; the sheep keeps 0.4 cells to the fence and
## the parts.
func _models() -> void:
	var made := Livestock.animal("sheep", 0.8)
	var body: Node3D = made.node
	_check(is_equal_approx(float(made.radius), 0.4), "sheep: keeps 0.4 cells to the fence and the parts")
	var player: AnimationPlayer = made.player
	_check(player != null and ["walk", "peck", "idle"].all(func(k): return player.has_animation(str(made.clips[k]))),
		"sheep: the walk, graze and idle clips are the model's (%s)" % [player.get_animation_list() if player != null else []])
	var bounds := AABB()
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = _local_to(body, mesh) * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.size != Vector3.ZERO else box
	_check(absf(bounds.size.z - 1.045 * 0.8) < 0.05 and absf(bounds.size.x - 0.592 * 0.8) < 0.05,
		"sheep: %.2f m long along its facing, scaled once by cell_m (%s)" % [1.045 * 0.8, bounds.size])
	# Faces −Z of its pivot (where ParcelLivestock walks it): the tail is toward +Z.
	var skeleton: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var tail := _local_to(body, skeleton) * skeleton.get_bone_global_rest(skeleton.find_bone("Tail")).origin
	_check(tail.z > 0.2, "sheep: the tail behind, so it walks head first (tail at %s)" % tail)
	body.free()
	var wool := Livestock.drop_model("wool", 0.8)
	_check(wool.get_child_count() == 1 and wool.get_node_or_null("Placeholder") == null, "wool: SEN-C-180's model on the ground")
	wool.free()

func _items() -> void:
	# Loaded here, not preloaded: it reads P0's content through autoloads that exist only once the tree runs.
	var ParcelItems = load("res://modules/dynamic_farm/parcel_items.gd")
	_check(ParcelItems.name_of("wool") == "Wool" and ParcelItems.name_of("blueprint_sheep_pen") == "Sheep Pen Blueprint", "items: Wool, Sheep Pen Blueprint")
	_check(load("res://modules/p0/p0_logic.gd").plural("Wool") == "Wool", "items: `3 Wool`, not `3 Wools`")
	var icon: Texture2D = ParcelItems.icon_of("wool")
	_check(icon != null and icon.get_width() == 96, "items: wool has a drawn icon")
	var img := icon.get_image()
	_check(img.get_pixel(48, 52).a > 0.9 and img.get_pixel(48, 52).r > 0.8 and img.get_pixel(3, 3).a == 0.0 and img.get_pixel(48, 92).a == 0.0,
		"items: a cream fleece on a clear square")
	_check(ParcelItems.icon_of("blueprint_sheep_pen") != null, "items: the pen blueprint shows the recipe card")

## The keys' reasons: the feed key's (three Wild Herbs, `Need N more Wild Herb`, shown whole or short on the key) and the
## Build key's material gap (`Need N more Timber`, the item names as the bag shows them).
func _keys() -> void:
	var farming: Node = load("res://scenes/dynamic_farm/parcel_farming.gd").new()
	var rules := ParcelFarm.rules()
	var pen: Dictionary = rules.buildings.sheep_pen.livestock
	var herb := str(farming.item_name("wild_herb"))
	_check(farming.feed_gap(pen, 0) == "Need 3 more %s" % herb and farming.feed_gap(pen, 2) == "Need 1 more %s" % herb,
		"feed key: three Wild Herbs a sheep (%s / %s)" % [farming.feed_gap(pen, 0), farming.feed_gap(pen, 2)])
	var key_copy: Callable = farming.get_script().key_copy
	var shown: String = key_copy.call(farming.feed_gap(pen, 0), farming.feed_gap(pen, 0, true))
	_check(UiSceneAction.cost_fits(shown) and shown.begins_with("Need 3 more"), "feed key: shows whole on the key as `%s`" % shown)
	var copy: Dictionary = Livestock.building_art("sheep_pen").copy
	for k: String in ["fed", "full"]:
		var line: String = key_copy.call(str(copy[k]), str(copy.get(k + "_short", "")))
		_check(UiSceneAction.cost_fits(line), "feed key: the pen's `%s` shows whole as `%s`" % [copy[k], line])
	var state := ParcelFarm.empty_state()
	state.bag = {"wild_herb": 2}
	var b := {"id": 1, "type": "sheep_pen", "animals": ["sheep", "sheep", "sheep", "sheep"]}
	state.buildings = [b]
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "NO_FEED", "feed key: two Wild Herbs are not enough")
	state.bag.wild_herb = 3
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "", "feed key: three feed")
	farming.farm = {"bag": {"wood": 10, "stone": 15}}
	var dyn: Node = load("res://scenes/dynamic_farm/dynamic_farm.gd").new()
	dyn._farming = farming
	_check(dyn.build_gap("sheep_pen") == "Need 5 more %s" % farming.item_name("wood"), "build key: %s" % dyn.build_gap("sheep_pen"))
	farming.farm = {"bag": {"wood": 15, "stone": 3}}
	_check(dyn.build_gap("sheep_pen") == "Need 12 more %s" % farming.item_name("stone"), "build key: %s" % dyn.build_gap("sheep_pen"))
	farming.farm = {"bag": {"wood": 15, "stone": 15}}
	_check(dyn.build_gap("sheep_pen") == "", "build key: with the materials no gap")
	dyn.free()
	farming.free()

func _animals() -> void:
	seed(182)
	var rules := ParcelFarm.rules()
	var walk := Walk.new(Data.decode(Fixture.farm()))
	var host := LivestockScene.new()
	host.setup(walk)
	root.add_child(host)
	var farm := ParcelFarm.empty_state()
	farm.buildings = [{"id": 1, "type": "sheep_pen", "model": "sheep_pen", "x": 2, "y": 2, "width": 6, "depth": 6, "rotation": 1,
		"built_at": T0, "animals": ["sheep", "sheep", "sheep", "sheep"]}]
	farm.drops = [{"id": 1, "item": "wool", "amount": 1, "building": 1, "animal": 0, "spot": 1, "ready_at": T0 - 1000},
		{"id": 2, "item": "wool", "amount": 1, "building": 1, "animal": 1, "spot": 3, "ready_at": T0 + 5000}]
	farm.drop_seq = 2
	host.sync(farm, rules, T0)
	var snap: Dictionary = host.snapshot()
	_check(snap.has(1) and snap[1].animals.size() == 4, "animals: four sheep in the pen")
	_check(snap[1].drops == [1], "animals: the wool given while away lies there, the one not due yet does not")
	_check(host.covers(Vector2i(2, 2)) and host.covers(Vector2i(7, 7)) and not host.covers(Vector2i(8, 2)), "animals: the pen's cells are its floor")
	var wool: Vector3 = host.drop_position(1)
	_check(host.update(0.016, wool + Vector3(3, 0, 0), T0).is_empty() and host.update(0.016, wool + Vector3(0.5, 0, 0), T0) == [1],
		"pickup: wool 0.5 m away is in reach, 3 m is not")
	var b: Dictionary = farm.buildings[0]
	var frame := Building.transform(walk, Building.at_of(b), BASE, 1)
	# The player on the open floor in the middle-right, away from where the second sheep goes to give its wool.
	var middle := frame * Livestock.model_point(Vector2(3.0, 4.5), BASE, walk.cell_m)
	var radius := float(Livestock.animal_art("sheep").radius)
	var inside := true
	for i in 600:
		host.update(1.0 / 60.0, middle, T0 + i * 8)
		for a: Dictionary in host.snapshot()[1].animals:
			var p: Vector2 = a.pos
			inside = inside and Livestock.floor_rect("sheep_pen", BASE, radius).grow(0.01).has_point(p)
			for r: Rect2 in Livestock.blocked_rects("sheep_pen", radius): inside = inside and not r.grow(-0.01).has_point(p)
	_check(inside, "animals: the sheep always on the open floor, never in a part")
	host.update(0.016, middle + Vector3(30, 0, 30), T0 + 6000)
	_check(host.snapshot()[1].drops.has(2), "animals: the wool appears when it is due")
	farm.drops.append({"id": 3, "item": "wool", "amount": 1, "building": 1, "animal": 2, "spot": 0, "ready_at": T0 + 1800000})
	host.sync(farm, rules, T0 + 7000)
	_check(host.snapshot()[1].animals[2].errand == "feed", "animals: a fed sheep goes to the feeder")
	_check((host._yards[1].animals[2].target as Vector2).distance_to(Vector2(0.5, 3.5)) < 0.01, "animals: to (0.5, 3.5), in front of the hay feeder")
	var feeder := frame * Livestock.model_point(Livestock.feeders("sheep_pen")[0], BASE, walk.cell_m)
	var stand := frame * Livestock.model_point(Vector2(1.5, 2.5), BASE, walk.cell_m)
	var near_stand := host.feeder_near(stand + (stand - feeder).normalized() * 0.5, 1.1)
	_check(not host.feeder_near(feeder + (stand - feeder).normalized() * 0.6, 1.1).is_empty() and not near_stand.is_empty()
		and (near_stand.point as Vector3).is_equal_approx(feeder) and (near_stand.stand as Vector3).is_equal_approx(stand)
		and host.feeder_near(frame * Livestock.model_point(Vector2(4.5, 4.5), BASE, walk.cell_m), 1.1).is_empty(),
		"feeding: the key's feeder within 1.1 m of the hay feeder or of where it is filled from")
	farm.drops = []
	host.sync(farm, rules, T0 + 8000)
	_check(host.snapshot()[1].drops.is_empty(), "animals: picked wool leaves the ground")
	host.queue_free()
	await process_frame

## JSON numbers back to ints, so the client's and the server's results compare as text.
func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 9.0e15: return int(v)
	if v is Array: return v.map(func(x): return _ints(x))
	if v is Dictionary:
		var out := {}
		var keys: Array = v.keys()
		keys.sort()
		for k in keys: out[k] = _ints(v[k])
		return out
	return v

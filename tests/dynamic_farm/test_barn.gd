extends SceneTree
## The barn (C-181, 0.4.6): the client copy of the rules against the server on the shared cases (fixtures/barn_cases.json,
## also run by server/test/parcels/farm.test.ts), the barn's art (fence with the entry open, walls, the feeder, the
## placeholder yard, cow and milk while SEN-C-179's art is not in), placing it on a parcel in all four turns, the Build
## key's material gap and the feed key's reason (shown whole on the key, C-192), and ParcelLivestock with two cows: they
## keep to the open floor and step away from the player, milk given while away lies there, milk due appears, a laid one is reported in reach.
## C-202: SEN-C-179's final yard (cow_barn.tscn): 11×6 less the rear-left 2×2 (the rules' `cutouts`, free for anything
## else), the gate x 5–7 of the front, the trough left of it filled from its right end, its parts where the scene puts them.
## C-209: a C-192 8×6 barn (no cutouts) in an old save is taken down and given back when read, as the server reads it.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_barn.gd
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
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const T0 := 1795406400000
const BODY := 0.3
const BASE := Vector2i(11, 6)
## C-202: the barn's cutout, the rear-left 2×2 (owner SEN-Q-300).
const CUT := [[0, 0, 2, 2]]
const SCENE := "res://assets/dynamic_farm/cow_barn/cow_barn.tscn"
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
	_draft_barn()
	_layout()
	_walls()
	_entry()
	_placement()
	for path in OS.get_cmdline_user_args():
		_fit_parcel(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_placeholders()
	_items()
	_keys()
	await _animals()
	print("BARN_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The shipped barn, its livestock rule and Scott's price; malformed ones are refused as the server refuses them.
func _rules() -> void:
	var rules := ParcelFarm.rules()
	var barn: Dictionary = rules.buildings.barn
	_check(barn.width == 11 and barn.depth == 6 and barn.cutouts == CUT and barn.max == 1 and barn.blueprint == "blueprint_barn"
		and barn.materials == {"wood": 20, "stone": 10}, "barn: 11×6 less the rear-left 2×2, one per parcel, its blueprint and 20 Timber + 10 Stone")
	var l: Dictionary = barn.livestock
	_check(l.animals == ["cow", "cow"] and l.feed == "crop_carrot" and l.feed_amount == 2 and l.product == "milk" and l.amount == 1 \
		and l.produce_seconds == 900 and l.max_ground == 2 and l.spots.size() >= 2, "barn: two cows, 2 carrots give a milk in 15 min, 2 on the ground (SEN-Q-282)")
	_check(rules.buildings.coop.livestock.feed_amount == 1, "coop: a hen still eats one carrot (feed_amount defaults to 1)")
	_check(rules.economy.blueprints.barn == {"item": "blueprint_barn", "amount": 1, "min_sales": 0, "min_level": 2, "min_requests": 0, "coins": 600}
		and rules.economy.blueprints.coop.coins == 0 and rules.economy.blueprints.coop.min_level == 1,
		"Scott: the barn blueprint 600 coins from farm level 2 (SEN-Q-282), the coop's still free at any level")
	_check(rules.economy.sell_prices.milk == 45 and rules.energy.costs.feed == 1, "milk sells for 45; feeding 1 Energy")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(change: Callable) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		change.call(copy)
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call(func(_c): pass), "rules: the shipped barn parses")
	_check(bad.call(func(c): c.buildings.barn.livestock.feed_amount = 0), "rules: feeding 0 refused")
	_check(bad.call(func(c): c.buildings.barn.livestock.feed_amount = 100), "rules: feeding 100 refused")
	_check(bad.call(func(c): c.buildings.barn.livestock.spots.append([12, 1])), "rules: a spot outside the 11×6 footprint refused")
	_check(bad.call(func(c): c.buildings.barn.livestock.spots.append([1, 1])), "rules: a spot in the cutout refused (C-202)")
	_check(not bad.call(func(c): c.buildings.barn.livestock.spots.append([2, 1])), "rules: a spot on the cutout's edge is the barn's")
	for cut in [[[0, 0, 0, 2]], [[10, 0, 2, 1]], [[0, 5, 1, 2]], [[-1, 0, 1, 1]], [[0, 0, 1.5, 1]], [[0, 0, 11, 6]], [[0, 0, 2]], {}, "0,0,2,2"]:
		_check(bad.call(func(c): c.buildings.barn.cutouts = cut), "rules: cutouts %s refused, as the server refuses them" % [cut])
	_check(not bad.call(func(c): c.buildings.barn.cutouts = [[9, 4, 2, 2], [0, 0, 1, 6]]) and not bad.call(func(c): c.buildings.barn.cutouts = []),
		"rules: other cutouts inside the footprint, or none, parse")
	var many: Dictionary = raw.duplicate(true)
	many.buildings.barn.cutouts = []
	many.buildings.barn.cutouts.resize(9)
	many.buildings.barn.cutouts.fill([0, 0, 1, 1])
	_check(ParcelFarm.parse_rules(many).is_empty(), "rules: at most 8 cutouts")
	var priced := func(coins) -> Dictionary:
		var copy: Dictionary = raw.duplicate(true)
		copy.economy.blueprints.barn.coins = coins
		return ParcelFarm.parse_rules(copy).economy.blueprints
	_check(not priced.call(-1).has("barn") and not priced.call(100001).has("barn") and priced.call(0).barn.coins == 0,
		"rules: a blueprint priced out of 0–100000 is left out, as the server refuses it")
	var leveled := func(level) -> Dictionary:
		var copy: Dictionary = raw.duplicate(true)
		copy.economy.blueprints.barn.min_level = level
		return ParcelFarm.parse_rules(copy).economy.blueprints
	_check(not leveled.call(0).has("barn") and not leveled.call(100).has("barn") and not leveled.call(1.5).has("barn")
		and leveled.call(1).barn.min_level == 1 and leveled.call(99).barn.min_level == 99,
		"rules: a blueprint level out of 1–99 is left out, as the server refuses it (C-192)")

func _cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/barn_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 25, "barn cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
		var got := {"ok": true, "buildings": r.state.buildings, "drops": r.state.drops, "drop_seq": r.state.drop_seq, "bag": r.state.bag,
			"energy": r.state.energy, "coins": r.state.coins, "blueprints_claimed": r.state.blueprints_claimed} if r.ok \
			else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "barn case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "barn case '%s': the input save is untouched" % c.name)

## Milk and cows survive the save's JSON; a coop save from before the barn reads and plays as it did.
func _saves() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/barn_cases.json"))
	var fed: Dictionary = {}
	for c: Dictionary in shared.cases:
		if str(c.name).begins_with("two cows"): fed = ParcelFarm.apply(rules, ParcelFarm.normalize(c.farm), c.commands, int(c.now)).state
	var reread := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(fed)))
	_check(not fed.is_empty() and fed.drops.size() == 2 and JSON.stringify(reread, "", true) == JSON.stringify(fed, "", true),
		"saves: the milk on its way and the cows read back as written")
	var old := {"v": 1, "buildings": [{"id": 1, "type": "coop", "model": "chicken_yard", "x": 6, "y": 6, "width": 7, "depth": 5, "rotation": 0,
		"built_at": T0, "animals": ["hen_white", "hen_brown", "hen_white"]}], "house": null, "cleared": [], "tilled": [], "crops": {},
		"bag": {"crop_carrot": 3}, "welcomed_at": T0, "coins": 160, "sales": 3, "gathered": {}, "blueprints_claimed": {"coop": T0},
		"drops": [{"id": 4, "item": "egg", "amount": 1, "building": 1, "animal": 0, "spot": 2, "ready_at": T0}], "drop_seq": 4}
	var read := ParcelFarm.normalize(old)
	_check(read.drops.size() == 1 and read.drop_seq == 4 and read.bag == {"crop_carrot": 3} and read.coins == 160, "saves: a coop save reads as it was")
	var fed_hen := ParcelFarm.apply(rules, read, [{"type": "feed", "building": 1}], T0)
	_check(fed_hen.ok and fed_hen.state.bag.crop_carrot == 2, "saves: a hen still eats one carrot")
	var low := ParcelFarm.apply(rules, read, [{"type": "claim_blueprint", "blueprint": "barn"}], T0)
	_check(not low.ok and low.code == "CONDITION_NOT_MET" and low.get("detail", {}) == {"level": 1, "min_level": 2},
		"saves: read as level 1, the barn blueprint waits for level 2 (C-192)")
	var richer := read.duplicate(true)
	richer.level = 2
	richer.coins = 610
	var bought := ParcelFarm.apply(rules, richer, [{"type": "claim_blueprint", "blueprint": "barn"}], T0)
	_check(bought.ok and bought.state.coins == 10 and bought.state.bag.blueprint_barn == 1, "saves: at level 2 Scott sells it the barn blueprint")

## C-209: a C-192 8×6 barn (no cutouts) reads as taken down, as the server reads it (routes farmView): its blueprint,
## 20 Timber and 10 Stone and both milks (laid or not) in the bag, the coop and its egg left; the local store's entry
## writes that once; the 11×6 then goes down where it stood. A barn placed with its cutout stays.
func _draft_barn() -> void:
	var rules := ParcelFarm.rules()
	var old := {"v": 1, "buildings": [
		{"id": 1, "type": "cottage", "model": "cottage", "x": 2, "y": 2, "width": 3, "depth": 3, "rotation": 0, "built_at": T0},
		{"id": 2, "type": "barn", "model": "cow_barn", "x": 20, "y": 20, "width": 8, "depth": 6, "rotation": 0, "built_at": T0, "animals": ["cow", "cow"]},
		{"id": 3, "type": "coop", "model": "chicken_yard", "x": 6, "y": 10, "width": 7, "depth": 5, "rotation": 0, "built_at": T0,
			"animals": ["hen_white", "hen_brown", "hen_white"]}],
		"house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"crop_carrot": 2, "wood": 4, "stone": 2}, "welcomed_at": T0, "coins": 40,
		"sales": 2, "gathered": {}, "blueprints_claimed": {"barn": T0}, "grants": {"watering": T0}, "level": 2, "drop_seq": 6, "drops": [
		{"id": 4, "item": "milk", "amount": 1, "building": 2, "animal": 0, "spot": 1, "ready_at": T0 - 1000},
		{"id": 5, "item": "milk", "amount": 1, "building": 2, "animal": 1, "spot": 3, "ready_at": T0 + 600000},
		{"id": 6, "item": "egg", "amount": 1, "building": 3, "animal": 0, "spot": 2, "ready_at": T0}]}
	var read := ParcelFarm.normalize(old)
	var frozen := JSON.stringify(read, "", true)
	var seen := ParcelFarm.view(rules, read, T0)
	_check(seen.buildings.map(func(b): return b.type) == ["cottage", "coop"] and seen.house == read.house,
		"draft barn: read with the old 8×6 barn taken down, the cottage and the coop standing")
	_check(seen.bag == {"crop_carrot": 2, "wood": 24, "stone": 12, "blueprint_barn": 1, "milk": 2},
		"draft barn: its blueprint, 20 Timber, 10 Stone and both milks (laid or on its way) in the bag")
	_check(seen.drops.map(func(d): return d.id) == [6] and seen.drop_seq == 6, "draft barn: the coop's egg stays, drop ids go on")
	_check(JSON.stringify(read, "", true) == frozen, "draft barn: reading does not change the save")
	var placed := ParcelFarm.apply(rules, read, [{"type": "place_building", "building": "barn", "x": 20, "y": 20, "rotation": 0},
		{"type": "feed", "building": 4}], T0)
	_check(placed.ok and placed.state.buildings[2].width == 11 and placed.state.buildings[2].cutouts == CUT
		and placed.state.buildings[2].animals == ["cow", "cow"] and placed.state.bag.get("wood") == 4 and placed.state.bag.get("stone") == 2
		and placed.state.bag.get("milk") == 2 and placed.state.drops.size() == 2 and placed.state.drops[1].building == 4,
		"draft barn: the 11×6 goes down where it stood with the Timber and Stone given back, and its cows eat")
	var gone := ParcelFarm.apply(rules, read, [{"type": "pick_up", "drop": 4}], T0)
	_check(not gone.ok and gone.code == "NO_DROP", "draft barn: its milk is in the bag, not on the ground")
	var cut := read.duplicate(true)
	cut.buildings[1].width = 11
	cut.buildings[1].cutouts = CUT
	var kept := ParcelFarm.view(rules, cut, T0)
	_check(kept.buildings.size() == 3 and kept.drops.size() == 3 and kept.bag == read.bag, "draft barn: a barn placed with its cutout stays")
	var dir := "user://test_barn_%d" % Time.get_ticks_usec()
	var store := LocalStore.new("p-D", dir)
	store.now_ms = func() -> int: return T0
	store._save(read, 5)
	var entered := store.enter()
	_check(entered.ok and not entered.granted and entered.gift.is_empty() and entered.farm_version == 6 and entered.farm.bag == seen.bag
		and entered.farm.buildings.size() == 2, "draft barn: the local store's entry writes it taken down")
	var twice := store.enter()
	_check(twice.farm_version == 6 and twice.farm.bag == seen.bag and store.read().farm.bag == seen.bag, "draft barn: given back once only")
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

## The art file: the fence leaves the entry open and runs round the cutout; walls are the runs and the parts; the
## feeder and milk spots inside.
func _layout() -> void:
	var runs := Livestock.fence_runs("barn", BASE, CUT)
	_check(runs.size() == 7, "layout: four sides, the front split by the entry, the back and left short of the cutout, two round it (%d runs)" % runs.size())
	var front := runs.filter(func(r): return is_equal_approx(r.from.y, 6.0) and is_equal_approx(r.to.y, 6.0))
	_check(front.size() == 2 and is_equal_approx(front[0].from.x, 0.0) and is_equal_approx(front[0].to.x, 5.0) and front[0].open_to
		and is_equal_approx(front[1].from.x, 7.0) and is_equal_approx(front[1].to.x, 11.0) and front[1].open_from, "layout: the entry is x 5–7 of the front")
	var spans := runs.map(func(r): return [r.from, r.to])
	for want: Array in [[Vector2(2, 0), Vector2(11, 0)], [Vector2(0, 2), Vector2(0, 6)], [Vector2(11, 0), Vector2(11, 6)],
			[Vector2(0, 2), Vector2(2, 2)], [Vector2(2, 0), Vector2(2, 2)]]:
		_check(spans.has(want), "layout: a fence run from %s to %s (the model's posts)" % want)
	_check(Livestock.fence_runs("barn", BASE).size() == 5, "layout: without cutouts the plain rectangle's five runs")
	_check(Livestock.fence_runs("coop", Vector2i(7, 5)).size() == 5 and Livestock.fence_runs("coop", Vector2i(7, 5), []).size() == 5,
		"layout: the coop's fence unchanged")
	_check(Livestock.profiles("barn", BASE, 0.8, CUT).size() == runs.size() + Livestock.parts("barn").size(), "layout: a wall per run and per part")
	var feeders := Livestock.feeders("barn")
	_check(feeders.size() == 1 and feeders[0] == Vector2(4.0, 5.5), "layout: one feeder, the trough at (4, 5.5) left of the gate")
	_check(Livestock.refill_points("barn") == [Vector2(5.5, 5.5)] and Livestock.eat_points("barn") == [Vector2(4.0, 4.5)],
		"layout: filled from (5.5, 5.5) at its right end, the cows eat at (4, 4.5) behind it")
	_check(Livestock.refill_points("coop") == [null, null] and Livestock.eat_points("coop") == [null, null], "layout: the coop's feeders say neither")
	var cow := float(Livestock.animal_art("cow").radius)
	var open_at := func(p: Vector2, radius: float) -> bool:
		var open := Livestock.floor_rect("barn", BASE, radius).has_point(p)
		for r: Rect2 in Livestock.blocked_rects("barn", radius, CUT): open = open and not r.has_point(p)
		return open
	_check(open_at.call(Vector2(4.0, 4.5), cow), "layout: a cow fits where it eats")
	_check(not open_at.call(Vector2(1.0, 1.0), 0.05) and not open_at.call(Vector2(2.5, 2.5), cow) and open_at.call(Vector2(2.5, 2.5), 0.05),
		"layout: no cow in the cutout or against its fence")
	var toss := float(Livestock.lay("milk").toss_m) / 0.8
	for spot: Vector2 in ParcelFarm.rules().buildings.barn.livestock.spots:
		var free: bool = open_at.call(spot, 0.05)
		# A cow has somewhere to stand beside it to give the milk (the eight points ParcelLivestock tries).
		var stands := 0
		for k in 8:
			if open_at.call(spot + Vector2(toss, 0).rotated(float(k) * TAU / 8.0), cow): stands += 1
		_check(free and stands > 0, "layout: milk spot %s on the open floor, a cow can stand beside it (%d)" % [spot, stands])
	var model := Building.model("barn", BASE, 0.8)
	var scene := str(Livestock.building_art("barn").scene)
	_check(model != null and scene == SCENE and ResourceLoader.exists(scene) and model.get_node_or_null("Placeholder") == null,
		"layout: the barn is SEN-C-179's scene")
	model.free()
	_scene_matches()
	_check(Building.kind("barn").name == "Barn" and Building.kind("barn").get("livestock", false), "layout: Build Barn from the art file's name")
	var kept := Livestock.keep_clear("barn", BASE)
	_check(kept.size() == 2 and kept.all(func(k): return k.walk) and kept.map(func(k): return k.cell) == [Vector2i(5, 6), Vector2i(6, 6)],
		"layout: the two cells outside the gate are kept walkable")

## C-202: the rules and the art file say what SEN-C-179's scene says: its footprint and unoccupied corner, the gate
## (Entry), the trough's centre, where it is filled (Refill) and eaten at (EatingEdge), and each part's model where the
## scene puts it, its size the model's measured bounds.
func _scene_matches() -> void:
	var yard: Node3D = (load(SCENE) as PackedScene).instantiate()
	_check(yard.get_meta("footprint_cells") == BASE and yard.get_meta("unoccupied_corner") == Rect2i(0, 0, 2, 2),
		"scene: 11×6 with the rear-left 2×2 unoccupied, as the rules")
	var at := func(node: String) -> Vector2:
		var n: Node3D = yard.get_node(node)
		return Vector2(n.position.x, n.position.z)
	var art := Livestock.building_art("barn")
	var feeder: Dictionary = Livestock.parts("barn").filter(func(p): return p.feeder)[0]
	_check(at.call("Entry") == Vector2(art.entry[0], art.entry[1]) and at.call("CattleFeeder") == feeder.center
		and at.call("Refill") == feeder.refill and at.call("EatingEdge") == feeder.eat,
		"scene: the gate (6, 6), the trough (4, 5.5), filled from (5.5, 5.5), eaten at (4, 4.5)")
	var nodes := {"hay_shed": "LoadedHayShelter", "hay_rack": "SlattedHayRack", "water_trough": "WaterTrough", "feeder": "CattleFeeder"}
	for p: Dictionary in Livestock.parts("barn"):
		if not nodes.has(p.id): continue
		var node: Node3D = yard.get_node(nodes[p.id])
		var bounds := AABB()
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = _local_to(node, mesh) * mesh.get_aabb()
			bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
		var size := Vector2(bounds.size.x, bounds.size.z)
		var mid := Vector2(node.position.x, node.position.z) + Vector2(bounds.get_center().x, bounds.get_center().z)
		_check(mid.distance_to(p.center) < 0.03 and absf(size.x - p.size.x) < 0.03 and absf(size.y - p.size.y) < 0.03
			and str(node.scene_file_path) == p.model, "scene: %s at %s, %s (art: %s, %s)" % [p.id, mid, size, p.center, p.size])
	yard.free()

## The transform from `child`'s frame to `ancestor`'s, outside the tree.
static func _local_to(ancestor: Node3D, child: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = child
	while n != ancestor and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## The walls in all four turns: the player (0.3 m) passes the entry, not the fence or the parts, and stands on the floor;
## the cutout is open ground outside the fence (C-202).
func _walls() -> void:
	var walk := Walk.new(Data.decode(Fixture.farm()))
	for turns in 4:
		var at := Building.transform(walk, Vector2i(2, 2), BASE, turns)
		var proxies := Building.proxies(walk, "barn", Vector2i(2, 2), BASE, turns, CUT)
		var blocked := func(local: Vector2) -> bool:
			var p := at * Livestock.model_point(local, BASE, walk.cell_m)
			return proxies.any(func(x): return x.touches(p, BODY))
		_check(not blocked.call(Vector2(6.0, 6.0)) and not blocked.call(Vector2(6.0, 5.3)) and not blocked.call(Vector2(6.0, 6.6))
			and not blocked.call(Vector2(5.45, 6.0)) and not blocked.call(Vector2(6.55, 6.0)), "walls turned %d: in and out through the gate" % turns)
		_check(blocked.call(Vector2(2.5, 6.0)) and blocked.call(Vector2(9.0, 6.0)) and blocked.call(Vector2(5.5, 0.0)) and blocked.call(Vector2(0.0, 3.5)) \
			and blocked.call(Vector2(11.0, 3.0)) and blocked.call(Vector2(1.0, 2.0)) and blocked.call(Vector2(2.0, 1.0)),
			"walls turned %d: the fence, round the cutout too, stops the player" % turns)
		_check(not blocked.call(Vector2(1.0, 1.0)) and not blocked.call(Vector2(0.3, 0.3)), "walls turned %d: the cutout is open ground" % turns)
		_check(blocked.call(Vector2(8.0, 1.0)) and blocked.call(Vector2(4.0, 5.5)) and blocked.call(Vector2(10.5, 5.0)) and blocked.call(Vector2(1.5, 3.5))
			and blocked.call(Vector2(10.7, 2.0)) and blocked.call(Vector2(7.05, 5.5)),
			"walls turned %d: the shed, the trough, the water, the hay rack, the hedge and the open gate leaf stop the player" % turns)
		_check(not blocked.call(Vector2(5.0, 3.5)) and not blocked.call(Vector2(5.5, 5.5)) and not blocked.call(Vector2(4.0, 4.6)),
			"walls turned %d: the floor is open, at the trough's right end and behind it too" % turns)

## The real walker pushed straight in, and at a slant, from one cell outside the entry gets onto the floor in each turn.
func _entry() -> void:
	var data := Data.decode(Fixture.farm())
	var at := Vector2i(10, 10)
	var failed := []
	var total := 0
	for turns in 4:
		var walk := Walk.new(data)
		var frame := Building.transform(walk, at, BASE, turns)
		var back := frame.affine_inverse()
		for proxy in Building.proxies(walk, "barn", at, BASE, turns, CUT): walk.add_prop(proxy)
		var world := func(local: Vector2) -> Vector3: return frame * Livestock.model_point(local, BASE, walk.cell_m)
		for degrees: float in [0.0, 30.0, 50.0]:
			for side in [-1.0, 1.0]:
				for aim: float in [-0.25, 0.0, 0.25]:
					total += 1
					var a := deg_to_rad(degrees)
					var heading := Vector2(side * sin(a), -cos(a))
					var start: Vector2 = Vector2(6.0 + aim, 6.0) - heading / cos(a)
					walk.position = world.call(start)
					var direction: Vector3 = (world.call(start + heading) - world.call(start)).normalized()
					var inside := false
					for _frame in 360:
						walk.move(direction * 3.75 / 60.0)
						var now := Livestock.local_point(back * walk.position, BASE, walk.cell_m)
						if now.y < 5.3 and now.x > 0.5 and now.x < 10.5:
							inside = true
							break
					if not inside: failed.append("t%d %+d° aim %+.2f" % [turns, int(side * degrees), aim])
	_check(failed.is_empty(), "entry: %d walks in, four turns, up to 50°, all get in (failed %s)" % [total, failed])

## On the synthetic parcel the barn finds a spot in each turn, its kept entry cells clear; a cottage on that cell is
## refused. C-202: its footprint leaves the cutout out (the corner the scene's model turns to), and a building or a crop
## already in the cutout does not refuse it.
func _placement() -> void:
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var path := Space.protected_path(data)
	for turns in 4:
		var spot = Building.nearest(data, data.spawn, BASE, {}, path, walk.reserved, turns, "barn")
		_check(spot != null and Building.reason(data, spot, BASE, turns, {}, path, walk.reserved, "barn") == "",
			"placement turned %d: the barn fits the parcel's core" % turns)
		if spot == null: continue
		var kept: Array = Building.apron("barn", spot, BASE, turns).walk
		var footprint := Building.cells(spot, BASE, turns, CUT)
		_check(kept.size() == 2 and not kept.any(func(c): return footprint.has(c))
			and kept.all(func(c): return Building.reason(data, spot, BASE, turns, {}, path, walk.reserved.merged({c: true}), "barn") == Building.TAKEN),
			"placement turned %d: a solid obstacle on either cell outside the gate refuses it" % turns)
		var corner := Building.cells(spot, BASE, turns).filter(func(c): return not footprint.has(c))
		_check(footprint.size() == 62 and corner.size() == 4, "placement turned %d: 62 cells, the 2×2 cutout left out" % turns)
		# The cutout is the corner the model leaves empty: the rear-left 2×2 of the scene, turned with the building.
		var frame := Building.transform(walk, spot, BASE, turns)
		var drawn := {}
		for own in [Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(0.5, 1.5), Vector2(1.5, 1.5)]:
			drawn[walk.cell_at(frame * Livestock.model_point(own, BASE, walk.cell_m))] = true
		_check(corner.all(func(c): return drawn.has(c)), "placement turned %d: the cutout %s is the model's empty corner %s" % [turns, corner, drawn.keys()])
		var taken := {}
		for c in corner: taken[c] = true
		_check(Building.reason(data, spot, BASE, turns, taken, path, walk.reserved, "barn") == "",
			"placement turned %d: something already in the cutout does not refuse it" % turns)
		_check(Building.reason(data, spot, BASE, turns, {footprint[footprint.size() / 2]: true}, path, walk.reserved, "barn") == Building.TAKEN,
			"placement turned %d: something on its own cells does" % turns)

## C-192: on a real parcel (the pinned r4 fixtures), every barn spot the placement accepts in each turn keeps its
## entry cell in the core and off solid obstacles, and a solid obstacle there refuses it. How many spots each turn has
## is printed, not asserted: a small yard may have none (SEN-C-193), as with the coop.
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
	# The obstacles cleared, as a player does before building; solid ones still standing are judged below.
	var taken := Building.blocked({}, {})
	var stones := Building.solid(layout, obstacles)
	var exact := true
	var counts := []
	var coop := []
	for turns in 4:
		var spots := 0
		var coop_spots := 0
		for y in range(-1, data.grid_size.y):
			for x in range(-1, data.grid_size.x):
				var at := Vector2i(x, y)
				if Building.reason(data, at, Vector2i(7, 5), turns, taken, path, walk.reserved, "coop") == "": coop_spots += 1
				var why := Building.reason(data, at, BASE, turns, taken, path, walk.reserved, "barn")
				var kept := Building.apron_cells("barn", at, BASE, turns)
				if kept.any(func(c): return not data.by_cell.has(c) or data.by_cell[c].zone != "core"):
					exact = exact and why == Building.OUTSIDE
				if why != "": continue
				spots += 1
				if kept.any(func(c): return stones.has(c)):
					exact = exact and Building.reason(data, at, BASE, turns, taken, path, walk.reserved.merged(stones), "barn") == Building.TAKEN
		counts.append(spots)
		coop.append(coop_spots)
	_check(exact, "%s: every barn spot keeps its entry cell in the core, off solid obstacles" % data.block_id)
	print("BARN fit parcel=%s barn_spots=%s coop_spots=%s" % [data.block_id, counts, coop])

## Until SEN-C-179's art is in: a four-legged cow from the art's placeholder, a bottle for the milk.
func _placeholders() -> void:
	var made := Livestock.animal("cow", 0.8)
	var body: Node3D = made.node
	var holder := body.get_node_or_null("Placeholder")
	_check(ResourceLoader.exists(str(Livestock.animal_art("cow").model)) or (holder != null and holder.get_node_or_null("Head") != null
		and holder.get_node_or_null("Leg3") != null), "placeholder: the cow is a body, a head and four legs")
	# C-202: SEN-C-179's cow is 2.015 cells long and 0.8 wide, scaled once by cell_m (no extra scale); it keeps 0.6 cells
	# to the fence and the parts (C-192's stand-in kept 0.45).
	_check(is_equal_approx(float(made.radius), 0.6), "cow: keeps 0.6 cells to the fence and the parts")
	var bounds := AABB()
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = _local_to(body, mesh) * mesh.get_aabb()
		bounds = bounds.merge(box) if bounds.size != Vector3.ZERO else box
	if ResourceLoader.exists(str(Livestock.animal_art("cow").model)):
		_check(absf(bounds.size.z - 2.015 * 0.8) < 0.05 and absf(bounds.size.x - 0.803 * 0.8) < 0.05,
			"cow: SEN-C-179's cow, %.2f m long along its facing, scaled once by cell_m (%s)" % [2.015 * 0.8, bounds.size])
	else:
		_check(bounds.size.z > 0.8 and bounds.size.z < 1.2 and bounds.size.y > 0.3, "placeholder: a cow about a metre long (%s)" % bounds.size)
	body.free()
	var milk := Livestock.drop_model("milk", 0.8)
	_check(ResourceLoader.exists(str(Livestock.drop_art("milk").model)) or (milk.get_node_or_null("Placeholder/Cap") != null),
		"placeholder: the milk is a bottle with a cap")
	milk.free()
	var egg := Livestock.drop_model("egg", 0.8)
	_check(egg.get_node_or_null("Placeholder") == null, "the egg keeps its own model or egg placeholder")
	egg.free()

func _items() -> void:
	# Loaded here, not preloaded: it reads P0's content through autoloads that exist only once the tree runs.
	var ParcelItems = load("res://modules/dynamic_farm/parcel_items.gd")
	_check(ParcelItems.name_of("milk") == "Milk" and ParcelItems.name_of("blueprint_barn") == "Barn Blueprint", "items: Milk, Barn Blueprint")
	var icon: Texture2D = ParcelItems.icon_of("milk")
	_check(icon != null and icon.get_width() == 96, "items: milk has a drawn icon")
	var img := icon.get_image()
	_check(img.get_pixel(48, 60).a > 0.9 and img.get_pixel(48, 15).b > img.get_pixel(48, 15).r and img.get_pixel(5, 5).a == 0.0,
		"items: a white bottle with a blue cap on a clear square")
	_check(ParcelItems.icon_of("blueprint_barn") != null, "items: the barn blueprint shows the recipe card")

## The keys' reasons: the feed key's (two carrots, `Need N more Carrot`; the coop's `Need 1 Carrot` as before) and the
## Build key's material gap (`Need N more Timber`, the item names as the bag shows them).
func _keys() -> void:
	var farming: Node = load("res://scenes/dynamic_farm/parcel_farming.gd").new()
	var rules := ParcelFarm.rules()
	var barn: Dictionary = rules.buildings.barn.livestock
	var coop: Dictionary = rules.buildings.coop.livestock
	_check(farming.feed_gap(barn, 0) == "Need 2 more Carrot" and farming.feed_gap(barn, 1) == "Need 1 more Carrot",
		"feed key: two carrots a cow (%s / %s)" % [farming.feed_gap(barn, 0), farming.feed_gap(barn, 1)])
	_check(farming.feed_gap(coop, 0) == "Need 1 Carrot", "feed key: the coop's reason unchanged")
	# C-192: the key's second line shows whole; too wide, the shorter form (P0's `Need 2 more`), the toast keeps it all.
	var key_copy: Callable = farming.get_script().key_copy
	_check(farming.feed_gap(barn, 0, true) == "Need 2 more" and farming.feed_gap(coop, 0, true) == "Need 1",
		"feed key: the short forms (%s / %s)" % [farming.feed_gap(barn, 0, true), farming.feed_gap(coop, 0, true)])
	_check(key_copy.call(farming.feed_gap(barn, 0), farming.feed_gap(barn, 0, true)) == "Need 2 more"
		and key_copy.call(farming.feed_gap(coop, 0), farming.feed_gap(coop, 0, true)) == "Need 1 Carrot",
		"feed key: `Need 2 more Carrot` does not fit the key, `Need 1 Carrot` does")
	for type: String in ["coop", "barn"]:
		var copy: Dictionary = Livestock.building_art(type).copy
		for k: String in ["fed", "full"]:
			var shown: String = key_copy.call(str(copy[k]), str(copy.get(k + "_short", "")))
			_check(UiSceneAction.cost_fits(shown), "feed key: %s's `%s` shows whole as `%s`" % [type, copy[k], shown])
	_check(key_copy.call("Pick up milk first", "Pick up milk") == "Pick up milk first", "feed key: `Pick up milk first` fits as it is")
	var state := ParcelFarm.empty_state()
	state.bag = {"crop_carrot": 1}
	var b := {"id": 1, "type": "barn", "animals": ["cow", "cow"]}
	state.buildings = [b]
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "NO_FEED", "feed key: one carrot is not enough")
	state.bag.crop_carrot = 2
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "", "feed key: two carrots feed")
	# C-186#8: two milks on the ground and no carrots: the ground comes first (pick up), as on the server.
	state.drops = [{"id": 1, "item": "milk", "amount": 1, "building": 1, "animal": 0, "spot": 0, "ready_at": T0 - 1},
		{"id": 2, "item": "milk", "amount": 1, "building": 1, "animal": 1, "spot": 1, "ready_at": T0 - 1}]
	state.bag.crop_carrot = 0
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "GROUND_FULL", "feed key: a full ground before the missing carrots")
	state.drops = []
	farming.farm = {"bag": {"wood": 12, "stone": 10}}
	var dyn: Node = load("res://scenes/dynamic_farm/dynamic_farm.gd").new()
	dyn._farming = farming
	_check(dyn.build_gap("barn") == "Need 8 more %s" % farming.item_name("wood"), "build key: %s" % dyn.build_gap("barn"))
	farming.farm = {"bag": {"wood": 20, "stone": 3}}
	_check(dyn.build_gap("barn") == "Need 7 more %s" % farming.item_name("stone"), "build key: %s" % dyn.build_gap("barn"))
	farming.farm = {"bag": {"wood": 20, "stone": 10}}
	_check(dyn.build_gap("barn") == "" and dyn.build_gap("coop") == "", "build key: with the materials (and for the coop) no gap")
	dyn.free()
	farming.free()

func _animals() -> void:
	seed(181)
	var rules := ParcelFarm.rules()
	var walk := Walk.new(Data.decode(Fixture.farm()))
	var host := LivestockScene.new()
	host.setup(walk)
	root.add_child(host)
	var farm := ParcelFarm.empty_state()
	farm.buildings = [{"id": 1, "type": "barn", "model": "cow_barn", "x": 2, "y": 2, "width": 11, "depth": 6, "rotation": 3,
		"built_at": T0, "animals": ["cow", "cow"], "cutouts": CUT}]
	farm.drops = [{"id": 1, "item": "milk", "amount": 1, "building": 1, "animal": 0, "spot": 1, "ready_at": T0 - 1000},
		{"id": 2, "item": "milk", "amount": 1, "building": 1, "animal": 1, "spot": 3, "ready_at": T0 + 5000}]
	farm.drop_seq = 2
	host.sync(farm, rules, T0)
	var snap: Dictionary = host.snapshot()
	_check(snap.has(1) and snap[1].animals.size() == 2, "animals: two cows in the barn")
	_check(snap[1].drops == [1], "animals: the milk given while away lies there, the one not due yet does not")
	_check(host.covers(Vector2i(2, 2)) and host.covers(Vector2i(7, 9)) and not host.covers(Vector2i(8, 2)), "animals: the turned barn's cells are its floor")
	_check(not host.covers(Vector2i(7, 12)) and not host.covers(Vector2i(6, 11)) and host.covers(Vector2i(5, 12)),
		"animals: its turned cutout is not (C-202)")
	var milk: Vector3 = host.drop_position(1)
	_check(host.update(0.016, milk + Vector3(3, 0, 0), T0).is_empty() and host.update(0.016, milk + Vector3(0.5, 0, 0), T0) == [1],
		"pickup: milk 0.5 m away is in reach, 3 m is not")
	var b: Dictionary = farm.buildings[0]
	var frame := Building.transform(walk, Building.at_of(b), BASE, 3)
	# The player on the open floor left of the middle, away from spot 3 where the second cow goes to give her milk.
	var middle := frame * Livestock.model_point(Vector2(4.0, 3.0), BASE, walk.cell_m)
	var radius := float(Livestock.animal_art("cow").radius)
	var inside := true
	for i in 600:
		host.update(1.0 / 60.0, middle, T0 + i * 8)
		for a: Dictionary in host.snapshot()[1].animals:
			var p: Vector2 = a.pos
			inside = inside and Livestock.floor_rect("barn", BASE, radius).grow(0.01).has_point(p)
			for r: Rect2 in Livestock.blocked_rects("barn", radius, CUT): inside = inside and not r.grow(-0.01).has_point(p)
	_check(inside, "animals: the cows always on the open floor, never in a part or the cutout")
	var near := 0
	for a: Dictionary in host.snapshot()[1].animals:
		if (a.pos as Vector2).distance_to(Vector2(4.0, 3.0)) < 1.0: near += 1
	_check(near == 0, "animals: no cow stays within a cell of the player")
	host.update(0.016, middle + Vector3(30, 0, 30), T0 + 6000)
	_check(host.snapshot()[1].drops.has(2), "animals: the milk appears when it is due")
	farm.drops.append({"id": 3, "item": "milk", "amount": 1, "building": 1, "animal": 0, "spot": 0, "ready_at": T0 + 900000})
	host.sync(farm, rules, T0 + 7000)
	_check(host.snapshot()[1].animals[0].errand == "feed", "animals: a fed cow goes to the feeder")
	_check((host._yards[1].animals[0].target as Vector2).distance_to(Vector2(4.0, 4.5)) < 0.01, "animals: to (4, 4.5), behind the trough (C-202)")
	var feeder := frame * Livestock.model_point(Livestock.feeders("barn")[0], BASE, walk.cell_m)
	var stand := frame * Livestock.model_point(Vector2(5.5, 5.5), BASE, walk.cell_m)
	var near_stand := host.feeder_near(stand + (stand - feeder).normalized() * 0.5, 1.1)
	_check(not host.feeder_near(feeder + Vector3(0.6, 0, 0), 1.1).is_empty() and not near_stand.is_empty()
		and (near_stand.point as Vector3).is_equal_approx(feeder) and (near_stand.stand as Vector3).is_equal_approx(stand)
		and host.feeder_near(frame * Livestock.model_point(Vector2(8.5, 3.5), BASE, walk.cell_m), 1.1).is_empty(),
		"feeding: the key's feeder within 1.1 m of the trough or of where it is filled from (C-202)")
	farm.drops = []
	host.sync(farm, rules, T0 + 8000)
	_check(host.snapshot()[1].drops.is_empty(), "animals: picked milk leaves the ground")
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

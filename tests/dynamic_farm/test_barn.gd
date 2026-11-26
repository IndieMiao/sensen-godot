extends SceneTree
## The barn (C-181, 0.4.6): the client copy of the rules against the server on the shared cases (fixtures/barn_cases.json,
## also run by server/test/parcels/farm.test.ts), the barn's art (fence with the entry open, walls, the feeder, the
## placeholder yard, cow and milk while SEN-C-179's art is not in), placing it on a parcel in all four turns, the Build
## key's material gap and the feed key's reason, and ParcelLivestock with two cows: they keep to the open floor and step
## away from the player, milk given while away lies there, milk due appears, a laid one is reported in reach.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_barn.gd
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
const LivestockScene = preload("res://scenes/dynamic_farm/parcel_livestock.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const T0 := 1795406400000
const BODY := 0.3
const BASE := Vector2i(8, 6)
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
	_placement()
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
	_check(barn.width == 8 and barn.depth == 6 and barn.max == 1 and barn.blueprint == "blueprint_barn" and barn.materials == {"wood": 20, "stone": 10},
		"barn: 8×6, one per parcel, its blueprint and 20 Timber + 10 Stone")
	var l: Dictionary = barn.livestock
	_check(l.animals == ["cow", "cow"] and l.feed == "crop_carrot" and l.feed_amount == 2 and l.product == "milk" and l.amount == 1 \
		and l.produce_seconds == 900 and l.max_ground == 4 and l.spots.size() >= 4, "barn: two cows, 2 carrots give a milk in 15 min, 4 on the ground")
	_check(rules.buildings.coop.livestock.feed_amount == 1, "coop: a hen still eats one carrot (feed_amount defaults to 1)")
	_check(rules.economy.blueprints.barn == {"item": "blueprint_barn", "amount": 1, "min_sales": 0, "coins": 150}
		and rules.economy.blueprints.coop.coins == 0, "Scott: the barn blueprint 150 coins, the coop's still free")
	_check(rules.economy.sell_prices.milk == 45 and rules.energy.costs.feed == 1, "milk sells for 45; feeding 1 Energy")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(change: Callable) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		change.call(copy)
		return ParcelFarm.parse_rules(copy).is_empty()
	_check(not bad.call(func(_c): pass), "rules: the shipped barn parses")
	_check(bad.call(func(c): c.buildings.barn.livestock.feed_amount = 0), "rules: feeding 0 refused")
	_check(bad.call(func(c): c.buildings.barn.livestock.feed_amount = 100), "rules: feeding 100 refused")
	_check(bad.call(func(c): c.buildings.barn.livestock.spots.append([9, 1])), "rules: a spot outside the 8×6 footprint refused")
	var priced := func(coins) -> Dictionary:
		var copy: Dictionary = raw.duplicate(true)
		copy.economy.blueprints.barn.coins = coins
		return ParcelFarm.parse_rules(copy).economy.blueprints
	_check(not priced.call(-1).has("barn") and not priced.call(100001).has("barn") and priced.call(0).barn.coins == 0,
		"rules: a blueprint priced out of 0–100000 is left out, as the server refuses it")

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
	var bought := ParcelFarm.apply(rules, read, [{"type": "claim_blueprint", "blueprint": "barn"}], T0)
	_check(bought.ok and bought.state.coins == 10 and bought.state.bag.blueprint_barn == 1, "saves: Scott sells it the barn blueprint")

## The art file: the fence leaves the entry open; walls are the runs and the parts; the feeder and milk spots inside.
func _layout() -> void:
	var runs := Livestock.fence_runs("barn", BASE)
	_check(runs.size() == 5, "layout: four sides, the front split by the entry (%d runs)" % runs.size())
	var front := runs.filter(func(r): return is_equal_approx(r.from.y, 6.0) and is_equal_approx(r.to.y, 6.0))
	_check(front.size() == 2 and is_equal_approx(front[0].to.x, 3.0) and is_equal_approx(front[1].from.x, 4.0), "layout: the entry is x 3–4 of the front")
	_check(Livestock.profiles("barn", BASE, 0.8).size() == runs.size() + Livestock.parts("barn").size(), "layout: a wall per run and per part")
	var feeders := Livestock.feeders("barn")
	_check(feeders.size() == 1 and Rect2(Vector2.ZERO, Vector2(BASE)).has_point(feeders[0]), "layout: one feeder inside")
	var cow := float(Livestock.animal_art("cow").radius)
	var toss := float(Livestock.lay("milk").toss_m) / 0.8
	for spot: Vector2 in ParcelFarm.rules().buildings.barn.livestock.spots:
		var free := Livestock.floor_rect("barn", BASE, 0.05).has_point(spot)
		for r: Rect2 in Livestock.blocked_rects("barn", 0.05): free = free and not r.has_point(spot)
		# A cow has somewhere to stand beside it to give the milk (the eight points ParcelLivestock tries).
		var stands := 0
		for k in 8:
			var p := spot + Vector2(toss, 0).rotated(float(k) * TAU / 8.0)
			var open := Livestock.floor_rect("barn", BASE, cow).has_point(p)
			for r: Rect2 in Livestock.blocked_rects("barn", cow): open = open and not r.has_point(p)
			if open: stands += 1
		_check(free and stands > 0, "layout: milk spot %s on the open floor, a cow can stand beside it (%d)" % [spot, stands])
	var model := Building.model("barn", BASE, 0.8)
	var scene := str(Livestock.building_art("barn").scene)
	_check(model != null and (ResourceLoader.exists(scene) or model.get_node_or_null("Placeholder") != null),
		"layout: the barn's scene, or a placeholder until it exists")
	model.free()
	_check(Building.kind("barn").name == "Barn" and Building.kind("barn").get("livestock", false), "layout: Build Barn from the art file's name")
	var kept := Livestock.keep_clear("barn", BASE)
	_check(kept.size() == 1 and kept[0].walk and kept[0].cell == Vector2i(3, 6), "layout: the cell outside the entry is kept walkable")

## The walls in all four turns: the player (0.3 m) passes the entry, not the fence or the parts, and stands on the floor.
func _walls() -> void:
	var walk := Walk.new(Data.decode(Fixture.farm()))
	for turns in 4:
		var at := Building.transform(walk, Vector2i(2, 2), BASE, turns)
		var proxies := Building.proxies(walk, "barn", Vector2i(2, 2), BASE, turns)
		var blocked := func(local: Vector2) -> bool:
			var p := at * Livestock.model_point(local, BASE, walk.cell_m)
			return proxies.any(func(x): return x.touches(p, BODY))
		_check(not blocked.call(Vector2(3.5, 6.0)) and not blocked.call(Vector2(3.5, 5.3)) and not blocked.call(Vector2(3.5, 6.6)),
			"walls turned %d: in and out through the entry" % turns)
		_check(blocked.call(Vector2(1.5, 6.0)) and blocked.call(Vector2(3.5, 0.0)) and blocked.call(Vector2(0.0, 3.0)) \
			and blocked.call(Vector2(8.0, 3.0)), "walls turned %d: the fence stops the player" % turns)
		_check(blocked.call(Vector2(6.3, 1.2)) and blocked.call(Vector2(0.75, 3.2)) and blocked.call(Vector2(5.2, 5.4)),
			"walls turned %d: the shed, the feeder and the trough stop the player" % turns)
		_check(not blocked.call(Vector2(3.5, 3.0)) and not blocked.call(Vector2(1.8, 3.2)), "walls turned %d: the floor is open, beside the feeder too" % turns)

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
		for proxy in Building.proxies(walk, "barn", at, BASE, turns): walk.add_prop(proxy)
		var world := func(local: Vector2) -> Vector3: return frame * Livestock.model_point(local, BASE, walk.cell_m)
		for degrees: float in [0.0, 30.0, 50.0]:
			for side in [-1.0, 1.0]:
				for aim: float in [-0.25, 0.0, 0.25]:
					total += 1
					var a := deg_to_rad(degrees)
					var heading := Vector2(side * sin(a), -cos(a))
					var start: Vector2 = Vector2(3.5 + aim, 6.0) - heading / cos(a)
					walk.position = world.call(start)
					var direction: Vector3 = (world.call(start + heading) - world.call(start)).normalized()
					var inside := false
					for _frame in 360:
						walk.move(direction * 3.75 / 60.0)
						var now := Livestock.local_point(back * walk.position, BASE, walk.cell_m)
						if now.y < 5.3 and now.x > 0.5 and now.x < 7.5:
							inside = true
							break
					if not inside: failed.append("t%d %+d° aim %+.2f" % [turns, int(side * degrees), aim])
	_check(failed.is_empty(), "entry: %d walks in, four turns, up to 50°, all get in (failed %s)" % [total, failed])

## On the synthetic parcel the barn finds a spot in each turn, its kept entry cell clear; a cottage on that cell is refused.
func _placement() -> void:
	var data := Data.decode(Fixture.farm())
	var walk := Walk.new(data)
	var path := Space.protected_path(data)
	for turns in 4:
		var spot = Building.nearest(data, data.spawn, BASE, {}, path, walk.reserved, turns, "barn")
		_check(spot != null and Building.reason(data, spot, BASE, turns, {}, path, walk.reserved, "barn") == "",
			"placement turned %d: the barn fits the parcel's core" % turns)
		if spot == null: continue
		var entry: Vector2i = Building.apron("barn", spot, BASE, turns).walk[0]
		_check(not Building.cells(spot, BASE, turns).has(entry)
			and Building.reason(data, spot, BASE, turns, {}, path, walk.reserved.merged({entry: true}), "barn") == Building.TAKEN,
			"placement turned %d: a solid obstacle on the cell outside the entry refuses it" % turns)

## Until SEN-C-179's art is in: a four-legged cow from the art's placeholder, a bottle for the milk.
func _placeholders() -> void:
	var made := Livestock.animal("cow", 0.8)
	var body: Node3D = made.node
	var holder := body.get_node_or_null("Placeholder")
	_check(ResourceLoader.exists(str(Livestock.animal_art("cow").model)) or (holder != null and holder.get_node_or_null("Head") != null
		and holder.get_node_or_null("Leg3") != null), "placeholder: the cow is a body, a head and four legs")
	_check(is_equal_approx(float(made.radius), 0.45), "placeholder: the cow keeps 0.45 cells to the parts")
	var bounds := AABB()
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		bounds = bounds.merge(mesh.transform * mesh.get_aabb()) if bounds.size != Vector3.ZERO else mesh.transform * mesh.get_aabb()
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
	var state := ParcelFarm.empty_state()
	state.bag = {"crop_carrot": 1}
	var b := {"id": 1, "type": "barn", "animals": ["cow", "cow"]}
	state.buildings = [b]
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "NO_FEED", "feed key: one carrot is not enough")
	state.bag.crop_carrot = 2
	_check(ParcelFarm.feed_refusal(rules, state, b, T0) == "", "feed key: two carrots feed")
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
	farm.buildings = [{"id": 1, "type": "barn", "model": "cow_barn", "x": 2, "y": 2, "width": 8, "depth": 6, "rotation": 3,
		"built_at": T0, "animals": ["cow", "cow"]}]
	farm.drops = [{"id": 1, "item": "milk", "amount": 1, "building": 1, "animal": 0, "spot": 1, "ready_at": T0 - 1000},
		{"id": 2, "item": "milk", "amount": 1, "building": 1, "animal": 1, "spot": 3, "ready_at": T0 + 5000}]
	farm.drop_seq = 2
	host.sync(farm, rules, T0)
	var snap: Dictionary = host.snapshot()
	_check(snap.has(1) and snap[1].animals.size() == 2, "animals: two cows in the barn")
	_check(snap[1].drops == [1], "animals: the milk given while away lies there, the one not due yet does not")
	_check(host.covers(Vector2i(2, 2)) and host.covers(Vector2i(7, 9)) and not host.covers(Vector2i(8, 2)), "animals: the turned barn's cells are its floor")
	var milk: Vector3 = host.drop_position(1)
	_check(host.update(0.016, milk + Vector3(3, 0, 0), T0).is_empty() and host.update(0.016, milk + Vector3(0.5, 0, 0), T0) == [1],
		"pickup: milk 0.5 m away is in reach, 3 m is not")
	var b: Dictionary = farm.buildings[0]
	var frame := Building.transform(walk, Building.at_of(b), BASE, 3)
	var middle := frame * Livestock.model_point(Vector2(3.5, 3.5), BASE, walk.cell_m)
	var radius := float(Livestock.animal_art("cow").radius)
	var inside := true
	for i in 600:
		host.update(1.0 / 60.0, middle, T0 + i * 8)
		for a: Dictionary in host.snapshot()[1].animals:
			var p: Vector2 = a.pos
			inside = inside and Livestock.floor_rect("barn", BASE, radius).grow(0.01).has_point(p)
			for r: Rect2 in Livestock.blocked_rects("barn", radius): inside = inside and not r.grow(-0.01).has_point(p)
	_check(inside, "animals: the cows always on the open floor, never in a part")
	var near := 0
	for a: Dictionary in host.snapshot()[1].animals:
		if (a.pos as Vector2).distance_to(Vector2(3.5, 3.5)) < 1.0: near += 1
	_check(near == 0, "animals: no cow stays within a cell of the player")
	host.update(0.016, middle + Vector3(30, 0, 30), T0 + 6000)
	_check(host.snapshot()[1].drops.has(2), "animals: the milk appears when it is due")
	farm.drops.append({"id": 3, "item": "milk", "amount": 1, "building": 1, "animal": 0, "spot": 0, "ready_at": T0 + 900000})
	host.sync(farm, rules, T0 + 7000)
	_check(host.snapshot()[1].animals[0].errand == "feed", "animals: a fed cow goes to the feeder")
	var feeder := frame * Livestock.model_point(Livestock.feeders("barn")[0], BASE, walk.cell_m)
	_check(not host.feeder_near(feeder + Vector3(0.6, 0, 0), 1.1).is_empty() and host.feeder_near(feeder + Vector3(2, 0, 0), 1.1).is_empty(),
		"feeding: the key's feeder within 1.1 m")
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

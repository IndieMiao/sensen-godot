extends SceneTree
## C-34 rules (Q-39) without a scene: the shared numbers, the command rules mirrored from the
## C-31 server, the client-only spatial rules and the local save standing in for the server.
## C-138: the carrot's seven stages and the dry / wet soil blocks (ParcelCropArt).
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Guide = preload("res://modules/dynamic_farm/parcel_guide.gd")
const ParcelGather = preload("res://modules/dynamic_farm/parcel_gather.gd")
const CropArt = preload("res://modules/dynamic_farm/parcel_crop_art.gd")
const T0 := 1795392000000
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	_rules()
	_commands()
	_buildings()
	_space()
	_store()
	_guide()
	_crop_stages()
	_crop_art()
	print("PARCEL_FARMING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _rules() -> void:
	var rules := ParcelFarm.rules()
	_check(not rules.is_empty(), "dynamic_farm.json parses")
	_check(rules.welcome_gift.get("hoe_starter") == 1 and rules.welcome_gift.get("seed_carrot") == 3, "Q-39 gift: 1 hoe, 3 carrot seeds")
	_check(rules.crops.crop_carrot.grow_seconds == 60 and rules.crops.crop_carrot.seed == "seed_carrot", "Q-39: carrots ripen 60 s after sowing")
	_check(rules.till_tool == "hoe_starter", "the hoe tills")
	_check(ParcelFarm.parse_rules({"version": 1}).is_empty(), "malformed rules are refused")
	var main_farm = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
	for crop: Dictionary in main_farm.crops:
		if crop.id == "crop_carrot": _check(crop.grow_h == 12, "main-farm carrot keeps its own 12 h")

func _commands() -> void:
	var rules := ParcelFarm.rules()
	var empty := ParcelFarm.empty_state()
	var welcomed = ParcelFarm.welcome(rules, empty, T0)
	_check(welcomed.bag == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1} and welcomed.welcomed_at == T0, "first entry grants the gift")
	_check(ParcelFarm.welcome(rules, welcomed, T0 + 5) == null, "second entry grants nothing")
	_check(empty.bag.is_empty(), "welcome does not touch its input")
	var no_tool := ParcelFarm.apply(rules, empty, [{"type": "till", "cell": "10,10"}], T0)
	_check(not no_tool.ok and no_tool.code == "NO_TOOL", "tilling needs the hoe")
	var state: Dictionary = welcomed
	for command in [{"type": "clear_obstacle", "cell": "9,10"}, {"type": "till", "cell": "10,10"}]:
		var step := ParcelFarm.apply(rules, state, [command], T0)
		_check(step.ok, "one press completes " + command.type)
		state = step.state
	_check(state.bag.hoe_starter == 1 and state.bag.seed_carrot == 3, "clearing and tilling consume nothing")
	_check(not ParcelFarm.apply(rules, state, [{"type": "clear_obstacle", "cell": "9,10"}], T0).ok, "an obstacle clears once")
	_check(ParcelFarm.apply(rules, state, [{"type": "till", "cell": "10,10"}], T0).code == "ALREADY_TILLED", "a tilled cell stays tilled")
	_check(ParcelFarm.apply(rules, state, [{"type": "sow", "cell": "11,10", "crop": "crop_carrot"}], T0).code == "NOT_TILLED", "sow only on tilled soil")
	var sown := ParcelFarm.apply(rules, state, [{"type": "sow", "cell": "10,10", "crop": "crop_carrot"}], T0)
	_check(sown.ok and sown.state.bag.seed_carrot == 2 and sown.state.crops["10,10"].ripe_at == T0 + 60000, "sowing takes one seed; ripe 60 s later")
	state = sown.state
	var early := ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 59999)
	_check(not early.ok and early.code == "NOT_RIPE" and early.detail.ripe_at == T0 + 60000, "no harvest before 60 s")
	var ripe := ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 60000)
	_check(ripe.ok and ripe.state.bag.crop_carrot == 1 and "10,10" in ripe.state.tilled and ripe.state.crops.is_empty(), "harvest puts the carrot in the bag, soil stays tilled")
	var batch := ParcelFarm.apply(rules, state, [{"type": "till", "cell": "12,10"}, {"type": "harvest", "cell": "10,10"}], T0)
	_check(not batch.ok and batch.index == 1 and "12,10" not in state.tilled, "a failed batch changes nothing")
	# A save from before C-150: only the one house, no `buildings`.
	var housed := state.duplicate(true)
	housed.erase("buildings")
	housed.house = {"model": "cottage", "x": 20, "y": 8, "width": 3, "depth": 3, "rotation": 0, "built_at": T0}
	_check(ParcelFarm.apply(rules, housed, [{"type": "till", "cell": "22,10"}], T0).code == "CELL_OCCUPIED", "no tilling under the house")
	_check(ParcelFarm.apply(rules, housed, [{"type": "till", "cell": "23,10"}], T0).ok, "next to the house is fine")
	var place := {"type": "place_house", "x": 30, "y": 8, "rotation": 1}
	_check(ParcelFarm.apply(rules, state, [place], T0).ok, "the cottage blueprint places a house")
	var placed: Dictionary = ParcelFarm.apply(rules, state, [place], T0).state
	_check(placed.house == {"model": "cottage", "x": 30, "y": 8, "width": 3, "depth": 3, "rotation": 1, "built_at": T0} and not placed.bag.has("blueprint_cottage"), "placed at once, blueprint used")
	_check(ParcelFarm.apply(rules, placed, [place], T0).code == "HOUSE_PLACED", "one house only")
	var over := ParcelFarm.apply(rules, state, [{"type": "place_house", "x": 9, "y": 9}], T0)
	_check(over.code == "CELL_OCCUPIED" and over.detail.cells == ["10,10"], "no house over tilled soil or crops")
	_check(ParcelFarm.apply(rules, empty, [place], T0).code == "NO_BLUEPRINT", "a house needs the blueprint")
	_check(ParcelFarm.apply(rules, state, [{"type": "place_house", "x": 1022, "y": 0}], T0).code == "OUT_OF_BOUNDS", "the footprint stays on the grid")
	_check(ParcelFarm.apply(rules, state, [{"type": "place_house", "x": 1.5, "y": 0}], T0).code == "SCHEMA", "whole coordinates only")
	_check(ParcelFarm.parse_key("01,2") == null and ParcelFarm.parse_key("1, 2") == null and ParcelFarm.parse_key("3,4") == Vector2i(3, 4), "canonical cell keys only")
	var round_trip := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(housed)))
	var read := housed.duplicate(true)
	read.buildings = [{"model": "cottage", "x": 20, "y": 8, "width": 3, "depth": 3, "rotation": 0, "built_at": T0, "id": 1, "type": "cottage"}]
	_check(round_trip == read, "a JSON round trip keeps the farm, the old house read as cottage 1")
	_check(ParcelFarm.normalize(JSON.parse_string(JSON.stringify(placed))) == placed, "a JSON round trip keeps the buildings")
	_check(ParcelFarm.normalize({"v": 2}).is_empty(), "other versions are refused")

## C-150: several buildings by type, four turns, the same refusals as the server (farm.test.ts 'buildings (C-150)').
## The shipped rules have only the cottage; a copy adds two test-only types (not new buildings): a 1×1 well, at
## most 3, and a 4×2 coop, at most 1.
func _buildings() -> void:
	var rules := ParcelFarm.rules()
	_check(rules.buildings == {"cottage": {"model": "cottage", "blueprint": "blueprint_cottage", "width": 3, "depth": 3, "max": 1}},
		"buildings: the cottage only, one per parcel")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	raw.buildings["well"] = {"model": "well", "blueprint": "blueprint_well", "width": 1, "depth": 1, "max": 3}
	raw.buildings["coop"] = {"model": "coop", "blueprint": "blueprint_coop", "width": 4, "depth": 2, "max": 1}
	var multi := ParcelFarm.parse_rules(raw)
	_check(multi.buildings.coop.width == 4 and multi.buildings.well.max == 3, "buildings: per-type rules parse")
	var no_home: Dictionary = raw.duplicate(true)
	no_home.buildings.erase("cottage")
	var wide: Dictionary = raw.duplicate(true)
	wide.buildings.coop.width = 17
	_check(ParcelFarm.parse_rules(no_home).is_empty() and ParcelFarm.parse_rules(wide).is_empty(), "buildings: the cottage must stay; sides 1–16")
	var start := ParcelFarm.welcome(multi, ParcelFarm.empty_state(), T0) as Dictionary
	start.bag.blueprint_well = 5
	start.bag.blueprint_coop = 2
	var place := func(type: String, x: int, y: int, turns := 0) -> Dictionary:
		return {"type": "place_building", "building": type, "x": x, "y": y, "rotation": turns}
	var all := ParcelFarm.apply(multi, start, [place.call("well", 2, 2), place.call("cottage", 10, 10, 2), place.call("coop", 20, 5, 1),
		place.call("well", 4, 2, 3)], T0)
	_check(all.ok and all.state.buildings.map(func(b): return [b.id, b.type, b.x, b.y, b.rotation]) == \
		[[1, "well", 2, 2, 0], [2, "cottage", 10, 10, 2], [3, "coop", 20, 5, 1], [4, "well", 4, 2, 3]], "buildings: each with its type, spot and turn")
	_check(all.state.house == {"model": "cottage", "x": 10, "y": 10, "width": 3, "depth": 3, "rotation": 2, "built_at": T0},
		"buildings: house mirrors the cottage")
	_check(ParcelFarm.building_cells(all.state).has(Vector2i(21, 8)) and not ParcelFarm.building_cells(all.state).has(Vector2i(22, 5)),
		"buildings: the turned coop covers x 20–21, y 5–8")
	var cottage: Dictionary = ParcelFarm.apply(multi, start, [place.call("cottage", 10, 10)], T0).state
	var overlap := ParcelFarm.apply(multi, cottage, [place.call("well", 12, 12)], T0)
	_check(overlap.code == "BUILDING_OVERLAP" and overlap.detail.cells == ["12,12"], "buildings: not on another building")
	var turned := ParcelFarm.apply(multi, cottage, [place.call("coop", 9, 7, 1)], T0)
	_check(turned.code == "BUILDING_OVERLAP" and turned.detail.cells == ["10,10"], "buildings: the turned footprint counts")
	_check(ParcelFarm.apply(multi, cottage, [place.call("coop", 9, 7, 0)], T0).ok and ParcelFarm.apply(multi, cottage, [place.call("coop", 9, 7, 2)], T0).ok,
		"buildings: unturned the same spot is clear")
	var tilled: Dictionary = ParcelFarm.apply(multi, start, [{"type": "till", "cell": "5,8"}], T0).state
	var on_soil := ParcelFarm.apply(multi, tilled, [place.call("coop", 5, 5, 1)], T0)
	_check(on_soil.code == "CELL_OCCUPIED" and on_soil.detail.cells == ["5,8"] and ParcelFarm.apply(multi, tilled, [place.call("coop", 5, 5)], T0).ok,
		"buildings: not on tilled soil, turned or not")
	var coop: Dictionary = ParcelFarm.apply(multi, start, [place.call("coop", 5, 5)], T0).state
	_check(ParcelFarm.apply(multi, coop, [{"type": "till", "cell": "8,6"}], T0).code == "CELL_OCCUPIED", "buildings: no tilling under any building")
	var wells: Dictionary = ParcelFarm.apply(multi, start, [place.call("well", 1, 1), place.call("well", 3, 1), place.call("well", 5, 1)], T0).state
	var limit := ParcelFarm.apply(multi, wells, [place.call("well", 7, 1)], T0)
	_check(limit.code == "BUILDING_LIMIT" and limit.detail == {"building": "well", "max": 3}, "buildings: each type's limit")
	_check(ParcelFarm.apply(multi, start, [place.call("barn", 1, 1)], T0).code == "UNKNOWN_BUILDING", "buildings: unknown types refused")
	_check(ParcelFarm.apply(multi, start, [place.call("coop", 1021, 0)], T0).code == "OUT_OF_BOUNDS" and ParcelFarm.apply(multi, start, [place.call("coop", 1021, 0, 1)], T0).ok,
		"buildings: the turned footprint stays on the grid")
	_check(ParcelFarm.apply(multi, start, [place.call("well", 1, 1, 4)], T0).code == "SCHEMA" and ParcelFarm.apply(multi, start, [{"type": "place_building", "x": 1, "y": 1}], T0).code == "SCHEMA",
		"buildings: a turn of 0–3 and a type")
	var batch := ParcelFarm.apply(multi, start, [place.call("well", 1, 1), place.call("well", 1, 1)], T0)
	_check(batch.index == 1 and batch.code == "BUILDING_OVERLAP" and start.buildings.is_empty(), "buildings: a refused batch changes nothing")
	var old := ParcelFarm.apply(multi, start, [{"type": "place_house", "x": 9, "y": 9, "rotation": 1}], T0)
	_check(old.ok and old.state.buildings == [{"id": 1, "type": "cottage", "model": "cottage", "x": 9, "y": 9, "width": 3, "depth": 3, "rotation": 1, "built_at": T0}],
		"buildings: place_house is the cottage")
	var again: Dictionary = old.state.duplicate(true)
	again.bag.blueprint_cottage = 1
	_check(ParcelFarm.apply(multi, again, [place.call("cottage", 20, 20)], T0).code == "BUILDING_LIMIT"
		and ParcelFarm.apply(multi, again, [{"type": "place_house", "x": 20, "y": 20}], T0).code == "HOUSE_PLACED", "buildings: one cottage either way")
	# Saves from before C-150, the house turned any way: cottage 1 where it stood and facing as it did.
	for turns in 4:
		var house := {"model": "cottage", "x": 6, "y": 6, "width": 3, "depth": 3, "rotation": turns, "built_at": T0 - 5}
		var legacy := {"v": 1, "house": house, "cleared": [], "tilled": [], "crops": {}, "bag": {"blueprint_well": 1}, "welcomed_at": T0}
		var read := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(legacy)))
		var home := house.duplicate()
		home.id = 1
		home.type = "cottage"
		_check(read.buildings == [home] and read.house == house, "buildings: an old house (turn %d) reads unchanged" % turns)
		_check(ParcelFarm.apply(multi, legacy, [place.call("well", 7, 7)], T0).code == "BUILDING_OVERLAP"
			and ParcelFarm.apply(multi, legacy, [place.call("well", 9, 6)], T0).ok, "buildings: an old house still takes its cells (turn %d)" % turns)
	_check(ParcelFarm.normalize({"v": 1, "buildings": [{"x": 1, "y": 1, "width": 1, "depth": 1, "rotation": 0}], "cleared": [], "tilled": [], "crops": {}, "bag": {}}).is_empty(),
		"buildings: an entry without id and type is refused")

func _space() -> void:
	var rules := ParcelFarm.rules()
	var data := Data.decode(Fixture.farm())
	var path := Space.protected_path(data)
	var core_only := true
	for cell: Vector2i in path: core_only = core_only and data.by_cell[cell].zone == "core"
	_check(core_only and path.has(data.spawn), "protected path: core cells, spawn included")
	# Fixture: entry (24,1) outside the core, spawn (24,14); the walk enters the core at row 4.
	var through := true
	for y in range(4, 15): through = through and (path.has(Vector2i(23, y)) or path.has(Vector2i(24, y)) or path.has(Vector2i(25, y)))
	_check(through and path.size() < 60, "a narrow path from the core edge to the spawn")
	var state := ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0) as Dictionary
	state.buildings = [{"id": 1, "type": "cottage", "model": "cottage", "x": 8, "y": 6, "width": 3, "depth": 3, "rotation": 0, "built_at": T0}]
	var free_cell := Vector2i(36, 18)
	_check(not path.has(free_cell) and Space.till_refusal(data, path, state, free_cell) == "", "a free core cell may be tilled")
	_check(Space.till_refusal(data, path, state, Vector2i(1, 10)) == Space.OUTSIDE, "the walk-only outer ring refuses")
	_check(Space.till_refusal(data, path, state, Vector2i(24, 9)) == Space.PATH, "the protected path refuses")
	_check(Space.till_refusal(data, path, state, Vector2i(9, 7)) == Space.HOUSE, "the house footprint refuses")
	var obstacles := {Vector2i(30, 18): Vector2i(30, 18)}
	for cell: Vector2i in [Vector2i(32, 18), Vector2i(33, 18), Vector2i(32, 19), Vector2i(33, 19)]:
		obstacles[cell] = Vector2i(32, 18)
	var clear := Space.action(rules, data, path, obstacles, state, Vector2i(30, 18), T0)
	_check(clear.verb == "clear" and clear.command == {"type": "clear_obstacle", "cell": "30,18"}, "an obstacle offers Clear first")
	var block_clear := true
	for cell: Vector2i in [Vector2i(32, 18), Vector2i(33, 18), Vector2i(32, 19), Vector2i(33, 19)]:
		block_clear = block_clear and Space.action(rules, data, path, obstacles, state, cell, T0).command == {"type": "clear_obstacle", "cell": "32,18"}
	_check(block_clear, "every cell of a tree offers Clear, named by its anchor")
	var cleared := state.duplicate(true)
	cleared.cleared.append("30,18")
	cleared.cleared.append("32,18")
	_check(Space.action(rules, data, path, obstacles, cleared, Vector2i(30, 18), T0).command.type == "till", "a cleared cell can be tilled")
	_check(Space.action(rules, data, path, obstacles, cleared, Vector2i(33, 19), T0).command.type == "till", "a cleared tree frees its whole block")
	var till := Space.action(rules, data, path, obstacles, state, free_cell, T0)
	_check(till.command == {"type": "till", "cell": "36,18"}, "a free cell offers Till")
	var no_hoe := state.duplicate(true)
	no_hoe.bag.erase("hoe_starter")
	_check(Space.action(rules, data, path, obstacles, no_hoe, free_cell, T0).refusal == Space.NO_TOOL, "without the hoe Till is refused")
	_check(Space.action(rules, data, path, obstacles, state, Vector2i(24, 9), T0).refusal == Space.PATH, "the key says why")
	var tilled := ParcelFarm.apply(rules, state, [{"type": "till", "cell": "36,18"}], T0).state as Dictionary
	_check(Space.action(rules, data, path, obstacles, tilled, free_cell, T0).command.get("crop") == "crop_carrot", "tilled soil offers Sow")
	var growing := ParcelFarm.apply(rules, tilled, [{"type": "sow", "cell": "36,18", "crop": "crop_carrot"}], T0).state as Dictionary
	var waiting := Space.action(rules, data, path, obstacles, growing, free_cell, T0 + 18000)
	_check(waiting.refusal == Space.NOT_RIPE and waiting.ripe_in_ms == 42000 and waiting.command.is_empty(), "a growing carrot counts down")
	_check(Space.action(rules, data, path, obstacles, growing, free_cell, T0 + 60000).command.type == "harvest", "a ripe carrot offers Harvest")
	_check(Space.action(rules, data, path, obstacles, growing, Vector2i(-3, 0), T0).is_empty(), "nothing off the parcel")

func _store() -> void:
	var dir := "user://test_parcel_farming_%d" % Time.get_ticks_usec()
	var clock := [T0]
	var store := LocalStore.new("p-A", dir)
	store.now_ms = func() -> int: return clock[0]
	var first := store.enter()
	_check(first.ok and first.granted and first.farm.bag.seed_carrot == 3 and first.farm_version == 1, "first entry grants and saves")
	var version: int = first.farm_version
	for command in [{"type": "till", "cell": "36,18"}, {"type": "sow", "cell": "36,18", "crop": "crop_carrot"}]:
		var result := store.send(version, [command])
		_check(result.ok, "store applies " + command.type)
		version = result.farm_version
	_check(store.send(version - 1, [{"type": "till", "cell": "37,18"}]).code == "VERSION_CONFLICT", "stale versions are refused")
	clock[0] = T0 + 30000
	var reopened := LocalStore.new("p-A", dir)
	reopened.now_ms = func() -> int: return clock[0]
	var again := reopened.enter()
	_check(again.ok and not again.granted and again.farm.bag.seed_carrot == 2, "reopening does not grant again")
	_check(again.farm.crops["36,18"].ripe_at == T0 + 60000 and "36,18" in again.farm.tilled, "reopening keeps the soil and the original ripening time")
	_check(reopened.send(again.farm_version, [{"type": "harvest", "cell": "36,18"}]).code == "NOT_RIPE", "still 30 s to go")
	clock[0] = T0 + 60000
	var harvested := reopened.send(again.farm_version, [{"type": "harvest", "cell": "36,18"}])
	_check(harvested.ok and harvested.farm.bag.crop_carrot == 1, "harvest after 60 s fills the bag")
	_check(LocalStore.new("p-B", dir).enter().granted, "another parcel has its own save")
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

## C-35 / C-61: the guide's step follows the save alone: cottage, till, sow, harvest, sell, gather, sell again, the
## coop blueprint, then nothing.
func _guide() -> void:
	var rules := ParcelFarm.rules()
	_check(Guide.step({}, T0) == "", "guide: nothing before the save is read")
	var state: Dictionary = ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0)
	_check(Guide.step(state, T0) == "build", "guide: a blueprint and no house -> Build Cottage")
	var bare: Dictionary = state.duplicate(true)
	bare.bag.erase("blueprint_cottage")
	_check(Guide.step(bare, T0) == "", "guide: no house and no blueprint -> nothing")
	var steps := [[{"type": "place_house", "x": 4, "y": 4, "rotation": 0}, "till"],
		[{"type": "clear_obstacle", "cell": "9,10"}, "till"],
		[{"type": "till", "cell": "10,10"}, "sow"],
		[{"type": "sow", "cell": "10,10", "crop": "crop_carrot"}, ""]]
	for pair: Array in steps:
		var result := ParcelFarm.apply(rules, state, [pair[0]], T0)
		_check(result.ok, "guide: " + str(pair[0].type) + " applies")
		if not result.ok: return
		state = result.state
		_check(Guide.step(state, T0) == pair[1], "guide: after %s -> '%s' (got '%s')" % [pair[0].type, pair[1], Guide.step(state, T0)])
	_check(Guide.step(state, T0 + 59999) == "", "guide: quiet while the carrot grows")
	_check(Guide.step(state, T0 + 60000) == "harvest", "guide: a ripe carrot -> Harvest")
	var harvested := ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 60000)
	_check(harvested.ok and Guide.step(harvested.state, T0 + 60000) == "sell", "guide: a carrot in the bag -> sell it at the Market (C-61)")
	if not harvested.ok: return
	# C-61 (0.4.3): sell the carrot, gather round the yard, sell what was gathered, take the coop blueprint.
	state = harvested.state
	var now := T0 + 60000
	var object := "p-3139010:%s:wild_pz_rock_08:3,4:0" % ParcelGather.rules().recipe_version
	var chain := [[{"type": "sell", "item": "crop_carrot", "count": 1}, "gather"],
		[{"type": "gather", "object": object}, "sell_gathered"],
		[{"type": "sell", "item": "stone", "count": 1}, "blueprint"],
		[{"type": "claim_blueprint", "blueprint": "coop"}, ""]]
	for pair: Array in chain:
		var result := ParcelFarm.apply(rules, state, [pair[0]], now, "p-3139010")
		_check(result.ok, "guide: %s applies (%s)" % [pair[0].type, result.get("code", "")])
		if not result.ok: return
		state = result.state
		_check(Guide.step(state, now) == pair[1], "guide: after %s -> '%s' (got '%s')" % [pair[0].type, pair[1], Guide.step(state, now)])
	var gathered_first: Dictionary = harvested.state.duplicate(true)
	gathered_first.bag.wild_herb = 1
	_check(Guide.step(gathered_first, now) == "sell", "guide: gathered before the first sale -> still sell at the Market")
	var carrots_left: Dictionary = harvested.state.duplicate(true)
	carrots_left.bag.erase("crop_carrot")
	carrots_left.sales = 1
	carrots_left.bag.crop_carrot = 1
	_check(Guide.step(carrots_left, now) == "gather", "guide: carrots left after the first sale -> gather next")
	var regrown: Dictionary = carrots_left.duplicate(true)
	regrown.gathered = {object: now}
	_check(Guide.step(regrown, now) == "blueprint", "guide: gathered and sold -> the Carpenter")
	for key: String in ["build", "till", "sow", "harvest", "sell", "gather", "sell_gathered", "blueprint"]:
		_check(not Guide.text(key).is_empty(), "guide: copy for " + key)
	for key: String in ["sell", "gather", "sell_gathered", "blueprint"]:
		_check(not Guide.map_text(key).is_empty(), "guide: the map's line for " + key)
	for key: String in ["build", "till", "sow", "harvest", ""]:
		_check(Guide.map_text(key).is_empty(), "guide: no map line for '%s' (taught on the parcel)" % key)

## C-138: a sown carrot goes through stages 1..6 (stage 0 is tilled soil with nothing sown). Sowing to root thickening
## take a fifth of the growing time each; maturity starts exactly when the carrot ripens (Harvest opens).
func _crop_stages() -> void:
	var rules := ParcelFarm.rules()
	var state: Dictionary = ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0)
	for command in [{"type": "till", "cell": "10,10"}, {"type": "sow", "cell": "10,10", "crop": "crop_carrot"}]:
		state = ParcelFarm.apply(rules, state, [command], T0).state
	var crop: Dictionary = state.crops["10,10"]
	_check(crop.ripe_at - crop.planted_at == 60000, "stages: the carrot still ripens 60 s after sowing")
	_check(CropArt.STAGES.size() == 7 and CropArt.MATURE == 6, "stages: seven, the last one mature")
	var seen: Array = []
	for second in range(0, 61):
		var stage := CropArt.stage_of(crop, T0 + second * 1000)
		if seen.is_empty() or seen.back() != stage: seen.append(stage)
	_check(seen == [1, 2, 3, 4, 5, 6], "stages: sowing to maturity in order: %s" % [seen])
	var starts := [0, 12000, 24000, 36000, 48000, 60000]
	for i in starts.size():
		_check(CropArt.stage_of(crop, T0 + starts[i]) == i + 1 and (i == 0 or CropArt.stage_of(crop, T0 + starts[i] - 1) == i),
			"stages: stage %d starts %d s after sowing" % [i + 1, starts[i] / 1000])
	_check(CropArt.stage_of(crop, T0 + 59999) == 5 and ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 59999).code == "NOT_RIPE",
		"stages: not mature and not harvestable a moment before ripe")
	_check(CropArt.stage_of(crop, T0 + 60000) == CropArt.MATURE and ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 60000).ok,
		"stages: mature exactly when harvestable")
	_check(CropArt.stage_of(crop, T0 + 86400000) == CropArt.MATURE, "stages: stays mature")
	_check(CropArt.stage_of(crop, T0 - 5000) == 1, "stages: a clock behind the sowing shows sowing")
	# A carrot sown before this change: the save has only planted_at / ripe_at, so it lands by how long it has grown.
	var old := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(state)))
	_check(old.crops["10,10"] == crop and CropArt.stage_of(old.crops["10,10"], T0 + 40000) == 4, "stages: an existing save reads unchanged, 40 s in -> root shoulders")
	_check(rules.crops.crop_carrot == {"seed": "seed_carrot", "grow_seconds": 60, "yield": 1} and rules.economy.sell_prices.crop_carrot == 12,
		"stages: seed, growing time, yield and price unchanged")

## C-138: every tilled cell is one 1×1 soil block, dry or wet, with its carrot stage on it.
func _crop_art() -> void:
	var art := CropArt.new(func(cell: Vector2i) -> Vector3: return Vector3(cell.x, 0, -cell.y), 0.8)
	var crops := {"2,1": {"crop": "crop_carrot", "planted_at": T0, "ripe_at": T0 + 60000},
		"3,1": {"crop": "crop_carrot", "planted_at": T0 - 60000, "ripe_at": T0}}
	art.sync({"1,1": CropArt.DRY, "2,1": CropArt.DRY, "3,1": CropArt.DRY}, crops, T0 + 13000)
	_check(art.counts() == {"soil": {"dry": 3, "wet": 0}, "stages": [1, 0, 1, 0, 0, 0, 1]}, "art: three dry blocks, tilled / emergence / mature: %s" % [art.counts()])
	art.sync({"1,1": CropArt.WET, "2,1": CropArt.WET, "3,1": CropArt.DRY}, crops, T0 + 13000)
	_check(art.counts().soil == {"dry": 1, "wet": 2}, "art: wet blocks are drawn as wet")
	var dry: MultiMeshInstance3D = art._soil[CropArt.DRY]
	var wet: MultiMeshInstance3D = art._soil[CropArt.WET]
	_check(dry.multimesh.instance_count == 1 and wet.multimesh.instance_count == 2, "art: one block per tilled cell")
	var block := dry.multimesh.mesh.get_aabb()
	_check(block.size.x <= 1.0 and block.size.z <= 1.0 and block.size.x >= 0.9, "art: a block covers one cell and no more: %s" % [block.size])
	_check(CropArt.SOIL_COLORS.wet.get_luminance() < CropArt.SOIL_COLORS.dry.get_luminance(), "art: wet soil is darker")
	art.sync({}, {}, T0)
	_check(art.counts() == {"soil": {"dry": 0, "wet": 0}, "stages": [0, 0, 0, 0, 0, 0, 0]}, "art: nothing tilled, nothing drawn")
	art.free()

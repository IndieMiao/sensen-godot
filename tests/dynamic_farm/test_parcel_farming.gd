extends SceneTree
## C-34 rules (Q-39) without a scene: the shared numbers, the command rules mirrored from the
## C-31 server, the client-only spatial rules and the local save standing in for the server.
## C-138: the carrot's seven stages and the dry / wet soil blocks (ParcelCropArt).
## C-148: Energy, P0's numbers, the same cases as the server (fixtures/energy_cases.json), the key's price and Rest.
## C-151: watering, the same cases as the server (fixtures/watering_cases.json), the keys at the well and on dry crops.
## C-152: farm levels, the same cases as the server (fixtures/level_cases.json), Scott's upgrade sheet and the Build key.
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
	_energy()
	_energy_cases()
	_energy_space()
	_watering()
	_watering_cases()
	_watering_space()
	_levels()
	_level_cases()
	_upgrade_sheet()
	print("PARCEL_FARMING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## C-151: water `cells` of `state` at `now`: without a well, the one-off grant first and a well at 30,30; a pail drawn
## for every three cells. Fails the run when the rules refuse (a test helper, as farm.test.ts `watered`).
func _wet(rules: Dictionary, state: Dictionary, cells: Array, now: int) -> Dictionary:
	var s := state
	if ParcelFarm.wells(rules, s).is_empty():
		var granted = ParcelFarm.grant(rules, s, now)
		if granted != null: s = granted.state
		s = ParcelFarm.apply(rules, s, [{"type": "place_building", "building": "well", "x": 30, "y": 30, "rotation": 0}], now).state
	var well := int(ParcelFarm.wells(rules, s)[0].id)
	for i in range(0, cells.size(), 3):
		var commands: Array = [{"type": "draw_water", "building": well}]
		for cell in cells.slice(i, i + 3): commands.append({"type": "water", "cell": cell})
		var out := ParcelFarm.apply(rules, s, commands, now)
		_check(out.ok, "watering helper: %s" % out.get("code", ""))
		if not out.ok: return s
		s = out.state
	return s

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
	_check(sown.ok and sown.state.bag.seed_carrot == 2 and sown.state.crops["10,10"] == {"crop": "crop_carrot", "planted_at": T0,
		"ripe_at": ParcelFarm.NEVER, "watered_at": null}, "sowing takes one seed; dry, it does not count time (C-151)")
	state = sown.state
	_check(ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 86400000).code == "NOT_WATERED", "not watered, never harvested")
	var wet := _wet(rules, state, ["10,10"], T0)
	var early := ParcelFarm.apply(rules, wet, [{"type": "harvest", "cell": "10,10"}], T0 + 59999)
	_check(not early.ok and early.code == "NOT_RIPE" and early.detail.ripe_at == T0 + 60000, "no harvest before 60 s after watering")
	var ripe := ParcelFarm.apply(rules, wet, [{"type": "harvest", "cell": "10,10"}], T0 + 60000)
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

## The shipped rules have the cottage, (C-154) the 7×5 coop, (C-181) the 8×6 barn and (C-151) the 1×1 well; a copy
## lets the well be built 3 times and stands a plain 4×2 coop, at most 1, in for the shipped one.
func _buildings() -> void:
	var rules := ParcelFarm.rules()
	_check(rules.buildings.cottage == {"model": "cottage", "blueprint": "blueprint_cottage", "width": 3, "depth": 3, "max": 1, "materials": {}},
		"buildings: one 3×3 cottage per parcel")
	# C-192: the 8×6 barn (C-181's rules) comes after the coop; its own checks are test_barn.gd's.
	_check(rules.buildings.keys() == ["cottage", "coop", "barn", "well"] and rules.buildings.coop.width == 7 and rules.buildings.coop.depth == 5 \
		and rules.buildings.coop.max == 1 and rules.buildings.coop.blueprint == "blueprint_coop", "buildings: one 7×5 coop per parcel (C-154)")
	_check(rules.buildings.well == {"model": "well", "blueprint": "blueprint_well", "width": 1, "depth": 1, "max": 1, "materials": {}},
		"buildings: (C-151) one 1×1 well per parcel")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	raw.buildings["well"] = {"model": "well", "blueprint": "blueprint_well", "width": 1, "depth": 1, "max": 3}
	raw.buildings["coop"] = {"model": "coop", "blueprint": "blueprint_coop", "width": 4, "depth": 2, "max": 1}
	raw.farm_levels = []   # C-152's well limits by level would sit below this copy's 3
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
	_check(ParcelFarm.apply(multi, start, [place.call("silo", 1, 1)], T0).code == "UNKNOWN_BUILDING", "buildings: unknown types refused")
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
	var growing := _wet(rules, ParcelFarm.apply(rules, tilled, [{"type": "sow", "cell": "36,18", "crop": "crop_carrot"}], T0).state, ["36,18"], T0)
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
	_check(first.gift == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1, "blueprint_well": 1, "pail": 1}
		and first.farm.grants == {"watering": T0}, "first entry: the gift and (C-151) the well blueprint and the pail, in one save")
	var version: int = first.farm_version
	for command in [{"type": "till", "cell": "36,18"}, {"type": "sow", "cell": "36,18", "crop": "crop_carrot"},
			{"type": "place_building", "building": "well", "x": 30, "y": 30, "rotation": 0}, {"type": "draw_water", "building": 1},
			{"type": "water", "cell": "36,18"}]:
		var result := store.send(version, [command])
		_check(result.ok, "store applies " + command.type)
		version = result.farm_version
	_check(store.send(version - 1, [{"type": "till", "cell": "37,18"}]).code == "VERSION_CONFLICT", "stale versions are refused")
	clock[0] = T0 + 30000
	var reopened := LocalStore.new("p-A", dir)
	reopened.now_ms = func() -> int: return clock[0]
	var again := reopened.enter()
	_check(again.ok and not again.granted and again.gift.is_empty() and again.farm.bag.seed_carrot == 2 and again.farm.bag.pail == 1,
		"reopening does not grant again")
	_check(again.farm.crops["36,18"].ripe_at == T0 + 60000 and again.farm.crops["36,18"].watered_at == T0 and again.farm.pail_water == 2
		and "36,18" in again.farm.tilled, "reopening keeps the soil, the watering and the original ripening time")
	_check(reopened.send(again.farm_version, [{"type": "harvest", "cell": "36,18"}]).code == "NOT_RIPE", "still 30 s to go")
	clock[0] = T0 + 60000
	var harvested := reopened.send(again.farm_version, [{"type": "harvest", "cell": "36,18"}])
	_check(harvested.ok and harvested.farm.bag.crop_carrot == 1, "harvest after 60 s fills the bag")
	_check(LocalStore.new("p-B", dir).enter().granted, "another parcel has its own save")
	# C-151: a save from before watering (no grants) gets the well blueprint and the pail on its next entry, once.
	var old := LocalStore.new("p-C", dir)
	old.now_ms = func() -> int: return clock[0]
	var welcomed: Dictionary = ParcelFarm.welcome(ParcelFarm.rules(), ParcelFarm.empty_state(), T0)
	welcomed.erase("grants")
	welcomed.erase("pail_water")
	old._save(welcomed, 3)
	var topped := old.enter()
	_check(topped.ok and not topped.granted and topped.gift == {"blueprint_well": 1, "pail": 1} and topped.farm_version == 4
		and topped.farm.bag.blueprint_well == 1 and topped.farm.bag.pail == 1, "an old save gets the watering grant on entry")
	var twice := old.enter()
	_check(twice.gift.is_empty() and twice.farm_version == 4, "the watering grant only once")
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

## C-35 / C-61 / C-175: the guide's step follows the save alone: cottage, till, sow, the well and water, harvest, sell,
## the coop blueprint, the coop, a hen fed, the egg sold, the farm upgraded, then nothing.
func _guide() -> void:
	var rules := ParcelFarm.rules()
	_check(Guide.step({}, T0) == "", "guide: nothing before the save is read")
	var state: Dictionary = ParcelFarm.grant(rules, ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0), T0).state
	_check(Guide.step(state, T0) == "build", "guide: a blueprint and no house -> Build Cottage")
	var bare: Dictionary = state.duplicate(true)
	bare.bag.erase("blueprint_cottage")
	_check(Guide.step(bare, T0) == "", "guide: no house and no blueprint -> nothing")
	var steps := [[{"type": "place_house", "x": 4, "y": 4, "rotation": 0}, "till"],
		[{"type": "clear_obstacle", "cell": "9,10"}, "till"],
		[{"type": "till", "cell": "10,10"}, "sow"],
		[{"type": "sow", "cell": "10,10", "crop": "crop_carrot"}, "well"],
		[{"type": "place_building", "building": "well", "x": 30, "y": 30, "rotation": 0}, "water"],
		[{"type": "draw_water", "building": 2}, "water_pail"],
		[{"type": "water", "cell": "10,10"}, ""]]
	for pair: Array in steps:
		var result := ParcelFarm.apply(rules, state, [pair[0]], T0)
		_check(result.ok, "guide: " + str(pair[0].type) + " applies")
		if not result.ok: return
		state = result.state
		_check(Guide.step(state, T0) == pair[1], "guide: after %s -> '%s' (got '%s')" % [pair[0].type, pair[1], Guide.step(state, T0)])
	var no_well_blueprint: Dictionary = state.duplicate(true)
	no_well_blueprint.buildings = no_well_blueprint.buildings.filter(func(b): return b.type != "well")
	no_well_blueprint.crops["10,10"].watered_at = null
	_check(Guide.step(no_well_blueprint, T0) == "", "guide: a dry carrot, no well and no blueprint -> nothing")
	# A farm past the first ten minutes (sold, the coop blueprint claimed) still hears about a dry carrot.
	var veteran: Dictionary = no_well_blueprint.duplicate(true)
	veteran.sales = 3
	veteran.blueprints_claimed = {"coop": T0}
	_check(Guide.step(veteran, T0) == "", "guide: a veteran farm without well or blueprint stays quiet")
	veteran.bag.blueprint_well = 1
	_check(Guide.step(veteran, T0) == "well", "guide: a veteran farm with a dry carrot -> Build Well")
	veteran.buildings = state.buildings.duplicate(true)
	veteran.pail_water = 0
	_check(Guide.step(veteran, T0) == "water", "guide: a veteran farm with a well, an empty pail and a dry carrot -> water")
	veteran.pail_water = 1
	_check(Guide.step(veteran, T0) == "water_pail", "guide: the same with water in the pail -> just Water")
	veteran.crops["10,10"].watered_at = T0
	veteran.crops["10,10"].ripe_at = T0 + 60000
	_check(Guide.step(veteran, T0) == "", "guide: watered, the veteran farm is quiet again")
	var mixed: Dictionary = state.duplicate(true)
	mixed.crops["11,10"] = {"crop": "crop_carrot", "planted_at": T0, "ripe_at": ParcelFarm.NEVER, "watered_at": null}
	_check(Guide.step(mixed, T0 + 60000) == "harvest", "guide: a ripe carrot beside a dry one -> Harvest first")
	_check(Guide.step(state, T0 + 59999) == "", "guide: quiet while the carrot grows")
	_check(Guide.step(state, T0 + 60000) == "harvest", "guide: a ripe carrot -> Harvest")
	var harvested := ParcelFarm.apply(rules, state, [{"type": "harvest", "cell": "10,10"}], T0 + 60000)
	_check(harvested.ok and Guide.step(harvested.state, T0 + 60000) == "sell", "guide: a carrot in the bag -> sell it at the Market (C-61)")
	if not harvested.ok: return
	# C-175: a ripe carrot comes before selling the one in the bag; a pail with water left asks only for Water.
	var ripe_too: Dictionary = harvested.state.duplicate(true)
	ripe_too.crops["11,10"] = {"crop": "crop_carrot", "planted_at": T0, "ripe_at": T0, "watered_at": T0 - 60000}
	_check(Guide.step(ripe_too, T0 + 60000) == "harvest", "guide: a ripe carrot and one in the bag -> Harvest first")
	var dry_full: Dictionary = mixed.duplicate(true)
	dry_full.crops.erase("10,10")
	_check(dry_full.pail_water == 2 and Guide.step(dry_full, T0) == "water_pail", "guide: water left in the pail -> just Water")
	dry_full.pail_water = 0
	_check(Guide.step(dry_full, T0) == "water", "guide: an empty pail -> Fill at the well, then Water")
	# C-175 (0.4.5): past the first sale, Scott's coop blueprint, the coop, a carrot for a hen (sown first when the bag
	# has none), the egg picked up and sold, Timber and Stone gathered and the farm upgraded at Scott's; then nothing.
	state = harvested.state
	var now := T0 + 60000
	var lay: int = rules.buildings.coop.livestock.produce_seconds * 1000
	var chain := [[{"type": "sell", "item": "crop_carrot", "count": 1}, "blueprint", "blueprint", now],
		[{"type": "claim_blueprint", "blueprint": "coop"}, "coop", "coop", now],
		[{"type": "place_building", "building": "coop", "x": 40, "y": 40, "rotation": 0}, "sow", "feed", now],
		[{"type": "sow", "cell": "10,10", "crop": "crop_carrot"}, "water_pail", "feed", now],
		[{"type": "water", "cell": "10,10"}, "", "feed", now],
		[{"type": "harvest", "cell": "10,10"}, "feed", "feed", now + 60000],
		[{"type": "feed", "building": 3}, "egg", "sell_egg", now + 60000],
		[{"type": "pick_up", "drop": 1}, "sell_egg", "sell_egg", now + 60000 + lay],
		[{"type": "sell", "item": "egg", "count": 1}, "gather_upgrade", "upgrade", now + 60000 + lay]]
	for c: Array in chain:
		var result := ParcelFarm.apply(rules, state, [c[0]], c[3], "p-3139010")
		_check(result.ok, "guide: %s applies (%s)" % [c[0].type, result.get("code", "")])
		if not result.ok: return
		state = result.state
		_check(Guide.step(state, c[3]) == c[1] and Guide.stage(state, c[3]) == c[2], "guide: after %s -> '%s' / '%s' (got '%s' / '%s')"
			% [c[0].type, c[1], c[2], Guide.step(state, c[3]), Guide.stage(state, c[3])])
	now += 60000 + lay
	var before_coop: Dictionary = harvested.state.duplicate(true)
	before_coop.sales = 1
	before_coop.blueprints_claimed = {"coop": now}
	before_coop.bag.blueprint_coop = 1
	var placed := ParcelFarm.apply(rules, before_coop, [{"type": "place_building", "building": "coop", "x": 40, "y": 40, "rotation": 0}], now)
	_check(placed.ok, "guide: the coop goes down beside a carrot in the bag")
	if not placed.ok: return
	var fed: Dictionary = placed.state
	_check(Guide.step(fed, now) == "feed" and Guide.stage(fed, now) == "feed", "guide: a coop and a carrot in the bag -> Feed")
	var waiting: Dictionary = ParcelFarm.apply(rules, fed, [{"type": "feed", "building": int(fed.buildings.back().id)}], now).state
	_check(Guide.step(waiting, now + lay - 1) == "egg" and Guide.step(waiting, now + lay) == "egg", "guide: a hen fed -> her egg, laid or not")
	var no_seeds: Dictionary = fed.duplicate(true)
	no_seeds.bag.erase("crop_carrot")
	no_seeds.bag.erase("seed_carrot")
	_check(Guide.step(no_seeds, now) == "buy_seeds", "guide: no carrot and no seeds for the hens -> buy seeds")
	no_seeds.tilled.append("12,12")
	no_seeds.bag.seed_carrot = 1
	_check(Guide.step(no_seeds, now) == "sow", "guide: seeds and free soil -> Sow")
	var materials: Dictionary = state.duplicate(true)
	var price: Dictionary = ParcelFarm.next_level(rules, 1)
	for item: String in price.items: materials.bag[item] = int(price.items[item])
	# C-175#51: the materials gathered but coins short -> sell the carrots and eggs in the bag, else grow carrots (C-175#79: no eggs yet then).
	materials.coins = int(price.coins) - 5
	materials.bag.crop_carrot = 1
	_check(Guide.step(materials, now) == "sell_for_coins" and Guide.stage(materials, now) == "upgrade",
		"guide: Timber and Stone but 5 coins short, a carrot in the bag -> sell it at Washington Square")
	_check(Guide.TIPS.sell_for_coins == "Need more coins to upgrade. Sell carrots and eggs at Washington Square.", "guide: the card's sell-for-coins line (C-175#79): " + Guide.TIPS.sell_for_coins)
	materials.bag.erase("crop_carrot")
	materials.bag.erase("egg")
	_check(Guide.step(materials, now) == "earn_coins", "guide: coins short and nothing to sell -> grow carrots")
	_check(Guide.TIPS.earn_coins == "Need more coins to upgrade. Grow carrots to sell.", "guide: the card's earn-coins line (C-175#79): " + Guide.TIPS.earn_coins)
	materials.coins = int(price.coins)
	_check(Guide.step(materials, now) == "upgrade", "guide: Timber and Stone for Lv2 -> Scott's upgrade")
	var upgraded := ParcelFarm.apply(rules, materials, [{"type": "upgrade_farm"}], now)
	_check(upgraded.ok and Guide.step(upgraded.state, now) == "" and Guide.stage(upgraded.state, now) == "", "guide: upgraded -> nothing left")
	var again: Dictionary = upgraded.state.duplicate(true)
	again.drops = [{"id": 9, "item": "egg", "amount": 1, "building": 3, "animal": 0, "spot": 0, "ready_at": now}]
	again.drop_seq = 9
	_check(Guide.stage(again, now) == "", "guide: eggs on an upgraded farm do not bring the egg step back")
	var early: Dictionary = materials.duplicate(true)
	early.buildings = early.buildings.filter(func(b): return b.type != "coop")
	early.bag.blueprint_coop = 1
	_check(Guide.step(early, now) == "coop", "guide: materials for the upgrade but no coop yet -> the coop first")
	early.bag.erase("blueprint_coop")
	_check(Guide.step(early, now) == "" and Guide.stage(early, now) == "coop", "guide: no coop and no blueprint for it -> nothing to teach")
	var unclaimed: Dictionary = harvested.state.duplicate(true)
	unclaimed.sales = 1
	unclaimed.bag.erase("crop_carrot")
	_check(Guide.step(unclaimed, now) == "blueprint", "guide: sold, the blueprint not taken -> Scott")
	for key: String in ["build", "till", "sow", "well", "water", "water_pail", "harvest", "sell", "blueprint", "coop", "feed",
			"buy_seeds", "egg", "sell_egg", "gather_upgrade", "upgrade", "sell_for_coins", "earn_coins"]:
		_check(not Guide.text(key).is_empty(), "guide: copy for " + key)
	for key: String in ["sell", "blueprint", "buy_seeds", "sell_egg", "gather_upgrade", "upgrade", "sell_for_coins", "earn_coins"]:
		_check(not Guide.map_text(key).is_empty(), "guide: the map's line for " + key)
	for key: String in ["build", "till", "sow", "well", "water", "water_pail", "harvest", "coop", "feed", "egg", ""]:
		_check(Guide.map_text(key).is_empty(), "guide: no map line for '%s' (taught on the parcel)" % key)

## C-138: a sown carrot goes through stages 1..6 (stage 0 is tilled soil with nothing sown). Sowing to root thickening
## take a fifth of the growing time each; maturity starts exactly when the carrot ripens (Harvest opens).
## C-151: the time counts from watering; a carrot not watered stays at sowing.
func _crop_stages() -> void:
	var rules := ParcelFarm.rules()
	var state: Dictionary = ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0)
	for command in [{"type": "till", "cell": "10,10"}, {"type": "sow", "cell": "10,10", "crop": "crop_carrot"}]:
		state = ParcelFarm.apply(rules, state, [command], T0 - 90000).state
	_check(CropArt.stage_of(state.crops["10,10"], T0 + 86400000) == 1, "stages: not watered, it stays at sowing")
	state = _wet(rules, state, ["10,10"], T0)
	var crop: Dictionary = state.crops["10,10"]
	_check(crop.ripe_at - crop.watered_at == 60000 and crop.watered_at == T0, "stages: the carrot ripens 60 s after watering")
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
	_check(ParcelFarm.normalize(JSON.parse_string(JSON.stringify(state))).crops["10,10"] == crop, "stages: a JSON round trip keeps the watering")
	# A carrot sown before C-138 and C-151: the save has only planted_at / ripe_at, so it lands by how long it has grown.
	var legacy := {"crop": "crop_carrot", "planted_at": T0, "ripe_at": T0 + 60000}
	var old := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(state.merged({"crops": {"10,10": legacy}}, true))))
	_check(old.crops["10,10"] == legacy and CropArt.stage_of(old.crops["10,10"], T0 + 40000) == 4, "stages: an existing save reads unchanged, 40 s in -> root shoulders")
	_check(rules.crops.crop_carrot == {"seed": "seed_carrot", "grow_seconds": 60, "yield": 1, "energy": 3} and rules.economy.sell_prices.crop_carrot == 12,
		"stages: seed, growing time, yield and price unchanged (C-148 adds the carrot's 3 Energy)")

## C-138: every tilled cell is one 1×1 soil block, dry or wet, with its carrot stage on it.
func _crop_art() -> void:
	var art := CropArt.new(func(cell: Vector2i) -> Vector3: return Vector3(cell.x, 0, -cell.y), 0.8)
	var crops := {"2,1": {"crop": "crop_carrot", "planted_at": T0, "ripe_at": T0 + 60000},
		"3,1": {"crop": "crop_carrot", "planted_at": T0 - 60000, "ripe_at": T0},
		"4,1": {"crop": "crop_carrot", "planted_at": T0 - 60000, "ripe_at": ParcelFarm.NEVER, "watered_at": null}}
	art.sync({"1,1": CropArt.DRY, "2,1": CropArt.DRY, "3,1": CropArt.DRY, "4,1": CropArt.DRY}, crops, T0 + 13000)
	_check(art.counts() == {"soil": {"dry": 4, "wet": 0}, "stages": [1, 1, 1, 0, 0, 0, 1]}, "art: four dry blocks, tilled / sowing (not watered) / emergence / mature: %s" % [art.counts()])
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

## C-148: P0's numbers (assets/p0/p0_content.json) and the client's settlement.
func _energy() -> void:
	var rules := ParcelFarm.rules()
	var p0 = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
	var e: Dictionary = rules.energy
	_check(e.max_base == int(p0.energy.max_base) and e.max_base == 200 and e.per_level == 10, "energy: pool 200, +10 a farm level (P0)")
	_check(e.regen_ms == int(p0.energy.regen_ms) and e.rest_amount == int(p0.energy.rest_amount), "energy: +1 per 4 min, Rest +60 (P0)")
	_check(e.blessing.days == int(p0.blessing.days) and is_equal_approx(e.blessing.regen_mult, float(p0.blessing.regen_mult)), "energy: Newcomer 7 days ×1.5 (P0)")
	_check(e.costs == {"clear_obstacle": 2, "till": 2, "gather": 2, "feed": 1, "draw_water": 2},
		"energy: clear 2, till 2, gather 2, feed an animal 1 (P0), draw water 2 (C-151)")
	for crop: Dictionary in p0.crops:
		if crop.id == "crop_carrot": _check(rules.crops.crop_carrot.energy == int(crop.energy), "energy: a carrot sows for P0's 3")
	var bad := JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH)) as Dictionary
	bad.energy.regen_ms = 0
	_check(ParcelFarm.parse_rules(bad).is_empty(), "energy: malformed rules are refused")
	var fresh := ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0) as Dictionary
	_check(not fresh.has("energy") and ParcelFarm.energy_of(rules, fresh, T0) == {"value": 200, "at": T0, "rested_on": null}, "energy: none in the save reads full")
	_check(ParcelFarm.regen_ms(rules, fresh, T0) == 160000 and ParcelFarm.regen_ms(rules, fresh, T0 + 7 * 86400000) == 240000, "energy: Newcomer 2:40, then 4:00")
	_check(ParcelFarm.day_key(rules, T0) == "2026-11-22" and ParcelFarm.next_rollover(rules, T0) == T0 + 12 * 3600000, "energy: the day turns at 04:00 San Francisco time")
	var low := fresh.duplicate(true)
	low.energy = {"value": 0, "at": T0, "rested_on": null}
	_check(ParcelFarm.next_tick_in(rules, low, T0 + 1000) == 159000, "energy: the next point's countdown")
	var trip := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(low)))
	_check(trip.energy == low.energy, "energy: a JSON round trip keeps it")
	var odd := low.duplicate(true)
	odd.energy = {"value": -1, "at": "x"}
	_check(not ParcelFarm.normalize(odd).has("energy"), "energy: a malformed field reads as full, as the server")

## The shared cases: the client's apply gives the server's outcome for every one of them.
func _energy_cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/energy_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 20, "energy cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now), shared.parcel_id)
		var got := {"ok": true, "energy": r.state.energy} if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		# JSON numbers read as floats: compare through JSON text.
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "energy case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])

## Whole floats to ints, all the way down (JSON reads numbers as floats).
func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v): return int(v)
	if v is Dictionary:
		var out := {}
		for k in v: out[k] = _ints(v[k])
		return out
	if v is Array: return v.map(_ints)
	return v

## The key's Rest at the cottage's door: the door row turns with the cottage; rested today or full refuses.
func _energy_space() -> void:
	var rules := ParcelFarm.rules()
	var data := Data.decode(Fixture.farm())
	var path := Space.protected_path(data)
	var state := ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0) as Dictionary
	_check(Space.door_row(state).is_empty() and Space.door_cell(state) == null, "rest: no cottage, no door")
	# C-150: the cottage is found in the building list, whatever else stands there and whatever `house` says.
	var cottage := {"model": "cottage", "x": 8, "y": 6, "width": 3, "depth": 3, "rotation": 0, "built_at": T0}
	var other := {"id": 1, "type": "shed", "model": "shed", "x": 2, "y": 2, "width": 2, "depth": 2, "rotation": 0, "built_at": T0}
	state.buildings = [other, cottage.merged({"id": 2, "type": "cottage"})]
	state.house = null
	_check(ParcelFarm.has_home(state) and ParcelFarm.home_building(state).id == 2, "rest: the cottage is building 2 of the list")
	_check(Space.door_row(state).keys().size() == 3 and Space.door_row(state).has(Vector2i(9, 6)) and Space.door_cell(state) == Vector2i(9, 6),
		"rest: rotation 0 opens to −y, the door in the middle")
	var turned := state.duplicate(true)
	for turn in [[1, Vector2i(10, 7)], [2, Vector2i(9, 8)], [3, Vector2i(8, 7)]]:
		turned.buildings[1].rotation = turn[0]
		_check(Space.door_cell(turned) == turn[1], "rest: rotation %d's door at %s" % [turn[0], turn[1]])
	var no_cottage := state.duplicate(true)
	no_cottage.buildings = [other]
	no_cottage.house = cottage
	_check(not ParcelFarm.has_home(no_cottage) and Space.door_cell(no_cottage) == null, "rest: buildings without a cottage, no door")
	_check(ParcelFarm.apply(rules, no_cottage.merged({"energy": {"value": 50, "at": T0, "rested_on": null}}, true), [{"type": "rest"}], T0).code
		== "NO_HOUSE", "rest: the client refuses it without a cottage in the list, as the server")
	var old_save := state.duplicate(true)
	old_save.erase("buildings")
	old_save.house = cottage
	_check(ParcelFarm.has_home(old_save) and Space.door_cell(old_save) == Vector2i(9, 6), "rest: an old house-only save reads its cottage")
	state.energy = {"value": 50, "at": T0, "rested_on": null}
	var rest := Space.action(rules, data, path, {}, state, Vector2i(8, 6), T0)
	_check(rest.verb == "rest" and rest.refusal == "" and rest.command == {"type": "rest"} and rest.gain == 60, "rest: the door row offers Rest +60")
	_check(Space.action(rules, data, path, {}, state, Vector2i(9, 7), T0).refusal == Space.HOUSE, "rest: the rest of the cottage still says House here")
	state.energy.value = 170
	_check(Space.action(rules, data, path, {}, state, Vector2i(9, 6), T0).gain == 30, "rest: near the top it gives what fits")
	var rested: Dictionary = ParcelFarm.apply(rules, state, [{"type": "rest"}], T0).state
	_check(rested.energy.value == 200 and rested.energy.rested_on == "2026-11-22", "rest: the client applies it as the server")
	rested.energy.value = 100
	_check(Space.action(rules, data, path, {}, rested, Vector2i(9, 6), T0 + 60000).refusal == Space.RESTED, "rest: once a player day")
	rested.energy.at = T0 + 12 * 3600000
	_check(Space.action(rules, data, path, {}, rested, Vector2i(9, 6), T0 + 12 * 3600000).refusal == "", "rest: again after 04:00")
	state.energy.value = 200
	_check(Space.action(rules, data, path, {}, state, Vector2i(9, 6), T0).refusal == Space.FULL, "rest: nothing to gain when full")
	# The local stand-in refuses a short command and keeps its save.
	var dir := "user://test_parcel_energy_%d" % Time.get_ticks_usec()
	var store := LocalStore.new("p-E", dir)
	store.now_ms = func() -> int: return T0
	var first := store.enter()
	var low: Dictionary = first.farm.duplicate(true)
	low.energy = {"value": 1, "at": T0, "rested_on": null}
	store._save(low, first.farm_version)
	var refused := store.send(first.farm_version, [{"type": "till", "cell": "36,18"}])
	_check(not refused.ok and refused.code == "NO_ENERGY" and refused.detail.need == 2 and refused.detail.have == 1 and refused.farm_version == first.farm_version
		and refused.farm.tilled.is_empty(), "store: short of Energy refuses and keeps the save")
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

## C-151: the watering rules (owner SEN-C-137#6, #15), the one-off grant and old saves.
func _watering() -> void:
	var rules := ParcelFarm.rules()
	_check(rules.watering == {"well": "well", "pail": "pail", "pail_uses": 3}, "watering: the well fills a pail of 3")
	_check(rules.grants == {"watering": {"blueprint_well": 1, "pail": 1}}, "watering: every farm gets a well blueprint and a pail")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	for broken: Array in [["watering", null], ["watering", {"well": "castle", "pail": "pail", "pail_uses": 3}],
			["watering", {"well": "well", "pail": "pail", "pail_uses": 0}], ["grants", null], ["grants", {"watering": {}}],
			["grants", {"watering": {"pail": 0}}]]:
		var bad: Dictionary = raw.duplicate(true)
		bad[broken[0]] = broken[1]
		_check(ParcelFarm.parse_rules(bad).is_empty(), "watering: malformed %s refused: %s" % broken)
	var water_priced: Dictionary = raw.duplicate(true)
	water_priced.energy.costs.water = 1
	_check(ParcelFarm.parse_rules(water_priced).is_empty(), "watering: watering itself is never priced")
	# The grant: once, on a new farm with the first-entry gift, or on an old farm's next entry.
	var welcomed: Dictionary = ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0)
	var first = ParcelFarm.grant(rules, welcomed, T0)
	_check(first != null and first.gift == {"blueprint_well": 1, "pail": 1} and first.state.grants == {"watering": T0}
		and welcomed.bag == {"hoe_starter": 1, "seed_carrot": 3, "blueprint_cottage": 1}, "grant: given once, the input untouched")
	_check(ParcelFarm.grant(rules, first.state, T0 + 5) == null, "grant: never twice")
	var old := ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {"hoe_starter": 1}, "welcomed_at": T0})
	_check(old.grants == {} and old.pail_water == 0, "an old save reads with no grant and an empty pail")
	_check(ParcelFarm.grant(rules, old, T0).state.bag == {"hoe_starter": 1, "blueprint_well": 1, "pail": 1}, "grant: an old save gets it")
	# Commands' shapes, as the server's parse.
	var s: Dictionary = first.state
	for bad_building in [0, -1, 1.5, "1", null]:
		_check(ParcelFarm.apply(rules, s, [{"type": "draw_water", "building": bad_building}], T0).code == "SCHEMA", "draw_water: a whole building id (%s)" % [bad_building])
	_check(ParcelFarm.apply(rules, s, [{"type": "water", "cell": "01,2"}], T0).code == "SCHEMA", "water: a canonical cell")
	var trip := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(_wet(rules, ParcelFarm.apply(rules, s,
		[{"type": "till", "cell": "1,1"}, {"type": "sow", "cell": "1,1", "crop": "crop_carrot"}], T0).state, ["1,1"], T0))))
	_check(trip.pail_water == 2 and trip.crops["1,1"].watered_at == T0 and trip.grants == {"watering": T0}, "watering: a JSON round trip keeps the pail and the watering")
	_check(ParcelFarm.normalize({"v": 1, "house": null, "cleared": [], "tilled": ["1,1"], "bag": {},
		"crops": {"1,1": {"crop": "crop_carrot", "planted_at": T0, "ripe_at": T0 + 1, "watered_at": "x"}}}).is_empty(), "watering: a malformed watered_at is refused")

## The shared cases: the client's apply gives the server's outcome for every one of them.
func _watering_cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/watering_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 20, "watering cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now), shared.parcel_id)
		var got := {"ok": true, "crops": r.state.crops, "pail_water": r.state.pail_water, "bag": r.state.bag, "energy": r.state.energy} if r.ok \
			else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "watering case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])

## The key at the well and on a dry crop (C-151): Fill / Water, and why not.
func _watering_space() -> void:
	var rules := ParcelFarm.rules()
	var data := Data.decode(Fixture.farm())
	var path := Space.protected_path(data)
	var state: Dictionary = ParcelFarm.grant(rules, ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0), T0).state
	state = ParcelFarm.apply(rules, state, [{"type": "place_building", "building": "well", "x": 36, "y": 16, "rotation": 0},
		{"type": "till", "cell": "36,18"}, {"type": "sow", "cell": "36,18", "crop": "crop_carrot"}], T0).state
	_check(Space.well_cells(rules, state) == {Vector2i(36, 16): 1}, "the well's cell names the well")
	var fill := Space.action(rules, data, path, {}, state, Vector2i(36, 16), T0)
	_check(fill.verb == "fill" and fill.refusal == "" and fill.command == {"type": "draw_water", "building": 1}, "at the well the key fills the pail")
	var water := Space.action(rules, data, path, {}, state, Vector2i(36, 18), T0)
	_check(water.verb == "water" and water.refusal == Space.PAIL_EMPTY and water.command.is_empty(), "a dry carrot with an empty pail: Pail empty")
	var full: Dictionary = ParcelFarm.apply(rules, state, [fill.command], T0).state
	_check(Space.action(rules, data, path, {}, full, Vector2i(36, 16), T0).refusal == Space.PAIL_FULL, "a full pail: Pail full at the well")
	water = Space.action(rules, data, path, {}, full, Vector2i(36, 18), T0)
	_check(water.verb == "water" and water.refusal == "" and water.command == {"type": "water", "cell": "36,18"}, "a dry carrot and water in the pail: Water")
	_check(ParcelFarm.energy_cost(rules, fill.command) == 2 and ParcelFarm.energy_cost(rules, water.command) == 0, "Fill costs 2 Energy, Water nothing")
	var watered: Dictionary = ParcelFarm.apply(rules, full, [water.command], T0).state
	var growing := Space.action(rules, data, path, {}, watered, Vector2i(36, 18), T0 + 18000)
	_check(growing.refusal == Space.NOT_RIPE and growing.ripe_in_ms == 42000, "watered, it counts down from the watering")
	var no_pail: Dictionary = full.duplicate(true)
	no_pail.bag.erase("pail")
	_check(Space.action(rules, data, path, {}, no_pail, Vector2i(36, 16), T0).refusal == Space.NO_PAIL
		and Space.action(rules, data, path, {}, no_pail, Vector2i(36, 18), T0).refusal == Space.NO_PAIL, "no pail: Need a pail")
	_check(Space.till_refusal(data, path, state, Vector2i(36, 16)) == Space.HOUSE, "no tilling under the well")

## C-152: the shipped levels (SEN-C-152#14, for the owner to confirm), Max Energy and wells by level, the save's level,
## the rules' bounds (server rules.ts parseFarmLevels) and upgrade_farm as the server (farm.test.ts 'farm levels (C-152)').
func _levels() -> void:
	var rules := ParcelFarm.rules()
	_check(_ints(rules.farm_levels) == [{"level": 2, "coins": 40, "items": {"wood": 6, "stone": 4}},
		{"level": 3, "coins": 60, "items": {"wood": 10, "stone": 8}, "buildings": {"well": 2}, "gift": {"blueprint_well": 1}},
		{"level": 4, "coins": 70, "items": {"wood": 14, "stone": 12}},
		{"level": 5, "coins": 80, "items": {"wood": 20, "stone": 16}, "buildings": {"well": 3}, "gift": {"blueprint_well": 1}}],
		"levels: Lv2–5 as shipped")
	var at := func(level: int) -> Dictionary:
		var s := ParcelFarm.empty_state()
		s.level = level
		return s
	_check([1, 2, 3, 4, 5].map(func(l): return ParcelFarm.max_energy(rules, at.call(l))) == [200, 210, 220, 230, 240], "levels: Max Energy +10 a level")
	_check([1, 2, 3, 4, 5].map(func(l): return ParcelFarm.building_max(rules, "well", l)) == [1, 1, 2, 2, 3], "levels: wells 1 / 2 / 3 at Lv1 / 3 / 5")
	_check(ParcelFarm.next_level(rules, 5).is_empty() and int(ParcelFarm.next_level(rules, 1).coins) == 40, "levels: Lv5 is the top")
	_check(ParcelFarm.empty_state().level == 1, "levels: a new farm is Lv1")
	var old := {"v": 1, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": T0}
	_check(ParcelFarm.normalize(old).level == 1 and ParcelFarm.normalize(old.merged({"level": 0})).level == 1, "levels: no level (or a bad one) reads as Lv1")
	var three := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(old.merged({"level": 3}))))
	_check(three.level == 3 and ParcelFarm.normalize(JSON.parse_string(JSON.stringify(three))) == three, "levels: a JSON round trip keeps the level")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ParcelFarm.RULES_PATH))
	var bad := func(levels: Variant) -> bool:
		var copy: Dictionary = raw.duplicate(true)
		copy.farm_levels = levels
		return ParcelFarm.parse_rules(copy).is_empty()
	var lv2: Dictionary = raw.farm_levels[0]
	var none: Dictionary = raw.duplicate(true)
	none.erase("farm_levels")
	_check(ParcelFarm.parse_rules(none).farm_levels == [], "levels: none in the rules is Lv1 only")
	_check(bad.call({}) and bad.call([lv2.merged({"level": 3}, true)]) and bad.call([lv2, lv2]) and bad.call([lv2.merged({"coins": -1}, true)])
		and bad.call([lv2.merged({"items": {"wood": 0}}, true)]) and bad.call([{"level": 2, "coins": 40}])
		and bad.call([lv2.merged({"gift": {"x": 1000}}, true)]) and bad.call([lv2.merged({"buildings": {"castle": 2}}, true)])
		and bad.call([lv2.merged({"buildings": {"well": 0}}, true)])
		and bad.call([lv2.merged({"buildings": {"well": 3}}, true), (raw.farm_levels[1] as Dictionary).merged({"buildings": {"well": 2}}, true)]),
		"levels: malformed levels are refused as the server does")
	# upgrade_farm: the price taken, no Energy, a gift on Lv3; short is refused whole, materials before coins.
	var start := ParcelFarm.welcome(rules, ParcelFarm.empty_state(), T0) as Dictionary
	var paid: Dictionary = start.duplicate(true)
	paid.bag.merge({"wood": 6, "stone": 4})
	paid.coins = 40
	var up := ParcelFarm.apply(rules, paid, [{"type": "upgrade_farm"}], T0)
	_check(up.ok and up.state.level == 2 and up.state.coins == 0 and up.state.bag == start.bag and up.state.energy.value == 200,
		"levels: Lv2 takes 40 coins, 6 Timber and 4 Stone, no Energy")
	_check(ParcelFarm.max_energy(rules, up.state) == 210 and ParcelFarm.next_tick_in(rules, up.state, T0) != null, "levels: Lv2 tops at 210, filling from now")
	var short := ParcelFarm.apply(rules, start.merged({"coins": 40}, true), [{"type": "upgrade_farm"}], T0)
	_check(short.code == "NOT_ENOUGH" and short.detail == {"item": "wood", "have": 0, "need": 6}, "levels: no Timber, refused naming it")
	var poor: Dictionary = paid.duplicate(true)
	poor.coins = 39
	_check(ParcelFarm.apply(rules, poor, [{"type": "upgrade_farm"}], T0).code == "NOT_ENOUGH_COINS", "levels: a coin short")
	_check(ParcelFarm.apply(rules, paid, [{"type": "upgrade_farm"}, {"type": "upgrade_farm"}], T0).index == 1 and paid.get("level", 1) == 1,
		"levels: a refused batch changes nothing")
	var top: Dictionary = paid.duplicate(true)
	top.level = 5
	_check(ParcelFarm.apply(rules, top, [{"type": "upgrade_farm"}], T0).detail == {"level": 5}, "levels: none past Lv5")
	# The local stand-in saves the level and reads it back.
	var dir := "user://parcel_levels_test"
	var store := LocalStore.new("block-levels", dir)
	store.now_ms = func() -> int: return T0
	store.enter()
	var saved: Dictionary = store.read()
	_check(store.send(int(saved.farm_version), [{"type": "upgrade_farm"}]).code == "NOT_ENOUGH", "levels: the local store refuses a short upgrade")
	_check(store.read().farm.level == 1, "levels: the local store keeps Lv1 after it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("block-levels.json")))

## The same level cases as the server (fixtures/level_cases.json): both sides must give the file's results.
func _level_cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string("res://tests/dynamic_farm/fixtures/level_cases.json"))
	_check(shared is Dictionary and shared.cases.size() >= 20, "level cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now), shared.parcel_id)
		var got := {"ok": true, "level": r.state.level, "coins": r.state.coins, "bag": r.state.bag,
			"buildings": r.state.buildings.map(func(b): return b.type), "energy": r.state.energy} if r.ok \
			else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "level case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])

## Scott's upgrade sheet (parcel_upgrade.gd): the next level's needs and what changes, the first gap on the key; the top.
func _upgrade_sheet() -> void:
	var Upgrade = load("res://scenes/dynamic_farm/parcel_upgrade.gd")
	var rules := ParcelFarm.rules()
	var farm := ParcelFarm.empty_state()
	farm.bag = {"wood": 2, "stone": 9}
	farm.coins = 12
	var m: Dictionary = Upgrade.model(rules, farm)
	_check(m.title == "Farm Lv1 → Lv2" and not m.top, "sheet: Farm Lv1 → Lv2")
	_check(m.tiles == [{"id": "wood", "name": "Timber", "have": 2, "need": 6}, {"id": "stone", "name": "Stone", "have": 9, "need": 4},
		{"id": "coins", "name": "Coins", "have": 12, "need": 40}], "sheet: Timber, Stone, then Coins, have / need")
	_check(m.reason == "Need 4 more Timber", "sheet: the first gap on the key, materials first: " + str(m.reason))
	_check(m.changes == [{"icon": "energy", "text": "Max Energy 210", "note": "now 200"}], "sheet: Lv2 adds Max Energy only")
	farm.bag.wood = 6
	_check(Upgrade.model(rules, farm).reason == "Need 28 more coins", "sheet: then the coins")
	farm.coins = 40
	_check(Upgrade.model(rules, farm).reason == "", "sheet: enough, the key can go")
	farm.level = 2
	_check(Upgrade.model(rules, farm).changes == [{"icon": "energy", "text": "Max Energy 220", "note": "now 210"},
		{"icon": "water", "text": "Wells 2", "note": "now 1"}], "sheet: Lv3 adds a well")
	farm.level = 5
	var top: Dictionary = Upgrade.model(rules, farm)
	_check(top.title == "Farm Lv5" and top.top and top.tiles.is_empty(), "sheet: Lv5 is the top")
	var sheet = Upgrade.new(farm)
	root.add_child(sheet)
	_check(not sheet.button.visible and sheet.subtitle.visible and sheet.subtitle.text == "Highest level for now", "sheet: no key at the top")
	farm.level = 1
	farm.coins = 0
	sheet.refresh(farm)
	_check(sheet.button.visible and sheet.button.reason == "Need 40 more coins" and sheet._tiles.get_child_count() == 3,
		"sheet: refreshed to Lv1, three tiles and the gap on the key")
	sheet.free()

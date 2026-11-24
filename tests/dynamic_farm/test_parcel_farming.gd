extends SceneTree
## C-34 rules (Q-39) without a scene: the shared numbers, the command rules mirrored from the
## C-31 server, the client-only spatial rules and the local save standing in for the server.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Guide = preload("res://modules/dynamic_farm/parcel_guide.gd")
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
	_space()
	_store()
	_guide()
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
	var housed := state.duplicate(true)
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
	_check(round_trip == housed, "a JSON round trip keeps the farm")
	_check(ParcelFarm.normalize({"v": 2}).is_empty(), "other versions are refused")

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
	state.house = {"model": "cottage", "x": 8, "y": 6, "width": 3, "depth": 3, "rotation": 0, "built_at": T0}
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

## C-35: the guide's step follows the save alone: cottage, till, sow, harvest, then nothing.
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
	_check(harvested.ok and Guide.step(harvested.state, T0 + 60000) == "", "guide: done once a carrot is in the bag")
	var sold: Dictionary = harvested.state.duplicate(true)
	sold.bag.erase("crop_carrot")
	sold.sales = 1
	_check(Guide.step(sold, T0 + 60000) == "", "guide: stays done after selling it (0.4.3)")
	for key: String in ["build", "till", "sow", "harvest"]:
		_check(not Guide.text(key).is_empty(), "guide: copy for " + key)

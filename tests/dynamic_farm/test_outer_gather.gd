extends SceneTree
## C-60 outer gathering, without the scene: the rules the client reads match the server's
## config and the art recipe; every parcel numbers its gatherable trees, flowers and rocks
## the same way on every opening (C-58 id contract, pinned per r4 parcel in
## fixtures/outer_gather_ids.json); and the local stand-in replays the server's `gather` command.
## `-- <farm.json> ...` adds real parcels (CI passes the r4 fixtures); the synthetic one always runs.
## OUTER_GATHER_WRITE_PINS=1 rewrites the pins (only when the outer recipe version changes).
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Gather = preload("res://modules/dynamic_farm/parcel_gather.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const PINS_PATH := "res://tests/dynamic_farm/fixtures/outer_gather_ids.json"
const T0 := 1_800_000_000_000
const DAY_MS := 86_400_000
var checks := 0
var failures := 0
var pins := {}
var new_pins := {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	_rules()
	_ids()
	_commands()
	if FileAccess.file_exists(PINS_PATH): pins = JSON.parse_string(FileAccess.get_file_as_string(PINS_PATH))
	_parcel(Fixture.farm(), false)
	var files := OS.get_cmdline_user_args()
	if files.is_empty(): print("OUTER_GATHER SKIP real parcels (pass r4 JSON paths after --)")
	for path in files: _parcel(JSON.parse_string(FileAccess.get_file_as_string(path)), true)
	if OS.get_environment("OUTER_GATHER_WRITE_PINS") == "1" and not new_pins.is_empty():
		var file := FileAccess.open(PINS_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(new_pins, "  ", true) + "\n")
		file.close()
		print("OUTER_GATHER wrote %d pins" % new_pins.size())
	print("OUTER_GATHER checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The owner's answer (C-30#29 q4, C-30#36): hand-picked, one item, 24 h; kinds map to the recipe's models.
func _rules() -> void:
	var gather := Gather.rules()
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.RECIPE_PATH))
	var outer: Dictionary = recipe.outer_groves
	_check(not gather.is_empty(), "economy.gather parses")
	_check(gather.recipe_version == outer.version, "ids lock the outer recipe version (%s)" % outer.version)
	_check(gather.respawn_ms == DAY_MS, "grows back after 24 hours")
	var expected := {"tree": "wood", "flower": "wild_herb", "rock": "stone"}
	_check(gather.sources.keys().size() == 3, "three kinds")
	var trees: Array = outer.grove.tree_weights.keys() + [outer.grove.young_pine_id]
	var rocks: Array = outer.rock_pile.main_ids + outer.rock_pile.companion_ids
	var models := {"tree": trees, "flower": recipe.roles.flower.ids, "rock": rocks}
	var names := {}
	# Loaded at run time: P0Logic needs the autoloads, which a --script does not see when it compiles.
	var p0 = load("res://modules/p0/p0_logic.gd")
	var materials: Dictionary = p0.content().materials
	for kind: String in expected:
		var src: Dictionary = gather.sources.get(kind, {})
		_check(src.get("item") == expected[kind] and src.get("amount") == 1, "%s gives one %s" % [kind, expected[kind]])
		_check(src.get("max_objects") == int(outer.targets[kind].cap), "%s cap equals the recipe's" % kind)
		for model in models[kind]:
			_check(gather.kind_of.get(model) == kind, "%s is a %s" % [model, kind])
		# Main-farm item definitions are reused; none is new (stone included).
		_check(materials.has(expected[kind]) and not str(materials[expected[kind]].name).is_empty(), "%s is a main-farm material" % expected[kind])
		names[expected[kind]] = materials[expected[kind]].name
	_check(names == {"wood": "Timber", "wild_herb": "Wild Herb", "stone": "Stone"}, "existing names")
	for id: String in ["wood", "wild_herb", "stone"]:
		_check(p0.icon(id) != p0.icon("field"), "%s has its own icon" % id)
	for model in recipe.roles.shrub.ids + recipe.roles.groundcover.ids:
		_check(not gather.kind_of.has(model), "%s is not gatherable" % model)
	# The server's bounds.
	var bad := {"recipe_version": "outer-groves-v2", "respawn_seconds": 0, "sources": {"tree": {"item": "wood", "amount": 1, "max_objects": 1, "models": ["a"]}}}
	_check(Gather.parse(bad).is_empty(), "respawn below 1 s is refused")
	bad.respawn_seconds = 60
	bad.sources["rock"] = {"item": "stone", "amount": 1, "max_objects": 1, "models": ["a"]}
	_check(Gather.parse(bad).is_empty(), "a model in two kinds is refused")

## The C-58 id shape, as the server's parseObjectId reads it.
func _ids() -> void:
	var good = Gather.parse_id("p-3512001:outer-groves-v2:wild_pz_tree_20:41,7:0")
	_check(good is Dictionary and good.parcel_id == "p-3512001" and good.cell == "41,7" and good.ordinal == 0, "the documented example parses")
	for wrong in ["p-1:outer-groves-v2:wild_pz_tree_20:041,7:0", "p-1:outer-groves-v2:wild_pz_tree_20:1024,7:0",
			"p-1:outer-groves-v2:wild_pz_tree_20:4,7:100", "1:outer-groves-v2:wild_pz_tree_20:4,7:0",
			"p-1:Outer:wild_pz_tree_20:4,7:0", "p-1:outer-groves-v2:wild_pz_tree_20:4,7", 7]:
		_check(Gather.parse_id(wrong) == null, "refused: %s" % str(wrong))

## The local stand-in's `gather`, against the server's rules (C-58 farm.ts).
func _commands() -> void:
	var rules := ParcelFarm.rules()
	var gather := Gather.rules()
	var own := "p-A"
	var tree := "p-A:%s:wild_pz_tree_20:40,3:0" % gather.recipe_version
	var flower := "p-A:%s:wild_pz_flower_23:41,3:0" % gather.recipe_version
	var rock := "p-A:%s:wild_pz_rock_08:42,3:0" % gather.recipe_version
	var state := ParcelFarm.empty_state()
	var step := ParcelFarm.apply(rules, state, [{"type": "gather", "object": tree}, {"type": "gather", "object": flower},
		{"type": "gather", "object": rock}], T0, own)
	_check(step.ok, "one tree, flower and rock gather in one batch")
	state = step.state
	_check(state.bag == {"wood": 1, "wild_herb": 1, "stone": 1}, "each gives one of its material")
	_check(state.gathered == {tree: T0, flower: T0, rock: T0}, "the gather times are kept")
	var again := ParcelFarm.apply(rules, state, [{"type": "gather", "object": tree}], T0 + DAY_MS - 1, own)
	_check(not again.ok and again.code == "NOT_RESPAWNED" and again.detail.ready_at == T0 + DAY_MS, "not again before 24 h")
	var later := ParcelFarm.apply(rules, state, [{"type": "gather", "object": tree}], T0 + DAY_MS, own)
	_check(later.ok and later.state.bag.wood == 2, "again after 24 h")
	_check(later.ok and later.state.gathered.size() == 1, "grown-back records are dropped")
	var codes := {
		"NOT_YOUR_PARCEL": ["p-B:%s:wild_pz_tree_20:40,3:0" % gather.recipe_version, own],
		"STALE_RECIPE": ["p-A:outer-groves-v1:wild_pz_tree_20:40,3:0", own],
		"UNKNOWN_OBJECT": ["p-A:%s:wild_pz_shrub_09:40,3:0" % gather.recipe_version, own],
	}
	for code: String in codes:
		var out := ParcelFarm.apply(rules, ParcelFarm.empty_state(), [{"type": "gather", "object": codes[code][0]}], T0, codes[code][1])
		_check(not out.ok and out.code == code, code)
	_check(ParcelFarm.apply(rules, ParcelFarm.empty_state(), [{"type": "gather", "object": tree}], T0).code == "NOT_YOUR_PARCEL",
		"no parcel, no gathering")
	var tilled := ParcelFarm.empty_state()
	tilled.tilled.append("40,3")
	_check(ParcelFarm.apply(rules, tilled, [{"type": "gather", "object": tree}], T0, own).code == "NOT_OUTER", "a core cell is not outer")
	_check(ParcelFarm.apply(rules, state, [{"type": "gather", "object": "x".repeat(257)}], T0, own).code == "SCHEMA", "an overlong id is malformed")
	var capped := ParcelFarm.empty_state()
	for i in int(gather.sources.rock.max_objects):
		capped.gathered["p-A:%s:wild_pz_rock_13:%d,900:0" % [gather.recipe_version, i]] = T0
	var full := ParcelFarm.apply(rules, capped, [{"type": "gather", "object": rock}], T0 + 1, own)
	_check(not full.ok and full.code == "TOO_MANY_OBJECTS" and full.detail.max == gather.sources.rock.max_objects, "a kind stops at its cap")
	_check(ParcelFarm.apply(rules, capped, [{"type": "gather", "object": tree}], T0 + 1, own).ok, "other kinds are not capped by it")
	# A saved farm keeps its gather records (and a save from before C-58 reads as none).
	var read := ParcelFarm.normalize(JSON.parse_string(JSON.stringify(state)))
	_check(read.gathered == state.gathered and read.bag == state.bag, "gather records survive a save")
	var old := ParcelFarm.empty_state()
	old.erase("gathered")
	_check(ParcelFarm.normalize(old).gathered == {}, "an old save has gathered nothing")

## One parcel opened twice: same ids at the same places, all outer, within the caps, as pinned.
func _parcel(raw: Dictionary, real: bool) -> void:
	var first := _open(raw)
	var second := _open(raw)
	if first.is_empty() or second.is_empty():
		_check(false, "%s opens" % raw.get("block_id"))
		return
	var data: Dictionary = first.data
	var objects: Array = first.objects
	if real: _check(not objects.is_empty(), "%s has gatherable objects" % data.block_id)
	_check(_signature(objects) == _signature(second.objects), "%s: same ids and places on every opening" % data.block_id)
	var ids := {}
	var kinds := {}
	for object: Dictionary in objects:
		ids[object.id] = true
		kinds[object.kind] = int(kinds.get(object.kind, 0)) + 1
		var parsed = Gather.parse_id(object.id)
		_check(parsed != null and parsed.parcel_id == data.block_id and parsed.model == object.asset, "%s parses as its own" % object.id)
		var cell: Vector2i = object.cell
		_check(data.by_cell.has(cell) and data.by_cell[cell].zone == "extension", "%s stands in the extension" % object.id)
	_check(ids.size() == objects.size(), "%s: ids are unique" % data.block_id)
	for kind: String in kinds:
		_check(kinds[kind] <= int(Gather.rules().sources[kind].max_objects), "%s: %s within the cap" % [data.block_id, kind])
	if not real: return
	var pin := {"count": objects.size(), "kinds": kinds, "sha256": _signature(objects).sha256_text(),
		"first": {}}
	for object: Dictionary in objects:
		if not pin.first.has(object.kind): pin.first[object.kind] = object.id
	new_pins[data.block_id] = pin
	if not pins.has(data.block_id):
		_check(false, "%s has pinned ids in %s" % [data.block_id, PINS_PATH])
		print("OUTER_GATHER pin %s %s" % [data.block_id, JSON.stringify(pin)])
		return
	var pinned: Dictionary = pins[data.block_id]
	_check(int(pinned.count) == pin.count and pinned.sha256 == pin.sha256 and pinned.first == pin.first,
		"%s: ids and places match the pinned numbering" % data.block_id)

func _open(raw: Dictionary) -> Dictionary:
	var data := Data.decode(raw)
	if not data.ok: return {}
	var walk := Walk.new(data)
	var plan := Scenery.plan(data, walk)
	if not plan.ok: return {}
	Shade.enforce_budget(plan, data, walk)
	return {"data": data, "objects": Gather.objects(plan.layout, walk, data.block_id, Gather.rules(), plan.recipe.outer_groves.version)}

## Ids with their origins to the millimetre, in order.
func _signature(objects: Array) -> String:
	var lines := PackedStringArray()
	for object: Dictionary in objects:
		lines.append("%s@%d,%d" % [object.id, roundi(object.origin.x * 1000.0), roundi(object.origin.z * 1000.0)])
	return "\n".join(lines)

extends SceneTree
## C-228 (0.4.7; design SEN-C-227 D-555, owner SEN-Q-344) in the real scene on the local save: the Build key that only
## offered the rules' first buildable type is the Blueprints key; it opens the blueprint book, one card per blueprint
## in the bag in the rules' order whatever can be built, and any card's Place starts that type's preview. Here the
## coop, the well and the cottage are built in that order (not the rules' cottage, coop, well), the coop turned once.
## Cancel and Android Back in a preview go back to the book where it was; Back in the book closes it. A blueprint short
## of materials reads `Need N more …` and places nothing; a type at its level limit reads `Farm Lv3 needed`. With every
## blueprint used the book says `No blueprints` and the key stays (buildings stand) without its number. The quick bar
## never holds a blueprint (D4). An older save (built before C-228, a blueprint still in the bag) opens with its
## buildings and that blueprint on its card.
## Run in the private preview project (README), optionally with `-- <farm.json>`.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
var checks := 0
var failures := 0
var raw: Dictionary
var dir := ""
var scene

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if not args.is_empty() else Fixture.farm()
	dir = "user://test_blueprint_book_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	await _any_order()
	await _older_save()
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("BLUEPRINT_BOOK_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _open(store: RefCounted) -> Node:
	var args := {"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": store}
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	scene.preview_error.connect(func(message): push_error(message))
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 30000
	while not state.ready and Time.get_ticks_msec() < deadline: await process_frame
	_check(state.ready, "own parcel opens")
	await process_frame
	var farming: Node = scene.get_node("ParcelFarming")
	deadline = Time.get_ticks_msec() + 10000
	while not farming.loaded() and Time.get_ticks_msec() < deadline: await process_frame
	await process_frame
	return farming

func _close() -> void:
	scene.queue_free()
	await process_frame
	await process_frame

## A welcomed save with no building, the given bag and every core obstacle cleared (room for the coop).
func _seed(store: RefCounted, bag: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var seeded := ParcelFarm.empty_state()
	seeded.welcomed_at = now - 86400000
	seeded.grants = {"watering": now}
	seeded.bag = bag
	store._save(seeded, 2)
	var farming := await _open(store)
	var cleared := {}
	for anchor: Vector2i in farming._obstacles.values(): cleared[ParcelFarm.key(anchor)] = true
	seeded.cleared = cleared.keys()
	store._save(seeded, 3)
	await _close()
	return seeded

func _types(entries: Array) -> Array:
	return entries.map(func(e): return e.type)

func _book_types() -> Array:
	return _types(scene._book.entries) if scene._book != null else []

## Opens the book (if closed) and taps `type`'s key; true when its preview is up.
func _place(type: String) -> bool:
	if not scene.book_open(): scene._build.pressed.emit()
	await process_frame
	if scene._book == null or not scene._book.keys.has(type): return false
	scene._book.keys[type].pressed.emit()
	await process_frame
	return scene._placement != null and scene._placement.type == type

## Build in the preview; waits for the reply.
func _build() -> void:
	scene._placement._bar.confirmed.emit()
	var deadline := Time.get_ticks_msec() + 5000
	while scene._placement != null and Time.get_ticks_msec() < deadline: await process_frame
	for _i in 3: await process_frame

func _any_order() -> void:
	var store := LocalStore.new(raw.block_id, dir)
	await _seed(store, {"hoe_starter": 1, "pail": 1, "blueprint_cottage": 1, "blueprint_coop": 1, "blueprint_well": 1, "blueprint_barn": 1,
		"wood": 12, "stone": 10})
	var farming := await _open(store)
	# The key and its number; the bar without blueprints (D4).
	_check(scene._build.visible and scene._build.label == "Blueprints" and scene._build_count.visible and scene._build_count_label.text == "4",
		"the Blueprints key shows the 4 blueprints in the bag")
	_check(farming._bar.slots.all(func(slot): return not str(slot.id).begins_with("blueprint_")), "no blueprint on the quick bar: %s" % [farming._bar.slots.map(func(s): return s.id)])
	scene._build.pressed.emit()
	await process_frame
	_check(scene.book_open() and _book_types() == ["cottage", "coop", "barn", "well"], "the book lists the blueprints in the rules' order: %s" % [_book_types()])
	_check(scene._book.title == "Blueprints" and scene._book.hero != null and scene._book.cards.size() == 4, "a Blueprints tag, the book's hero, one card each")
	_check(not farming._keys.visible and not farming._bar.visible and not scene._build.visible, "under the book: no action key, quick bar or Blueprints key")
	var barn = scene._book.keys.barn
	_check(barn.reason == "Need 8 more %s" % farming.item_name("wood") and scene._book.keys.cottage.reason == "" and scene._book.keys.well.label == "Place",
		"short of Timber the barn's key reads its gap; the others read Place (%s)" % barn.reason)
	var barn_card: Control = scene._book.card_of("barn")
	var tiles: Array = barn_card.find_children("Need_*", "", true, false)
	_check(tiles.size() == 2 and tiles[0].have == 12 and tiles[0].need == 20 and tiles[1].have == 10,
		"the barn card's NEED-TILEs: Timber 12/20, Stone 10/10")
	barn.pressed.emit()
	await process_frame
	_check(scene.book_open() and scene._placement == null, "the barn's grey key places nothing; the book stays")
	# The well first: its preview, the chip naming it; Cancel goes back to the book.
	_check(await _place("well"), "the well's Place opens the well's preview, not the first card's")
	_check(scene._placing_chip.visible and scene._placing_name.text == "Well", "the chip under the avatar names the well")
	_check(not scene._build.visible and not farming._keys.visible, "the preview holds the screen")
	scene._placement._bar.cancelled.emit()
	await process_frame
	_check(scene._placement == null and scene.book_open() and not scene._placing_chip.visible, "Cancel goes back to the book")
	# Android Back in a preview goes back to the book too; in the book it closes the book.
	await _place("cottage")
	_check(scene.close_modal() and scene._placement == null and scene.book_open(), "Back in the cottage's preview goes back to the book")
	_check(scene.close_modal() and not scene.book_open() and scene._build.visible and farming._keys.visible, "Back in the book closes it; the farm's keys are back")
	# Coop, then well, then cottage: none waits for another.
	_check(await _place("coop"), "the coop's Place opens its preview")
	var p = scene._placement
	var start_at: Vector2i = p.at
	p._bar.secondary_pressed.emit()
	await create_timer(0.25).timeout
	_check(p.rotation_steps == 1 and p._ghost.transform.basis.z.is_equal_approx(Vector3.BACK.rotated(Vector3.UP, PI * 0.5)),
		"Rotate turns the coop a quarter")
	if p.reason != "":
		# Turned, it may not fit where it started: back to the start's turn search.
		for i in 3:
			if p.reason == "": break
			p._bar.secondary_pressed.emit()
	var turned: int = p.rotation_steps
	_check(p.reason == "", "the coop fits (%s at %s, turn %d)" % [p.reason, p.at, turned])
	await _build()
	var built: Array = scene.buildings_state()
	_check(built.size() == 1 and built[0].type == "coop" and int(built[0].rotation) == turned, "the coop stands first, turned %d: %s" % [turned, built])
	_check(not scene.book_open() and scene._build.visible and scene._build_count_label.text == "3", "built: back on the farm, the key counts 3")
	_check(await _place("well"), "then the well")
	await _build()
	_check(await _place("cottage"), "then the cottage")
	await _build()
	built = scene.buildings_state()
	_check(_types(built) == ["coop", "well", "cottage"] and farming.farm.house is Dictionary, "coop, well, cottage stand in the order placed: %s" % [_types(built)])
	_check(scene._build.visible and scene._build_count_label.text == "1", "the barn's blueprint is left")
	scene._build.pressed.emit()
	await process_frame
	_check(_book_types() == ["barn"], "the book holds the barn alone: %s" % [_book_types()])
	scene.close_book()
	# Every blueprint used: the empty book.
	farming.farm.bag.erase("blueprint_barn")
	scene._refresh_build()
	_check(scene._build.visible and not scene._build_count.visible, "no blueprint left: the key stays (buildings stand), without its number")
	scene._build.pressed.emit()
	await process_frame
	var empty: Node = scene._book.find_child("Empty", true, false)
	_check(empty is Label and (empty as Label).text == "No blueprints" and scene._book.cards.is_empty(), "the empty book says No blueprints")
	scene.close_book()
	await _close()
	# Reopened, they all stand where they were.
	await _open(store)
	_check(_types(scene.buildings_state()) == ["coop", "well", "cottage"] and scene._buildings.size() == 3, "reopened, the three buildings stand")
	await _close()

## A save from before C-228 (the cottage and a well built with the Build key, a spare Lv1 well blueprint and a coop
## blueprint in the bag): it opens with both buildings and both blueprints; the well's card reads Farm Lv3 needed.
func _older_save() -> void:
	var old_dir := dir + "_old"
	DirAccess.make_dir_recursive_absolute(old_dir)
	var store := LocalStore.new(raw.block_id, old_dir)
	var seeded := await _seed(store, {"hoe_starter": 1, "pail": 1, "blueprint_well": 1, "blueprint_coop": 1})
	var farming := await _open(store)
	var data: Dictionary = scene._data
	var taken := Building.blocked(farming.obstacle_cells(), farming.farm)
	var cottage_at = Building.nearest(data, data.spawn, Vector2i(3, 3), taken, farming.protected_path(), scene._walk_blocked(farming.obstacle_cells()), 0, "cottage")
	await _close()
	var cottage := {"model": "cottage", "x": cottage_at.x, "y": cottage_at.y, "width": 3, "depth": 3, "rotation": 0, "built_at": 0}
	seeded.buildings = [cottage.merged({"id": 1, "type": "cottage"}),
		{"id": 2, "type": "well", "model": "well", "x": cottage_at.x + 4, "y": cottage_at.y, "width": 1, "depth": 1, "rotation": 0, "built_at": 0}]
	seeded.house = cottage
	store._save(seeded, 9)
	farming = await _open(store)
	_check(_types(scene.buildings_state()) == ["cottage", "well"] and scene._buildings.size() == 2, "the older save's cottage and well stand")
	_check(farming.farm.bag.get("blueprint_well") == 1 and farming.farm.bag.get("blueprint_coop") == 1, "its blueprints are still in the bag")
	_check(scene._build.visible and scene._build_count_label.text == "2", "the Blueprints key counts them")
	scene._build.pressed.emit()
	await process_frame
	var entries: Array = scene._book.entries
	_check(_types(entries) == ["coop", "well"] and entries[1].reason == "Farm Lv3 needed" and scene._book.keys.well.reason == "Farm Lv3 needed",
		"the book: the coop to place, the spare well waiting for Lv3: %s" % [entries])
	scene.close_book()
	await _close()
	for name in DirAccess.get_files_at(old_dir): DirAccess.remove_absolute(old_dir.path_join(name))
	DirAccess.remove_absolute(old_dir)

extends SceneTree
## C-229 (0.4.7; design SEN-C-227 D-555 README §5, figure 3; owner SEN-Q-344 D1–D3): moving built buildings and storing
## them back into blueprints. First the client copy of the rules against the server on the shared cases
## (fixtures/arrange_cases.json, also run by server/test/parcels/farm.test.ts). Then the real scene on the local save:
## the book's Arrange key (only while a building stands) starts the arrange mode — the farming UI away (key, quick bar,
## phone, Blueprints key), one marker per building, one `Done`. The coop's card says `3 Hens` and `1 Egg on the ground`
## and, an egg still on its way, greys Store with `Ready in …` (D2); the cottage's has Move only (D3). The well is
## stored (the question lists its blueprint; D1): it goes, its blueprint is in the bag, the mode stays. The coop is
## moved: its own preview starts where it stands, `Move` its key, its old outline dashed; Cancel leaves it; moved
## elsewhere it stands there with its hens and both eggs. Back folds the card, then ends the mode; Done ends it too.
## Reopened, everything is where it was left. C-247 (V-779): an egg laid with the card up shows on it at once; the
## Energy countdown goes on under the Move preview; the cottage moved over the player leaves them where the camera
## sees them, not behind its roof. C-254 (V-798): a building panned up to the top bar keeps its marker just under the
## bar (LOCK-06 as it was), still tappable, and loses it once up behind the bar.
## Run in the private preview project (README), optionally with `-- <farm.json>`.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const CASES := "res://tests/dynamic_farm/fixtures/arrange_cases.json"
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
	_cases()
	var args := OS.get_cmdline_user_args()
	raw = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if not args.is_empty() else Fixture.farm()
	dir = "user://test_building_arrange_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	await _arrange()
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("ARRANGE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The shared cases: the client's rules give the server's result, and leave the input save as it was.
func _cases() -> void:
	var rules := ParcelFarm.rules()
	var shared = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	_check(shared is Dictionary and shared.cases.size() >= 12, "arrange cases: the shared fixture reads")
	for c: Dictionary in shared.cases:
		var farm := ParcelFarm.normalize(c.farm)
		var frozen := JSON.stringify(farm, "", true)
		var r := ParcelFarm.apply(rules, farm, c.commands, int(c.now))
		var got := {"ok": true, "buildings": r.state.buildings, "house": r.state.house, "drops": r.state.drops, "drop_seq": r.state.drop_seq,
			"bag": r.state.bag, "energy": r.state.energy} if r.ok else {"ok": false, "index": r.index, "code": r.code, "detail": r.get("detail", {})}
		var want := JSON.stringify(_ints(c.expect), "", true)
		_check(JSON.stringify(_ints(got), "", true) == want, "arrange case '%s': %s, server %s" % [c.name, JSON.stringify(_ints(got)), want])
		_check(JSON.stringify(farm, "", true) == frozen, "arrange case '%s': the input save is untouched" % c.name)
	# The scene's reads: what Store gives back, and why it waits.
	var coop := {"id": 2, "type": "coop", "model": "chicken_yard", "x": 20, "y": 40, "width": 7, "depth": 5, "rotation": 0, "built_at": 0,
		"animals": ["hen_white", "hen_brown", "hen_white"]}
	var state := {"buildings": [coop, {"id": 1, "type": "cottage", "model": "cottage", "x": 40, "y": 40, "width": 3, "depth": 3, "rotation": 0,
		"built_at": 0}], "drops": [{"id": 1, "item": "egg", "amount": 1, "building": 2, "animal": 0, "spot": 1, "ready_at": 1000},
		{"id": 2, "item": "egg", "amount": 1, "building": 2, "animal": 1, "spot": 2, "ready_at": 5000}]}
	_check(ParcelFarm.store_refusal(rules, state, 2, 2000) == {"code": "PRODUCING", "detail": {"ready_at": 5000}}, "an egg on its way: PRODUCING until 5000")
	_check(ParcelFarm.store_refusal(rules, state, 2, 5000).code == "", "both laid: it can be stored")
	_check(ParcelFarm.store_refusal(rules, state, 1, 0).code == "CANNOT_STORE", "the cottage never")
	_check(ParcelFarm.store_returns(rules, state, 2) == {"blueprint_coop": 1, "egg": 2}, "the coop gives back its blueprint and both eggs")

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

## A welcomed save with no building, the given bag and every core obstacle cleared.
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

## Places `type` from the book where its preview starts (turning it until it fits).
func _place(type: String) -> bool:
	if not scene.book_open(): scene._build.pressed.emit()
	await process_frame
	if scene._book == null or not scene._book.keys.has(type): return false
	scene._book.keys[type].pressed.emit()
	await process_frame
	var p = scene._placement
	if p == null: return false
	for i in 4:
		if p.reason == "": break
		p.turn()
	if p.reason != "": return false
	p._bar.confirmed.emit()
	await _settled()
	return true

## Waits for the preview to end and the reply to land.
func _settled() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (scene._placement != null or scene._sending) and Time.get_ticks_msec() < deadline: await process_frame
	for _i in 3: await process_frame

## The step-out before C-247: the nearest clear point in rings of 0.1 m, wherever the camera is.
func _nearest_clear(from: Vector3) -> Variant:
	for ring in range(1, 40):
		for k in 32:
			var q := from + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 32.0) * ring * 0.1
			if scene._walk.clear_position(q): return q
	return null

func _id_of(type: String) -> int:
	for b: Dictionary in scene.buildings_state():
		if b.type == type: return int(b.id)
	return 0

func _state_of(id: int) -> Dictionary:
	for b: Dictionary in scene.buildings_state():
		if int(b.id) == id: return b
	return {}

## Where building `id`'s marker would be without the top bar (over its model's top, as marker_point).
func _marker_raw(id: int) -> Vector2:
	var lift: float = load("res://scenes/dynamic_farm/building_arrange.gd").MARKER_LIFT
	var built: Dictionary = scene._buildings[id]
	var b: Dictionary = built.state
	var middle: Vector3 = Building.center(scene._walk, Building.at_of(b), Building.base_of(b), int(b.rotation))
	var top := middle.y
	for mesh: VisualInstance3D in (built.node as Node3D).find_children("*", "VisualInstance3D", true, false):
		top = maxf(top, (mesh.global_transform * mesh.get_aabb()).end.y)
	return scene._camera.unproject_position(Vector3(middle.x, top + lift, middle.z))

## C-254 (C-247 V-798): the camera pans until building `id` goes up behind the top bar (LOCK-06). Its marker never
## goes over the bar: where it would (the V-798 frame) it stays just under it, the bar as it was, and a tap on it
## picks the building; once the building is up behind the bar the marker goes. Panned back, it is where it was.
func _marker_under_bar(arrange: Control, id: int) -> void:
	var focus_was: Vector3 = scene._focus
	var overview_was: bool = scene._overview
	var bar: float = scene.top_bar_bottom()
	var hit: float = load("res://scenes/dynamic_farm/building_arrange.gd").MARKER_HIT
	var header: Control = scene._header
	var header_was := header.get_global_rect()
	var marker: Control = arrange.markers[id]
	var start_pos: Vector2 = marker.position + marker.size * 0.5
	var middle: Vector2 = scene.get_viewport().get_visible_rect().size * 0.5
	# First well under the bar: the marker is over its building, as before.
	for _i in 200:
		if _marker_raw(id).y > bar + hit * 2.0: break
		scene.pan(middle, middle + Vector2(0, 4))
	arrange._place_markers()
	var low_raw := _marker_raw(id)
	_check(low_raw.y > bar + hit * 2.0 and marker.visible and (marker.position + marker.size * 0.5).distance_to(low_raw) < 0.5,
		"C-254: well under the bar, the marker is over its building: %s, unbarred %s" % [marker.position + marker.size * 0.5, low_raw])
	var over := 0
	var tucked := false
	var picked := false
	var hid_early := false
	var gone := false
	for _i in 600:
		scene.pan(middle, middle - Vector2(0, 4))
		arrange._place_markers()
		var raw := _marker_raw(id)
		if not marker.visible:
			gone = true
			hid_early = raw.y - hit * 0.5 > bar
			break
		if marker.position.y < bar - 0.01: over += 1
		if raw.y < bar and not tucked:
			# The V-798 frame: unbarred, the marker's middle would be on the bar.
			tucked = absf(marker.position.y - bar) < 0.01
			arrange.tap(marker.position + marker.size * 0.5)
			picked = arrange.selected == id
			arrange.close_card()
	_check(tucked, "C-254: pushed up, building %d's marker would be on the top bar; it stays just under it" % id)
	_check(over == 0, "C-254: the marker never goes over the top bar (%d frames did)" % over)
	_check(picked, "C-254: a tap on the marker under the bar picks building %d" % id)
	_check(gone and not hid_early, "C-254: up behind the bar the marker goes, not before")
	_check(header.get_global_rect() == header_was and header.visible, "C-254: the top bar stays as it was")
	scene._focus = focus_was
	scene._overview = overview_was
	scene._place_camera()
	arrange._place_markers()
	_check(marker.visible and (marker.position + marker.size * 0.5).distance_to(start_pos) < 0.5,
		"C-254: panned back, the marker is where it was: %s, was %s" % [marker.position + marker.size * 0.5, start_pos])
	await process_frame

func _arrange() -> void:
	var store := LocalStore.new(raw.block_id, dir)
	await _seed(store, {"hoe_starter": 1, "pail": 1, "blueprint_cottage": 1, "blueprint_coop": 1, "blueprint_well": 1, "crop_carrot": 2})
	var farming := await _open(store)
	# No building yet: the book has no Arrange key.
	scene._build.pressed.emit()
	await process_frame
	_check(scene.book_open() and scene._book.arrange_key == null, "no building stands: the book has no Arrange key")
	scene.close_book()
	for type in ["coop", "well", "cottage"]: _check(await _place(type), "the %s is placed" % type)
	_check(scene.buildings_state().size() == 3, "three buildings stand: %s" % [scene.buildings_state()])
	# An egg laid and one on its way in the coop.
	await _close()
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var saved: Dictionary = store._load()
	var coop_id := 0
	for b: Dictionary in saved.farm.buildings:
		if b.type == "coop": coop_id = int(b.id)
	saved.farm.drops = [{"id": 1, "item": "egg", "amount": 1, "building": coop_id, "animal": 0, "spot": 1, "ready_at": now - 60000},
		{"id": 2, "item": "egg", "amount": 1, "building": coop_id, "animal": 1, "spot": 4, "ready_at": now + 600000}]
	saved.farm.drop_seq = 2
	store._save(saved.farm, int(saved.version) + 1)
	farming = await _open(store)
	_check(farming.farm.drops.size() == 2, "the coop's two eggs are in the save")
	# The book's Arrange key; the mode takes the screen.
	scene._build.pressed.emit()
	await process_frame
	_check(scene._book.arrange_key != null and scene._book.arrange_key.label == "Arrange", "a building stands: the book has Arrange")
	scene._book.arrange_key.pressed.emit()
	await process_frame
	await process_frame
	var arrange = scene._arrange
	_check(arrange != null and not scene.book_open(), "Arrange: the book goes, the arrange mode is on")
	_check(not farming._keys.visible and not farming._bar.visible and not farming.phone_button.visible and not scene._build.visible,
		"the action key, quick bar, phone and Blueprints key are away (M-16)")
	_check(arrange.tray.visible and arrange.tray.confirm == "Done" and arrange.tray.cancel == "", "the bottom has one Done")
	_check(arrange.markers.size() == 3, "one marker per building: %d" % arrange.markers.size())
	for id: int in arrange.markers:
		var m: Control = arrange.markers[id]
		# Approximate: a marker sits at its building's projected point, a fractional position, and a Control's size is
		# kept as offset_bottom - offset_top in float32, so it can read 44.00001 at some points (C-249).
		_check(m.visible and m.size.is_equal_approx(Vector2(44, 44)), "building %d's marker shows, its hit area 44: %s" % [id, m.size])
	await _marker_under_bar(arrange, _id_of("coop"))
	# The coop: its facts, Store waiting for the egg (D2).
	arrange.select(coop_id)
	await process_frame
	_check(arrange.card != null and arrange.facts == ["3 Hens", "1 Egg on the ground"], "the coop's card: %s" % [arrange.facts])
	_check(arrange.store_key != null and arrange.store_key.reason.begins_with("Ready in") and arrange.move_key.label == "Move",
		"an egg on its way: Store reads %s; Move is there" % (arrange.store_key.reason if arrange.store_key != null else "?"))
	arrange.store_key.pressed.emit()
	await process_frame
	_check(not arrange.asking and scene.buildings_state().size() == 3, "the grey Store asks nothing and sends nothing")
	# C-247: the egg on its way is laid while the card is up: the facts say so within the second, Store turns back.
	for d: Dictionary in farming.farm.drops:
		if int(d.id) == 2: d.ready_at = farming.server_now() - 1
	arrange._process(1.0)
	var lines: Array = arrange.card.find_children("Fact*", "Label", true, false).map(func(l: Label): return l.text)
	_check(arrange.facts == ["3 Hens", "2 Egg on the ground"] and lines == arrange.facts,
		"C-247: laid with the card up, the facts update at once: %s, shown %s" % [arrange.facts, lines])
	_check(arrange.store_key != null and arrange.store_key.reason == "", "C-247: laid, Store is no longer grey")
	# The cottage: Move only (D3).
	var home := _id_of("cottage")
	arrange.tap(arrange.markers[home].position + Vector2(22, 22))
	await process_frame
	_check(arrange.selected == home and arrange.store_key == null and arrange.move_key != null, "a tap on the cottage's marker: its card, Move only")
	# The well: stored (D1), the mode stays.
	var well := _id_of("well")
	arrange.select(well)
	await process_frame
	_check(arrange.store_key != null and arrange.store_key.reason == "", "the well can be stored")
	arrange.store_key.pressed.emit()
	await process_frame
	_check(arrange.asking and arrange.card.name == "StoreCard" and arrange.returns == ["1 %s" % farming.item_name("blueprint_well")],
		"Store asks first, listing the blueprint: %s" % [arrange.returns])
	var question: Label = arrange.card.find_child("Question", true, false)
	_check(question != null and question.text == "Store Well?", "the question reads Store Well?")
	_check(scene.close_modal() and not arrange.asking and arrange.selected == well, "Back goes from the question to the well's card")
	arrange.store_key.pressed.emit()
	await process_frame
	(arrange.card.find_child("StoreConfirm", true, false) as UiCommandButton).pressed.emit()
	var deadline := Time.get_ticks_msec() + 5000
	while scene._sending and Time.get_ticks_msec() < deadline: await process_frame
	for _i in 3: await process_frame
	_check(_id_of("well") == 0 and farming.farm.bag.get("blueprint_well") == 1, "the well is stored: gone, its blueprint in the bag")
	_check(scene._arrange == arrange and arrange.markers.size() == 2 and arrange.card == null, "the mode stays, two markers left")
	var leaving: Node = scene.find_child("Building%dLeaving" % well, false, false)
	_check(leaving != null or scene.find_child("Building%d" % well, false, false) == null, "the well's model shrinks away")
	# The coop: Move, then Cancel.
	var before := _state_of(coop_id)
	arrange.select(coop_id)
	await process_frame
	arrange.move_key.pressed.emit()
	await process_frame
	var p = scene._placement
	_check(p != null and scene._moving == coop_id and not arrange.visible, "Move: the coop's own preview, the arrange UI away")
	_check(p != null and p._bar.confirm == "Move" and p.at == Building.at_of(before) and p.rotation_steps == int(before.rotation),
		"it starts where the coop stands, turned as it is, its key Move")
	_check(p != null and p.reason == "", "its own cells are free for it: %s" % (p.reason if p != null else "?"))
	_check(p != null and p.origin_dashes().size() > 0, "the old place has its dashed outline (%d dashes)" % (p.origin_dashes().size() if p != null else 0))
	_check(scene._placing_chip.visible and scene._placing_name.text == "Coop", "the chip names the coop")
	var yard = farming.livestock._yards.get(coop_id)
	_check(not scene._buildings[coop_id].node.visible and yard != null and not yard.root.visible,
		"the coop and its hens hide behind the preview")
	# C-247: the Energy chip's `+1 in m:ss` counts on under the preview (the clock moved 5 s on).
	farming.farm.energy = {"value": 10, "at": farming.server_now(), "rested_on": null}
	for _i in 2: await process_frame
	var regen_before: String = farming.energy_chip.regen
	farming._clock_offset_ms += 5000
	for _i in 2: await process_frame
	var regen_after: String = farming.energy_chip.regen
	var want := "+1 in " + str(load("res://modules/p0/p0_logic.gd").duration(float(farming.energy_now().next_in)))
	_check(scene._placement == p and regen_before.begins_with("+1 in ") and regen_after != regen_before and regen_after == want,
		"C-247: under the Move preview the Energy countdown goes on: %s -> %s (want %s)" % [regen_before, regen_after, want])
	farming._clock_offset_ms -= 5000
	farming.farm.erase("energy")
	p._bar.cancelled.emit()
	await process_frame
	_check(scene._placement == null and scene._arrange != null and arrange.visible and _state_of(coop_id) == before,
		"Cancel: back in the arrange mode, the coop where it was")
	_check(scene._buildings[coop_id].node.visible and yard.root.visible, "Cancel: the coop and its hens show again")
	# Moved elsewhere.
	arrange.select(coop_id)
	await process_frame
	arrange.move_key.pressed.emit()
	await process_frame
	p = scene._placement
	var start: Vector2i = p.at
	var found := false
	for r in range(2, 30):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				for cell in [start + Vector2i(dx, dy), start + Vector2i(dy, dx)]:
					if found: break
					p.move_to(cell)
					found = p.reason == ""
	_check(found and p.at != start, "the coop fits somewhere else (%s)" % [p.at])
	var to: Vector2i = p.at
	var turn: int = p.rotation_steps
	p._bar.confirmed.emit()
	await _settled()
	var moved := _state_of(coop_id)
	_check(Building.at_of(moved) == to and int(moved.rotation) == turn and moved.animals == before.animals,
		"the coop stands at %s with its hens: %s" % [to, moved])
	_check(farming.farm.drops.size() == 2 and farming.farm.drops.all(func(d): return int(d.building) == coop_id), "both eggs go with it")
	_check(scene._buildings[coop_id].node.visible and farming.livestock._yards[coop_id].root.visible, "moved, the coop and its hens show")
	_check(scene._arrange == arrange and arrange.visible and scene._placement == null, "back in the arrange mode")
	# C-247: the cottage moved over the player, who stands by its back wall: they step out where the camera sees them,
	# not behind its roof (the nearest clear point, as before, was behind it).
	arrange.select(home)
	await process_frame
	arrange.move_key.pressed.emit()
	await process_frame
	p = scene._placement
	var home_start: Vector2i = p.at
	var spot = null
	for r in range(3, 30):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				for cell in [home_start + Vector2i(dx, dy), home_start + Vector2i(dy, dx)]:
					if spot != null: break
					p.move_to(cell)
					if p.reason == "": spot = cell
	_check(spot != null, "C-247: the cottage fits elsewhere (%s)" % [spot])
	var back: Vector3 = scene._camera.global_basis.z
	var far := Vector3(-back.x, 0.0, -back.z).normalized()
	var middle: Vector3 = Building.center(scene._walk, p.at, p.base, p.rotation_steps)
	var stand: Vector3 = Vector3(middle.x, scene._walk.position.y, middle.z) + far * (float(mini(p.base.x, p.base.y)) * scene._walk.cell_m * 0.5 - 0.3)
	_check(scene._walk.clear_position(stand), "C-247: the player can stand there before the cottage comes")
	scene._walk.position = stand
	scene._actor.position = stand
	p._bar.confirmed.emit()
	await _settled()
	# The landing pop (Fence.POP_S) over, the cottage at its full size for the sight checks.
	var pop_end := Time.get_ticks_msec() + int(float(load("res://scenes/p0/p0_fence.gd").POP_S) * 1000.0) + 300
	while Time.get_ticks_msec() < pop_end: await process_frame
	var standing := _state_of(home)
	_check(Building.at_of(standing) == spot, "C-247: the cottage stands over where the player stood: %s" % [standing])
	var now_at: Vector3 = scene._actor.position
	_check(now_at.distance_to(stand) > 0.01 and scene._walk.clear_position(now_at) and now_at.distance_to(stand) < 6.0,
		"C-247: the player stepped out to a clear point %.2f m away" % now_at.distance_to(stand))
	_check(scene.seen(now_at), "C-247: the camera sees the player there (not behind the roof): %s" % [now_at])
	var nearest: Variant = _nearest_clear(stand)
	_check(nearest != null and not scene.seen(nearest),
		"C-247 control: the nearest clear point (the old step-out) is hidden behind the cottage: %s" % [nearest])
	# Back folds the card, then ends the mode.
	arrange.select(home)
	await process_frame
	_check(scene.close_modal() and arrange.card == null and scene._arrange != null, "Back folds the card")
	_check(scene.close_modal() and scene._arrange == null, "Back again ends the mode")
	await process_frame
	_check(farming._keys.visible and scene._build.visible and scene._build_count_label.text == "1", "the farming UI is back; the key counts the well's blueprint")
	# Done ends it too.
	scene._build.pressed.emit()
	await process_frame
	scene._book.arrange_key.pressed.emit()
	await process_frame
	scene._arrange.tray.confirmed.emit()
	await process_frame
	_check(scene._arrange == null and farming._keys.visible, "Done ends the arrange mode")
	await _close()
	# Reopened: as left.
	farming = await _open(store)
	var reopened := _state_of(coop_id)
	_check(Building.at_of(reopened) == to and int(reopened.rotation) == turn and _id_of("well") == 0 and _id_of("cottage") == home,
		"reopened: the coop where it was moved, the cottage, no well")
	_check(farming.farm.bag.get("blueprint_well") == 1 and farming.farm.drops.size() == 2, "reopened: the well's blueprint and both eggs")
	_check(scene._buildings.size() == 2, "reopened: two buildings drawn")
	await _close()

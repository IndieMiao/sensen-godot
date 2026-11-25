extends SceneTree
## C-107 the in-game phone on one's own parcel (design C-85 ⑦ / ⑧):
## - ParcelTasks: the guide's eight steps as rows, done / current / todo from the save alone, at every stage of the
##   first visit (a growing carrot waits on Harvest, the coop blueprint ends the list);
## - the kit: UiTaskRow's finishing beat, UiTaskDropDown's rows / More… / fold, UiPhone's tabs, badge and head;
## - the phone's pages over data: tasks with groups and only the current row tappable, the inbox's rows and Claim all,
##   empty Parcels / Updates, collection cards opening their grid (silhouettes for what is not got) and ‹ back;
## - the real scene on the local save: the task button in the top bar with its new-task dot, the drop-down (three rows,
##   More… opening the phone), the phone (quick bar away, three tabs, the current task's tip on a tap, Back closes it),
##   a step finished while the drop-down is up moving the rows on, and the seen task kept after reopening.
## Run in the private preview project (README), optionally with `-- <farm.json>`.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Tasks = preload("res://modules/dynamic_farm/parcel_tasks.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const NOW := 1_800_000_000_000
var checks := 0
var failures := 0
var raw: Dictionary
var dir := ""
var scene
## The phone's script is loaded once the autoloads are up (it reads P0's content through P0Inbox).
var Phone: GDScript

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
	dir = "user://test_parcel_phone_%d" % Time.get_ticks_usec()
	Phone = load("res://scenes/dynamic_farm/parcel_phone.gd")
	_task_progress()
	await _kit()
	await _pages()
	await _scene()
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("PARCEL_PHONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _farm(changes: Dictionary) -> Dictionary:
	var f := ParcelFarm.empty_state()
	f.merge(changes, true)
	f.house = ParcelFarm.home_of(f.buildings)
	return f

const HOUSE := {"model": "cottage", "x": 2, "y": 2, "width": 3, "depth": 3, "rotation": 0, "built_at": 0, "id": 1, "type": "cottage"}

func _task_progress() -> void:
	_check(Tasks.TASKS.size() == 8 and Tasks.keys() == ["build", "till", "sow", "harvest", "sell", "gather", "sell_gathered", "blueprint"],
		"eight tasks in the guide's order")
	_check(Tasks.done_count({}, NOW) == 0 and Tasks.current({}, NOW) == "", "no save: nothing done, no current task")
	var cases := [
		["a blueprint, no house: Build", {"bag": {"blueprint_cottage": 1, "seed_carrot": 3, "hoe_starter": 1}}, 0],
		["a house and seeds: Till", {"buildings": [HOUSE], "bag": {"seed_carrot": 3, "hoe_starter": 1}}, 1],
		["tilled soil: Sow", {"buildings": [HOUSE], "tilled": ["7,7"], "bag": {"seed_carrot": 3}}, 2],
		["a carrot growing: Harvest waits", {"buildings": [HOUSE], "tilled": ["7,7"], "crops": {"7,7": {"crop": "crop_carrot", "planted_at": NOW, "ripe_at": NOW + 60000}}}, 3],
		["a ripe carrot: Harvest", {"buildings": [HOUSE], "tilled": ["7,7"], "crops": {"7,7": {"crop": "crop_carrot", "planted_at": NOW - 90000, "ripe_at": NOW - 30000}}}, 3],
		["a carrot in the bag: Sell", {"buildings": [HOUSE], "bag": {"crop_carrot": 1}}, 4],
		["sold, nothing gathered: Gather", {"buildings": [HOUSE], "sales": 1, "coins": 12}, 5],
		["gathered something sellable: Sell it", {"buildings": [HOUSE], "sales": 1, "bag": {"wood": 1}, "gathered": {"x": NOW}}, 6],
		["gathered and sold: the blueprint", {"buildings": [HOUSE], "sales": 2, "gathered": {"x": NOW}}, 7],
		["the coop blueprint taken: all done", {"buildings": [HOUSE], "sales": 2, "gathered": {"x": NOW}, "blueprints_claimed": {"coop": NOW}}, 8],
	]
	for c: Array in cases:
		var f := _farm(c[1])
		_check(Tasks.done_count(f, NOW) == c[2], "%s (%d done, got %d)" % [c[0], c[2], Tasks.done_count(f, NOW)])
		var rows := Tasks.rows(f, NOW)
		var states := rows.map(func(r: Dictionary): return r.state)
		var want := []
		for i in rows.size(): want.append("done" if i < c[2] else "current" if i == c[2] else "todo")
		_check(states == want, c[0] + ": row states follow the count")
	_check(Tasks.current(_farm(cases[9][1]), NOW) == "", "all done: no current task")
	_check(Tasks.rows({}, NOW)[0].state == "current" and Tasks.rows({}, NOW)[0].group == "GET STARTED"
		and Tasks.rows({}, NOW)[4].group == "TOWN", "groups: GET STARTED then TOWN")
	_check(Tasks.title("sell") == "Sell to Jasmine" and Tasks.title("blueprint") == "Take Scott's blueprint", "design copy")

func _host(c: Control) -> Control:
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.size = Vector2(360, 800)
	root.add_child(holder)
	holder.add_child(c)
	return holder

func _kit() -> void:
	# UiTaskRow: the finishing beat ends done, struck through and grey.
	var row := UiTaskRow.new("Sow Carrot Seeds", UiTaskRow.State.CURRENT)
	var holder := _host(row)
	row.size = Vector2(200, 28)
	await process_frame
	_check(row.strike_progress() == 0.0 and row.label().get_theme_color(&"font_color") == UiTokens.COLOR_PHONE_TEXT, "current row: no strike, phone text")
	row.complete()
	_check(row.state == UiTaskRow.State.DONE, "complete() marks it done")
	await create_timer(0.5).timeout
	_check(row.strike_progress() == 1.0 and row.label().get_theme_color(&"font_color") == UiTokens.COLOR_PHONE_TEXT_MUTED,
		"after the beat: struck through and grey")
	holder.queue_free()
	# UiTaskDropDown: at most three rows, More…, no touches taken by the rows, folds on its own.
	var drop := UiTaskDropDown.new()
	holder = _host(drop)
	var more := [0]
	drop.more_pressed.connect(func(): more[0] += 1)
	var folded := [0]
	drop.folded.connect(func(): folded[0] += 1)
	drop.open([{"title": "Build Cottage", "state": UiTaskRow.State.DONE}, {"title": "Till a spot in your yard", "state": UiTaskRow.State.CURRENT},
		{"title": "Sow Carrot Seeds", "state": UiTaskRow.State.TODO}, {"title": "Harvest a carrot", "state": UiTaskRow.State.TODO}], true)
	await process_frame
	_check(drop.rows.size() == 3 and drop.more != null and drop.more.title == "More…", "three rows then More…")
	_check(drop.rows.all(func(r: UiTaskRow): return r.mouse_filter == Control.MOUSE_FILTER_IGNORE) and drop.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"rows let touches through to the scene")
	_check(drop.rows[0].look == UiTaskRow.Look.GLASS and drop.rows[0].pill().get_theme_stylebox(&"panel").bg_color == UiTokens.COLOR_GLASS_FILL_STRONG,
		"glass rows")
	_check(drop.rows[0].size.x < drop.rows[1].size.x, "a glass pill hugs its text")
	drop.more.pressed.emit()
	await create_timer(0.3).timeout
	_check(more[0] == 1 and not drop.showing and not drop.visible and folded[0] == 1, "More… asks for the phone and folds")
	drop.open([{"title": "Build Cottage", "state": UiTaskRow.State.CURRENT}], false)
	_check(drop.more == null, "no More… with nothing more")
	await create_timer(UiTaskDropDown.STAY_S + 0.5).timeout
	_check(not drop.showing and folded[0] == 2, "folds itself after 4 s")
	holder.queue_free()
	# UiPhone: tabs, the selected one, a badge, the head.
	var phone := UiPhone.new([{"title": "Tasks", "icon": UiArt.color("tab_tasks")}, {"title": "Inbox", "icon": UiArt.color("tab_inbox")}])
	holder = _host(phone)
	await process_frame
	_check(phone.frame.size == Vector2(UiTokens.SIZE_PHONE_W, UiTokens.SIZE_PHONE_H), "224 × 436 phone")
	_check(phone.tab_count() == 2 and phone.selected == 0, "tabs, the first selected")
	# C-M4: only the unselected tab is greyed, from the incoming COLOR (texture × modulate); sampling TEXTURE again
	# and multiplying kept the icon in colour on the device.
	var grey := UiPhone.grey_material().shader.code
	_check(phone.tab(0).icon_rect().material == null and phone.tab(1).icon_rect().material == UiPhone.grey_material(),
		"the unselected tab's icon greyed, the selected one in colour")
	_check(grey.contains("dot(COLOR.rgb") and not grey.contains("texture(TEXTURE"), "grey from the incoming COLOR alone")
	phone.set_badge(1, 3)
	_check(phone.badge(1) == 3, "a red count on a tab")
	phone.set_head("Fish", true, "9/20")
	_check(phone.head_title() == "Fish" and phone.back_button().visible, "a sub-page's head with ‹")
	phone.place(Vector2(346, 300), 8)
	_check(phone.frame.position.y == 8.0 and phone.frame.position.x == 346 - UiTokens.SIZE_PHONE_W, "kept inside the top on a short screen")
	var asked := [0]
	phone.close_requested.connect(func(): asked[0] += 1)
	phone.close_button().pressed.emit()
	_check(asked[0] == 1, "✕ asks to close")
	var gone := [false]
	phone.closed.connect(func(): gone[0] = true)
	phone.close()
	await create_timer(0.4).timeout
	_check(gone[0] and not is_instance_valid(phone), "close() plays out and frees it")
	holder.queue_free()

func _texts(n: Node) -> Array:
	var out := []
	if n is Label: out.append((n as Label).text)
	if n is Button and not (n as Button).text.is_empty(): out.append((n as Button).text)
	for c in n.get_children(): out.append_array(_texts(c))
	return out

func _find(n: Node, name: String) -> Node:
	return n.find_child(name, true, false)

func _pages() -> void:
	var phone = Phone.new()
	var holder := _host(phone)
	phone.place(Vector2(346, 700))
	var bag := _farm({"buildings": [HOUSE], "tilled": ["7,7"], "bag": {"seed_carrot": 3}})
	phone.refresh(Tasks.rows(bag, NOW))
	phone.show_tab(Phone.TASKS_TAB)
	await process_frame
	var texts := _texts(phone.page)
	_check("GET STARTED" in texts and "TOWN" in texts and "Sow Carrot Seeds" in texts, "task page: groups and rows")
	var sow: UiTaskRow = _find(phone.page, "Task_sow")
	var till: UiTaskRow = _find(phone.page, "Task_till")
	var harvest: UiTaskRow = _find(phone.page, "Task_harvest")
	_check(sow.state == UiTaskRow.State.CURRENT and till.state == UiTaskRow.State.DONE and harvest.state == UiTaskRow.State.TODO,
		"done, current and todo rows")
	_check(sow.tappable and not till.tappable and not harvest.tappable, "only the current row is tappable")
	var pressed := [""]
	phone.task_pressed.connect(func(k: String): pressed[0] = k)
	sow.pressed.emit()
	_check(pressed[0] == "sow", "tapping the current row names its step")
	_check(phone.page is TouchScrollContainer, "the list scrolls (TouchScrollContainer)")
	# Inbox: the dynamic farm has none.
	phone.show_tab(Phone.INBOX_TAB, 1)
	await process_frame
	_check(phone.selected == Phone.INBOX_TAB and phone.head_title() == "Inbox", "Inbox tab")
	_check("No parcels" in _texts(phone.page), "no inbox: No parcels")
	(_find(phone.page, "Part1") as Button).pressed.emit()
	await process_frame
	_check("No updates yet" in _texts(phone.page), "Updates: No updates yet")
	(_find(phone.page, "Part0") as Button).pressed.emit()
	await process_frame
	# Inbox with P0's rows (a P0-style view).
	var view := {"inbox": {"parcels": [{"key": "p1", "id": "crop_carrot", "qty": 5, "source": "Order reward", "left": 86400000, "can_claim": true}],
		"updates": [{"key": "u1", "id": "crop_carrot", "qty": 2, "status": "expired", "coins": 18, "at": NOW, "read": false}]},
		"bag": {"capacity": 25, "free": 6}}
	phone.refresh(Tasks.rows(bag, NOW), view)
	await process_frame
	texts = _texts(phone.page)
	_check(phone.badge(Phone.INBOX_TAB) == 2, "the Inbox tab counts parcels and unread updates")
	_check("Parcels · 1" in texts and "Bag 19/25 · 6 slots free" in texts and "Claim" in texts and "Claim all · 1 slot" in texts,
		"parcels: count, capacity, Claim and Claim all")
	_check(_find(phone.page, "Unread") != null, "unread Updates: a dot on the switch")
	var claimed := [{}]
	phone.claim_requested.connect(func(cmd: Dictionary): claimed[0] = cmd)
	(_find(phone.page, "Claim") as UiCommandButton).activated.emit()
	_check(claimed[0].get("type") == "claim_parcel" and claimed[0].get("key") == "p1", "Claim asks to claim that parcel")
	# Collection: none in the dynamic farm; with data, cards then a grid.
	phone.refresh(Tasks.rows(bag, NOW))
	phone.show_tab(Phone.COLLECTION_TAB, 1)
	await process_frame
	_check(_texts(phone.page) == ["Nothing collected yet"], "no collection data: Nothing collected yet")
	var fish := {"id": "fish", "name": "Fish", "icon": UiArt.item("fish_koi"), "got": 1, "total": 4,
		"items": [{"icon": UiArt.item("fish_koi"), "got": true}, {"icon": UiArt.item("fish_perch"), "got": false},
			{"icon": UiArt.item("fish_crucian"), "got": false}, {"icon": UiArt.item("fish_sturgeon"), "got": false}]}
	phone.refresh(Tasks.rows(bag, NOW), {}, [fish, {"id": "pages", "name": "Pages", "total": 0}])
	await process_frame
	texts = _texts(phone.page)
	_check("Fish" in texts and "1/4" in texts and not "Pages" in texts, "a card per category with data; empty ones hidden")
	(_find(phone.page, "Card_fish") as Button).pressed.emit()
	await process_frame
	_check(phone.head_title() == "Fish" and phone.back_button().visible, "a card opens its grid with ‹")
	var grid := _find(phone.page, "Grid") as GridContainer
	_check(grid != null and grid.get_child_count() == 4 and grid.columns == 4, "4-column grid")
	var shades := grid.get_children().map(func(c: Node): return (c.get_child(0) as Control).modulate)
	_check(shades[0] == Color.WHITE and shades[1] == Phone.SILHOUETTE, "got in colour, the rest as silhouettes")
	phone.back_button().pressed.emit()
	await process_frame
	_check(phone.head_title() == "Collection" and not phone.back_button().visible, "‹ back to the cards")
	phone.tab(Phone.TASKS_TAB).pressed.emit()
	await create_timer(0.3).timeout
	_check(phone.selected == Phone.TASKS_TAB and phone.body.get_child_count() == 1, "switching tabs leaves one page")
	holder.queue_free()

func _store() -> RefCounted:
	return LocalStore.new(raw.block_id, dir)

func _open() -> Node:
	var args := {"farm": raw, "dataset": raw.dataset_version, "block_id": raw.block_id, "own_parcel": true, "farm_store": _store()}
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup(args)
	var state := {"ready": false}
	scene.preview_ready.connect(func(_summary): state.ready = true)
	scene.preview_error.connect(func(message): push_error(message))
	root.add_child(scene)
	var farming: Node = scene.get_node("ParcelFarming")
	farming.phone_seen_path = dir.path_join("phone.json")
	var deadline := Time.get_ticks_msec() + 30000
	while not (state.ready and farming.loaded()) and Time.get_ticks_msec() < deadline: await process_frame
	_check(state.ready, "own parcel opens")
	for _i in 3: await process_frame
	return farming

func _close() -> void:
	scene.queue_free()
	await process_frame
	await process_frame

func _scene() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var farming := await _open()
	_check(not farming.farm.is_empty(), "the save is read")
	var button: UiTaskButton = farming.task_button
	_check(button.get_parent() == scene._header and button.get_index() < farming.energy_chip.get_index(), "the task button sits in the top bar before Energy")
	_check(button.visible and farming.phone_button.visible, "task and phone buttons show once the save is read")
	_check(Tasks.current(farming.farm, farming.server_now()) == "build", "first visit: Build Cottage is current")
	_check(button.badge and farming.phone_button.badge, "a task not seen yet marks both buttons")
	var bar_rect: Rect2 = farming._bar.get_global_rect()
	var phone_rect: Rect2 = farming.phone_button.get_global_rect()
	var key_rect: Rect2 = farming._keys.get_global_rect()
	_check(phone_rect.end.y <= key_rect.position.y and phone_rect.end.x <= farming._ui.size.x and phone_rect.end.y < bar_rect.position.y,
		"the phone button sits at the right above the action key")
	# The drop-down.
	button.pressed.emit()
	await process_frame
	var drop: UiTaskDropDown = farming.drop_down
	_check(drop.showing and drop.rows.size() == 3 and drop.more != null, "the task button drops three rows and More…")
	_check(drop.rows[0].title == "Build Cottage" and drop.rows[0].state == UiTaskRow.State.CURRENT, "the current task leads on a first visit")
	_check(not button.badge and not farming.phone_button.badge, "seeing the task clears both dots")
	_check(not farming._tip.visible, "the tip card steps aside for the drop-down")
	_check(drop.get_global_rect().position.y >= scene._header.get_global_rect().end.y, "the rows sit under the top bar")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(farming.phone_seen_path))
	_check(saved is Dictionary and saved.get(raw.block_id) == "build", "the seen task is kept on the device")
	# A step finished while the drop-down is up: the row's beat, then the rows move on.
	var next: Dictionary = farming.farm.duplicate(true)
	var at := _free_block(preload("res://modules/dynamic_farm/farm_data.gd").decode(raw))
	var house := HOUSE.duplicate()
	house.x = at.x
	house.y = at.y
	next.buildings = [house]
	next.bag.erase("blueprint_cottage")
	farming._adopt({"ok": true, "farm": next, "farm_version": farming.farm_version + 1})
	await process_frame
	_check(drop.rows[0].state == UiTaskRow.State.DONE, "the finished row turns done in place")
	_check(button.badge == false, "a step finished in view counts as seen")
	await create_timer(UiTaskDropDown.DONE_STAY_S + 0.6).timeout
	_check(drop.showing and drop.rows[1].title == "Till a spot in your yard" and drop.rows[1].state == UiTaskRow.State.CURRENT,
		"a second later the rows show Till as current")
	# More… opens the phone on Tasks.
	drop.more.pressed.emit()
	await create_timer(0.4).timeout
	var phone = farming.phone
	_check(phone != null and phone.selected == Phone.TASKS_TAB and phone.head_title() == "Tasks", "More… opens the phone on Tasks")
	_check(not farming._bar.visible, "the quick bar slides away under the phone")
	_check(not farming._tip.visible, "no tip card over the phone")
	var frame: Rect2 = phone.frame.get_global_rect()
	_check(absf(frame.end.x - (farming._ui.size.x - farming.PHONE_RIGHT)) < 1.0, "the phone sits 14 in from the right")
	_check(frame.position.y >= UiTokens.SIZE_SCREEN_SAFE_INSET - 0.5, "the phone stays on screen")
	_check(phone.tab_count() == 3 and phone.tab(1).get("count") == 0, "three tabs; no inbox count in the dynamic farm")
	var till: UiTaskRow = phone.page.find_child("Task_till", true, false)
	_check(till != null and till.state == UiTaskRow.State.CURRENT and till.tappable, "the phone's current row is Till")
	phone.tab_selected.emit(Phone.INBOX_TAB)
	await create_timer(0.3).timeout
	_check("No parcels" in _texts(phone.page), "Inbox: No parcels")
	phone.tab_selected.emit(Phone.COLLECTION_TAB)
	await create_timer(0.3).timeout
	_check(_texts(phone.page) == ["Nothing collected yet"], "Collection: Nothing collected yet")
	# Back closes the phone first.
	_check(scene.close_modal() and farming.phone == null, "Back closes the phone")
	await create_timer(0.5).timeout
	_check(farming._bar.visible, "the quick bar comes back")
	# The current row in the phone: the phone closes and the step's tip shows again.
	farming._tip_closed = farming.tip_step
	farming._refresh_tip()
	_check(not farming._tip.visible, "the tip was closed by a tap")
	farming.open_phone()
	await create_timer(0.4).timeout
	(farming.phone.page.find_child("Task_till", true, false) as UiTaskRow).pressed.emit()
	await process_frame
	_check(farming.phone == null and farming._tip.visible and farming._tip.tip == preload("res://modules/dynamic_farm/parcel_guide.gd").text("till"),
		"tapping the current task closes the phone and shows its tip")
	# House placement holds the screen: the buttons and phone go.
	farming.held = true
	_check(not button.visible and not farming.phone_button.visible and not drop.showing, "placement hides the task and phone buttons")
	farming.held = false
	await _close()
	# Reopen on a save with the cottage built: Till was seen in the drop-down, so no dot.
	var file := FileAccess.open(dir.path_join(raw.block_id.validate_filename() + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id": raw.block_id, "farm_version": 1, "farm": next}))
	file.close()
	farming = await _open()
	_check(farming._seen() == "till", "reopening reads the seen task")
	_check(Tasks.current(farming.farm, farming.server_now()) == "till" and not farming.task_button.badge,
		"the cottage stands, Till already seen: no dot")
	await _close()

## A 3×3 core block away from the path and the arrival, for the stand-in house (as test_parcel_farming_scene).
func _free_block(data: Dictionary) -> Vector2i:
	var path := preload("res://modules/dynamic_farm/parcel_space.gd").protected_path(data)
	for cell: Dictionary in data.cells:
		var at := Vector2i(cell.x, cell.y)
		var ok := true
		for dy in 3:
			for dx in 3:
				var c := at + Vector2i(dx, dy)
				ok = ok and data.by_cell.has(c) and data.by_cell[c].zone == "core" and not path.has(c)
		if ok and (at - data.spawn).length() > 6: return at
	return Vector2i(-1, -1)

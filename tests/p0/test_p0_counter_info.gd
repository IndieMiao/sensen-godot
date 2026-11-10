extends GdUnitTestSuite
## A counter row's › (不知火舞 on 284): it opened nothing — P0Ui never took the drawer's info_requested. Now it opens the
## item's card over the counter (UiInfoSheet.layered; Back or a tap outside closes it first): the name, the row's use line
## under it, the materials as NeedTile M (Bag Upgrades, shown however far the gate is), the price beside the row's own
## key — Buy, or the grey reason — which does what the row's key does. The row's line 3 reads the first material still
## short (`Reeds 0/10`). The view is the real server view of tests/p0/fixtures/counter_view.json (Homestead Lv1).

const STORE := "user://test_p0_counter_info.json"
const TIPS := "user://test_p0_counter_info_tips.json"

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _view() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(ui)
	ui.set_view(v)
	return ui

func _drawer(ui: P0Ui) -> P0CounterDrawer:
	return ui.find_children("*", "P0CounterDrawer", true, false)[0]

func test_the_chevron_opens_the_items_card_over_the_counter() -> void:
	var ui := _ui(_view())
	await await_idle_frame()
	ui.open_counter("homestead", {"section": "buy"})
	for i in 3: await get_tree().process_frame
	var d := _drawer(ui)
	var row := d.row_of("bag_upgrade_1")
	assert_array(row.spec().facts).is_equal(["+5 bag slots", "Reeds 0/10"])   # the row's line 3: the first one short
	row.info_requested.emit("bag_upgrade_1")   # the title's ›
	await get_tree().process_frame
	var sheets := ui.find_children("*", "UiInfoSheet", true, false).filter(func(s): return (s as UiInfoSheet).is_open())
	assert_int(sheets.size()).is_equal(1)
	var sheet: UiInfoSheet = sheets[0]
	var spec := sheet.spec()
	assert_that([spec.title, spec.rarity_text, spec.facts]).is_equal(["Bag Upgrade I", "+5 bag slots", ["150 coins"]])
	assert_array(spec.buttons.map(func(b): return [str(b.kind), str(b.label)])).is_equal([["unavailable", "Home Lv3 needed"]])
	# the materials, gate or not: NeedTile M with the count
	var tiles := sheet.find_child("Needs", true, false).find_children("*", "UiNeedTile", true, false)
	assert_array(tiles.map(func(t): return [(t as UiNeedTile).item_name, (t as UiNeedTile).size_class])).is_equal(
		[["Reeds", UiNeedTile.Size.M], ["Timber", UiNeedTile.Size.M]])
	# a tile tapped says where it comes from, as on HOME-1 (LOCK-10; 不知火舞 on 284 a5fd65e4)
	(tiles[0] as UiNeedTile).pressed.emit()
	await get_tree().process_frame
	var src := ui.root.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(src).contains([str(P0Logic.need_source(ui.view, "fiber").text)])
	var pop: UiNeedSource = ui.root.find_children("*", "UiNeedSource", true, false)[0]
	var up := InputEventMouseButton.new()   # a tap anywhere lets the line go (as on HOME-1); the card stays
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	(pop.get_parent() as Control).gui_input.emit(up)
	await get_tree().process_frame
	assert_bool(sheet.is_open()).is_true()
	# over the counter, not instead of it: Back closes the card first
	assert_str(ui.modal_kind).is_equal("counter")
	ui.close_top_layer()
	for i in 2: await get_tree().process_frame
	assert_bool(sheet.is_open() if is_instance_valid(sheet) else false).is_false()
	assert_str(ui.modal_kind).is_equal("counter")

## A plain good: no materials group; the card's Buy does what the row's Buy does (the row's count, here 1).
func test_a_seeds_card_has_no_materials_and_its_buy_is_the_rows() -> void:
	var ui := _ui(_view())
	await await_idle_frame()
	ui.open_counter("homestead", {"section": "buy"})
	for i in 3: await get_tree().process_frame
	var d := _drawer(ui)
	var sent: Array = []
	d.action_requested.connect(func(a: StringName, id: String, p: Dictionary): sent.append([a, id, p]))
	var sheet := ui.counter_info(d, "seed_radish")
	await get_tree().process_frame
	assert_object(sheet.find_child("Needs", true, false)).is_null()
	assert_that([sheet.spec().title, sheet.spec().facts]).is_equal(["Radish Seeds", ["4 coins"]])
	assert_array(sheet.spec().buttons.map(func(b): return str(b.label))).is_equal(["Buy"])
	sheet.action_requested.emit(&"buy", "seed_radish", {})
	await get_tree().process_frame
	assert_array(sent).is_equal([[&"buy", "seed_radish", {qty = 1}]])
	assert_bool(sheet.is_open() if is_instance_valid(sheet) else false).is_false()

## q(278) (SGODOT-386): a rod's card says which Fishing levels its top tier needs, its own line under the reach — once
## the rod can be bought, as the row's line 3 (the Buy key says the gate till then).
func test_a_rods_card_says_its_tier_once_it_can_be_bought() -> void:
	var v := _view()
	v.skills.fishing = {"level": 3, "xp": 230, "floor": 220, "next": 480}
	for o in v.shops.tackle.buy + v.tackle.buy: if str(o.id) == "rod_reed": o.unlocked = true
	var ui := _ui(v)
	await await_idle_frame()
	ui.open_counter("tackle")
	for i in 3: await get_tree().process_frame
	var d := _drawer(ui)
	assert_array(d.row_of("rod_reed").spec().facts).is_equal(["Lands up to Rare fish", "Rare needs Fishing Lv4–6"])
	var sheet := ui.counter_info(d, "rod_reed")
	await get_tree().process_frame
	assert_that([sheet.spec().rarity_text, sheet.spec().facts]).is_equal(["Lands up to Rare fish", ["Rare needs Fishing Lv4–6", "80 coins"]])
	ui.close_top_layer()
	ui.close_modal()
	for o in v.shops.tackle.buy + v.tackle.buy: if str(o.id) == "rod_reed": o.unlocked = false
	v.skills.fishing.level = 2
	ui.set_view(v)
	ui.open_counter("tackle")
	for i in 3: await get_tree().process_frame
	assert_that(ui.counter_info(_drawer(ui), "rod_reed").spec().facts).is_equal(["80 coins"])   # Fishing Lv3 needed

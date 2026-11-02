extends GdUnitTestSuite
## SGODOT-368 (不知火舞's spec): S8 with a dish to eat — Today's `Eat it` row opens the bag on Dishes wherever the player
## is; the dish's cells pulse until its card opens, then the card's Eat; the cabinet's row, then its Eat; the cook card's
## Eat. Finding a target never opens a page or selects anything.

const DISH := "dish_grilled_crucian"

func _view(marks: Array) -> Dictionary:
	return {guide = {step = "t_meal", at = 100, recover = "r_eat_bag", marks = marks,
		row = {line = "Eat it: Grilled Crucian", icon = DISH, go = "bag"}},
		bag = {capacity = 25, slots = [{id = DISH + "@good", qty = 1}, {id = "fish_crucian", qty = 1}]},
		energy = {value = 100, max = 200}, names = {DISH: "Grilled Crucian", "fish_crucian": "Pond Crucian"},
		plots = [], residents = {}, cooking = {cabinet = {items = [], cap = 6}}}

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = "user://test_guide_s8_eat_bar_%d.json" % OS.get_process_id()
	ui.tips_path = "user://test_guide_s8_eat_tips_%d.json" % OS.get_process_id()
	add_child(ui)
	ui.set_process(false)
	ui.set_surface("farm")
	ui.space = "home"
	ui.set_view(v)
	await await_idle_frame()
	for file in [ui.quick_store, ui.tips_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return ui

func test_the_eat_row_shows_the_bag_anywhere() -> void:
	for here in ["home", "farm", "map", "pond", "outpost"]:
		assert_str(P0Ui.show_label("bag", here, false, "sh_market_1")).is_equal("Show")

func test_show_opens_the_bag_on_dishes_and_pulses_the_dish_then_its_eat() -> void:
	var ui := await _ui(_view([{item = DISH, pulse = true}, {button = "eat", item = DISH, pulse = true}]))
	ui.open_today()
	await await_idle_frame()
	ui._show_today_row(0)
	await get_tree().create_timer(0.6).timeout   # the drawer settled where it stays
	assert_str(ui.modal_kind).is_equal("bag")
	assert_str(ui._bag.category).is_equal("Dishes")
	assert_str(ui._bag.grid.selected_id).is_empty()   # nothing selected for the player
	ui._refresh_guide_pulses()
	assert_int(int(ui.guide_pulses._counts.get("item:" + DISH + "@good", 0))).is_equal(1)
	assert_bool(ui.guide_pulses._counts.has("eat:" + DISH)).is_false()
	ui._bag.grid.select(DISH + "@good")
	await get_tree().create_timer(0.3).timeout
	ui._refresh_guide_pulses()
	var eat: Control = ui._bag.sheet.button_for(&"eat")
	assert_object(eat).is_not_null()
	assert_int(int(ui.guide_pulses._counts.get("eat:" + DISH, 0))).is_equal(1)

func test_another_dish_card_has_no_eat_pulse() -> void:
	var v := _view([{button = "eat", item = DISH, pulse = true}])
	v.bag.slots.append({id = "dish_veggie_plate", qty = 1})
	var ui := await _ui(v)
	ui.open_bag("", "bag", "Dishes")
	ui._bag.grid.select("dish_veggie_plate")
	await await_idle_frame()
	ui._refresh_guide_pulses()
	assert_bool(ui.guide_pulses._counts.has("eat:" + DISH)).is_false()

func test_the_cabinet_pulses_its_row_then_the_selected_rows_eat() -> void:
	var sheet := P0StorageSheet.new("cabinet", {})
	sheet.set("_rows", {"dish_veggie_plate": Button.new(), DISH + "@plain": Button.new()})
	sheet.selected = "dish_veggie_plate"
	assert_object(sheet.guide_row(DISH)).is_same(sheet._rows[DISH + "@plain"])
	assert_object(sheet.guide_eat(DISH)).is_null()
	sheet.selected = DISH + "@plain"
	sheet._eat = Button.new()
	assert_object(sheet.guide_row(DISH)).is_null()   # selected: its Eat now
	assert_object(sheet.guide_eat(DISH)).is_same(sheet._eat)
	for b in sheet._rows.values(): b.free()
	sheet._eat.free()
	sheet.free()

func test_the_cook_card_eat_pulses_for_that_dish_only() -> void:
	var ui := await _ui(_view([{button = "eat", item = DISH, pulse = true}]))
	var card := UiRewardMoment.new()
	card.primary = "Eat · +25 Energy"
	card.secondary = "Keep"
	card.set_meta(&"dish", DISH + "@good")
	ui._open_modal(card, UiTokens.OPACITY_SCRIM_MODAL, true)
	ui.modal_kind = "kitchen_card"
	await await_idle_frame()
	assert_object(ui._guide_eat_target(DISH)).is_same(card.primary_button())
	ui._refresh_guide_pulses()
	assert_int(int(ui.guide_pulses._counts.get("eat:" + DISH, 0))).is_equal(1)
	card.set_meta(&"dish", "dish_fish_soup@plain")
	assert_object(ui._guide_eat_target(DISH)).is_null()

func test_the_cabinet_object_pulses_its_open_name_strip_at_home() -> void:
	var ui := await _ui(_view([{object = "cabinet", pulse = true}]))
	ui._refresh_guide_pulses()
	assert_bool(ui.guide_pulses._counts.has("object:cabinet")).is_false()
	ui.name_bar("room:use_warming_cabinet", P0Logic.icon("pot"), "Warming Cabinet", "1 dish", Vector2(100, 250), true)
	await get_tree().create_timer(0.25).timeout
	ui._refresh_guide_pulses()
	assert_int(int(ui.guide_pulses._counts.get("object:cabinet", 0))).is_equal(1)

## The cabinet's path through P0Ui (周瑜 on #580): the real sheet opened as the farmhouse opens it — the dish's row pulses
## while another row is selected; selected, its Eat.
func test_the_open_cabinet_sheet_pulses_the_dishs_row_then_its_eat() -> void:
	var v := _view([{item = DISH, pulse = true}, {button = "eat", item = DISH, pulse = true}])
	v.guide.recover = "r_eat_cabinet"
	v.cooking = {cabinet = {have = 2, cap = 6, items = [{id = "dish_veggie_plate", qty = 1, energy = 15, name = "Veggie Plate"},
		{id = DISH + "@good", qty = 1, energy = 20, name = "Grilled Crucian"}]}}
	var ui := await _ui(v)
	var sheet := P0StorageSheet.new("cabinet", ui.view)
	ui._open_modal(sheet, 0.0, true)
	ui.modal_kind = "storage"
	await get_tree().create_timer(0.6).timeout   # the sheet settled where it stays
	assert_str(sheet.selected).is_equal("dish_veggie_plate")   # the first row, as it opens
	ui._refresh_guide_pulses()
	assert_int(int(ui.guide_pulses._counts.get("row:" + DISH, 0))).is_equal(1)
	assert_bool(ui.guide_pulses._counts.has("eat:" + DISH)).is_false()
	(sheet._rows[DISH + "@good"] as Button).pressed.emit()   # a tap on the dish's row
	await get_tree().create_timer(0.3).timeout
	assert_str(sheet.selected).is_equal(DISH + "@good")
	ui._refresh_guide_pulses()
	assert_int(int(ui.guide_pulses._counts.get("eat:" + DISH, 0))).is_equal(1)

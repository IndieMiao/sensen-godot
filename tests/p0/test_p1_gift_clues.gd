extends GdUnitTestSuite
## Gift Clues (Fishing Lv7, q(167); 不知火舞 302 b308ee14; RESIDENT-GIFT 1216:83527): from the server's view.gift_clues
## ({dish: [{resident, verdict}]}, residents met, null before Lv7) and residents[id].gift_points ({dish: delta}, null
## before Lv7) — a coral ♥ on the dish's bag cell, `♥ Liked by Hana · Old Kai` on its card, and in the gift drawer each
## dish's `♥ +3` / `♥ +1` / `−2` over its cell, the rows making room, the key `Gift · +3`. Nothing before Lv7.

const STORE := "user://test_p1_gift_clues.json"
const TIPS := "user://test_p1_gift_clues_tips.json"

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _view(lv7 := true) -> Dictionary:
	var v := {
		"energy": {"value": 142, "max": 200}, "coins": 230,
		"skills": {"fishing": {"level": 7 if lv7 else 6, "xp": 0}},
		"names": {"dish_grilled_crucian": "Grilled Crucian", "dish_fish_soup": "Fresh Fish Soup", "dish_mystery": "Mystery Dish", "dish_radish_salad": "Radish Salad", "dish_carrot_cake": "Carrot Cake",
			"seed_radish": "Radish Seeds"},
		"bag": {"capacity": 25, "slots": [{"id": "dish_grilled_crucian", "qty": 2}, {"id": "dish_fish_soup", "qty": 1},
			{"id": "dish_mystery", "qty": 1}, {"id": "dish_radish_salad", "qty": 1}, {"id": "dish_carrot_cake", "qty": 1},
			{"id": "seed_radish", "qty": 5}]},
		"residents": {"res_pip": {"affinity": 12, "stage": "Acquainted", "gift_today": false, "meal": "none", "request": null,
			"request_state": "none", "gift_points": null}},
		"gift_clues": null,
	}
	if lv7:
		v.gift_clues = {
			"dish_grilled_crucian": [{"resident": "res_old_kai", "verdict": "liked"}, {"resident": "res_ivo", "verdict": "loved"},
				{"resident": "res_pip", "verdict": "liked"}],
			"dish_fish_soup": [{"resident": "res_granny_wu", "verdict": "loved"}],
			"dish_radish_salad": [{"resident": "res_hana", "verdict": "liked"}]}
		v.residents.res_pip.gift_points = {"dish_grilled_crucian": 2, "dish_fish_soup": 1, "dish_mystery": -2, "dish_radish_salad": 1,
			"dish_carrot_cake": 2}
	return v

func test_the_card_line_names_two_and_counts_the_rest() -> void:
	var v := _view()
	assert_str(P0Logic.liked_by_line(v, "dish_grilled_crucian")).is_equal("Liked by Old Kai · Ivo · +1 more")
	assert_str(P0Logic.liked_by_line(v, "dish_fish_soup")).is_equal("Liked by Granny Wu")
	assert_str(P0Logic.liked_by_line(v, "dish_mystery")).is_empty()
	assert_str(P0Logic.liked_by_line(_view(false), "dish_grilled_crucian")).is_empty()   # before Lv7
	assert_str(str(P0ItemInfo.spec(v, "dish_fish_soup", &"bag", {}).liked_by)).is_equal("Liked by Granny Wu")

func test_a_liked_dish_wears_the_heart_on_its_cell() -> void:
	var items := P0BagDrawer.bag_items(_view())
	var liked := {}
	for it in items: liked[str(it.id)] = bool(it.liked)
	# Radish Salad: only Hana likes it, by rarity (`Fine+`) — no ♥ on the cell, her name on the card (不知火舞 on 283)
	assert_dict(liked).is_equal({"dish_grilled_crucian": true, "dish_fish_soup": true, "dish_mystery": false,
		"dish_radish_salad": false, "dish_carrot_cake": false, "seed_radish": false})
	assert_str(P0Logic.liked_by_line(_view(), "dish_radish_salad")).is_equal("Liked by Hana")
	assert_bool(P0BagDrawer.bag_items(_view(false)).any(func(it): return bool(it.liked))).is_false()
	# the cell: a 14 px coral ♥ 4 in from the top-right corner; it stays when selected, never on an empty cell
	var c: UiItemCell = auto_free(UiItemCell.new())
	c.size = Vector2(52, 52)
	add_child(c)
	c.icon = P0Logic.icon("dish_grilled_crucian")
	c.liked = true
	await await_idle_frame()
	var heart := c.find_child("Liked", true, false) as TextureRect
	assert_bool(heart.visible).is_true()
	assert_that(Rect2(heart.get_global_rect().position - c.get_global_rect().position, heart.size)).is_equal(Rect2(34, 4, 14, 14))
	c.state = UiItemCell.State.SELECTED
	assert_bool(heart.visible).is_true()
	c.state = UiItemCell.State.EMPTY
	assert_bool(heart.visible).is_false()

func test_the_card_reads_who_likes_it_under_the_rarity_line() -> void:
	var sheet: UiInfoSheet = auto_free(UiInfoSheet.new())
	sheet.theme = UiKit.theme()
	sheet.size = Vector2(328, 120)
	add_child(sheet)
	var v := _view()
	sheet.rules = func(id: String, ctx: StringName, o: Dictionary) -> Dictionary: return P0ItemInfo.spec(v, id, ctx, o)
	sheet.open("dish_fish_soup", &"bag", {})
	await await_idle_frame()
	var line := sheet.find_child("LikedBy", true, false) as Control
	assert_bool(line.visible).is_true()
	assert_array(line.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)).is_equal(["Liked by Granny Wu"])
	v.gift_clues = null
	sheet.open("dish_fish_soup", &"bag", {})
	await await_idle_frame()
	assert_bool(line.visible).is_false()

## SGODOT-468: under 中文's fonts (Noto SC behind Nunito) the ♥ is drawn by Noto SC, a pixel over Nunito's line: every
## mark keeps the tallest line, so `♥ +2` and `−2` stand the same height on the same baseline, 2 above their cells.
func test_the_gift_marks_stand_level_under_chinese_fonts() -> void:
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	Localization.set_cjk_fonts(true)
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(ui)
	ui.set_view(_view())
	await await_idle_frame()
	ui.open_gift("res_pip")
	await await_idle_frame()
	var d: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false)[0]
	var th := UiKit.theme()
	var line_h := UiKit.line_height(th.get_font(&"font", UiTokens.STYLE_C10_XB), th.get_font_size(&"font_size", UiTokens.STYLE_C10_XB))
	assert_float(line_h).is_greater(15.0)   # the fallback's line, over Nunito's 15
	var marks := {}
	for it in d.grid.shown_items():
		var c := d.grid.cell_for(str(it.id))
		var g := c.find_child("Gain", true, false) as PanelContainer
		marks[(g.get_child(0) as Label).text] = [g.get_global_rect().end.y - c.get_global_rect().position.y, g.size.y]
	assert_dict(marks).is_equal({"♥ +2": [-2.0, line_h + 2.0], "♥ +1": [-2.0, line_h + 2.0], "−2": [-2.0, line_h + 2.0]})
	Localization.set_cjk_fonts(false)
	TranslationServer.set_locale(locale)

## RESIDENT-GIFT: `♥ +2` green on the tint where Pip loves or likes it, any other on white (`♥ +2` / `♥ +1`), `−2` on the grey keys' fill; 17 high, 2 above the cell;
## the rows 31 apart and the first 22 down; the key `Gift · +2`; no ♥ on the cells. Before Lv7: no marks, rows 12 apart, `Gift`.
func test_the_gift_drawer_marks_what_each_dish_adds() -> void:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(ui)
	ui.set_view(_view())
	await await_idle_frame()
	ui.open_gift("res_pip")
	await await_idle_frame()
	var d: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false)[0]
	var gains := {}
	for it in d.grid.shown_items(): gains[str(it.id)] = it.get("gain", null)
	assert_dict(gains).is_equal({"dish_grilled_crucian": 2, "dish_fish_soup": 1, "dish_mystery": -2, "dish_radish_salad": 1,
		"dish_carrot_cake": 2})
	# no ♥ on its cells, only the marks (不知火舞 on 283: the bag's ♥ may be someone else's)
	assert_bool(d.grid.shown_items().any(func(it): return bool(it.get("liked", false)))).is_false()
	assert_bool(d.grid.cells().any(func(c): return (c.find_child("Liked", true, false) as Control).visible)).is_false()
	assert_that([d.grid.row_room, d.grid.top_room]).is_equal([19.0, 22.0])
	# green only where Pip loves or likes the dish (Grilled Crucian), by the hit, not the number: the Carrot Cake's Perfect
	# +2, which Pip does not care for, is white like a +1 (不知火舞 on 283)
	var marks := {}
	for it in d.grid.shown_items():
		var c := d.grid.cell_for(str(it.id))
		var g := c.find_child("Gain", true, false) as PanelContainer
		var label := g.get_child(0) as Label
		var box := g.get_theme_stylebox(&"panel") as UiStyleBox
		marks[str(it.id)] = [label.text, box.bg_color.to_html(false), label.get_theme_color(&"font_color").to_html(false),
			g.get_global_rect().end.y - c.get_global_rect().position.y, g.size.y]
	# text in the action colour is the v3 ink (C-105: lime text would be 1.8:1 on the tint)
	var green := [UiTokens.COLOR_PRIMARY_TINT.to_html(false), UiTokens.COLOR_PRIMARY_INK.to_html(false), -2.0, 17.0]
	var white := [UiTokens.COLOR_SURFACE_RAISED.to_html(false), UiTokens.COLOR_SECONDARY.to_html(false), -2.0, 17.0]
	assert_dict(marks).is_equal({
		"dish_grilled_crucian": ["♥ +2"] + green,
		"dish_carrot_cake": ["♥ +2"] + white,
		"dish_fish_soup": ["♥ +1"] + white,
		"dish_radish_salad": ["♥ +1"] + white,
		"dish_mystery": ["−2", UiTokens.COLOR_DISABLED.to_html(false), UiTokens.COLOR_SECONDARY.to_html(false), -2.0, 17.0]})
	assert_str(P0ItemInfo._gift_label(P0BagDrawer.gift_target(ui.view, {"id": "res_pip"}, "dish_grilled_crucian"))).is_equal("Gift · +2")
	assert_str(P0ItemInfo._gift_label(P0BagDrawer.gift_target(ui.view, {"id": "res_pip"}, "dish_mystery"))).is_equal("Gift · −2")
	# before Lv7
	ui.close_modal()
	ui.set_view(_view(false))
	ui.open_gift("res_pip")
	await await_idle_frame()
	d = ui.find_children("*", "P0BagDrawer", true, false).filter(func(x): return not x.is_queued_for_deletion())[0]
	assert_bool(d.grid.shown_items().any(func(it): return it.has("gain"))).is_false()
	assert_that([d.grid.row_room, d.grid.top_room]).is_equal([0.0, 0.0])
	assert_str(P0ItemInfo._gift_label(P0BagDrawer.gift_target(ui.view, {"id": "res_pip"}, "dish_grilled_crucian"))).is_equal("Gift")

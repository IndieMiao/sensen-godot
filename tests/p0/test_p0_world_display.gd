extends GdUnitTestSuite
## P0 adapters for the SGODOT-222 HUD, Today panel, Energy card / panel and NeedSource.

func _view() -> Dictionary:
	return {
		"energy": {"value": 142, "max": 200, "next_in": 160000, "regen_ms": 240000},
		"coins": 230,
		"skills": {"farming": {"level": 2, "xp": 70, "floor": 50, "next": 100}, "fishing": {"level": 1, "xp": 0, "floor": 0, "next": 40}},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"names": {"crop_radish": "Radish", "seed_radish": "Radish Seeds", "fish_crucian": "Pond Crucian", "dish_grilled_crucian": "Grilled Crucian"},
		"bag": {"capacity": 25, "slots": [{"id": "seed_radish", "qty": 20}]},
		"plots": [{"state": "growing", "crop": "crop_radish", "ready_in": 4320000}],
		"firsts": ["harvest:crop_radish"],
		"rest": {"used": 1, "limit": 1, "resets_in": 3600000},
		"meals": {"used": 100, "cap": 300, "resets_in": 3600000},
	}

func test_hud_state_carries_energy_regen_skills_and_the_today_dots() -> void:
	var v := _view()
	var h := P0Logic.hud_state(v, {"next_cost": 2, "place": {"city": "San Francisco", "space": "Homestead"}})
	assert_int(int(h.energy)).is_equal(142)
	assert_str(str(h.regen)).is_equal("+1 in 2:40")
	assert_int(int(h.next_cost)).is_equal(2)
	assert_float(float(h.skills.farming)).is_equal_approx(0.4, 0.0001)
	assert_int(int(h.coins)).is_equal(230)
	# The Today icon has no words (q(107)): the red dot's keys, none for a crop still growing.
	assert_bool(h.has("today")).is_false()
	assert_array(h.today_dots).is_equal(P0Logic.today_dots(P0Logic.today_rows(v)))
	assert_array(h.today_dots).is_empty()
	assert_str(str(h.place.space)).is_equal("Homestead")
	v.energy = {"value": 200, "max": 200, "next_in": null}
	assert_str(str(P0Logic.hud_state(v).regen)).is_equal("Full")
	v.energy = {"value": 214, "max": 200, "next_in": null}
	assert_str(str(P0Logic.hud_state(v).regen)).is_equal("Bonus +14")
	assert_bool(P0Logic.hud_state(v).has("place")).is_false()   # unchanged unless the caller knows it

func test_place_info_reads_the_scene_place_and_the_farmhouse_override() -> void:
	var p := P0Logic.place_info("San Francisco · Willow Pond")
	assert_str(str(p.city)).is_equal("San Francisco")
	assert_str(str(p.space)).is_equal("Willow Pond")
	assert_int(int(p.kind)).is_equal(UiHud.PlaceKind.HOME)
	assert_str(str(P0Logic.place_info("San Francisco · Homestead", "Farmhouse").space)).is_equal("Farmhouse")

func test_today_rows_keep_the_lines_and_add_icons_and_show_targets() -> void:
	var v := _view()
	var rows := P0Logic.today_rows(v)
	assert_that(rows.map(func(r): return r.line)).is_equal(P0Logic.today_lines(v))
	assert_str(str(rows[0].line)).is_equal("Radishes ready in 1h 12m")
	assert_str(str(rows[0].icon)).is_equal("crop_radish")
	assert_str(str(rows[0].go)).is_equal("plots")
	assert_str(str(rows[1].icon)).is_equal("xp")
	assert_str(str(rows[1].go)).is_equal("")   # no camera target: no Show pill

func test_first_sow_row_is_short_when_energy_cannot_pay_for_it() -> void:
	var v := _view()
	v.plots = []
	v.firsts = []
	v.energy = {"value": 1, "max": 200, "next_in": 161000}
	var row: Dictionary = P0Logic.today_rows(v)[0]
	assert_str(str(row.line)).is_equal("Sow your first plot")
	assert_str(str(row.state)).is_equal("short")
	assert_str(str(row.tail)).is_equal("needs 2 Energy · +1 in 2:41")

func test_energy_card_away_from_home_greys_cook_and_rest_with_at_home() -> void:
	var v := _view()
	v.energy = {"value": 1, "max": 200, "next_in": 161000, "regen_ms": 240000}
	var home := P0Logic.energy_card(v, 2, "Sow ×1")
	assert_int(int(home.have)).is_equal(1)
	assert_str(str(home.regen)).is_equal("+1 in 2:41")
	assert_str(str(home.fact)).is_equal("Sow ×1 needs 2 Energy · you have 1")
	var away := P0Logic.energy_card(v, 2, "Sow ×1", false)
	var by_label := {}
	for t in away.tiles: by_label[t.label] = t
	for label in ["Cook", "Rest"]:
		assert_str(str(by_label[label].fact)).is_equal("At home")
		assert_bool(bool(by_label[label].on)).is_false()
	assert_str(str(by_label["Eat"].guide)).is_equal("Open bag")

func test_energy_panel_lists_today_use_and_the_blessing() -> void:
	var v := _view()
	v["blessing"] = {"left": 4.5 * 86400000.0, "regen_mult": 1.5}
	var p := P0Logic.energy_panel(v)
	assert_int(int(p.max)).is_equal(200)
	assert_that(p.uses.map(func(u): return [u.name, u.have, u.need])).is_equal([["Meals", 100, 300], ["Rest", 1, 1]])
	assert_str(str(p.blessing.title)).is_equal("Newcomer Blessing · 5 days left")
	assert_str(str(p.blessing.detail)).is_equal("Energy returns 1.5× faster · Meals 300 a day")
	v.erase("blessing")
	assert_bool((P0Logic.energy_panel(v).blessing as Dictionary).is_empty()).is_true()

func test_need_source_is_one_line_with_a_camera_only_target() -> void:
	var v := _view()
	assert_that(P0Logic.need_source(v, "seed_radish")).is_equal({"text": "Radish Seeds · Homestead Stall", "go": "stall"})
	assert_that(P0Logic.need_source(v, "crop_radish")).is_equal({"text": "Radish · Grow it on your plots", "go": "plots"})
	assert_that(P0Logic.need_source(v, "fish_crucian")).is_equal({"text": "Pond Crucian · Ponds on the map", "go": ""})
	assert_that(P0Logic.need_source(v, "dish_grilled_crucian")).is_equal({"text": "Grilled Crucian · Cook it at the stove", "go": "stove"})

## PR #11 review: a Show that cannot move the camera (the pond has no p0_show_spot) must not be offered.
func _ui(reachable: bool) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.can_show_spot = func() -> bool: return reachable
	add_child(ui)
	ui.set_view(_view())
	return ui

func _today_actions(ui: P0Ui) -> Array:
	ui.open_today()
	var panel: UiTodayPanel = ui.find_children("*", "UiTodayPanel", true, false)[0]
	return panel.find_children("*", "UiShowPill", true, false).map(func(b): return (b as UiShowPill).label_text())

func test_today_show_only_where_the_camera_can_go() -> void:
	var farm := _ui(true)
	await get_tree().process_frame
	assert_array(_today_actions(farm)).contains(["Show"])
	var pond := _ui(false)
	pond.surface = "pond"
	await get_tree().process_frame
	# homestead targets from the pond: Show on map, never a Show that cannot move the camera (LOCK-08)
	assert_array(_today_actions(pond)).not_contains(["Show"])
	assert_array(_today_actions(pond)).contains(["Show on map"])

func test_show_label_follows_where_the_target_is() -> void:
	assert_str(P0Ui.show_label("plots", "farm", true)).is_equal("Show")
	assert_str(P0Ui.show_label("stall", "farm", false)).is_equal("")          # here, but no camera target
	assert_str(P0Ui.show_label("stove", "pond", false)).is_equal("Show on map")
	assert_str(P0Ui.show_label("pond:pond_san_francisco_03", "farm", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label("tackle", "farm", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label("", "farm", true)).is_equal("")
	assert_str(P0Ui.map_target("plots")).is_equal("home")
	assert_str(P0Ui.map_target("pond:pond_san_francisco_03")).is_equal("pond:pond_san_francisco_03")

func test_show_on_map_reports_the_pin() -> void:
	var pond := _ui(false)
	pond.surface = "pond"
	await get_tree().process_frame
	var got := []
	pond.show_on_map.connect(func(t: String): got.append(t))
	pond.open_today()
	var panel: UiTodayPanel = pond.find_children("*", "UiTodayPanel", true, false)[0]
	panel.show_pressed.emit(0)
	assert_array(got).is_equal(["home"])

# ---------------------------------------------------------------- residents (SGODOT-225 / 228)

func _resident_view() -> Dictionary:
	var v := _view()
	v["residents"] = {"res_pip": {"affinity": 12, "stage": "Acquainted", "next_stage": "Familiar", "next_at": 30,
		"chatted_today": false, "gift_today": false, "meal": "none",
		"request": {"id": "req_res_pip_1", "kind": "fish", "rarity": 1, "qty": 1, "coins": 20, "have": 0, "ready": false},
		"request_state": "open", "need_stage": null, "next_in": null}}
	v.bag.slots.append({"id": "dish_grilled_crucian", "qty": 1})
	return v

func test_open_resident_talks_once_and_shows_the_bar() -> void:
	var ui := _ui(true)
	ui.set_view(_resident_view())
	await get_tree().process_frame
	var sent := []
	ui.command.connect(func(c: Dictionary): sent.append(c))
	assert_bool(ui.open_resident("res_pip")).is_true()
	assert_array(sent).is_equal([{"type": "talk", "resident": "res_pip"}])
	var bar: UiResidentBar = ui.find_children("*", "UiResidentBar", true, false)[0]
	assert_str(str(bar.data.name)).is_equal("Pip")
	assert_str(str(bar.data.line)).is_equal("Could you catch me a fish? Any kind is fine.")   # the open request asks
	assert_str(bar.gift_button().reason).is_equal("")
	ui.open_resident("res_pip")   # a refresh after the reply: no second talk
	assert_int(sent.size()).is_equal(1)
	assert_bool(ui.open_resident("res_nobody")).is_false()

func test_request_card_accepts_and_not_now_returns_to_the_bar() -> void:
	var ui := _ui(true)
	ui.set_view(_resident_view())
	await get_tree().process_frame
	var sent := []
	ui.command.connect(func(c: Dictionary): sent.append(c))
	ui.open_resident("res_pip")
	ui.open_resident_request("res_pip")
	var card: UiRequestCard = ui.find_children("*", "UiRequestCard", true, false)[0]
	assert_str(str(card.data.title)).is_equal("Pip's request")
	assert_str(str(card.data.line)).is_equal("Could you catch me a fish? Any kind is fine.")
	assert_str(str(card.data.reward)).is_equal("+5 Friendship · 20 coins")
	assert_str(str(card.data.needs[0].name)).is_equal("Common fish")
	card.action_pressed.emit()
	assert_that(sent.back()).is_equal({"type": "accept", "request": "req_res_pip_1"})

func test_request_card_uses_the_requests_own_need_line() -> void:
	var v := _view()
	v["residents"] = {"res_old_kai": {"request": {"id": "req_res_kai_1", "kind": "fish", "rarity": 3, "qty": 1, "coins": 50, "have": 0}}}
	var q: Dictionary = P0Logic.content().residents.res_old_kai.requests[0]
	var had: Variant = q.get("need_line", null)
	q["need_line"] = "1 Rare fish · Golden Koi · Pond"   # Li Bai q(46), 苏烈 ac0479c7
	assert_str(str(P0Ui._request_card_data(v, "res_old_kai", {}).needs[0].name)).is_equal("Rare fish · Golden Koi · Pond")
	q.erase("need_line")
	assert_str(str(P0Ui._request_card_data(v, "res_old_kai", {}).needs[0].name)).is_equal("Rare fish")
	if had != null: q["need_line"] = had

func test_gift_drawer_shows_dishes_and_sends_gift() -> void:
	var ui := _ui(true)
	ui.set_view(_resident_view())
	await get_tree().process_frame
	var sent := []
	ui.command.connect(func(c: Dictionary): sent.append(c))
	ui.open_gift("res_pip")
	var d: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false)[0]
	assert_str(d.category).is_equal("Dishes")
	assert_bool(d.header.tabs().visible).is_false()   # Bag side only, no Gear (WP1b)
	assert_that(d.grid.shown_items().map(func(it): return it.id)).is_equal(["dish_grilled_crucian"])
	d.action_requested.emit(&"gift", "dish_grilled_crucian", {})
	assert_that(sent.back()).is_equal({"type": "gift", "resident": "res_pip", "item": "dish_grilled_crucian"})

## The bag's dish card (225): Gift to <Name> opens that resident's gift drawer with the dish selected; with no resident
## within reach the grey button only says where (a Toast), and the bag stays open.
func test_bag_dish_gift_goes_to_the_resident_within_reach() -> void:
	var ui := _ui(true)
	ui.set_view(_resident_view())
	var near := [""]
	ui.near_resident = func() -> String: return near[0]
	await get_tree().process_frame
	ui.open_bag("dish_grilled_crucian")
	var bag: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false)[0]
	assert_bool(bag.sheet.spec().buttons.any(func(b): return str(b.label) == "Gift to a resident")).is_true()
	bag.unavailable_requested.emit(&"gift", "dish_grilled_crucian", "Gift to a resident")
	assert_str(ui.toast_text()).is_equal("Find a resident at an outpost to gift this dish")
	assert_str(ui.modal_kind).is_equal("bag")
	ui._toasts.dismiss()
	bag.unavailable_requested.emit(&"gift", "fish_crucian", "Gift · Mutual friends only")   # fish: no resident Toast
	assert_str(ui.toast_text()).is_equal("")
	ui.close_modal()
	await get_tree().process_frame
	near[0] = "res_pip"
	ui.open_bag("dish_grilled_crucian")
	bag = ui.find_children("*", "P0BagDrawer", true, false).filter(func(d): return not d.is_queued_for_deletion())[0]
	assert_bool(bag.sheet.spec().buttons.any(func(b): return str(b.label) == "Gift to Pip")).is_true()
	bag.action_requested.emit(&"gift", "dish_grilled_crucian", {})
	await get_tree().process_frame
	assert_str(ui.modal_kind).is_equal("gift")
	var gift: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false).filter(func(d): return not d.is_queued_for_deletion())[0]
	assert_str(str(gift.gift_to.id)).is_equal("res_pip")
	assert_str(gift.grid.selected_id).is_equal("dish_grilled_crucian")

## 亚瑟 on #37: the homestead is one space (farm or farmhouse) for Show; an outpost room is not home for the bag.
func test_show_and_the_bag_go_by_the_space_not_the_surface() -> void:
	assert_str(P0Ui.show_label("plots", "home", true)).is_equal("Show")        # in the farmhouse: steps out, then Show
	assert_str(P0Ui.show_label("stove", "home", true)).is_equal("Show")
	assert_str(P0Ui.show_label("plots", "outpost", true)).is_equal("Show on map")
	var ui := _ui(true)
	ui.set_surface("room")
	ui.space = "outpost"
	assert_str(ui.space_here()).is_equal("outpost")
	ui.open_bag()
	var bag: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false)[0]
	assert_str(bag.place).is_equal("outpost")
	var sent := []
	ui.command.connect(func(c: Dictionary): sent.append(c))
	ui._bag_action(&"store", "crop_radish", {})
	ui._bag_action(&"take_out", "crop_radish", {})
	assert_array(sent).is_empty()   # Farm Storage only at home
	ui.space = "home"
	ui._bag_action(&"store", "crop_radish", {})
	assert_str(str(sent.back().type)).is_equal("store")

## Today's meal on the bar (亚瑟 on #37): only while the meal is there; it opens the bag on it or the Inbox.
func test_todays_meal_opens_where_the_meal_is() -> void:
	var v := _resident_view()
	v.residents.res_pip["meal"] = "given"
	assert_bool(P0Logic.resident_bar(v, "res_pip").meal).is_false()   # given, then eaten: no button
	v.bag.slots.append({"id": "dish_carrot_cake", "qty": 1, "gifted": true, "from": "res_pip"})
	assert_dict(P0Logic.gift_meal(v, "res_pip")).is_equal({"at": "bag", "item": "dish_carrot_cake"})
	assert_bool(P0Logic.resident_bar(v, "res_pip").meal).is_true()
	var ui := _ui(true)
	ui.set_view(v)
	ui._open_todays_meal("res_pip")
	await get_tree().process_frame
	assert_str(ui.modal_kind).is_equal("bag")
	var bag: P0BagDrawer = ui.find_children("*", "P0BagDrawer", true, false).filter(func(d): return not d.is_queued_for_deletion())[0]
	assert_str(bag.grid.selected_id).is_equal("dish_carrot_cake")
	v.bag.slots.pop_back()
	v["inbox"] = {"parcels": [{"key": "gift_meal:res_pip:2026-10-08:0", "id": "dish_carrot_cake", "qty": 1, "left": 3600000}]}
	assert_dict(P0Logic.gift_meal(v, "res_pip")).is_equal({"at": "inbox", "item": "dish_carrot_cake"})
	ui.set_view(v)
	ui._open_todays_meal("res_pip")
	assert_str(ui.modal_kind).is_equal("inbox")

## Back and a scrim tap on a layer opened from the resident bar return to the bar, as its own Close does.
func test_back_from_a_layer_over_the_resident_bar_returns_to_the_bar() -> void:
	var ui := _ui(true)
	ui.set_view(_resident_view())
	await get_tree().process_frame
	for open in [func(): ui.open_gift("res_pip"), func(): ui.open_resident_profile("res_pip"), func(): ui.open_resident_request("res_pip")]:
		open.call()
		assert_bool(ui.close_top_layer()).is_true()
		assert_str(ui.modal_kind).is_equal("resident")
	ui.open_bag()
	ui.close_top_layer()
	assert_str(ui.modal_kind).is_equal("")   # the bag from the HUD just closes

func test_rest_tile_at_full_energy_says_so_and_is_off() -> void:
	var v := _view()
	v.energy.value = int(v.energy.get("max", 200))
	v["rest"] = {"used": 0, "limit": 1, "resets_in": 3600000, "amount": 60, "away_ready_in": 0}
	var rest: Dictionary = P0Logic.energy_card(v, 2, "Sow").tiles.filter(func(t): return t.label == "Rest")[0]
	assert_that([rest.fact, rest.on]).is_equal(["Energy full", false])

func test_energy_card_tea_and_rest_read_the_drinks_and_away_facts() -> void:
	var v := _view()
	v.energy = {"value": 1, "max": 200, "next_in": 161000, "regen_ms": 240000}
	v["drinks"] = {"used": 1, "limit": 3, "left": 2, "price": 50, "need": null, "full": false, "resets_in": 3600000}
	v.rest = {"used": 0, "limit": 1, "resets_in": 3600000, "away_h": 2, "away_ready_in": 4320000}
	var tiles := {}
	for t in P0Logic.energy_card(v, 2, "Sow ×1").tiles: tiles[t.label] = t
	assert_str(str(tiles["Tea"].fact)).is_equal("1/3 today · 50 coins")
	assert_bool(bool(tiles["Tea"].on)).is_true()
	assert_str(str(tiles["Tea"].go)).is_equal("outpost:tea")
	assert_str(str(tiles["Rest"].fact)).is_equal("Ready in 1h 12m")
	assert_bool(bool(tiles["Rest"].on)).is_false()
	v.drinks.need = 245   # drinksView: price + the 40-coin floor; with 230 coins that is 15 short
	v.rest.away_ready_in = null
	tiles = {}
	for t in P0Logic.energy_card(v, 2, "Sow ×1").tiles: tiles[t.label] = t
	assert_str(str(tiles["Tea"].fact)).is_equal("Need 15 more coins")
	assert_bool(bool(tiles["Tea"].on)).is_false()
	assert_str(str(tiles["Rest"].fact)).is_equal("After 2h away")
	v.rest.away_ready_in = 0
	tiles = {}
	for t in P0Logic.energy_card(v, 2, "Sow ×1").tiles: tiles[t.label] = t
	assert_str(str(tiles["Rest"].fact)).is_equal("Available")
	assert_bool(bool(tiles["Rest"].on)).is_true()

# ---------------------------------------------------------------- 225 registry additions (209 c 8cd572de)

func test_rest_tile_guides_to_the_bench_and_says_the_real_gain_near_full() -> void:
	var v := _view()
	v.rest = {"used": 0, "limit": 1, "resets_in": 3600000, "amount": 60, "away_h": 2, "away_ready_in": 0}
	v.energy.value = 180
	var rest: Dictionary = P0Logic.energy_card(v, 30, "Cast").tiles.filter(func(t): return t.label == "Rest")[0]
	assert_that([rest.guide, rest.go, rest.fact]).is_equal(["Show bench", "bench", "+20 Energy"])
	assert_str(P0Ui.show_label("bench", "farm", true)).is_equal("Show")
	assert_str(P0Ui.show_label("bench", "pond", true)).is_equal("Show on map")

func test_resident_profile_sheet_from_the_name_on_the_bar() -> void:
	var ui := _ui(true)
	ui.set_view(_resident_view())
	await get_tree().process_frame
	var d := P0Ui.resident_profile_data(_resident_view(), "res_pip")
	assert_that([d.name, d.role, d.stage, d.friendship, d.likes, d.details]).is_equal(["Pip", "Courier Kid", "Acquainted", "12/30", "Dessert", false])
	assert_object(d.face).is_not_null()
	# 不知火舞 on 235 B1: the dialogue bar's portrait, its face square (hat top to chin), not a vector placeholder.
	assert_str((d.face as AtlasTexture).atlas.resource_path).is_equal("res://assets/p0/art/pip-portrait.jpg")
	assert_that((d.face as AtlasTexture).region).is_equal(P0Ui.FACE_CROPS.pip)
	var kai := P0Ui.resident_face("kai") as AtlasTexture
	assert_that([kai.atlas.resource_path, kai.region]).is_equal(["res://assets/p0/art/kai-portrait.jpg", P0Ui.FACE_CROPS.kai])
	assert_object(d.likes_icon).is_not_null()
	ui.open_resident("res_pip")
	(ui.find_children("*", "UiResidentBar", true, false)[0] as UiResidentBar).identity_pressed.emit()
	await get_tree().process_frame   # the bar's modal frees on the next frame
	assert_str(ui.modal_kind).is_equal("resident_profile")
	assert_int(ui.find_children("*", "UiResidentProfile", true, false).size()).is_equal(1)
	assert_int(ui.find_children("*", "UiCloseButton", true, false).size()).is_equal(1)
	(ui.find_children("*", "UiResidentProfile", true, false)[0] as UiResidentProfile).back_pressed.emit()
	assert_str(ui.modal_kind).is_equal("resident")   # Back returns to the bar

func test_affinity_on_the_open_bar_floats_a_pill_and_puts_the_answer_in_the_bubble() -> void:
	assert_str(P0Ui.affinity_text({"delta": 2, "reason": "chat"})).is_equal("+2 · first chat today")
	assert_str(P0Ui.affinity_text({"delta": -2, "reason": "gift", "verdict": "not_a_fan"})).is_equal("−2 · not a fan")
	var ui := _ui(true)
	ui.set_view(_resident_view())
	await get_tree().process_frame
	assert_bool(ui.resident_affinity({"resident": "res_pip", "delta": 2, "reason": "chat"})).is_false()   # bar not open
	ui.open_resident("res_pip")
	await get_tree().process_frame
	assert_bool(ui.resident_affinity({"resident": "res_pip", "delta": -2, "reason": "gift", "verdict": "not_a_fan"},
		"Um… thanks? I'll save it for later.")).is_true()
	var pills := ui.find_children("*", "UiFloatText", true, false)
	assert_int(pills.size()).is_equal(1)
	assert_str((pills[0] as UiFloatText).text).is_equal("−2 · not a fan")
	ui.open_resident("res_pip")   # the runtime's refresh after the reply
	await get_tree().process_frame
	assert_str(str((ui.find_children("*", "UiResidentBar", true, false)[0] as UiResidentBar).data.line)).is_equal("Um… thanks? I'll save it for later.")
	assert_int(ui.find_children("*", "UiCloseButton", true, false).size()).is_equal(1)

func test_energy_card_tea_tile_reads_the_drinks_without_a_placeholder() -> void:
	var v := _view()
	var tea: Dictionary = P0Logic.energy_card(v, 2, "Sow ×1").tiles[2]
	assert_that([tea.label, tea.fact, tea.guide, tea.on]).is_equal(["Tea", "", "", false])   # no server drinks: no line
	# the server's drinksView: need = price + the 40-coin floor (coinsNeeded), not the gap
	# N/3 is cups drunk today, then the next cup's price (李白: 0/3 · 40, 1/3 · 50, 2/3 · 60, 3/3)
	v["drinks"] = {"used": 0, "limit": 3, "left": 3, "price": 40, "need": 80, "energy": 25, "gain": 25, "full": false, "resets_in": 3600000}
	tea = P0Logic.energy_card(v, 2, "Sow ×1").tiles[2]   # 230 coins ≥ 80
	assert_that([tea.fact, tea.guide, tea.go, tea.on]).is_equal(["0/3 today · 40 coins", "Show on map", "outpost:tea", true])
	v.coins = 50
	tea = P0Logic.energy_card(v, 2, "Sow ×1").tiles[2]
	assert_that([tea.fact, tea.on]).is_equal(["Need 30 more coins", false])
	v.coins = 230
	v.drinks.left = 0
	v.drinks.used = 3
	assert_str(str(P0Logic.energy_card(v, 2, "Sow ×1").tiles[2].fact)).is_equal("3/3 today")
	var ui := _ui(true)
	var got := []
	ui.show_on_map.connect(func(t: String): got.append(t))
	ui.open_energy_card(2, "Sow ×1")
	(ui.find_children("*", "UiEnergyCard", true, false)[0] as UiEnergyCard).tile_pressed.emit("outpost:tea")
	assert_array(got).is_equal(["outpost:tea"])   # Show on map: the map opens on the Tea House pin

# ---------------------------------------------------------------- bell and Inbox (SGODOT-232 parcels, LOCK-14)

func test_bell_reads_the_inbox_badge_and_lists_parcels_read_only() -> void:
	var v := _view()
	assert_int(int(P0Logic.hud_state(v).unread)).is_equal(0)
	v["inbox"] = {"badge": 2, "waiting": 1, "parcels": [
		{"key": "a", "id": "crop_radish", "qty": 3, "left": 79200000.0},
		{"key": "b", "id": "seed_radish", "qty": 5, "left": 1500000.0}]}
	assert_int(int(P0Logic.hud_state(v).unread)).is_equal(2)   # the two parcels the sheet lists; queued rewards stay off
	assert_that(P0Logic.parcel_lines(v)).is_equal(["Radish Seeds ×5 · 25m left", "Radish ×3 · 22h left"])
	var ui := _ui(true)
	ui.set_view(v)
	ui.open_inbox()   # SGODOT-234: the Inbox drawer, on Parcels, one InboxRow per parcel (soonest first)
	await get_tree().process_frame
	assert_that(ui.inbox().rows.map(func(r): return [r.title.text, r.left_label.text])).is_equal(
		[["Radish Seeds ×5", "25m left"], ["Radish ×3", "22h left"]])
	ui.close_modal()
	v.inbox.parcels = []
	v.inbox.waiting = 0
	ui.set_view(v)
	ui.open_inbox("parcels")
	await get_tree().process_frame
	assert_int(ui.find_children("*", "UiEmptyState", true, false).size()).is_equal(1)

func test_rest_tile_follows_the_away_rule() -> void:
	var v := _view()
	v.rest = {"used": 0, "limit": 1, "resets_in": 3600000, "away_h": 2, "away_ready_in": null}
	var rest: Dictionary = P0Logic.energy_card(v, 2, "Sow ×1").tiles[3]
	assert_that([rest.fact, rest.on]).is_equal(["After 2h away", false])
	v.rest.away_ready_in = 4320000
	assert_str(str(P0Logic.energy_card(v, 2, "Sow ×1").tiles[3].fact)).is_equal("Ready in 1h 12m")
	v.rest.away_ready_in = 0
	# near full (142/200, Rest gives 60) it says the real gain, like the bench card (225)
	assert_that([P0Logic.energy_card(v, 2, "Sow ×1").tiles[3].fact, P0Logic.energy_card(v, 2, "Sow ×1").tiles[3].on]).is_equal(["+58 Energy", true])
	v.rest.used = 1
	assert_str(str(P0Logic.energy_card(v, 2, "Sow ×1").tiles[3].fact)).is_equal("Rested today")

func test_an_expired_parcel_rings_the_bell_and_opens_updates() -> void:
	# The server keeps an unread expiry record (badge 1) once a parcel runs out. SGODOT-234 shows records (q(79)): the
	# bell reads the server's badge and the Inbox opens on Updates with the record (replaces #11's interim option B).
	var v := _view()
	v["inbox"] = {"badge": 1, "waiting": 0, "parcels": [], "updates": [{"key": "a", "id": "crop_radish", "qty": 3, "status": "expired", "coins": 0, "read": false}]}
	assert_int(int(P0Logic.hud_state(v).unread)).is_equal(1)
	var ui := _ui(true)
	ui.set_view(v)
	ui.open_inbox()
	await get_tree().process_frame
	assert_str(ui.inbox().tab).is_equal("updates")
	assert_that(ui.inbox().rows.map(func(r): return r.title.text)).is_equal(["Parcel expired · Radish ×3 lost"])

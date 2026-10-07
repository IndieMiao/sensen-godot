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

func test_hud_state_carries_energy_regen_skills_and_today() -> void:
	var v := _view()
	var h := P0Logic.hud_state(v, {"next_cost": 2, "place": {"city": "Shanghai", "space": "Homestead"}})
	assert_int(int(h.energy)).is_equal(142)
	assert_str(str(h.regen)).is_equal("+1 in 2:40")
	assert_int(int(h.next_cost)).is_equal(2)
	assert_float(float(h.skills.farming)).is_equal_approx(0.4, 0.0001)
	assert_int(int(h.coins)).is_equal(230)
	assert_str(str(h.today)).is_equal(str(P0Logic.today_lines(v)[0]))
	assert_str(str(h.place.space)).is_equal("Homestead")
	v.energy = {"value": 200, "max": 200, "next_in": null}
	assert_str(str(P0Logic.hud_state(v).regen)).is_equal("Full")
	v.energy = {"value": 214, "max": 200, "next_in": null}
	assert_str(str(P0Logic.hud_state(v).regen)).is_equal("Bonus +14")
	assert_bool(P0Logic.hud_state(v).has("place")).is_false()   # unchanged unless the caller knows it

func test_place_info_reads_the_scene_place_and_the_farmhouse_override() -> void:
	var p := P0Logic.place_info("Shanghai · Willow Pond")
	assert_str(str(p.city)).is_equal("Shanghai")
	assert_str(str(p.space)).is_equal("Willow Pond")
	assert_int(int(p.kind)).is_equal(UiHud.PlaceKind.HOME)
	assert_str(str(P0Logic.place_info("Shanghai · Homestead", "Farmhouse").space)).is_equal("Farmhouse")

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
	return panel.find_children("*", "UiCommandButton", true, false).map(func(b): return (b as Button).text)

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
	assert_str(P0Ui.show_label("pond:pond_shanghai_03", "farm", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label("tackle", "farm", true)).is_equal("Show on map")
	assert_str(P0Ui.show_label("", "farm", true)).is_equal("")
	assert_str(P0Ui.map_target("plots")).is_equal("home")
	assert_str(P0Ui.map_target("pond:pond_shanghai_03")).is_equal("pond:pond_shanghai_03")

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

func test_bell_reads_the_inbox_badge() -> void:
	var v := _view()
	assert_int(int(P0Logic.hud_state(v).unread)).is_equal(0)
	v["inbox"] = {"badge": 3, "waiting": 2, "parcels": []}   # SGODOT-232: queued rewards are not on the bell
	assert_int(int(P0Logic.hud_state(v).unread)).is_equal(3)
	assert_int(int(P0Logic.hud_state(v, {"unread": 0}).unread)).is_equal(0)

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
	v.drinks.need = 15
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

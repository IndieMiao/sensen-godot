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

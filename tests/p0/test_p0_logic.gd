extends GdUnitTestSuite

func _view() -> Dictionary:
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}, {"id": "crop_carrot", "seed": "seed_carrot", "energy": 3}],
		"names": {"crop_radish": "Radish", "seed_radish": "Radish Seeds", "crop_carrot": "Carrot"},
		"bag": {"capacity": 25, "slots": [{"id": "seed_radish", "qty": 20}, {"id": "seed_lettuce", "qty": 10}, {"id": "crop_radish", "qty": 3}]},
		"plots": [], "rest": {"used": 0, "limit": 1, "resets_in": 3600000},
	}

func test_durations_are_countdowns() -> void:
	assert_str(P0Logic.duration(161000)).is_equal("2:41")
	assert_str(P0Logic.duration(4320000)).is_equal("1h 12m")
	assert_str(P0Logic.duration(0)).is_equal("0:00")

func test_main_action_follows_the_plot_in_front() -> void:
	var v := _view()
	assert_str(str(P0Logic.main_action(v, {"id": 3, "state": "wild"}, "").verb)).is_equal("Till")
	var sow := P0Logic.main_action(v, {"id": 3, "state": "tilled"}, "seed_radish")
	assert_str(str(sow.verb)).is_equal("Sow ×1")
	assert_str(str(sow.sub)).is_equal("2 Energy")
	assert_that(sow.cmd).is_equal({"type": "sow", "plot": 3, "seed": "seed_radish"})
	assert_str(str(P0Logic.main_action(v, {"id": 3, "state": "tilled"}, "").sub)).is_equal("Pick a seed")
	# A pinned seed at 0 stays on the bar; the key says so instead of sending a sow the server turns down.
	var out := P0Logic.main_action(v, {"id": 3, "state": "tilled"}, "seed_carrot")
	assert_bool(bool(out.enabled)).is_false()
	assert_str(str(out.sub)).is_equal("Pick a seed")   # 李白 q(44) ③: a 0 seed reads as no seed
	assert_that(out.cmd).is_equal({})
	assert_str(str(P0Logic.main_action(v, {"id": 3, "state": "sown"}, "").verb)).is_equal("Water")
	assert_str(str(P0Logic.main_action(v, {"id": 3, "state": "ready"}, "").verb)).is_equal("Harvest")
	var growing := P0Logic.main_action(v, {"id": 3, "state": "growing", "ready_in": 4320000}, "seed_radish")
	assert_bool(bool(growing.enabled)).is_false()
	assert_str(str(growing.sub)).is_equal("Ready in 1h 12m")

func test_short_energy_turns_amber_and_opens_the_card() -> void:
	var v := _view()
	v.energy = {"value": 2, "max": 200, "next_in": 161000, "regen_ms": 240000}
	v.bag.slots.append({"id": "seed_carrot", "qty": 4})
	var a := P0Logic.main_action(v, {"id": 1, "state": "tilled"}, "seed_carrot")
	assert_bool(bool(a.amber)).is_true()
	assert_str(str(a.sub)).is_equal("Need 3 Energy")
	assert_that(a.cmd).is_equal({"type": "energy_card"})
	var card := P0Logic.energy_card(v, 3, "Sow ×1")
	assert_str(str(card.title)).is_equal("Energy 2/200 · +1 in 2:41")
	assert_str(str(card.subtitle)).is_equal("Sow ×1 needs 3 Energy · you have 2")
	assert_str(str(card.wait)).is_equal("Wait · Full in 13h 10m")
	assert_str(str(card.tiles[0].fact)).is_equal("No dishes in bag")
	v.energy.value = 0
	assert_str(str(P0Logic.energy_card(v, 3, "Sow ×1").subtitle)).is_equal("Recover or do something free")

func test_quick_bar_keeps_order_then_fills_by_count() -> void:
	var v := _view()
	assert_that(P0Logic.quick_bar(v, [])).is_equal(["seed_radish", "seed_lettuce"])
	assert_that(P0Logic.quick_bar(v, ["seed_lettuce"])).is_equal(["seed_lettuce", "seed_radish"])

func test_quick_bar_keeps_pinned_slots_at_zero_and_skips_removed_ones() -> void:
	var v := _view()
	# A pinned seed the bag no longer holds stays in its place at 0 (LOCK-05, §10.3.3 归零).
	assert_that(P0Logic.quick_bar(v, ["seed_carrot", "seed_radish"], "farm", ["seed_carrot"])).is_equal(["seed_carrot", "seed_radish", "seed_lettuce"])
	# A seed dragged off the bar is not refilled until it is pinned again (§10.3.4).
	assert_that(P0Logic.quick_bar(v, [], "farm", [], ["seed_radish"])).is_equal(["seed_lettuce"])
	assert_that(P0Logic.quick_bar(v, [], "farm", ["seed_radish"], ["seed_radish"])).is_equal(["seed_radish", "seed_lettuce"])

func test_today_line_names_the_nearest_crop() -> void:
	var v := _view()
	assert_str(P0Logic.today_line(v)).is_equal("Sow your first plot")
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 4320000}, {"state": "growing", "crop": "crop_carrot", "ready_in": 9000000}]
	assert_str(P0Logic.today_line(v)).is_equal("Radishes ready in 1h 12m")
	v.bag.slots.append({"id": "fish_crucian", "qty": 2})
	assert_str(P0Logic.today_line(v)).is_equal("2 fish · the stove is free")
	v["cooking"] = {"stove": {"dish": "dish_grilled_crucian", "ready_in": 3000}}
	v.names["dish_grilled_crucian"] = "Grilled Crucian"
	assert_str(P0Logic.today_line(v)).is_equal("Grilled Crucian · 0:03 left at the stove")
	v.cooking.stove.ready_in = 0
	assert_str(P0Logic.today_line(v)).is_equal("Grilled Crucian ready at the stove")
	v.plots.append({"state": "ready", "crop": "crop_carrot"})
	assert_str(P0Logic.today_line(v)).is_equal("Carrots ready to harvest")
	v["stall"] = {"board": {"requests": [{"title": "Pond Catch", "item": "fish_crucian", "qty": 2, "have": 1, "status": "accepted"}]}}
	v.names["fish_crucian"] = "Pond Crucian"
	assert_str(P0Logic.today_line(v)).is_equal("Pond Catch · Pond Crucian 1/2")
	v.stall.board.requests[0].have = 2
	assert_str(P0Logic.today_line(v)).is_equal("Pond Catch · Deliver at the Stall")

func test_projection_ticks_energy_and_ripens_crops() -> void:
	var v := _view()
	v.energy = {"value": 198, "max": 200, "next_in": 1000, "regen_ms": 240000}
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 500}]
	var p := P0Logic.project(v, 241000 + 1000)
	assert_int(int(p.energy.value)).is_equal(200)
	assert_that(p.energy.next_in).is_null()
	assert_str(str(p.plots[0].state)).is_equal("ready")

func test_today_panel_orders_now_then_countdown_then_skill() -> void:
	var v := _view()
	v["stall"] = {"board": {"requests": [{"title": "Pond Catch", "item": "fish_crucian", "qty": 2, "have": 0, "status": "open"}]}}
	v.names["fish_crucian"] = "Pond Crucian"
	assert_that(P0Logic.today_lines(v)).is_equal(["Sow your first plot", "Pond Catch · 2 Pond Crucian · Stall Board"])
	v.stall.board.requests.clear()
	v["skills"] = {"farming": {"level": 1, "xp": 20, "next": 50}, "fishing": {"level": 1, "xp": 60, "next": 70}}
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 4320000}, {"state": "sown", "crop": "crop_carrot"}]
	assert_that(P0Logic.today_lines(v)).is_equal(["Water 1 sown plot · Free", "Radishes ready in 1h 12m", "Fishing Lv2 in 10 XP"])

func test_parcel_countdowns_run_between_responses() -> void:
	var v := _view()
	v["inbox"] = {"badge": 1, "parcels": [{"key": "level:fishing:2:0", "id": "bait_worm", "qty": 3, "left": 60000}]}
	var later := P0Logic.project(v, 45000)
	assert_float(float(later.inbox.parcels[0].left)).is_equal(15000.0)
	assert_float(float(P0Logic.project(v, 90000).inbox.parcels[0].left)).is_equal(0.0)
	assert_float(float(v.inbox.parcels[0].left)).is_equal(60000.0)

func test_one_inbox_float_per_reply_and_none_for_gift_meals() -> void:
	var v := _view()
	v["names"]["bait_worm"] = "Worm Bait"
	var worm := {"kind": "parcel", "id": "bait_worm", "qty": 3, "waiting": false, "expires_in": 86400000}
	var herb := {"kind": "parcel", "id": "wild_herb", "qty": 3, "waiting": false, "expires_in": 86400000}
	var meal := {"kind": "parcel", "id": "dish_carrot_cake", "qty": 1, "waiting": false, "expires_in": 3600000, "gift": true}
	assert_str(P0Logic.parcel_toast(v, [worm])).is_equal("Bag full · Worm Bait ×3 sent to Inbox · 24h")
	assert_str(P0Logic.parcel_toast(v, [{"kind": "level"}, worm, herb])).is_equal("Bag full · 2 rewards sent to Inbox · 24h")
	assert_str(P0Logic.parcel_toast(v, [meal])).is_equal("")
	var queued := worm.duplicate()
	queued["waiting"] = true
	queued.erase("expires_in")
	assert_str(P0Logic.parcel_toast(v, [queued])).is_equal("Inbox full · Worm Bait ×3 saved for later")

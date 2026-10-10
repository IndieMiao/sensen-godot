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

## A duration inside a sentence (q(97) ②) says `42m` under an hour, never `42:00`: whole minutes rounded up, at least
## `1m`, `2h` on the hour, `9h 12m` otherwise — the Inbox's `42m left` without ` left`.
func test_sentence_durations_say_minutes_under_an_hour() -> void:
	assert_str(P0Logic.span(2520000)).is_equal("42m")
	assert_str(P0Logic.span(2519001)).is_equal("42m")
	assert_str(P0Logic.span(161000)).is_equal("3m")
	assert_str(P0Logic.span(30000)).is_equal("1m")
	assert_str(P0Logic.span(0)).is_equal("1m")
	assert_str(P0Logic.span(3570000)).is_equal("1h")   # rounded up first, then sorted: never `60m`
	assert_str(P0Logic.span(7200000)).is_equal("2h")
	assert_str(P0Logic.span(7200001)).is_equal("2h 1m")
	assert_str(P0Logic.span(4320000)).is_equal("1h 12m")
	assert_str(P0Logic.span(33120000)).is_equal("9h 12m")
	assert_str(P0Inbox.left_text(2520000)).is_equal("42m left")   # the Inbox writes the same, plus ` left`

## The sentences around the farm switch; the timers that tick in front of the player keep m:ss.
func test_sentences_say_minutes_and_ticking_timers_keep_seconds() -> void:
	var v := _view()
	v.energy = {"value": 190, "max": 200, "next_in": 161000, "regen_ms": 240000}
	var card := P0Logic.energy_card(v, 2, "Sow ×1")
	assert_str(str(card.title)).is_equal("Energy 190/200 · +1 in 2:41")
	assert_str(str(card.regen)).is_equal("+1 in 2:41")
	assert_str(str(card.wait)).is_equal("Wait · Full in 39m")   # 2:41 + 9 × 4:00
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 2520000}]
	assert_str(P0Logic.today_line(v)).is_equal("Radishes ready in 42m")
	assert_str(str(P0Logic.main_action(v, v.plots[0], "").sub)).is_equal("Ready in 42m")
	v["cooking"] = {"stove": {"dish": "dish_grilled_crucian", "ready_in": 42000}}
	v.names["dish_grilled_crucian"] = "Grilled Crucian"
	assert_str(P0Logic.today_line(v)).is_equal("Grilled Crucian · 0:42 left at the stove")
	v["meals"] = {"cap": 200, "used": 200, "resets_in": 2520000}
	v.energy.value = 100
	v["items"] = {"dish_grilled_crucian": {"meal": 30}}
	assert_str(str(P0Logic.eat_button(v, "dish_grilled_crucian").text)).is_equal("Full belly · Meals reset in 42m")

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
	assert_str(str(growing.sub)).is_equal("1h 12m")   # two units drop `Ready in` (≤ 80 px, 不知火舞 on 241)

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
	assert_str(str(card.wait)).is_equal("Wait · Full in 13h 11m")   # 790.7 min, rounded up (q(97))
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
	assert_that(P0Logic.today_lines(v)).is_equal(["Sow your first plot"])   # untaken: on its board, not in Today (q(104))
	v.stall.board.requests.clear()
	v["skills"] = {"farming": {"level": 1, "xp": 20, "next": 50}, "fishing": {"level": 1, "xp": 60, "next": 70}}
	v.plots = [{"state": "growing", "crop": "crop_radish", "ready_in": 4320000}, {"state": "sown", "crop": "crop_carrot"}]
	assert_that(P0Logic.today_lines(v)).is_equal(["Water 1 sown plot", "Radishes ready in 1h 12m", "Fishing Lv2 · 10 XP to go"])   # q(69)

func test_parcel_countdowns_run_between_responses() -> void:
	var v := _view()
	v["inbox"] = {"badge": 1, "parcels": [{"key": "level:fishing:2:0", "id": "bait_worm", "qty": 3, "left": 60000}]}
	var later := P0Logic.project(v, 45000)
	assert_float(float(later.inbox.parcels[0].left)).is_equal(15000.0)
	assert_float(float(P0Logic.project(v, 90000).inbox.parcels[0].left)).is_equal(0.0)
	assert_float(float(v.inbox.parcels[0].left)).is_equal(60000.0)

## q(87): one InboxNotice per reply, speaking of the first parcel; the others are `+N more`; gift meals are the
## resident bar's.
func test_one_inbox_notice_per_reply_and_none_for_gift_meals() -> void:
	var v := _view()
	v["names"]["bait_worm"] = "Worm Bait"
	var worm := {"kind": "parcel", "id": "bait_worm", "qty": 3, "waiting": false, "expires_in": 86400000}
	var herb := {"kind": "parcel", "id": "wild_herb", "qty": 3, "waiting": false, "expires_in": 86400000}
	var meal := {"kind": "parcel", "id": "dish_carrot_cake", "qty": 1, "waiting": false, "expires_in": 3600000, "gift": true}
	assert_dict(P0Logic.parcel_notice(v, [worm])).is_equal({title = "Sent to Inbox", item = "Worm Bait", quantity = "×3", line = "Expires in 24h"})
	assert_dict(P0Logic.parcel_notice(v, [{"kind": "level"}, worm, herb, meal])).is_equal(
		{title = "Sent to Inbox", item = "Worm Bait", quantity = "×3", line = "+1 more · Expires in 24h"})
	assert_dict(P0Logic.parcel_notice(v, [meal])).is_empty()
	# A full Inbox: the parcel waits for a place, its 24 h not started (§10.4.8); the card speaks of the first parcel.
	var queued := worm.duplicate()
	queued["waiting"] = true
	queued.erase("expires_in")
	assert_dict(P0Logic.parcel_notice(v, [queued])).is_equal({title = "Inbox full · waiting", item = "Worm Bait", quantity = "×3", line = "Claim a parcel first"})
	assert_dict(P0Logic.parcel_notice(v, [queued, herb, herb.duplicate()])).is_equal(
		{title = "Inbox full · waiting", item = "Worm Bait", quantity = "×3", line = "+2 more · Claim a parcel first"})
	assert_str(str(P0Logic.parcel_notice(v, [herb, queued]).title)).is_equal("Sent to Inbox")

## q(88): a resident's gift meal into a full bag says who sent it and its countdown to 04:00, as the Parcels row does.
func test_a_gift_meal_sent_to_the_inbox_says_who_and_when_it_goes_back() -> void:
	var v := _view()
	v["names"]["dish_grilled_crucian"] = "Grilled Crucian"
	var meal := {"kind": "gift_meal", "resident": "res_pip", "dish": "dish_grilled_crucian", "given": true, "to": "parcel"}
	var parcel := {"kind": "parcel", "id": "dish_grilled_crucian", "qty": 1, "waiting": false, "expires_in": 33120000, "gift": true}
	var pip := str(P0Logic.content().get("residents", {}).get("res_pip", {}).get("name", ""))
	assert_str(pip).is_not_empty()
	assert_dict(P0Logic.gift_meal_notice(v, meal, [parcel])).is_equal({title = "Sent to Inbox", item = "Grilled Crucian",
		quantity = "×1", line = "From %s · Expires in 9h 12m" % pip})
	parcel.expires_in = 59 * 60000
	assert_str(str(P0Logic.gift_meal_notice(v, meal, [parcel]).line)).is_equal("From %s · Expires in 59m" % pip)
	var queued := parcel.duplicate()
	queued.waiting = true
	queued.erase("expires_in")
	assert_dict(P0Logic.gift_meal_notice(v, meal, [queued])).is_equal({title = "Inbox full · waiting", item = "Grilled Crucian",
		quantity = "×1", line = "From %s · Claim a parcel first" % pip})
	# 刘邦 on #118: no parcel in the reply — the Inbox's own row gives the time; with neither, no time rather than `1m`.
	v["inbox"] = {"parcels": [{"key": "gift_meal:res_pip:d", "id": "dish_grilled_crucian", "qty": 1, "left": 3600000, "gift": {"from": "res_pip"}}]}
	assert_str(str(P0Logic.gift_meal_notice(v, meal, []).line)).is_equal("From %s · Expires in 1h" % pip)
	v["inbox"] = {"parcels": []}
	assert_str(str(P0Logic.gift_meal_notice(v, meal, []).line)).is_equal("From %s" % pip)
	var bagged := meal.duplicate()
	bagged.erase("to")
	assert_dict(P0Logic.gift_meal_notice(v, bagged, [])).is_empty()   # into the bag: the resident bar says it
	assert_dict(P0Logic.parcel_notice(v, [parcel])).is_empty()   # and the reward card leaves it out

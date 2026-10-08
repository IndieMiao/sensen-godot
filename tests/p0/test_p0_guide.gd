extends GdUnitTestSuite
## First-session guide rules (SGODOT-232 U6; plan §14.2–14.5, §3.7.4, q(44), q(46), q(49)) over hand-built views.

const Guide := preload("res://modules/p0/p0_guide.gd")

func _view(over: Dictionary = {}) -> Dictionary:
	var v := {
		"energy": {"value": 160, "max": 200, "next_in": 100000, "regen_ms": 160000},
		"skills": {"farming": {"level": 1, "xp": 0, "next": 50}, "fishing": {"level": 1, "xp": 0, "next": 70}, "cooking": {"level": 1, "xp": 0, "next": 30}},
		"names": {"fish_crucian": "Pond Crucian", "crop_radish": "Radish", "crop_lettuce": "Lettuce", "seed_lettuce": "Lettuce Seeds"},
		"items": {"fish_crucian": {"kind": "fish", "sell": 2, "cook": true}, "fish_koi": {"kind": "fish", "sell": 13, "cook": false},
			"crop_radish": {"kind": "crop", "sell": 5, "cook": true}},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}, {"id": "crop_lettuce", "seed": "seed_lettuce", "energy": 2}],
		"plots": [], "firsts": [], "bag": {"slots": []},
		"stall": {"board": {"requests": [{"id": "req_pond_catch", "title": "Pond Catch", "item": "fish_crucian", "qty": 2, "status": "open", "have": 0}]}},
		"cooking": {"slots": 2, "stove": null, "first_fire": true, "cookbook": [
			{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "slots": 1, "known": true, "cooked": false, "can_cook": false},
			{"id": "dish_herb_grilled_fish", "name": "Herb Grilled Fish", "slots": 2, "known": false, "cooked": false, "can_cook": false},
			{"id": "dish_fisher_stew", "name": "Fisher's Stew", "slots": 3, "known": false, "cooked": false, "can_cook": false}]},
		"mine": {"run": null},
	}
	v.merge(over, true)
	return v

func _plots(states: Array) -> Array:
	var out: Array = []
	for i in states.size():
		var st: String = states[i]
		var p := {"id": i, "state": st}
		if st in ["sown", "growing", "ready"]: p.merge({"crop": "crop_radish", "xp_pct": 100, "ready_in": 14000000})
		out.append(p)
	return out

func _lines(rows: Array) -> Array:
	return rows.map(func(r): return "%s%s" % [r.line, " ✓" if r.state == "done" else ""])

# ---------------------------------------------------------------- TipCards

func test_eight_tips_with_toast_timing() -> void:
	assert_int(Guide.TIPS.size()).is_equal(8)
	assert_str(Guide.TIPS.heat).is_equal("Tap when the needle hits gold!")
	assert_float(Guide.tip_seconds("Casting uses 5 Energy")).is_equal(2.5)        # 21 characters
	assert_float(Guide.tip_seconds(Guide.TIPS.sow)).is_equal(3.5)               # 67 characters
	assert_float(Guide.tip_seconds("x".repeat(400))).is_equal(5.0)

func test_tips_come_from_first_surfaces_and_events() -> void:
	assert_str(Guide.tip_for_surface("farm")).is_equal("sow")
	assert_str(Guide.tip_for_surface("pond")).is_equal("creel")
	assert_str(Guide.tip_for_surface("stove")).is_equal("cook")
	assert_str(Guide.tip_for_surface("outpost")).is_equal("")
	var first_fire := {"cooking": {"first_fire": true}}
	var later := {"cooking": {"first_fire": false}}
	assert_str(Guide.tip_for_event({"kind": "pot"}, first_fire, later)).is_equal("heat")
	assert_str(Guide.tip_for_event({"kind": "pot"}, later, later)).is_equal("")
	assert_str(Guide.tip_for_event({"kind": "meal", "gain": 25}, {}, {})).is_equal("meal")
	assert_str(Guide.tip_for_event({"kind": "meal", "gain": 0}, {}, {})).is_equal("")
	assert_str(Guide.tip_for_event({"kind": "energy", "delta": -5}, {}, {"energy": {"value": 0}})).is_equal("meal")
	assert_str(Guide.tip_for_event({"kind": "energy", "delta": -5}, {}, {"energy": {"value": 40}})).is_equal("")
	assert_str(Guide.tip_for_event({"kind": "level"}, {}, {})).is_equal("level")

## q(49): while a RewardMoment / MomentBanner is up, a new tip waits; the one already showing stays.
func test_tip_queue_waits_for_moments_and_shows_each_tip_once() -> void:
	var q = Guide.TipQueue.new({"sow": true})
	assert_bool(q.request("sow")).is_false()                 # shown before
	q.moment_opened()                                       # the first catch: Caught! is up
	assert_bool(q.request("creel")).is_true()
	assert_str(q.next()).is_equal("")                         # waits for the card
	q.moment_closed()
	assert_str(q.next()).is_equal("creel")
	assert_bool(q.request("creel")).is_false()
	q.moment_opened()                                       # a Moment over a tip already showing: the tip stays
	assert_str(q.showing).is_equal("creel")
	q.request("cast")
	q.moment_closed()
	assert_str(q.next()).is_equal("")                         # one at a time
	q.close()
	assert_str(q.next()).is_equal("cast")
	assert_bool(q.did("sow")).is_false()
	assert_bool(q.did("cast")).is_true()                      # doing what it teaches closes it
	assert_that(q.seen.keys()).contains_exactly_in_any_order(["sow", "creel", "cast"])

# ---------------------------------------------------------------- Today rows (§14.2)

func test_first_session_rows_follow_the_director_table() -> void:
	var v := _view({"plots": _plots(["growing"])})
	assert_that(_lines(Guide.lead_rows(v))).is_equal(["Catch 2 Pond Crucian · Reed Pond", "Cook it: Grilled Crucian"])
	assert_str(Guide.lead_rows(v)[0].go).is_equal("pond:pond_shanghai_05")   # Show on map (q(31)); the stall's "!" takes it
	v.stall.board.requests[0].status = "accepted"
	assert_str(Guide.lead_rows(v)[0].go).is_equal("pond:pond_shanghai_05")   # Show on map at Reed Pond
	# q(58): two in the creel → Deliver at the stall, not ticked, and it has the focus
	v.stall.board.requests[0].have = 2
	var rows := Guide.lead_rows(v)
	assert_that(_lines(rows)).is_equal(["Deliver 2 Pond Crucian · Stall", "Cook it: Grilled Crucian"])
	assert_str(rows[0].go).is_equal("stall")
	assert_that(rows.map(func(r): return r.focus)).is_equal([true, false])
	assert_str(Guide.stall_badge(v)).is_equal("deliver")
	# a fish eaten: back to Catch (the request's state, not an event)
	v.stall.board.requests[0].have = 1
	assert_str(Guide.lead_rows(v)[0].line).is_equal("Catch 2 Pond Crucian · Reed Pond")
	# handed in (Request complete · +14 coins): Deliver ticks, Cook it takes the focus; no lettuce row yet
	v.stall.board.requests = []
	v.req_done = ["req_pond_catch"]
	v.cooking.cookbook[0].can_cook = true
	v.bag.slots = [{"id": "fish_crucian", "qty": 1}, {"id": "seed_lettuce", "qty": 10}]
	rows = Guide.lead_rows(v)
	assert_that(_lines(rows)).is_equal(["Deliver 2 Pond Crucian · Stall ✓", "Cook it: Grilled Crucian"])
	assert_that(rows.map(func(r): return r.focus)).is_equal([false, true])
	# cooked and eaten: the first session is over — Sow 10 Lettuce · 20 Energy (the 10 wild beds till for free)
	v.cooking.cookbook[0].cooked = true
	v.plots = _plots(["growing", "growing", "wild", "wild", "wild", "wild", "wild", "wild", "wild", "wild", "wild", "wild"])
	assert_that(_lines(Guide.lead_rows(v))).is_equal(["Sow 10 Lettuce · 20 Energy"])

func test_cooking_before_handing_in_is_not_blocked() -> void:
	var v := _view({"plots": _plots(["growing"])})
	v.stall.board.requests[0].status = "accepted"
	v.stall.board.requests[0].have = 2
	v.cooking.cookbook[0].cooked = true
	var rows := Guide.lead_rows(v)
	assert_that(_lines(rows)).is_equal(["Deliver 2 Pond Crucian · Stall", "Cook it: Grilled Crucian ✓"])
	assert_that(rows.map(func(r): return r.focus)).is_equal([true, false])

func test_crop_plurals() -> void:
	var v := {"names": {"crop_lettuce": "Lettuce", "crop_chili": "Chili", "crop_radish": "Radish", "crop_potato": "Potato", "crop_corn": "Corn"}}
	assert_str(Guide.crop_count_name(v, "crop_lettuce", 10)).is_equal("Lettuce")
	assert_str(Guide.crop_count_name(v, "crop_corn", 4)).is_equal("Corn")
	assert_str(Guide.crop_count_name(v, "crop_chili", 5)).is_equal("Chilies")
	assert_str(Guide.crop_count_name(v, "crop_radish", 20)).is_equal("Radishes")
	assert_str(Guide.crop_count_name(v, "crop_potato", 2)).is_equal("Potatoes")
	assert_str(Guide.crop_count_name(v, "crop_radish", 1)).is_equal("Radish")

func test_short_of_energy_the_sow_row_says_when() -> void:
	var v := _view({"stall": {"board": {"requests": []}}, "plots": _plots(["growing", "tilled", "tilled"]),
		"bag": {"slots": [{"id": "seed_lettuce", "qty": 10}]}, "energy": {"value": 1, "max": 200, "next_in": 60000, "regen_ms": 160000}})
	v.cooking.cookbook[0].cooked = true
	var row: Dictionary = Guide.lead_rows(v)[0]
	assert_str(row.line).is_equal("Sow 2 Lettuce · 4 Energy")
	assert_str(row.state).is_equal("short")
	assert_str(row.tail).is_equal("needs 4 Energy · +3 in 7m")   # 60 s + 2 × 160 s = 380 s

func test_new_recipe_and_third_slot_rows() -> void:
	var v := _view({"stall": {"board": {"requests": []}}})
	v.cooking.cookbook[0].cooked = true
	v.cooking.cookbook[1].known = true
	v.cooking.cookbook[1].can_cook = true
	assert_that(_lines(Guide.lead_rows(v))).is_equal(["Cook: Herb Grilled Fish · new recipe"])
	v.cooking.slots = 3   # Cooking Lv4 (q(46))
	assert_that(_lines(Guide.lead_rows(v))).is_equal(["3rd slot open · try Fine fish + Potato + Rock Salt", "Cook: Herb Grilled Fish · new recipe"])
	v.cooking.cookbook[2].cooked = true
	assert_that(_lines(Guide.lead_rows(v))).is_equal(["Cook: Herb Grilled Fish · new recipe"])

func test_harvest_tail_says_when_the_first_harvest_levels_farming() -> void:
	var v := _view()
	v.plots = _plots(["growing", "growing"])   # 2 radishes: 2 × 2 + first 10 = 14 < 50
	assert_str(Guide.harvest_level_tail(v)).is_equal("")
	var twenty: Array = []
	for i in 20: twenty.append("growing")
	v.plots = _plots(twenty)                    # 20 radishes: 40 + 10 = 50 → Farming Lv 2 (§14.2.2)
	assert_str(Guide.harvest_level_tail(v)).is_equal(" · Farming Lv 2 at first harvest")

# ---------------------------------------------------------------- badges and Free to do now

func test_farmhouse_door_badge_needs_a_cookable_fish_and_a_cook_row() -> void:
	var v := _view()
	assert_bool(Guide.door_badge(v)).is_false()                         # no fish
	v.bag.slots = [{"id": "fish_koi", "qty": 1}]
	assert_bool(Guide.door_badge(v)).is_false()                         # Golden Koi is not for cooking
	v.bag.slots = [{"id": "fish_crucian", "qty": 1}]
	assert_bool(Guide.door_badge(v)).is_true()                          # Cook it: Grilled Crucian is open
	v.cooking.cookbook[0].cooked = true
	assert_bool(Guide.door_badge(v)).is_false()                         # ticked

func test_stall_badge_comes_from_the_board() -> void:
	var v := _view()
	assert_str(Guide.stall_badge(v)).is_equal("request")
	v.stall.board.requests[0].status = "accepted"
	assert_str(Guide.stall_badge(v)).is_equal("")
	v.stall.board.requests[0].have = 2
	assert_str(Guide.stall_badge(v)).is_equal("deliver")

func test_free_to_do_now_lists_free_things_in_order_with_the_map_as_fallback() -> void:
	var v := _view({"stall": {"board": {"requests": []}}})
	assert_that(_lines(Guide.free_now(v))).is_equal(["Browse the map"])
	v.plots = _plots(["ready", "ready", "growing"])
	v.cooking.cookbook[0].can_cook = true
	v.bag.slots = [{"id": "fish_crucian", "qty": 4}, {"id": "crop_radish", "qty": 12}]
	assert_that(_lines(Guide.free_now(v))).is_equal(["Harvest 2 ready", "Cook · 4 fish in creel", "Sell 12 at Homestead Stall"])
	v.cooking.stove = {"dish": "dish_grilled_crucian", "ready_in": 3000}   # the stove is busy
	v.mine.run = {"id": 1}
	assert_that(_lines(Guide.free_now(v))).is_equal(["Harvest 2 ready", "Sell 12 at Homestead Stall", "Mine run · Continue · Free"])

func test_new_bag_items_flash_once() -> void:
	var before := {"bag": {"slots": [{"id": "seed_radish", "qty": 19}]}}
	var after := {"bag": {"slots": [{"id": "seed_radish", "qty": 19}, {"id": "bait_worm", "qty": 3}, {"id": "wild_herb", "qty": 3}]}}
	assert_that(Guide.new_items(before, after)).is_equal(["bait_worm", "wild_herb"])
	assert_that(Guide.new_items(after, after)).is_empty()

# ---------------------------------------------------------------- Today integration (P0Logic.today_rows)

func test_today_rows_lead_with_the_guide_and_drop_their_generic_twins() -> void:
	var v := _view({"plots": _plots(["growing"])})
	v.stall.board.requests[0].status = "accepted"
	v.bag.slots = [{"id": "fish_crucian", "qty": 1}]
	var rows := P0Logic.today_rows(v)
	# Catch (not "Pond Catch · Pond Crucian 0/2"), Cook it (not "1 fish · the stove is free"), then the radishes' timer
	assert_that(_lines(rows)).is_equal(["Catch 2 Pond Crucian · Reed Pond", "Cook it: Grilled Crucian", "Radishes ready in 3h 53m"])
	assert_that(rows.map(func(r): return r.focus)).is_equal([true, false, false])

func test_today_rows_before_the_first_sow_put_sowing_first() -> void:
	var v := _view()
	assert_that(_lines(P0Logic.today_rows(v))).is_equal(["Sow your first plot", "Catch 2 Pond Crucian · Reed Pond", "Cook it: Grilled Crucian"])

func test_after_the_first_session_the_crop_timer_says_what_the_harvest_does() -> void:
	var twenty: Array = []
	for i in 20: twenty.append("growing")
	var v := _view({"plots": _plots(twenty), "req_done": ["req_pond_catch"]})
	v.stall.board.requests = []
	v.cooking.cookbook[0].cooked = true
	assert_str(str(P0Logic.today_rows(v)[0].line)).is_equal("Radishes ready in 3h 53m · Farming Lv 2 at first harvest")

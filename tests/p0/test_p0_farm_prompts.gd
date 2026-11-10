extends GdUnitTestSuite
## The farm's world prompts (SGODOT-250; LOCK-07 v2, q(62), WORLD-HINT-1…5): what each facility's icon button and
## name strip say, and which of the two shows. No "Tap to …" anywhere.

func _view() -> Dictionary:
	return {"energy": {"value": 120, "max": 200}, "rest": {"used": 0, "limit": 1, "amount": 60, "away_ready_in": 0},
		"stall": {"board": {"requests": []}}, "bag": {"slots": []}, "homestead": {"level": 1}}

func test_the_open_one_strips_the_rest_show_buttons_within_8_m_or_with_a_state() -> void:
	var plain := P0WorldPrompts.workbench()
	assert_int(P0WorldPrompts.show("workbench", "workbench", 2.0, plain)).is_equal(P0WorldPrompts.Show.BAR)
	assert_int(P0WorldPrompts.show("workbench", "stall", 7.9, plain)).is_equal(P0WorldPrompts.Show.ICON)
	assert_int(P0WorldPrompts.show("workbench", "", 8.1, plain)).is_equal(P0WorldPrompts.Show.NONE)
	var plaque := P0WorldPrompts.plaque({})
	assert_int(P0WorldPrompts.show("plaque", "", 1.0, plaque)).is_equal(P0WorldPrompts.Show.NONE)   # no mark, ever
	assert_int(P0WorldPrompts.show("plaque", "plaque", 1.0, plaque)).is_equal(P0WorldPrompts.Show.BAR)
	assert_str(plaque.text).is_equal("Home Badge")   # q(287) ③, q(306) ⑦

func test_the_stall_is_homestead_stall_with_its_board_state() -> void:
	var v := _view()
	var p := P0WorldPrompts.stall(v)
	assert_str(p.text).is_equal("Home Stall")
	assert_object(p.icon).is_same(P0Logic.icon("homestead_stall"))
	assert_int(p.status).is_equal(-1)
	v.stall.board.requests = [{"id": "r1", "qty": 2, "have": 0, "status": "open"}]
	assert_int(P0WorldPrompts.stall(v).status).is_equal(UiStatusBadge.State.REQUEST)
	v.stall.board.requests[0].have = 2
	assert_int(P0WorldPrompts.stall(v).status).is_equal(UiStatusBadge.State.DELIVERABLE)

func test_the_stall_shows_no_state_while_the_guide_is_on() -> void:   # q(215) ④ ⑥
	var v := _view()
	v.stall.board.requests = [{"id": "r1", "qty": 2, "have": 0, "status": "open"}]
	v["guide"] = {"step": "sow_two", "phase": "B", "recover": null, "at": 0, "progress": null}
	var p := P0WorldPrompts.stall(v)
	assert_int(p.status).is_equal(-1)
	assert_int(P0WorldPrompts.show("stall", "", 30.0, p)).is_equal(P0WorldPrompts.Show.NONE)   # no ! from across the farm
	assert_int(P0WorldPrompts.stall(v, true).status).is_equal(-1)                              # nor New (q(215) ⑥)
	v.stall.board.requests[0].have = 2
	assert_int(P0WorldPrompts.stall(v).status).is_equal(-1)                                    # nor a ✓
	v.guide = {"step": null, "end": "done"}
	assert_int(P0WorldPrompts.stall(v).status).is_equal(UiStatusBadge.State.DELIVERABLE)
	v.stall.board.requests[0].have = 0
	assert_int(P0WorldPrompts.stall(v).status).is_equal(UiStatusBadge.State.REQUEST)
	v.stall.board.requests = []
	assert_int(P0WorldPrompts.stall(v, true).status).is_equal(UiStatusBadge.State.NEW)

func test_the_farmhouse_is_its_name_and_carries_the_guides_request() -> void:
	var p := P0WorldPrompts.farmhouse(_view())
	assert_str(p.text).is_equal("Farmhouse")
	assert_str(p.fact).is_empty()
	assert_int(p.status).is_equal(-1)
	# A-03 (蒙恬, 232): a cookable fish in the bag and Today's Cook row still open → the house's mark is the ! (one mark
	# per facility; P0Guide.door_badge is its only source).
	var v := _view()
	v.merge({"items": {"fish_crucian": {"kind": "fish", "sell": 2, "cook": true}}, "skills": {"cooking": {"level": 1}},
		"cooking": {"slots": 2, "stove": null, "first_fire": true, "cookbook": [
			{"id": "dish_grilled_crucian", "name": "Grilled Crucian", "slots": 1, "known": true, "cooked": false, "can_cook": false}]}}, true)
	assert_int(P0WorldPrompts.farmhouse(v).status).is_equal(-1)   # no fish yet
	v.bag.slots = [{"id": "fish_crucian", "qty": 1}]
	assert_int(P0WorldPrompts.farmhouse(v).status).is_equal(UiStatusBadge.State.REQUEST)
	assert_int(P0WorldPrompts.show("home", "", 30.0, P0WorldPrompts.farmhouse(v))).is_equal(P0WorldPrompts.Show.ICON)

func test_the_bench_reads_what_resting_gives_and_dims_when_it_cannot() -> void:
	var v := _view()
	var p := P0WorldPrompts.bench(v)
	assert_array([p.text, p.fact, p.status, p.dimmed]).is_equal(["+60 Energy", "", -1, false])
	assert_object(p.icon).is_same(P0Logic.icon("rest"))
	v.energy.value = 175   # REST-NEARFULL: what it really gives
	assert_array([P0WorldPrompts.bench(v).text, P0WorldPrompts.bench(v).dimmed]).is_equal(["+25 Energy", false])
	v.energy.value = 200
	p = P0WorldPrompts.bench(v)
	assert_array([p.text, p.fact, p.dimmed]).is_equal(["+60 Energy", "Energy full", true])
	v.energy.value = 120
	v.rest.used = 1
	p = P0WorldPrompts.bench(v)
	assert_array([p.text, p.status, p.dimmed]).is_equal(["Rested today", UiStatusBadge.State.USED_TODAY, true])
	v.rest.used = 0
	# q(269) (SGODOT-377): no away countdown — a server before it that still sends one, or null ("never left"), is the
	# plain usable bench: no clock, no fact, not dimmed
	for away in [4320000, null]:
		v.rest.away_ready_in = away
		p = P0WorldPrompts.bench(v)
		assert_array([p.text, p.fact, p.status, p.dimmed]).is_equal(["+60 Energy", "", -1, false])

func test_no_prompt_says_tap() -> void:   # the farm's gathering spots left with v4q(4) ①
	var v := _view()
	for p in [P0WorldPrompts.workbench(), P0WorldPrompts.stall(v), P0WorldPrompts.bench(v)]:
		assert_bool(str(p.text).contains("Tap")).is_false()

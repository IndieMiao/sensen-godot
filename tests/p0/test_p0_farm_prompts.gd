extends GdUnitTestSuite
## The farm's world prompts (SGODOT-250; LOCK-07 v2, q(62), WORLD-HINT-1…5): what each facility's icon button and
## name strip say, and which of the two shows. No "Tap to …" anywhere.

func _view() -> Dictionary:
	return {"energy": {"value": 120, "max": 200}, "rest": {"used": 0, "limit": 1, "amount": 60, "away_ready_in": 0},
		"stall": {"board": {"requests": []}}, "bag": {"slots": []}, "homestead": {"level": 1},
		"gather": {"spots": [
			{"id": "spot_grove", "name": "Timber Grove", "open": true, "ready": true},
			{"id": "spot_reed_bank", "name": "Reed Bank", "open": true, "ready": false, "ready_in": 7800000},
			{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2}]}}

func _spot(v: Dictionary, id: String) -> Dictionary:
	for m in P0MaterialLogic.gather_marks(v):
		if str(m.id) == id: return P0WorldPrompts.spot(v, m)
	return {}

func test_the_open_one_strips_the_rest_show_buttons_within_8_m_or_with_a_state() -> void:
	var plain := P0WorldPrompts.workbench()
	assert_int(P0WorldPrompts.show("workbench", "workbench", 2.0, plain)).is_equal(P0WorldPrompts.Show.BAR)
	assert_int(P0WorldPrompts.show("workbench", "stall", 7.9, plain)).is_equal(P0WorldPrompts.Show.ICON)
	assert_int(P0WorldPrompts.show("workbench", "", 8.1, plain)).is_equal(P0WorldPrompts.Show.NONE)
	var ready := _spot(_view(), "spot_grove")
	assert_int(P0WorldPrompts.show("spot_grove", "", 25.0, ready)).is_equal(P0WorldPrompts.Show.ICON)   # LOCK-11 from afar
	var plaque := P0WorldPrompts.plaque({})
	assert_int(P0WorldPrompts.show("plaque", "", 1.0, plaque)).is_equal(P0WorldPrompts.Show.NONE)   # no mark, ever
	assert_int(P0WorldPrompts.show("plaque", "plaque", 1.0, plaque)).is_equal(P0WorldPrompts.Show.BAR)
	assert_str(plaque.text).is_equal("Upgrade Plaque")

func test_the_stall_is_homestead_stall_with_its_board_state() -> void:
	var v := _view()
	var p := P0WorldPrompts.stall(v)
	assert_str(p.text).is_equal("Homestead Stall")
	assert_object(p.icon).is_same(P0Logic.icon("homestead_stall"))
	assert_int(p.status).is_equal(-1)
	v.stall.board.requests = [{"id": "r1", "qty": 2, "have": 0, "status": "open"}]
	assert_int(P0WorldPrompts.stall(v).status).is_equal(UiStatusBadge.State.REQUEST)
	v.stall.board.requests[0].have = 2
	assert_int(P0WorldPrompts.stall(v).status).is_equal(UiStatusBadge.State.DELIVERABLE)

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
	v.rest.away_ready_in = 4320000
	p = P0WorldPrompts.bench(v)
	assert_array([p.text, p.fact, p.status, p.dimmed]).is_equal(["+60 Energy", "in 1h 12m", UiStatusBadge.State.COUNTDOWN, true])   # q(70)
	v.rest.away_ready_in = null   # never been away yet
	assert_array([P0WorldPrompts.bench(v).fact, P0WorldPrompts.bench(v).dimmed]).is_equal(["after 2h away", true])   # no countdown

func test_a_spot_names_itself_with_at_most_one_fact() -> void:
	var v := _view()
	var grove := _spot(v, "spot_grove")
	assert_array([grove.text, grove.fact, grove.status]).is_equal(["Timber Grove", "", UiStatusBadge.State.READY])
	assert_object(grove.icon).is_same(P0Logic.icon("wood"))
	var reeds := _spot(v, "spot_reed_bank")
	assert_array([reeds.text, reeds.fact, reeds.status]).is_equal(["Reed Bank", "Ready in 2h 10m", -1])
	var clay := _spot(v, "spot_clay_bank")
	assert_array([clay.text, clay.fact, clay.status]).is_equal(["Clay Bank", "Homestead Lv2", UiStatusBadge.State.LOCKED])
	for p in [grove, reeds, clay, P0WorldPrompts.workbench(), P0WorldPrompts.stall(v), P0WorldPrompts.bench(v)]:
		assert_bool(str(p.text).contains("Tap")).is_false()

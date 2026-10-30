extends GdUnitTestSuite
## SGODOT-260 Q3: the runtime's view projection copies only what ages and shares the rest with the server view; the
## session keeps one projection per view and millisecond and holds its view read-only (editor and tests).

## Every timer project() advances, and parts it never touches.
func _view() -> Dictionary:
	var pot := {"id": 1, "ms": 5000, "elapsed": 1000, "ready_in": 4000}
	return {
		"seq": 7, "coins": 120,
		"energy": {"value": 198, "max": 200, "next_in": 1000, "regen_ms": 240000},
		"plots": [{"id": 0, "state": "growing", "crop": "crop_radish", "ready_in": 500}, {"id": 1, "state": "growing", "crop": "crop_carrot", "ready_in": 90000},
			{"id": 2, "state": "tilled", "crop": null}],
		"guide": {"step": "t_sow", "row": {"text": "Radishes ready", "countdown": "Radishes ready in {t}", "ready_in": 60000}},
		"cooking": {"stove": pot, "stoves": [pot, {"id": 2, "ms": 15000, "elapsed": 0, "ready_in": 15000}, null], "batch": {"max": 2}},
		"fishing": {"cast": {"bite_in": 3000, "place": "pond_san_francisco_01"}, "trap": {"traps": [{"place": "p", "next_in": 7200000}, {"place": "q", "next_in": null}]},
			"places": {"pond_san_francisco_01": {"name": "Fern Pond"}}},
		"inbox": {"badge": 1, "parcels": [{"key": "k1", "id": "bait_worm", "qty": 3, "left": 60000}]},
		"bag": {"capacity": 25, "slots": [{"id": "seed_radish", "qty": 20}]},
		"travel": {"home": "gn-5391959", "visits": {}},
	}

## What project() returned before Q3 (the whole view deep-copied, then the same timers aged): the values must not change.
func _reference(view: Dictionary, elapsed_ms: float) -> Dictionary:
	var v := view.duplicate(true)
	var e: Dictionary = v.energy
	var remaining := float(e.next_in) - elapsed_ms
	var value := int(e.value)
	while remaining <= 0 and value < int(e.max):
		value += 1
		remaining += float(e.regen_ms)
	e.value = value
	e.next_in = null if value >= int(e.max) else remaining
	for p in v.plots:
		if str(p.state) == "growing":
			p.ready_in = maxf(0.0, float(p.ready_in) - elapsed_ms)
			if float(p.ready_in) <= 0.0: p.state = "ready"
	v.guide.row.ready_in = maxf(0.0, float(v.guide.row.ready_in) - elapsed_ms)
	for st in [v.cooking.stoves[0], v.cooking.stoves[1]]:
		st.elapsed = float(st.elapsed) + elapsed_ms
		st.ready_in = maxf(0.0, float(st.ready_in) - elapsed_ms)
	v.cooking.stove = v.cooking.stoves[0]
	v.fishing.cast.bite_in = maxf(0.0, float(v.fishing.cast.bite_in) - elapsed_ms)
	v.fishing.trap.traps[0].next_in = maxf(0.0, float(v.fishing.trap.traps[0].next_in) - elapsed_ms)
	v.inbox.parcels[0].left = maxf(0.0, float(v.inbox.parcels[0].left) - elapsed_ms)
	return v

func test_the_projection_has_the_same_values_as_the_whole_copy() -> void:
	for ms in [1.0, 700.0, 2000.0, 241000.0 + 1000.0, 1e9]:
		var view := _view()
		assert_str(JSON.stringify(P0Logic.project(view, ms))).override_failure_message("at %d ms" % ms) \
			.is_equal(JSON.stringify(_reference(view, ms)))

func test_the_server_view_is_left_as_it_was_and_untouched_parts_are_shared() -> void:
	var view := _view()
	var before := JSON.stringify(view)
	var p := P0Logic.project(view, 2000.0)
	assert_str(JSON.stringify(view)).is_equal(before)   # nothing written into the server's view
	assert_bool(is_same(p.bag, view.bag)).is_true()     # shared: never aged
	assert_bool(is_same(p.travel, view.travel)).is_true()
	assert_bool(is_same(p.fishing.places, view.fishing.places)).is_true()
	assert_bool(is_same(p.plots[2], view.plots[2])).is_true()   # a tilled plot does not age
	assert_bool(is_same(p.energy, view.energy)).is_false()      # copied: aged
	assert_bool(is_same(p.cooking, view.cooking)).is_false()
	assert_bool(is_same(p.fishing.cast, view.fishing.cast)).is_false()
	# stove 1 is the same pot in cooking.stove and cooking.stoves[0]: one copy, aged once
	assert_bool(is_same(p.cooking.stove, p.cooking.stoves[0])).is_true()
	assert_float(float(p.cooking.stove.ready_in)).is_equal(2000.0)
	assert_that(p.cooking.stoves[2]).is_null()
	assert_bool(p.has("blackjack")).is_false()   # no key is added: a view without one stays without it
	assert_bool(is_same(P0Logic.project(view, 0.0), view)).is_true()   # no time passed: the view itself, as before

func test_a_view_without_the_aging_parts_projects_without_adding_them() -> void:
	var view := {"seq": 1, "coins": 5, "bag": {"slots": []}}
	var p := P0Logic.project(view, 5000.0)
	assert_array(p.keys()).contains_exactly_in_any_order(["seq", "coins", "bag"])

func test_the_session_keeps_one_projection_per_view_and_millisecond() -> void:
	var session := P0Session.new()
	session.view = _view()
	session.set("_received_ms", Time.get_ticks_msec() - 2000)
	var shared := false
	for i in 50:   # two reads inside the same millisecond share one projection
		var at := Time.get_ticks_msec()
		var a := session.current()
		var b := session.current()
		if Time.get_ticks_msec() == at:
			assert_bool(is_same(a, b)).is_true()
			shared = true
			break
	assert_bool(shared).is_true()
	var old := session.current()
	session.view = _view()   # a new server view: a new projection, whatever the millisecond
	assert_bool(is_same(session.current(), old)).is_false()
	session.free()

func test_the_sessions_view_is_read_only_in_the_editor_and_tests() -> void:
	var session := P0Session.new()
	var v := _view()
	session.view = v
	assert_bool(session.view.is_read_only()).is_true()
	assert_bool((session.view.bag as Dictionary).is_read_only()).is_true()
	assert_bool((session.view.bag.slots as Array).is_read_only()).is_true()
	assert_bool((session.view.cooking.stoves[1] as Dictionary).is_read_only()).is_true()
	# the projection's aged copies are its own and writable; the server's stay as they were
	var p := session.current()
	assert_float(float(session.view.energy.next_in)).is_equal(1000.0)
	assert_bool(is_same(p.bag, session.view.bag)).is_true()
	session.free()

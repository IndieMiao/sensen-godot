extends GdUnitTestSuite
## SGODOT-303 PR-3, the first home pick (HOME-PICK-1 / -2 / -3, NOIP, PICK-ERR-LIST / -SPOTS, PICK-SEARCH-EMPTY): what
## the pages show from the routes' answers, a pin and its card as one, and the flow from the city to choose_home.

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const P0HomeSpotMaps := preload("res://modules/p0/p0_home_spot_maps.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
const SpotPage := preload("res://scenes/p0/panels/p0_home_spot_page.gd")
const HomeFlow := preload("res://scenes/p0/panels/p0_home_flow.gd")

const SF := {"id": "gn-5391959", "name": "San Francisco", "country": "US", "region": "California", "climate": "temperate", "status": "open"}
const SEATTLE := {"id": "gn-5809844", "name": "Seattle", "country": "US", "region": "Washington", "climate": "temperate", "status": "open"}
const LA := {"id": "gn-5368361", "name": "Los Angeles", "country": "US", "region": "California", "climate": "subtropical", "status": "open"}
const SINGAPORE := {"id": "gn-1880252", "name": "Singapore", "country": "SG", "region": "Singapore", "climate": "tropical", "status": "open"}
const SAN_JOSE := {"id": "gn-5392171", "name": "San Jose", "country": "US", "region": "California", "climate": "temperate", "status": "not_open"}
const SANTA_CRUZ := {"id": "gn-5393052", "name": "Santa Cruz", "country": "US", "region": "California", "climate": "temperate", "status": "small"}
const OPEN := [SF, SEATTLE, LA, SINGAPORE]
const POND := {"id": "gn-5391959~pond0", "name": "Fern Pond", "lat": 37.760, "lng": -122.440}

static func spots() -> Array:
	return [
		{"spot": 0, "lat": 37.770, "lng": -122.428, "km": 1.234, "toward": "northeast", "pond": POND, "hood": "Mission"},
		{"spot": 1, "lat": 37.759, "lng": -122.449, "km": 0.81, "toward": "west", "pond": POND, "hood": "Noe Valley"},
		{"spot": 2, "lat": 37.748, "lng": -122.430, "km": 1.6, "toward": "southeast", "pond": POND, "hood": null}]

func after_test() -> void:
	P0HomePick.clear()

func _texts(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)

func test_the_list_is_near_you_then_recommended_by_climate() -> void:
	var parts := P0HomePick.sections(OPEN, SF)
	assert_array(parts.map(func(p): return str(p.get("text", p.get("row", {}).get("name", ""))))).is_equal(
		["Near you", "San Francisco", "Recommended", "Temperate", "Seattle", "Subtropical", "Los Angeles", "Tropical", "Singapore"])
	# q(205): no city near — no Near you, San Francisco back at the head of Temperate, nothing picked
	parts = P0HomePick.sections(OPEN, null)
	assert_array(parts.map(func(p): return str(p.get("text", p.get("row", {}).get("name", ""))))).is_equal(
		["Recommended", "Temperate", "San Francisco", "Seattle", "Subtropical", "Los Angeles", "Tropical", "Singapore"])
	assert_str(P0HomePick.preselect(null)).is_empty()
	assert_str(P0HomePick.preselect(SF)).is_equal(SF.id)
	assert_str(P0HomePick.preselect(SF, true)).is_empty()   # a change of home never picks for the player
	# a search: its rows only, no titles
	assert_array(P0HomePick.sections(OPEN, SF, [SF, SAN_JOSE]).map(func(p): return p.kind)).is_equal(["row", "row"])
	# the ones that can be picked first, each group in the server's order (不知火舞 on #451)
	assert_array(P0HomePick.sections(OPEN, SF, [SAN_JOSE, SF, SANTA_CRUZ, LA]).map(func(p): return p.row.id)).is_equal(
		[SF.id, LA.id, SAN_JOSE.id, SANTA_CRUZ.id])
	assert_array(P0HomePick.sections(OPEN, SF, [SF, LA], SF.id).map(func(p): return p.row.id)).is_equal([LA.id, SF.id])   # a change: home is grey

func test_why_a_city_cannot_be_picked_and_the_spot_lines() -> void:
	assert_str(P0HomePick.note(SF)).is_empty()
	assert_str(P0HomePick.note(SAN_JOSE)).is_equal("Not open yet · pick a nearby city")
	assert_str(P0HomePick.note(SANTA_CRUZ)).is_equal("Small town · pick a nearby city")
	assert_str(P0HomePick.note(SF, SF.id)).is_equal("Your home city")
	var s := spots()
	assert_str(P0HomePick.spot_line(s[0])).is_equal("1.2 km to Fern Pond · northeast")
	assert_str(P0HomePick.spot_line(s[1])).is_equal("0.8 km to Fern Pond · west")
	assert_str(P0HomePick.spot_title(s[0])).is_equal("Mission")
	assert_str(P0HomePick.spot_title(s[2])).is_equal("Spot 3")   # a spot without a district

func _pick_page() -> Control:
	var page: Control = auto_free(PickPage.new())
	page.size = Vector2(360, 800)
	add_child(page)
	return page

func test_near_you_is_picked_and_continue_goes_with_it() -> void:
	var page := _pick_page()
	page.show_cities({"open": OPEN, "near": SF}, "")
	await await_idle_frame()
	assert_array(_texts(page.list)).contains_exactly(["Near you", "San Francisco", " · California", "Temperate", "Recommended", "Temperate",
		"Seattle", " · Washington", "Temperate", "Subtropical", "Los Angeles", " · California", "Subtropical", "Tropical", "Singapore",
		" · Singapore", "Tropical"])
	assert_bool(page.rows[SF.id].picked).is_true()
	assert_bool(page.rows[SF.id].check.visible).is_true()
	assert_float(page.rows[SF.id].size.x).is_equal(344.0)   # the picked ground reaches 8 past the list's 328 each side
	assert_str(page.key.reason).is_empty()
	var got := []
	page.picked.connect(func(r): got.append(r.id))
	page.key.activated.emit()
	assert_array(got).is_equal([SF.id])
	page.rows[SEATTLE.id].pressed.emit()
	assert_bool(page.rows[SF.id].picked).is_false()
	assert_bool(page.rows[SEATTLE.id].picked).is_true()

func test_no_city_near_opens_with_nothing_picked() -> void:
	var page := _pick_page()
	page.show_cities({"open": OPEN, "near": null}, "")
	await await_idle_frame()
	assert_bool(_texts(page.list).has("Near you")).is_false()
	assert_bool(page.rows.values().any(func(r): return r.picked)).is_false()
	assert_str(page.key.reason).is_equal("Pick a city")   # LOCK-10: grey, its toast says the same
	var said := []
	page.unavailable.connect(func(t): said.append(t))
	page.key.pressed.emit()
	assert_array(said).is_equal(["Pick a city"])

func test_a_search_lists_its_matches_greyed_with_why() -> void:
	var page := _pick_page()
	page.show_cities({"open": OPEN, "near": SF}, "")
	var asked := []
	page.read_cities.connect(func(q): asked.append(q))
	page.field.text = "san"
	page.field.text_changed.emit("san")
	page._process(0.1)
	assert_array(asked).is_empty()   # typing still
	page._process(PickPage.SEARCH_WAIT_S)
	assert_array(asked).is_equal(["san"])
	page.show_cities({"open": OPEN, "near": SF, "matches": [SF, SAN_JOSE, SANTA_CRUZ]}, "sa")   # an older search's answer
	await await_idle_frame()
	assert_bool(page.rows.has(SAN_JOSE.id)).is_false()
	page.show_cities({"open": OPEN, "near": SF, "matches": [SF, SAN_JOSE, SANTA_CRUZ]}, "san")
	await await_idle_frame()
	assert_bool(_texts(page.list).has("Near you")).is_false()   # no titles
	var jose = page.rows[SAN_JOSE.id]
	assert_bool(jose.disabled).is_true()
	assert_str((jose.find_child("Note", true, false) as Label).text).is_equal("Not open yet · pick a nearby city")
	assert_float((jose.find_child("First", true, false) as Control).modulate.a).is_equal(0.5)
	assert_str((page.rows[SANTA_CRUZ.id].find_child("Note", true, false) as Label).text).is_equal("Small town · pick a nearby city")
	assert_bool(page.rows[SF.id].picked).is_true()   # the city picked stays picked
	page.show_cities({"open": OPEN, "near": SF, "matches": []}, "san")
	await await_idle_frame()
	assert_bool(page.none.visible).is_true()   # PICK-SEARCH-EMPTY
	assert_str(page.none.text).is_equal("No matching cities")
	assert_bool(page.scroll.visible).is_false()
	assert_str(page.key.reason).is_empty()   # the key follows the city picked
	page.field.text_changed.emit("s")   # back under two letters: the list again
	await await_idle_frame()
	assert_bool(page.none.visible).is_false()
	assert_bool(_texts(page.list).has("Near you")).is_true()

func test_a_list_that_fails_says_so_and_retries() -> void:
	var page := _pick_page()
	page.show_failed("")
	await await_idle_frame()
	assert_bool(page.error.visible).is_true()
	assert_array(_texts(page.error)).contains(["Couldn't load cities"])
	assert_str(page.key.reason).is_equal("Pick a city")
	var asked := []
	page.read_cities.connect(func(q): asked.append(q))
	(page.error.find_child("Retry", true, false) as UiCommandButton).activated.emit()
	assert_array(asked).is_equal([""])
	page.show_cities({"open": OPEN, "near": SF}, "")
	await await_idle_frame()
	assert_bool(page.error.visible).is_false()
	assert_bool(page.scroll.visible).is_true()

func _spot_page() -> Control:
	var page: Control = auto_free(SpotPage.new("gn-5391959", "San Francisco"))
	page.size = Vector2(360, 800)
	add_child(page)
	return page

func test_a_pin_and_its_card_are_one() -> void:
	var page := _spot_page()
	page.show_spots(spots())
	await await_idle_frame()
	assert_array(_texts(page)).contains(["Pick your farm spot", "San Francisco", "Mission", "1.2 km to Fern Pond · northeast", "Fern"])
	assert_int(page.cards.size()).is_equal(3)
	assert_int(page.map_card.pins.size()).is_equal(3)
	assert_str(page.build.reason).is_equal("Pick a spot")   # nothing picked when it opens
	page.cards[1].pressed.emit()
	assert_bool(page.cards[1].picked).is_true()
	assert_bool(page.map_card.pins[1].picked).is_true()
	assert_float(page.map_card.pins[1].size.x).is_equal(36.0)
	assert_float(page.map_card.pins[0].size.x).is_equal(30.0)
	assert_str(page.build.reason).is_empty()
	page.map_card.spot_pressed.emit(2)   # the pin's tap
	assert_bool(page.cards[2].picked).is_true()
	assert_bool(page.cards[1].picked).is_false()
	var got := []
	page.chosen.connect(func(c, s): got.append([c, s]))
	page.build.activated.emit()
	page.for_me.activated.emit()   # the first spot, whatever is picked
	assert_array(got).is_equal([["gn-5391959", 2], ["gn-5391959", 0]])

func test_the_map_is_north_up_and_clear_of_its_edges() -> void:
	var page := _spot_page()
	page.show_spots(spots())
	await await_idle_frame()
	var card: Control = page.map_card
	var pond: UiMapDestination = card.pond
	var pond_at: Vector2 = pond.position + pond.anchor_offset()
	var pins: Array = card.pins
	assert_float(pins[0].position.y).is_less(pond_at.y)   # north of the pond: above it
	assert_float(pins[2].position.y).is_greater(pond_at.y)   # south: below
	assert_float(pins[1].position.x).is_less(pond_at.x)   # west: left
	for i in 3:
		page.picked = i   # picked, a pin is 36
		var r := Rect2(pins[i].position, pins[i].size)
		assert_bool(Rect2(Vector2.ONE * 24, card.size - Vector2.ONE * 48).encloses(r)).override_failure_message("pin %d %s" % [i, r]).is_true()
	assert_bool(Rect2(Vector2.ONE * 24, card.size - Vector2.ONE * 48).encloses(Rect2(pond.position, Vector2(pond.size.x, 60)))).is_true()

## 不知火舞 on #451 (q(207) ③): while the spots are read, the plain map, three blank cards and two quiet grey keys; the
## real cards take the blanks' places.
func test_while_the_spots_are_read_blank_cards_hold_their_places() -> void:
	var page := _spot_page()
	await await_idle_frame()
	var blanks: Array = page._cards_box.get_children()
	assert_array(blanks.map(func(c): return c.name)).is_equal(["Placeholder1", "Placeholder2", "Placeholder3"])
	assert_array(page._cards_box.find_children("*", "Label", true, false)).is_empty()
	var at: Array = blanks.map(func(c): return (c as Control).global_position)
	assert_object(page.map_card.pond).is_null()
	assert_array(page.map_card.pins).is_empty()
	assert_str(page.build.reason).is_equal("Pick a spot")
	assert_str(page.for_me.reason).is_equal("Pick for me")
	var said := []
	page.unavailable.connect(func(t): said.append(t))
	page.build.pressed.emit()
	page.for_me.pressed.emit()
	assert_array(said).is_empty()
	page.show_spots(spots())
	await await_idle_frame()
	assert_int(page._cards_box.get_child_count()).is_equal(3)
	assert_array(page.cards.map(func(c): return (c as Control).global_position)).is_equal(at)   # nothing moves

func test_spots_that_fail_leave_the_keys_grey_and_quiet() -> void:
	var page := _spot_page()
	page.show_failed()
	await await_idle_frame()
	assert_bool(page.empty.visible).is_true()
	assert_array(_texts(page.empty)).contains(["Couldn't load farm spots"])
	assert_bool(page.map_card.visible).is_false()
	assert_str(page.build.reason).is_equal("Pick a spot")
	assert_str(page.for_me.reason).is_equal("Pick for me")
	var said := []
	page.unavailable.connect(func(t): said.append(t))
	page.build.pressed.emit()
	page.for_me.pressed.emit()
	assert_array(said).is_empty()   # PICK-ERR-SPOTS: no toast
	var retried := []
	page.retry_pressed.connect(func(): retried.append(1))
	(page.empty.find_child("Retry", true, false) as UiCommandButton).activated.emit()
	assert_array(retried).is_equal([1])

func test_the_flow_reads_the_cities_then_the_spots_and_comes_back_as_it_was() -> void:
	var session := P0Session.new()   # not in the tree: no reads of its own
	var asked := []
	session.transport = func(_m, path: String, _b, _c): asked.append(path)
	var flow: Control = auto_free(HomeFlow.new(session))
	flow.size = Vector2(360, 800)
	add_child(flow)
	await await_idle_frame()
	assert_array(asked).is_equal(["/p0/home/cities"])
	P0HomePick.answer("/p0/home/cities", {"ok": true, "open": OPEN, "near": SF, "matches": []})
	await await_idle_frame()
	flow.cities.rows[SEATTLE.id].pressed.emit()
	flow.cities.key.activated.emit()
	assert_array(asked).is_equal(["/p0/home/cities", "/p0/home/spots/" + SEATTLE.id])
	assert_bool(flow.cities.visible).is_false()
	P0HomePick.answer("/p0/home/spots/" + SEATTLE.id, {"ok": true, "city": SEATTLE.id, "spots": spots(), "resets_at": null})
	await await_idle_frame()
	assert_int(flow.spots.cards.size()).is_equal(3)
	var chose := []
	flow.chose.connect(func(c, s): chose.append([c, s]))
	flow.spots.cards[0].pressed.emit()
	flow.spots.build.activated.emit()
	flow.spots.build.activated.emit()   # one choice on the wire at a time
	assert_array(chose).is_equal([[SEATTLE.id, 0]])
	flow.sent(false)   # refused: another go
	flow.spots.back_pressed.emit()
	await await_idle_frame()
	assert_bool(flow.cities.visible).is_true()
	assert_str(flow.cities.choice).is_equal(SEATTLE.id)   # as it was
	session.free()

func test_a_failed_spot_read_is_the_error_and_retry_reads_again() -> void:
	var session := P0Session.new()
	var asked := []
	session.transport = func(_m, path: String, _b, _c): asked.append(path)
	var flow: Control = auto_free(HomeFlow.new(session))
	add_child(flow)
	flow.open_spots(SF)
	P0HomePick.answer("/p0/home/spots/" + SF.id, null)
	await await_idle_frame()
	assert_bool(flow.spots.failed).is_true()
	(flow.spots.empty.find_child("Retry", true, false) as UiCommandButton).activated.emit()
	assert_int(asked.count("/p0/home/spots/" + SF.id)).is_equal(2)
	# 周瑜 on #451: Retry goes back to reading — the error gone (no second Retry), the blank cards back
	assert_bool(flow.spots.failed).is_false()
	assert_bool(flow.spots.empty.visible).is_false()
	assert_str(str(flow.spots._cards_box.get_child(0).name)).starts_with("Placeholder")
	P0HomePick.answer("/p0/home/spots/" + SF.id, {"ok": true, "city": SF.id, "spots": spots()})
	await await_idle_frame()
	assert_int(flow.spots.cards.size()).is_equal(3)
	session.free()

func test_an_older_spot_reads_late_answer_is_dropped() -> void:
	var session := P0Session.new()
	session.transport = func(_m, _p, _b, _c): pass
	var flow: Control = auto_free(HomeFlow.new(session))
	add_child(flow)
	var path := "/p0/home/spots/" + SF.id
	flow.open_spots(SF)   # read 1
	var first: Array = P0HomePick._waiting[path]
	flow._read_spots(SF.id)   # read 2 (a Retry) before read 1 answers
	P0HomePick.answer(path, {"ok": true, "city": SF.id, "spots": spots()})   # read 2 comes back
	(first[1] as Callable).call()   # then read 1's late failure: dropped
	await await_idle_frame()
	assert_bool(flow.spots.failed).is_false()
	assert_int(flow.spots.cards.size()).is_equal(3)
	session.free()

func test_a_pending_save_and_the_feature_header() -> void:
	assert_bool(P0Runtime.home_pending({"home": {"pending": true}})).is_true()
	assert_bool(P0Runtime.home_pending({"home": {"pending": false}})).is_false()
	assert_bool(P0Runtime.home_pending({})).is_false()
	# 周瑜 on #451: the first reply lost, the second Build here is refused (home_chosen) with the home already picked —
	# taken all the same; a refusal while still pending, or a lost reply with no view, is not
	assert_bool(P0Runtime.home_taken(true, {"home": {"pending": true}})).is_true()
	assert_bool(P0Runtime.home_taken(false, {"home": {"pending": false, "city": "gn-1850147"}})).is_true()
	assert_bool(P0Runtime.home_taken(false, {"home": {"pending": true}})).is_false()
	assert_bool(P0Runtime.home_taken(false, {})).is_false()
	var session := P0Session.new()
	assert_array(Array(session._headers())).contains(["x-p0-features: choose_home"])
	session.free()

func test_a_baked_map_is_used_only_while_the_points_fit_it() -> void:
	var pts: Array = [Vector2(POND.lat, POND.lng)]
	for s in spots(): pts.append(Vector2(s.lat, s.lng))
	var frame := P0HomeSpotMaps.fit(pts, Vector2(328, 268), 24.0)
	var zoom := log(float(frame.scale) / P0HomeSpotMaps.TILE) / log(2.0)
	var centre := Vector2(POND.lat, POND.lng)
	# a picture centred on the pond at a zoom that holds them
	assert_bool(P0HomeSpotMaps.fits({"lat": centre.x, "lng": centre.y, "zoom": zoom - 1.0}, pts, Vector2(328, 268), 24.0)).is_true()
	# baked for another table (a point far outside): the plain card
	assert_bool(P0HomeSpotMaps.fits({"lat": centre.x + 0.05, "lng": centre.y, "zoom": zoom}, pts, Vector2(328, 268), 24.0)).is_false()

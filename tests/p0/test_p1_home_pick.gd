extends GdUnitTestSuite
## SGODOT-303 PR-3, the first home pick (HOME-PICK-1 / -2, NOIP, PICK-ERR-LIST, PICK-SEARCH-EMPTY): what the pages show
## from the routes' answers, and the flow from the city through the pin page (SGODOT-342 PR-2, HOME-PIN; its own
## states in test_p1_home_pin_page) and its confirm card to choose_home.

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
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

## A spots read with its pin area (#473): the circle round Fern Pond's city, the start on spot 1.
static func spot_read(city: String) -> Dictionary:
	var s := spots()
	return {"ok": true, "city": city, "spots": s, "resets_at": null,
		"pin": {"base": {"lat": 37.76, "lng": -122.44}, "range_km": 10, "clear_m": 300, "start": {"lat": s[1].lat, "lng": s[1].lng},
			"blocks": [{"id": POND.id, "lat": POND.lat, "lng": POND.lng}]}}

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
	# a search: its rows only, no titles
	assert_array(P0HomePick.sections(OPEN, SF, [SF, SAN_JOSE]).map(func(p): return p.kind)).is_equal(["row", "row"])
	# the ones that can be picked first, each group in the server's order (不知火舞 on #451)
	assert_array(P0HomePick.sections(OPEN, SF, [SAN_JOSE, SF, SANTA_CRUZ, LA]).map(func(p): return p.row.id)).is_equal(
		[SF.id, LA.id, SAN_JOSE.id, SANTA_CRUZ.id])
	# a change: the home city can be picked as any other (q(216) ⑨), in the server's order
	assert_array(P0HomePick.sections(OPEN, SF, [SF, LA]).map(func(p): return p.row.id)).is_equal([SF.id, LA.id])

func test_why_a_city_cannot_be_picked() -> void:
	assert_str(P0HomePick.note(SF)).is_empty()
	assert_str(P0HomePick.note(SAN_JOSE)).is_equal("Not open yet · pick a nearby city")
	assert_str(P0HomePick.note(SANTA_CRUZ)).is_equal("Small town · pick a nearby city")
	assert_str(P0HomePick.note(SF, SF.id)).is_equal("Your home city")   # a note, yet it can be picked (q(216) ⑨)
	assert_bool(P0HomePick.can_pick(SF)).is_true()
	assert_bool(P0HomePick.can_pick(SAN_JOSE)).is_false()

func _pick_page() -> Control:
	var page: Control = auto_free(PickPage.new())
	page.size = Vector2(360, 800)
	add_child(page)
	return page

## 340 6cb4d10e ② (q(216)): Near you is listed, never picked for the player — the key is `Pick a city` until a row is.
func test_near_you_is_listed_not_picked_and_continue_goes_with_the_row_picked() -> void:
	var page := _pick_page()
	page.show_cities({"open": OPEN, "near": SF}, "")
	await await_idle_frame()
	assert_array(_texts(page.list)).contains_exactly(["Near you", "San Francisco", " · California", "Temperate", "Recommended", "Temperate",
		"Seattle", " · Washington", "Temperate", "Subtropical", "Los Angeles", " · California", "Subtropical", "Tropical", "Singapore",
		" · Singapore", "Tropical"])
	assert_bool(page.rows.values().any(func(r): return r.picked)).is_false()
	assert_str(page.key.reason).is_equal("Pick a city")
	page.show_cities({"open": OPEN, "near": SF}, "")   # a second answer still picks nothing
	assert_str(page.choice).is_empty()
	page.rows[SF.id].pressed.emit()
	await await_idle_frame()
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
	await await_idle_frame()
	page.rows[SF.id].pressed.emit()   # the player picks Near you
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

func test_the_flow_reads_the_cities_then_the_spots_and_comes_back_as_it_was() -> void:
	var session := P0Session.new()   # not in the tree: no reads of its own
	var asked := []
	session.transport = func(_m, path: String, _b, _c): asked.append(path)
	var flow: Control = auto_free(HomeFlow.new(session))
	flow.size = Vector2(360, 800)
	add_child(flow)
	await await_idle_frame()
	assert_array(asked).is_equal(["/p0/home/cities"])
	# no city near: the list (a city near opens HOME-WELCOME first, test_a_city_near_opens_on_the_welcome_card)
	P0HomePick.answer("/p0/home/cities", {"ok": true, "open": OPEN, "near": null, "matches": []})
	await await_idle_frame()
	assert_object(flow.welcome).is_null()
	flow.cities.rows[SEATTLE.id].pressed.emit()
	flow.cities.key.activated.emit()
	assert_array(asked).is_equal(["/p0/home/cities", "/p0/home/spots/" + SEATTLE.id])
	assert_bool(flow.cities.visible).is_false()
	P0HomePick.answer("/p0/home/spots/" + SEATTLE.id, spot_read(SEATTLE.id))
	await await_idle_frame()
	assert_bool(flow.spots.area.is_empty()).is_false()
	var chose := []
	flow.chose.connect(func(c, lat, lng): chose.append([c, lat, lng]))
	# Build here asks HOME-PIN-CONFIRM first (q(216) ③); Cancel leaves the pin where it was
	flow.spots.build.activated.emit()
	assert_array(chose).is_empty()
	assert_array(_texts(flow.confirm)).contains(["Build your farm here?", "Seattle · 0.8 km to Fern Pond",
		"You can move it once while your farm is new."])
	assert_str(flow.confirm.move.label).is_equal("Build farm")
	flow.confirm.cancel.activated.emit()
	assert_object(flow.confirm).is_null()
	flow.spots.build.activated.emit()
	flow.confirm.move.activated.emit()
	flow.confirm.move.activated.emit()   # one choice on the wire at a time
	assert_int(chose.size()).is_equal(1)
	assert_str(chose[0][0]).is_equal(SEATTLE.id)
	assert_float(chose[0][1]).is_equal_approx(37.759, 1e-9)   # spot 1, as the server sent it (doubles)
	assert_float(chose[0][2]).is_equal_approx(-122.449, 1e-9)
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
	(flow.spots.error_card.find_child("Retry", true, false) as UiCommandButton).activated.emit()
	assert_int(asked.count("/p0/home/spots/" + SF.id)).is_equal(2)
	# 周瑜 on #451: Retry goes back to reading — the error gone (no second Retry), the outline card back
	assert_bool(flow.spots.failed).is_false()
	assert_bool(flow.spots.error_card.visible).is_false()
	assert_bool(flow.spots.loading_card.visible).is_true()
	P0HomePick.answer("/p0/home/spots/" + SF.id, spot_read(SF.id))
	await await_idle_frame()
	assert_bool(flow.spots.area.is_empty()).is_false()
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
	P0HomePick.answer(path, spot_read(SF.id))   # read 2 comes back
	(first[1] as Callable).call()   # then read 1's late failure: dropped
	await await_idle_frame()
	assert_bool(flow.spots.failed).is_false()
	assert_bool(flow.spots.area.is_empty()).is_false()
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
	assert_array(Array(session._headers())).contains(["x-p0-features: choose_home,guide"])
	session.free()

func _welcome_flow(near: Variant) -> Array:
	var session := P0Session.new()   # not in the tree: no reads of its own
	var asked := []
	session.transport = func(_m, path: String, _b, _c): asked.append(path)
	var flow: Control = auto_free(HomeFlow.new(session))
	flow.size = Vector2(360, 800)
	add_child(flow)
	await await_idle_frame()
	P0HomePick.answer("/p0/home/cities", {"ok": true, "open": OPEN, "near": near, "matches": []})
	await await_idle_frame()
	return [flow, session, asked]

## A city near: the first page is the card — the city, Start here, Choose another city; the list waits behind it.
func test_a_city_near_opens_on_the_welcome_card() -> void:
	var r: Array = await _welcome_flow(SF)
	var flow: Control = r[0]
	assert_bool(flow.welcome.visible).is_true()
	assert_bool(flow.cities.visible).is_false()
	var texts := _texts(flow.welcome)
	assert_array(texts).contains(["Welcome to Gensen!", "San Francisco", "Start your farm here? It's the closest home city to you."])
	assert_str(flow.welcome.start.label).is_equal("Start here")
	assert_str(flow.welcome.other.label).is_equal("Choose another city")
	assert_object(flow.welcome.find_child("Close", true, false)).is_null()   # no ×, no later
	# 不知火舞 on #476 (342 590be5c5): the line in the secondary ink, as the pick page's
	var line := flow.welcome.find_child("Line", true, false) as Label
	assert_object(line.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	# row 101 51:160752: the card 16 in from the side; its city row's thumb at the card's padding (20), not the list's 8 more
	var card: Control = flow.welcome.card
	var thumb := flow.welcome.find_child("Row", true, false).get_child(0) as Control
	assert_float(card.global_position.x).is_equal(16.0)
	assert_float(thumb.global_position.x - card.global_position.x).is_equal(20.0)
	(r[1] as Node).free()

## Start here: that city's spots at once; the spot page's back comes back to the card.
func test_start_here_goes_to_the_city_spots_and_back_to_the_card() -> void:
	var r: Array = await _welcome_flow(SF)
	var flow: Control = r[0]
	flow.welcome.start.activated.emit()
	assert_array(r[2]).is_equal(["/p0/home/cities", "/p0/home/spots/" + SF.id])
	assert_bool(flow.welcome.visible).is_false()
	assert_bool(flow.cities.visible).is_false()
	flow.spots.back_pressed.emit()
	await await_idle_frame()
	assert_bool(flow.welcome.visible).is_true()
	assert_bool(flow.cities.visible).is_false()
	(r[1] as Node).free()

## Choose another city: the list with `‹ Back` and Near you shown but not picked (`Pick a city` grey); Back (the pill
## or the system's) to the card; a city picked there goes on as ever, and its spot page comes back to the list.
func test_choose_another_city_opens_the_list_unpicked_with_back() -> void:
	var r: Array = await _welcome_flow(SF)
	var flow: Control = r[0]
	flow.welcome.other.activated.emit()
	await await_idle_frame()
	assert_bool(flow.cities.visible).is_true()
	assert_bool(flow.welcome.visible).is_false()
	assert_str(flow.cities.choice).is_equal("")
	assert_str(flow.cities.key.reason).is_equal("Pick a city")
	assert_bool(flow.cities.rows.has(SF.id)).is_true()   # Near you stays
	var back := flow.cities.find_child("Back", true, false) as Button
	assert_str(back.text).contains("Back")
	back.pressed.emit()
	assert_bool(flow.welcome.visible).is_true()
	assert_bool(flow.cities.visible).is_false()
	flow.welcome.other.activated.emit()
	flow.back()   # Android Back
	assert_bool(flow.welcome.visible).is_true()
	flow.back()   # the card itself stays: a first pick has nowhere to go back to
	assert_bool(flow.welcome.visible).is_true()
	flow.welcome.other.activated.emit()
	flow.cities.rows[SEATTLE.id].pressed.emit()
	flow.cities.key.activated.emit()
	assert_array(r[2]).is_equal(["/p0/home/cities", "/p0/home/spots/" + SEATTLE.id])
	flow.spots.back_pressed.emit()
	await await_idle_frame()
	assert_bool(flow.cities.visible).is_true()
	assert_bool(flow.welcome.visible).is_false()
	(r[1] as Node).free()

## No city near: no card, the list (HOME-PICK-1-NOIP) without a back; a first read that fails: the list's error.
func test_no_city_near_or_a_failed_read_is_the_list() -> void:
	var r: Array = await _welcome_flow(null)
	var flow: Control = r[0]
	assert_object(flow.welcome).is_null()
	assert_bool(flow.cities.visible).is_true()
	assert_object(flow.cities.find_child("Back", true, false)).is_null()
	(r[1] as Node).free()
	var session := P0Session.new()
	session.transport = func(_m, _p, _b, _c): pass
	var failed: Control = auto_free(HomeFlow.new(session))
	add_child(failed)
	await await_idle_frame()
	P0HomePick.answer("/p0/home/cities", null)
	await await_idle_frame()
	assert_object(failed.welcome).is_null()
	assert_bool(failed.cities.error.visible).is_true()
	session.free()

## Till the first read is in (不知火舞 342 8c4168ab): the card's outline where the card goes, no words, nothing to tap;
## the read in, the real card in its place (or the list); a read that fails, the list's error, the outline gone.
func test_the_first_read_holds_the_cards_place_with_its_outline() -> void:
	var session := P0Session.new()
	session.transport = func(_m, _p, _b, _c): pass
	var flow: Control = auto_free(HomeFlow.new(session, 0.0, 34.0))
	flow.size = Vector2(360, 800)
	add_child(flow)
	await await_idle_frame()
	await await_idle_frame()
	var outline: Control = flow.loading
	assert_object(outline).is_not_null()
	assert_array(flow.find_children("*", "Label", true, false).filter(
		func(l): return (l as Label).is_visible_in_tree() and _shown(l))).is_empty()   # no words
	assert_array(outline.find_children("*", "BaseButton", true, false).filter(func(b): return not (b as BaseButton).disabled)).is_empty()
	assert_object(flow.cities).is_null()
	assert_object(flow.welcome).is_null()
	var sb := (outline.card as PanelContainer).get_theme_stylebox(&"panel") as UiStyleBox
	assert_float(sb.bg_color.a).is_equal(0.0)   # an edge only
	assert_float(sb.border_width).is_greater(0.0)
	assert_float(sb.corner_radius.x).is_equal(20.0)
	assert_float(sb.shadow_size).is_equal(0.0)
	var held := (outline.card as Control).get_global_rect()
	P0HomePick.answer("/p0/home/cities", {"ok": true, "open": OPEN, "near": SF, "matches": []})
	await await_idle_frame()
	assert_object(flow.loading).is_null()
	assert_bool(is_instance_valid(outline) and outline.is_inside_tree() and not outline.is_queued_for_deletion()).is_false()
	# the card stands where the outline stood, the same size (a one-line city), 16 above the safe area
	await await_idle_frame()
	var card := (flow.welcome.card as Control).get_global_rect()
	assert_object(card).is_equal(held)
	assert_float(flow.get_global_rect().end.y - card.end.y).is_equal(16.0 + 34.0)
	flow.free()
	var failed: Control = HomeFlow.new(session)
	add_child(failed)
	await await_idle_frame()
	P0HomePick.answer("/p0/home/cities", null)
	await await_idle_frame()
	assert_object(failed.loading).is_null()
	assert_bool(failed.cities.error.visible).is_true()
	failed.free()
	session.free()

## A label that shows: in the tree, visible, not under a transparent parent.
func _shown(l: Node) -> bool:
	var n: Node = l
	while n is CanvasItem:
		if (n as CanvasItem).modulate.a == 0.0 or (n as CanvasItem).self_modulate.a == 0.0: return false
		n = n.get_parent()
	return true

## The real map's stand-in for the flow (PR-2b): the flat map's geometry, recording the flight and the glide.
class FakeMap extends RefCounted:
	const PinPage := preload("res://scenes/p0/panels/p0_home_pin_page.gd")
	var flat := PinPage.FlatMap.new()
	var ground := false
	var flies: Array = []      # [to_zoom, seconds, at]
	var frames: Array = []     # [lat, lng, seconds]
	var landing := Callable()  # the flight's done, held till the test lands it
	var flying := false
	func pick_fly(z: float, s: float, at: Vector2, done := Callable()) -> void:
		flies.append([z, s, at])
		if s <= 0.0:
			if done.is_valid(): done.call()
		else:
			landing = done
	func pick_frame(lat: float, lng: float, at: Vector2, s := 0.0) -> void:
		frames.append([lat, lng, s])
		flat.pick_put(lat, lng, at)
		flying = s > 0.0
	func pick_flying() -> bool: return flying
	func pick_settling() -> bool: return flying
	func pick_area(_lat: float, _lng: float, _km: float) -> void: pass
	func pick_geo_at(s: Vector2) -> Array: return flat.pick_geo_at(s)
	func pick_screen_of(lat: float, lng: float) -> Variant: return flat.pick_screen_of(lat, lng)
	func pick_put(lat: float, lng: float, s: Vector2) -> void: flat.pick_put(lat, lng, s)
	func pick_dragging() -> bool: return flying
	func pick_px_per_m() -> float: return flat.px_per_m
	func pick_has_ground() -> bool: return ground

func _welcome_map_flow() -> Array:
	var session := P0Session.new()
	var asked := []
	session.transport = func(_m, path: String, _b, _c): asked.append(path)
	var flow: Control = auto_free(HomeFlow.new(session, 24.0, 0.0))
	flow.size = Vector2(360, 800)
	var maps := []
	var closed := []
	var m := FakeMap.new()
	flow.open_map = func(c: String) -> Object:
		maps.append(c)
		return m
	flow.close_map = func(): closed.append(1)
	add_child(flow)
	await await_idle_frame()
	P0HomePick.answer("/p0/home/cities", {"ok": true, "open": OPEN, "near": SF, "matches": []})
	for i in 3: await get_tree().process_frame   # laid out, then the flight
	return [flow, session, asked, m, maps, closed]

## PR-2b (340 §4; 不知火舞 342 bce34a87): behind HOME-WELCOME the real map flies from the globe to the city view (z 11)
## in a second with the city between the status bar and the card's top; the card slides in once it lands. Modal: no
## touches to the map. The flow's land goes; the card's own lies over the map till it draws, then the credit line.
func test_the_welcome_card_waits_for_the_flight_over_the_real_map() -> void:
	var r: Array = await _welcome_map_flow()
	var flow: Control = r[0]
	var m: FakeMap = r[3]
	assert_array(r[4]).is_equal([SF.id])
	assert_int(m.flies.size()).is_equal(1)
	assert_float(m.flies[0][0]).is_equal(HomeFlow.WELCOME_ZOOM)
	assert_float(m.flies[0][1]).is_equal(HomeFlow.WELCOME_FLY_S)
	var w: Control = flow.welcome
	var card_top: float = w.size.y - 16.0 - w.card.size.y
	assert_float((m.flies[0][2] as Vector2).y).is_equal_approx((24.0 + card_top) * 0.5, 0.5)   # between the bar and the card
	assert_float((m.flies[0][2] as Vector2).x).is_equal(w.size.x * 0.5)
	assert_bool(w.waiting()).is_true()   # in the air: not drawn, its keys quiet
	assert_float(w.card.modulate.a).is_equal(0.0)
	var started := []
	w.start_pressed.connect(func(): started.append(1))
	w.start.activated.emit()
	assert_array(started).is_empty()
	assert_int(flow.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)   # modal
	assert_bool(flow._land.visible).is_false()
	assert_bool(w.land.visible).is_true()   # the map has not drawn yet
	m.landing.call()
	assert_bool(w.waiting()).is_false()
	await get_tree().create_timer(UiKit.secs(UiTokens.MOTION_DRAWER_MS) + 0.1).timeout
	assert_float(w.card.global_position.y).is_equal_approx(card_top, 1.0)   # slid up to its place
	assert_bool(w.credits == null or not w.credits.visible).is_true()
	m.ground = true
	for i in 2: await get_tree().process_frame
	assert_bool(w.land.visible).is_false()
	assert_bool(w.credits.visible).is_true()
	assert_float(w.credits.position.y + w.credits.size.y).is_equal_approx(w.card.position.y - CityMapView.CREDITS_GAP_PT, 0.5)
	(r[1] as Node).free()

## Start here on the same city: the pin page goes on on the card's map (no second one), its start gliding in over
## motion.recenterMs with the card held back till it lands; ‹ Change city back to the card keeps the map, puts it at the
## city view at once and slides the card in again. Choose another city lets the map go (the list covers it), ‹ Back
## brings one back, straight at the city view.
func test_start_here_glides_on_the_same_map_and_back_to_the_card_slides_it_in_again() -> void:
	var r: Array = await _welcome_map_flow()
	var flow: Control = r[0]
	var m: FakeMap = r[3]
	m.landing.call()
	flow.welcome.start.activated.emit()
	assert_array(r[4]).is_equal([SF.id])   # the same map
	assert_array(r[5]).is_empty()
	m.ground = true   # drawn: reading the spots, the map stays in sight (no land over it), no pin yet
	flow.spots._refresh()
	assert_bool(flow.spots.land.visible).is_false()
	assert_bool(flow.spots.pin.visible).is_false()
	assert_object(flow.spots.map).is_same(m)
	assert_int(flow.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)   # the pin page lets the drags through
	P0HomePick.answer("/p0/home/spots/" + SF.id, spot_read(SF.id))
	await await_idle_frame()
	assert_int(m.frames.size()).is_equal(1)
	assert_float(m.frames[0][2]).is_equal(UiKit.secs(UiTokens.MOTION_RECENTER_MS))
	assert_bool(flow.spots.card.visible).is_false()   # gliding: the card comes as the pin drops
	assert_bool(flow.spots.back_key.visible).is_false()   # and no back-to-start key on the way
	assert_bool(flow.spots.pin.lifted).is_true()
	m.flying = false
	flow.spots._refresh()
	assert_bool(flow.spots.card.visible).is_true()
	assert_bool(flow.spots.pin.lifted).is_false()
	flow.spots.back_pressed.emit()
	for i in 2: await get_tree().process_frame
	assert_array(r[5]).is_empty()   # the card's map stays
	assert_float(m.flies[-1][1]).is_equal(0.0)   # at the city view at once
	assert_bool(flow.welcome.waiting()).is_false()   # and the card slides in again
	assert_int(flow.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	flow.welcome.other.activated.emit()
	assert_array(r[5]).is_equal([1])   # the list covers the screen: the map goes
	flow.cities.find_child("Back", true, false).pressed.emit()
	for i in 2: await get_tree().process_frame
	assert_array(r[4]).is_equal([SF.id, SF.id])
	assert_float(m.flies[-1][1]).is_equal(0.0)
	assert_bool(flow.welcome.waiting()).is_false()
	(r[1] as Node).free()

## Without a map (the tests, a navigation under way) the card comes at once on the land, as before.
func test_without_a_map_the_welcome_card_is_there_at_once() -> void:
	var r: Array = await _welcome_flow(SF)
	assert_bool(r[0].welcome.waiting()).is_false()
	assert_float(r[0].welcome.card.modulate.a).is_equal(1.0)
	(r[1] as Node).free()

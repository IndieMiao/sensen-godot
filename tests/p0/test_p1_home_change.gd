extends GdUnitTestSuite
## SGODOT-303 PR-4, the change of home (SET-HOME-1 / -2, HOME-CHANGE-PICK, HOME-CHANGE-CONFIRM): Settings' Home row,
## the change's city page, the confirm card over the spot page, Back a layer at a time, and a lost reply.

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const PickPage := preload("res://scenes/p0/panels/p0_home_pick_page.gd")
const HomeFlow := preload("res://scenes/p0/panels/p0_home_flow.gd")
const Pick := preload("res://tests/p0/test_p1_home_pick.gd")

const DAY := 86400000.0
const NOW := 1_790_000_000_000.0
const TOKYO := {"id": "gn-1850147", "name": "Tokyo", "country": "JP", "region": "Tokyo", "climate": "temperate", "status": "open"}

static func _view(open: bool, until_ms: float) -> Dictionary:
	return {"now": NOW, "travel": {"home": Pick.SF.id}, "home": {"city": Pick.SF.id, "name": "San Francisco", "pending": false,
		"change": {"open": open, "until": until_ms, "before_level": 5, "used": 0}}}

func after_test() -> void:
	P0HomePick.clear()

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)

func test_the_home_row_says_how_long_the_change_stays_open() -> void:
	assert_dict(P0HomePick.settings_row(_view(true, NOW + 4.2 * DAY), NOW)).is_equal(
		{name = "San Francisco", open = true, line = "Change once · 5 days left"})   # whole days, rounded up
	assert_str(str(P0HomePick.settings_row(_view(true, NOW + 0.3 * DAY), NOW).line)).is_equal("Change once · 1 day left")
	assert_dict(P0HomePick.settings_row(_view(false, NOW - DAY), NOW)).is_equal({name = "San Francisco", open = false, line = "Set for good"})
	assert_dict(P0HomePick.settings_row({}, NOW)).is_empty()   # no view yet: no Home group
	assert_str(P0HomePick.resets_line({"resets_day": "Thu"}, "Tokyo")).is_equal("Your day resets Thu 4 AM, Tokyo time.")
	assert_str(P0HomePick.resets_line({"resets_day": null}, "Tokyo")).is_empty()

func test_settings_lists_home_first_and_opens_the_change_while_it_is_open() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("dev", 0.0, 0.0, P0HomePick.settings_row(_view(true, NOW + 5 * DAY), NOW)))
	add_child(page)
	await await_idle_frame()
	assert_array(_labels(page.body).slice(0, 4)).is_equal(["Home", "Home city · San Francisco", "Change once · 5 days left", "›"])
	var said := []
	page.open_pressed.connect(func(w): said.append(w))
	(page.body.find_child("HomeCity", true, false).find_child("Hit", true, false) as Button).pressed.emit()
	assert_array(said).is_equal(["home"])

func test_set_for_good_is_read_only() -> void:
	var page: P0SettingsPage = auto_free(P0SettingsPage.settings("dev", 0.0, 0.0, P0HomePick.settings_row(_view(false, 0), NOW)))
	add_child(page)
	await await_idle_frame()
	var row := page.body.find_child("HomeCity", true, false)
	assert_array(_labels(row).filter(func(t): return t != "")).is_equal(["Home city · San Francisco", "Set for good"])   # no ›
	assert_object(row.find_child("Hit", true, false)).is_null()

func test_the_change_page_greys_the_home_and_picks_nothing() -> void:
	var page: Control = auto_free(PickPage.new(0.0, 0.0, Pick.SF.id))
	page.size = Vector2(360, 800)
	add_child(page)
	page.show_cities({"open": Pick.OPEN, "near": Pick.SF}, "")
	await await_idle_frame()
	assert_array(_labels(page)).contains(["Change home city", "Your farm and everything on it move with you.", "Your home city"])
	assert_bool(page.rows[Pick.SF.id].disabled).is_true()
	assert_bool(page.rows.values().any(func(r): return r.picked)).is_false()
	assert_str(page.key.reason).is_equal("Pick a city")
	var back := page.find_child("Back", true, false) as Button
	assert_str(back.text).is_equal("‹  Settings")
	var left := []
	page.back_pressed.connect(func(): left.append(1))
	back.pressed.emit()
	assert_array(left).is_equal([1])
	# HOME-CHANGE-PICK: the title at 72 and the field at 137, under the back pill
	assert_float((page.find_child("Title", false, false) as Control).position.y).is_equal(72.0)
	assert_float(page.field.position.y).is_equal(137.0)

func _change_flow(asked: Array) -> Array:
	var session := P0Session.new()
	session.transport = func(_m, path: String, _b, _c): asked.append(path)
	var flow: Control = auto_free(HomeFlow.new(session, 0.0, 0.0, Pick.SF.id))
	flow.size = Vector2(360, 800)
	add_child(flow)
	return [session, flow]

func test_a_spot_asks_first_and_move_farm_is_the_change() -> void:
	var asked := []
	var made := _change_flow(asked)
	var flow: Control = made[1]
	await await_idle_frame()
	flow.open_spots(TOKYO)
	assert_str(str(flow.spots.title.text)).is_equal("Change home city")
	P0HomePick.answer("/p0/home/spots/" + TOKYO.id, {"ok": true, "city": TOKYO.id, "spots": Pick.spots(), "resets_at": NOW + DAY, "resets_day": "Thu"})
	await await_idle_frame()
	var chose := []
	flow.chose.connect(func(c, s): chose.append([c, s]))
	flow.spots.cards[1].pressed.emit()
	flow.spots.build.activated.emit()
	assert_array(chose).is_empty()   # not yet: the card asks
	assert_object(flow.confirm).is_not_null()
	assert_array(_labels(flow.confirm)).contains(["Move your farm to Tokyo?",
		"Everything on your farm moves with you. You can't change your home city again.", "Your day resets Thu 4 AM, Tokyo time."])
	flow.confirm.cancel.activated.emit()
	await await_idle_frame()
	assert_object(flow.confirm).is_null()
	assert_bool(flow.spots.cards[1].picked).is_true()   # the spot page as it was
	flow.spots.build.activated.emit()
	flow.confirm.move.activated.emit()
	flow.confirm.move.activated.emit()   # one change on the wire at a time
	assert_array(chose).is_equal([[TOKYO.id, 1]])
	(made[0] as Node).free()

func test_back_closes_a_layer_at_a_time_then_leaves_for_settings() -> void:
	var made := _change_flow([])
	var flow: Control = made[1]
	var left := []
	flow.left.connect(func(): left.append(1))
	flow.open_spots(TOKYO)
	P0HomePick.answer("/p0/home/spots/" + TOKYO.id, {"ok": true, "city": TOKYO.id, "spots": Pick.spots()})
	flow.spots.chosen.emit(TOKYO.id, 0)
	assert_object(flow.confirm).is_not_null()
	flow.back()
	assert_object(flow.confirm).is_null()
	assert_object(flow.spots).is_not_null()
	flow.back()
	assert_object(flow.spots).is_null()
	assert_array(left).is_empty()
	flow.back()
	assert_array(left).is_equal([1])
	(made[0] as Node).free()

## A first pick's flow has nowhere before its city page: Back there does nothing.
func test_a_first_pick_stays_on_its_city_page() -> void:
	var session := P0Session.new()
	session.transport = func(_m, _p, _b, _c): pass
	var flow: Control = auto_free(HomeFlow.new(session))
	add_child(flow)
	var left := []
	flow.left.connect(func(): left.append(1))
	flow.back()
	assert_array(left).is_empty()
	assert_bool(flow.cities.visible).is_true()
	session.free()

## 周瑜 on #451 for the change: a lost reply, then a second Move farm refused — taken only when the view's home is the
## city asked for (a change is never pending, so that test alone would take any refusal).
func test_a_change_refused_is_taken_only_when_home_is_already_the_new_city() -> void:
	var moved := {"travel": {"home": TOKYO.id}, "home": {"city": TOKYO.id, "pending": false}}
	var stayed := {"travel": {"home": Pick.SF.id}, "home": {"city": Pick.SF.id, "pending": false}}
	assert_bool(P0Runtime.home_taken(false, moved, TOKYO.id)).is_true()
	assert_bool(P0Runtime.home_taken(false, stayed, TOKYO.id)).is_false()
	assert_bool(P0Runtime.home_taken(true, stayed, TOKYO.id)).is_true()

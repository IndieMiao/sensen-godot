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

## q(216) ⑨ (HOME-CHANGE-PICK 9:132751 / -SAME 92:164061): the home city reads and picks as any other, `Your home city`
## its third line; nothing picked when the page opens.
func test_the_change_page_lets_the_home_be_picked_and_picks_nothing() -> void:
	var page: Control = auto_free(PickPage.new(0.0, 0.0, Pick.SF.id))
	page.size = Vector2(360, 800)
	add_child(page)
	page.show_cities({"open": Pick.OPEN, "near": Pick.SF}, "")
	await await_idle_frame()
	assert_array(_labels(page)).contains(["Change home city", "Your farm and everything on it move with you.", "Your home city"])
	var home_row = page.rows[Pick.SF.id]
	assert_bool(home_row.disabled).is_false()
	assert_bool(home_row.grey).is_false()
	assert_bool(page.rows.values().any(func(r): return r.picked)).is_false()
	assert_str(page.key.reason).is_equal("Pick a city")
	home_row.pressed.emit()   # -SAME: the home city picked, Continue on
	assert_bool(home_row.picked).is_true()
	assert_str(page.key.reason).is_equal("")
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

func test_a_pin_asks_first_and_move_farm_is_the_change() -> void:
	var asked := []
	var made := _change_flow(asked)
	var flow: Control = made[1]
	await await_idle_frame()
	flow.open_spots(TOKYO)
	assert_str(str(flow.spots.title.text)).is_equal("Change home city")
	var read := Pick.spot_read(TOKYO.id)
	read.resets_at = NOW + DAY
	read.resets_day = "Thu"
	P0HomePick.answer("/p0/home/spots/" + TOKYO.id, read)
	await await_idle_frame()
	var chose := []
	flow.chose.connect(func(c, lat, lng): chose.append([c, lat, lng]))
	flow.spots.build.activated.emit()
	assert_array(chose).is_empty()   # not yet: the card asks
	assert_object(flow.confirm).is_not_null()
	# 0.2.9 (李元芳's run): a place pin's name rides above other pins (NAME_Z), and the card must draw over it too
	assert_int(flow.confirm.z_index).is_greater(UiMapDestination.NAME_Z)
	assert_array(_labels(flow.confirm)).contains(["Move your farm to Tokyo?",
		"Everything on your farm moves with you. You can't change your home city again.", "Your day resets Thu 4 AM, Tokyo time."])
	flow.confirm.cancel.activated.emit()
	await await_idle_frame()
	assert_object(flow.confirm).is_null()
	flow.spots.build.activated.emit()
	flow.confirm.move.activated.emit()
	flow.confirm.move.activated.emit()   # one change on the wire at a time
	assert_int(chose.size()).is_equal(1)
	assert_str(chose[0][0]).is_equal(TOKYO.id)
	assert_float(chose[0][1]).is_equal_approx(37.759, 1e-9)   # spot 1, as the server sent it (doubles)
	assert_float(chose[0][2]).is_equal_approx(-122.449, 1e-9)
	(made[0] as Node).free()

## q(216) ⑨ / q(223) (HOME-PIN-REPIN 92:164194): the home city itself — the pin starts on the farm as it stands, the
## back-to-start key takes it back there, and Build here asks the change card for the home city (one card, 78cbe60f).
func test_the_home_city_re_pins_from_the_farm_with_the_change_card() -> void:
	var made := _change_flow([])
	var session: P0Session = made[0]
	session.view = {"home": {"city": Pick.SF.id, "farm": {"lat": 37.751, "lng": -122.431}, "pending": false}}
	var flow: Control = made[1]
	await await_idle_frame()
	flow.open_spots(Pick.SF)
	assert_bool(flow.spots.same_city).is_true()
	P0HomePick.answer("/p0/home/spots/" + Pick.SF.id, Pick.spot_read(Pick.SF.id))
	await await_idle_frame()
	assert_float(float(flow.spots.at[0])).is_equal_approx(37.751, 1e-9)
	assert_float(float(flow.spots.at[1])).is_equal_approx(-122.431, 1e-9)
	assert_bool(flow.spots.back_key.visible).is_false()
	flow.spots.map.pan(Vector2(0, 60))
	flow.spots._refresh()
	assert_bool(flow.spots.back_key.visible).is_true()
	flow.spots.back_key.pressed.emit()
	assert_float(float(flow.spots.at[0])).is_equal_approx(37.751, 1e-9)
	flow.spots.build.activated.emit()
	assert_array(_labels(flow.confirm)).contains(["Move your farm to San Francisco?"])
	(made[0] as Node).free()

func test_back_closes_a_layer_at_a_time_then_leaves_for_settings() -> void:
	var made := _change_flow([])
	var flow: Control = made[1]
	var left := []
	flow.left.connect(func(): left.append(1))
	flow.open_spots(TOKYO)
	P0HomePick.answer("/p0/home/spots/" + TOKYO.id, Pick.spot_read(TOKYO.id))
	flow.spots.chosen.emit(35.68, 139.7)
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
	flow.back()   # before the first read (SGODOT-342: the list, or HOME-WELCOME, comes with it)
	assert_array(left).is_empty()
	await await_idle_frame()
	P0HomePick.answer("/p0/home/cities", {"ok": true, "open": [], "near": null, "matches": []})
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

## 周瑜 on #460: with the confirm card raised over the pin names, a toast or the system line said while it is up (Move
## farm refused, `Didn't go through`) still draws over it — not dimmed under its scrim, the banner's Retry in reach.
func test_toasts_and_the_system_line_stay_over_the_confirm_card() -> void:
	var ui := P0Ui.new()
	ui.quick_store = "user://test_p1_home_change_ui.json"
	ui.tips_path = "user://test_p1_home_change_tips.json"
	add_child(auto_free(ui))
	await await_idle_frame()
	var card := load("res://scenes/p0/panels/p0_home_move_confirm.gd").new("Tokyo", "") as Control
	ui.toast("Couldn't move your farm")
	ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through")
	assert_int(ui._toasts.z_index).is_greater(card.z_index)
	assert_int(ui._sys.z_index).is_greater(card.z_index)
	card.free()
	for f in ["user://test_p1_home_change_ui.json", "user://test_p1_home_change_tips.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

extends GdUnitTestSuite
## SGODOT-261 (the user's call, for the demo; 不知火舞 keeps 197): away from home the map's camera follows the player to
## the pond or outpost, and among many pins the homestead is hard to find. A home key over the recenter key — the same
## 44 round key, i-home, 12 apart — flies the camera back to the homestead and selects it, as a tap on its pin does
## (away: Go home · Free) and on the avatar at home (Back to Homestead). It gives way to an open sheet with the recenter key.
## SGODOT-267 (the user: no jump; 不知火舞): it flies the city's flight, 0.6–1.2 s, and selects on landing; a touch on the
## map stops it where it is with nothing selected, and a press of the key while it flies is ignored.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func _close(rt: P0Runtime) -> void:
	rt.ui.close_modal()
	await get_tree().process_frame

static func _primary(rt: P0Runtime) -> String:
	return str((rt.ui._modal.find_child("Primary", true, false) as UiCommandButton).label)

func _at_home(m: Node) -> void:
	assert_float(m.center_lat).is_equal_approx(m.home_lat, 1e-6)
	assert_float(m.center_lng).is_equal_approx(m.home_lng, 1e-6)
	assert_float(m.zoom).is_equal_approx(m.SHOW_ZOOM, 0.01)

func test_the_home_key_sits_over_the_recenter_key_and_gives_way_to_a_sheet() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var city: CityMapView = m.city_map
	var home: Button = city.home_key
	assert_bool(home.visible).is_true()
	assert_that(home.size).is_equal(city.recenter.size)
	assert_float(home.position.x).is_equal(city.recenter.position.x)   # right-aligned with it
	assert_float(city.recenter.position.y - home.get_rect().end.y).is_equal(CityMapView.RECENTER_GAP)   # 12 apart
	assert_object(home.icon).is_same(P0Logic.icon("home"))
	assert_str(String(home.theme_type_variation)).is_equal(String(city.recenter.theme_type_variation))   # the same key
	m._own_pin_pressed()   # a sheet opens: both keys give way (不知火舞 on 234 A2 / 261)
	m.p0_frame(rt.session.view, 0.0)
	assert_bool(home.visible).is_false()
	assert_bool(city.recenter.visible).is_false()
	await _close(rt)
	m.p0_frame(rt.session.view, 0.0)
	assert_bool(home.visible).is_true()

## Presses the home key and waits for the landing (the card): the seconds it took, or -1 if it never landed.
func _fly_home(m: Node) -> float:
	var started := Time.get_ticks_msec()
	m.city_map.home_key.pressed.emit()
	await _card(m)
	return (Time.get_ticks_msec() - started) / 1000.0 if m.rt.ui.modal_kind == "place_card" else -1.0

func _landed(m: Node) -> void:   # the map's own flight has landed, at most 2 s
	var until := Time.get_ticks_msec() + 2000
	while m._flight != null and m._flight.is_running() and Time.get_ticks_msec() < until: await get_tree().process_frame

func _card(m: Node) -> void:   # until a card opens, at most 2 s
	var until := Time.get_ticks_msec() + 2000
	while m.rt.ui.modal_kind != "place_card" and Time.get_ticks_msec() < until: await get_tree().process_frame

## From an outpost or a pond, back on the map: the camera is where the player is; the home key flies it home and on
## landing selects the Homestead pin — its card, as a tap on the pin. While it flies nothing is selected.
func test_away_the_home_key_flies_home_and_selects_the_homestead() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved: Dictionary = rt.here
	var city: CityMapView = m.city_map
	var tea := P0Outposts.by_role("tea")
	for here in [{"space": "outpost", "place": str(tea.id)}, {"space": "pond", "place": "pond_shanghai_05"}]:
		rt.here = here
		m._sync_here()
		m._city_action("recenter")   # the camera follows the player to the place
		await _landed(m)
		var from := Vector2(m.center_lat, m.center_lng)
		assert_float(from.distance_to(Vector2(m.home_lat, m.home_lng))).is_greater(1e-3)
		city.home_key.pressed.emit()
		await get_tree().create_timer(0.25).timeout   # a quarter of a second into a 0.6–1.2 s flight
		var mid := Vector2(m.center_lat, m.center_lng)
		assert_vector(mid).is_not_equal(from)   # on its way: not a jump, not standing still
		assert_float(mid.distance_to(Vector2(m.home_lat, m.home_lng))).is_greater(1e-5)
		assert_dict(city.selected).is_empty()   # selected only on landing
		assert_str(rt.ui.modal_kind).is_not_equal("place_card")
		await _card(m)
		_at_home(m)
		assert_str(str(city.selected.get("id", ""))).is_equal("home")
		assert_str(_primary(rt)).is_equal("Go home · Free")
		await _close(rt)
		assert_dict(city.selected).is_empty()   # closing the card clears the pin, as after a tap on it
	rt.here = saved
	m._sync_here()

## At home the key works the same: from anywhere on the map back to the homestead, with its card (Back to Homestead).
func test_at_home_the_home_key_brings_the_homestead_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var tea := P0Outposts.by_role("tea")
	m.fly_to(float(tea.lat), float(tea.lng))   # looking elsewhere in the city
	assert_float(await _fly_home(m)).is_greater(0.0)
	_at_home(m)
	assert_str(_primary(rt)).is_equal("Back to Homestead")
	await _close(rt)

## 0.35 s per unit of path between 0.6 and 1.2 s (不知火舞 on 267): across the city it still lands within 1.2 s, and a
## short hop takes no less than 0.6 s.
func test_the_flight_home_takes_0_6_to_1_2_s() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	m.fly_to(m.home_lat + 0.3, m.home_lng + 0.3)   # some 45 km off, zoomed out: a city's flight would take longer
	m._set_zoom(11.0)
	var far := await _fly_home(m)
	assert_float(far).is_between(0.6, 1.2 + 0.15)
	await _close(rt)
	m.fly_to(m.home_lat + 0.0005, m.home_lng)   # a street away
	var near := await _fly_home(m)
	assert_float(near).is_between(0.6 - 0.05, 1.2 + 0.15)
	await _close(rt)
	assert_float(MapFlight.plan(31.0, 121.0, 11.0, 31.3, 121.3, 15.0, 360.0).duration(1.2)).is_equal(1.2)   # capped
	assert_float(MapFlight.plan(31.0, 121.0, 15.0, 31.0001, 121.0, 15.0, 360.0).duration(1.2)).is_equal(0.6)

## A touch on the map while it flies (a tap, a drag, a pinch all start with a press) stops the camera where it is:
## no landing, nothing selected, no card.
func test_a_touch_stops_the_flight_where_it_is() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var tea := P0Outposts.by_role("tea")
	m.fly_to(float(tea.lat), float(tea.lng))
	m.city_map.home_key.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	var down := InputEventScreenTouch.new()
	down.position = Vector2(60, 300)
	down.pressed = true
	m._unhandled_input(down)
	var up := InputEventScreenTouch.new()
	up.position = down.position
	up.canceled = true   # lifted without a tap of its own
	m._unhandled_input(up)
	var stopped := Vector2(m.center_lat, m.center_lng)
	await get_tree().create_timer(1.5).timeout
	assert_vector(Vector2(m.center_lat, m.center_lng)).is_equal(stopped)   # where the touch stopped it
	assert_float(stopped.distance_to(Vector2(m.home_lat, m.home_lng))).is_greater(1e-5)   # short of home
	assert_dict(m.city_map.selected).is_empty()
	assert_str(rt.ui.modal_kind).is_not_equal("place_card")

## A press of the key while it flies is ignored: the same flight, landing when it would have.
func test_a_press_while_it_flies_is_ignored() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var tea := P0Outposts.by_role("tea")
	m.fly_to(float(tea.lat), float(tea.lng))
	var started := Time.get_ticks_msec()
	m.city_map.home_key.pressed.emit()
	var flight: Tween = m._flight
	await get_tree().create_timer(0.25).timeout
	m.city_map.home_key.pressed.emit()
	assert_object(m._flight).is_same(flight)
	assert_bool(flight.is_running()).is_true()
	await _card(m)
	assert_float((Time.get_ticks_msec() - started) / 1000.0).is_less(1.2 + 0.15)   # not started over
	_at_home(m)
	await _close(rt)

## Already over the homestead at its zoom: nothing to fly, the card at once.
func test_over_the_homestead_the_card_opens_at_once() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	m.fly_to(m.home_lat, m.home_lng)
	m._set_zoom(m.SHOW_ZOOM)
	m.city_map.home_key.pressed.emit()
	assert_str(rt.ui.modal_kind).is_equal("place_card")
	assert_str(_primary(rt)).is_equal("Back to Homestead")
	await _close(rt)

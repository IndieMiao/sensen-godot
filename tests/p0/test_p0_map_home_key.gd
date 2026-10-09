extends GdUnitTestSuite
## SGODOT-261 (the user's call, for the demo; 不知火舞 keeps 197): away from home the map's camera follows the player to
## the pond or outpost, and among many pins the homestead is hard to find. A home key over the recenter key — the same
## 44 round key, i-home, 12 apart — flies the camera back to the homestead and selects it, as a tap on its pin does
## (away: Go home · Free) and on the avatar at home (Back to Homestead). It gives way to an open sheet with the recenter key.

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

## From an outpost or a pond, back on the map: the camera is where the player is; the home key brings it home and
## selects the Homestead pin — its card, as a tap on the pin.
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
		assert_float(Vector2(m.center_lat, m.center_lng).distance_to(Vector2(m.home_lat, m.home_lng))).is_greater(1e-3)
		city.home_key.pressed.emit()
		_at_home(m)
		assert_str(str(city.selected.get("id", ""))).is_equal("home")
		assert_str(rt.ui.modal_kind).is_equal("place_card")
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
	m.city_map.home_key.pressed.emit()
	_at_home(m)
	assert_str(rt.ui.modal_kind).is_equal("place_card")
	assert_str(_primary(rt)).is_equal("Back to Homestead")
	await _close(rt)

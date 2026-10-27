extends GdUnitTestSuite
## SGODOT-342 PR-2, the free pin page (HOME-PIN row 102) on its own flat map: reading, failed, the pin on the start,
## dragged out of the circle or near a place, the card's line, the grey key and its toast, the back-to-start key, and
## Build here giving the pin's point.

const PinPage := preload("res://scenes/p0/panels/p0_home_pin_page.gd")
const P0HomePin := preload("res://modules/p0/p0_home_pin.gd")

const POND := {"id": "pond_fern_test", "name": "Fern Pond", "lat": 37.76, "lng": -122.44}
const START := {"lat": 37.76, "lng": -122.44909}   # 0.8 km west of the pond

static func _read() -> Dictionary:
	return {"ok": true, "city": "gn-5391959",
		"spots": [{"spot": 0, "lat": START.lat, "lng": START.lng, "km": 0.8, "toward": "west", "pond": POND, "hood": null}],
		"pin": {"base": {"lat": 37.76, "lng": -122.44}, "range_km": 10, "clear_m": 300, "start": START,
			"blocks": [{"id": "pond_fern_test", "lat": 37.76, "lng": -122.44}, {"id": "outpost_test_tea", "lat": 37.765, "lng": -122.45}]}}

func _page(same_city := false, farm: Variant = null) -> Control:
	var p: Control = auto_free(PinPage.new("gn-5391959", "San Francisco", "Pick your farm spot", 0.0, 0.0, same_city, farm))
	p.size = Vector2(360, 800)
	add_child(p)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.size = Vector2(360, 800)
	return p

func _texts(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return (l as Label).text)

func test_reading_shows_the_outline_and_keeps_build_grey_and_quiet() -> void:
	var p := _page()
	await await_idle_frame()
	assert_bool(p.loading_card.visible).is_true()
	assert_bool(p.pin.visible).is_false()
	assert_bool(p.card.visible).is_false()
	assert_bool(p.back_key.visible).is_false()
	assert_str(p.build.reason).is_equal("Build here")
	var said := []
	p.unavailable.connect(func(t): said.append(t))
	p.build.unavailable_pressed.emit("Build here")
	assert_array(said).is_empty()   # no toast (6cb4d10e)
	assert_array(_texts(p)).contains(["Pick your farm spot", "San Francisco"])

func test_a_failed_read_or_a_missing_pin_is_the_error_card() -> void:
	var p := _page()
	p.show_failed()
	assert_bool(p.error_card.visible).is_true()
	assert_bool(p.loading_card.visible).is_false()
	assert_array(_texts(p)).contains(["Couldn't load farm spots"])
	assert_object(p.error_card.find_child("Retry", true, false)).is_not_null()
	var retried := []
	p.retry_pressed.connect(func(): retried.append(1))
	(p.error_card.find_child("Retry", true, false) as UiCommandButton).activated.emit()
	assert_array(retried).has_size(1)
	assert_bool(p.loading_card.visible).is_true()
	var older := _read()
	older.erase("pin")   # an older server: no pin (周瑜 on #473)
	p.show_area(older)
	assert_bool(p.error_card.visible).is_true()

func test_the_pin_starts_on_spot_one_and_may_build_at_once() -> void:
	var p := _page()
	p.show_area(_read())
	await await_idle_frame()
	assert_float(float(p.at[0])).is_equal_approx(START.lat, 1e-9)
	assert_float(float(p.at[1])).is_equal_approx(START.lng, 1e-9)
	assert_str(p.line.text).is_equal("0.8 km to Fern Pond · west")
	assert_str(p.build.reason).is_equal("")
	assert_bool(p.back_key.visible).is_false()   # on the start
	# HOME-PIN-1: the tip in the middle of the map between the panel (safe + 112) and the card (620): 180, 378 with the
	# frame's 24 safe area, 366 with none
	assert_vector(p.pin.position + PinPage.Pin.TIP).is_equal(Vector2(180, 366))
	var built := []
	p.chosen.connect(func(lat, lng): built.append([lat, lng]))
	p.build.activated.emit()
	assert_float(float(built[0][0])).is_equal_approx(START.lat, 1e-9)

func test_out_of_the_circle_the_key_says_why_and_the_card_keeps_its_line() -> void:
	var p := _page()
	p.show_area(_read())
	(p.map as PinPage.FlatMap).pick_put(37.86, -122.44, p.tip())   # about 11 km north of the base
	p._refresh()
	assert_str(p.build.reason).is_equal("Too far from the city")
	assert_str(p.line.text).is_equal("11 km to Fern Pond · north")   # HOME-PIN-4: the line stays (fdf7c5df)
	assert_bool(p.back_key.visible).is_true()
	var said := []
	p.unavailable.connect(func(t): said.append(t))
	p.build.unavailable_pressed.emit(p.build.reason)
	assert_array(said).is_equal(["Move the pin back inside the circle."])
	var built := []
	p.chosen.connect(func(lat, lng): built.append(lat))
	p.build.activated.emit()
	assert_array(built).is_empty()
	p.back_key.pressed.emit()   # back to the start: may build again, the key hides
	assert_str(p.build.reason).is_equal("")
	assert_bool(p.back_key.visible).is_false()

func test_near_a_place_the_key_names_it_and_its_ring_shows() -> void:
	var p := _page()
	p.show_area(_read())
	p.names["outpost_test_tea"] = {"name": "Oak Tea House", "kind": "shop"}
	(p.map as PinPage.FlatMap).pick_put(37.7655, -122.45, p.tip())   # 56 m from the tea house
	p._refresh()
	assert_str(p.build.reason).is_equal("Too close to Oak Tea House")
	assert_array(P0HomePin.shown_blocks(p.area, Vector2(p.at[0], p.at[1])).map(func(b): return b.id)).contains(["outpost_test_tea"])
	var said := []
	p.unavailable.connect(func(t): said.append(t))
	p.build.unavailable_pressed.emit(p.build.reason)
	assert_array(said).is_equal(["Leave some room around ponds and shops."])
	# a name too long for the key: the general word
	p.names["outpost_test_tea"] = {"name": "The Very Long Named Riverside Lantern Tea House", "kind": "shop"}
	p._refresh()
	assert_str(p.build.reason).is_equal("Too close to a shop")

func test_dragging_lifts_the_pin_and_fades_the_card() -> void:
	var p := _page()
	p.show_area(_read())
	var f := p.map as PinPage.FlatMap
	f.dragging = true
	f.pan(Vector2(60, 0))
	p._refresh()
	assert_float(p.card.modulate.a).is_equal(0.5)
	assert_bool(p.pin.lifted).is_true()
	f.dragging = false
	p._refresh()
	assert_float(p.card.modulate.a).is_equal(1.0)
	assert_bool(p.pin.lifted).is_false()

func test_a_same_city_re_pin_starts_on_the_farm() -> void:
	var farm := [37.75, -122.43]
	var p := _page(true, farm)
	p.show_area(_read())
	assert_float(float(p.at[0])).is_equal_approx(37.75, 1e-4)
	assert_float(float(p.at[1])).is_equal_approx(-122.43, 1e-4)
	assert_bool(p.back_key.visible).is_false()
	(p.map as PinPage.FlatMap).pan(Vector2(0, 80))
	p._refresh()
	assert_bool(p.back_key.visible).is_true()
	p.back_key.pressed.emit()   # q(223): back to the farm, not spot 1
	assert_float(float(p.at[0])).is_equal_approx(37.75, 1e-4)

## A real map stand-in: the flat map's geometry, not a FlatMap (so the page treats it as the native one), with ground.
class GroundMap extends RefCounted:
	var flat := PinPage.FlatMap.new()
	var ground := true
	var settling := false
	func pick_settling() -> bool: return settling
	func pick_geo_at(s: Vector2) -> Array: return flat.pick_geo_at(s)
	func pick_screen_of(lat: float, lng: float) -> Variant: return flat.pick_screen_of(lat, lng)
	func pick_put(lat: float, lng: float, s: Vector2) -> void: flat.pick_put(lat, lng, s)
	func pick_dragging() -> bool: return settling
	func pick_px_per_m() -> float: return flat.px_per_m
	func pick_has_ground() -> bool: return ground

## 不知火舞 342 (q(133) ①): over the real map the page draws the map's credit line, 16 pt from the left, 6 pt over the
## card; not while reading or failed, not without ground, not on the page's own flat map.
func test_the_credit_line_rides_over_the_card_on_the_real_map_only() -> void:
	var flat := _page()
	flat.show_area(_read())
	await await_idle_frame()
	assert_bool(flat.credits.visible).is_false()   # the flat map (the desktop) has no Mapbox to credit
	var m := GroundMap.new()
	var p: Control = auto_free(PinPage.new("gn-5391959", "San Francisco", "Pick your farm spot", 0.0, 0.0, false, null, m))
	add_child(p)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.size = Vector2(360, 800)
	await await_idle_frame()
	assert_bool(p.credits.visible).is_false()   # reading
	p.show_area(_read())
	await await_idle_frame()
	assert_bool(p.credits.visible).is_true()
	assert_str(p.credits.text).is_equal("© Mapbox © OpenStreetMap")
	assert_float(p.credits.position.x).is_equal(CityMapView.CREDITS_LEFT_PT)
	assert_float(p.credits.position.y + p.credits.size.y).is_equal_approx(p.card.position.y - CityMapView.CREDITS_GAP_PT, 0.5)
	assert_float(p.credits.get_theme_color(&"font_color").a).is_equal_approx(CityMapView.CREDITS_ALPHA, 0.01)
	m.ground = false   # the native map not drawn yet
	p._refresh()
	assert_bool(p.credits.visible).is_false()
	m.ground = true
	p.show_failed()
	assert_bool(p.credits.visible).is_false()

## 不知火舞 342 (亚瑟 on #495 ②): the map sliding on after the finger lifted keeps the pin up, the card at 50 % with its
## line as it was and the key unchanged; settled, both are read again. Build here does nothing till then.
func test_while_the_map_slides_on_the_card_and_key_wait_for_it_to_settle() -> void:
	var m := GroundMap.new()
	var p: Control = auto_free(PinPage.new("gn-5391959", "San Francisco", "Pick your farm spot", 0.0, 0.0, false, null, m))
	add_child(p)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.size = Vector2(360, 800)
	p.show_area(_read())
	await await_idle_frame()
	var line_before: String = p.line.text
	assert_str(p.build.reason).is_equal("")
	m.settling = true
	m.flat.pick_put(37.7655, -122.45, p.tip())   # slid next to the tea house
	p._refresh()
	assert_str(p.line.text).is_equal(line_before)
	assert_str(p.build.reason).is_equal("")
	assert_float(p.card.modulate.a).is_equal(PinPage.DRAG_FADE)
	assert_bool(p.pin.lifted).is_true()
	var chose := []
	p.chosen.connect(func(lat, lng): chose.append([lat, lng]))
	p.build.activated.emit()
	assert_array(chose).is_empty()
	m.settling = false
	p._refresh()
	assert_str(p.build.reason).starts_with("Too close to")
	assert_str(p.line.text).is_not_equal(line_before)
	assert_float(p.card.modulate.a).is_equal(1.0)

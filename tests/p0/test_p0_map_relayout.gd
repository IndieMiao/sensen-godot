extends GdUnitTestSuite
## SGODOT-260 (蒙恬 on demo 02): over a busy street a still map fell from 89.5 to 30 fps once the phone warmed up. It
## laid its pins out every frame (CityMapView._update_markers, 2.9 ms a frame on a desktop with 100 POIs), and the sort
## in it made each candidate's key twice per comparison. A1: each key is made once, the same order. A2: the pins are laid
## out again only when something the layout reads changes (CityMapView._layout_wanted), and until the layout settles.
## Every frame here is a real one (MapPoc._process → CityMapView.tick). A layout replaces CityMapView._shown_last, so a
## frame that kept the old one laid nothing out.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const TEA := "sh_tea_1"   # an outpost pin: always shown on screen (q(72))

var viewport: SubViewport
var map: Node
var city: CityMapView
var rt: P0Runtime

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}
	viewport = SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	map = (load(P0_MAP) as PackedScene).instantiate()
	viewport.add_child(map)
	for i in 5: await get_tree().process_frame
	city = map.city_map
	rt = map.rt
	rt.session.view = {"skills": {"fishing": {"level": 1}}, "map_markers": []}   # a received view: the map's frame runs
	# Over the Tea House at street level, with the POIs of a busy street around it (Mapbox sends up to 100 a request).
	var tea := P0Outposts.find(TEA)
	_look(float(tea.lat), float(tea.lng))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pois := []
	for i in 60:
		pois.append({"id": "poi%d" % i, "name": "Place %d" % i, "maki": ["restaurant", "cafe", "shop", "park", "museum"][i % 5],
			"lat": float(tea.lat) + rng.randf_range(-0.003, 0.003), "lng": float(tea.lng) + rng.randf_range(-0.003, 0.003)})
	city._merge_pois(CityMapData.normalize(pois))
	await _settle()

func after_test() -> void:
	TranslationServer.set_locale("en")
	AppRouter._navigation_pending = false
	if is_instance_valid(map) and map.rt and map.rt.ui.has_modal(): map.rt.ui.close_modal()
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _look(lat: float, lng: float) -> void:
	map.center_lat = lat
	map.center_lng = lng
	map.zoom = 16.0
	map.bearing = 0.0
	map._camera_dirty = true

func _settle() -> void:
	for i in 12: await get_tree().process_frame

## Until the farm markers' pop-ins are over. They run on time (0.22 s), so a frame count waits less the faster the
## screen refreshes: 40 frames are 0.33 s at 120 Hz but 0.17 s at 240 Hz, the name still growing (2 s at most).
func _pops_done(fm: FarmMarkers) -> void:
	var until := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < until and fm._pin_tweens.values().any(func(t): return t is Tween and (t as Tween).is_running()):
		await get_tree().process_frame

## Whether `change` makes the next frames lay the pins out (from a settled, still map).
func _lays_out(change: Callable, frames := 2) -> bool:
	await _settle()
	var before: Dictionary = city._shown_last
	change.call()
	for i in frames: await get_tree().process_frame
	return not is_same(city._shown_last, before)

func _entry(id: String) -> Dictionary:
	return (city.entries + city.live_pois).filter(func(e): return str(e.get("id", "")) == id)[0]

# ---------------------------------------------------------------- still

## The bug: a still map laid its pins out every frame. Settled, it lays out nothing over half a second.
func test_a_still_map_lays_its_pins_out_once() -> void:
	assert_array(city.displayed).is_not_empty()
	var before: Dictionary = city._shown_last
	for i in 30: await get_tree().process_frame
	assert_bool(is_same(city._shown_last, before)).override_failure_message("a still map laid its pins out again").is_true()
	assert_bool(city._layout_settling).is_false()

## A layout that changes which pins show runs again (a pin shown last time packs with a smaller margin) until the pins
## shown stop changing — and where it stops is where laying out every frame ends up.
func test_a_layout_runs_until_the_pins_shown_settle() -> void:
	await _settle()
	var before := city._shown_last.keys()
	map.center_lng += 0.0015   # about 140 m: other pins come in
	map._camera_dirty = true
	await get_tree().process_frame
	assert_array(city._shown_last.keys()).is_not_equal(before)
	assert_bool(city._layout_settling).is_true()   # the pins shown changed: one more layout is due
	await _settle()
	assert_bool(city._layout_settling).is_false()
	var settled := city._shown_last.duplicate()
	city._update_markers()   # what one more frame laying out would show
	assert_dict(city._shown_last).is_equal(settled)

## A pin culled at a boundary may not come back before its cooldown (REAPPEAR_COOLDOWN_MS): when the first cooldown
## runs out the pins are laid out again, the map still.
func test_a_cooldown_running_out_lays_the_pins_out() -> void:
	await _settle()
	city._hidden_until["poi_gone"] = Time.get_ticks_msec() + 150
	city._update_markers()   # the layout that set it
	var before: Dictionary = city._shown_last
	for i in 2: await get_tree().process_frame
	assert_bool(is_same(city._shown_last, before)).override_failure_message("laid out before the cooldown ran out").is_true()
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	assert_bool(is_same(city._shown_last, before)).override_failure_message("the cooldown ran out unseen").is_false()

## A portrait drawn while the map is still still reaches the selected pin's card (_show_selected_art every frame).
func test_a_portrait_drawn_while_still_reaches_its_card() -> void:
	city.select({"kind": "resident", "id": "res_late", "name": "Late", "lat": map.center_lat, "lng": map.center_lng})
	await _settle()
	var face := MapPortrait.new()
	face.portrait = TextureRect.new()
	face.portrait.texture = PlaceholderTexture2D.new()
	face._desired_key = "drawn"
	face._shown_key = "drawn"
	city.markers["res_late"] = {"portrait": face, "node": Control.new()}
	var before: Dictionary = city._shown_last
	for i in 2: await get_tree().process_frame
	assert_bool(is_same(city._shown_last, before)).is_true()   # still: no layout
	assert_object(city.info_art.texture).is_same(face.portrait.texture)
	var mk: Dictionary = city.markers["res_late"]
	city.markers.erase("res_late")
	(mk.node as Node).free()
	face.portrait.free()
	face.free()
	city.clear_selection()

# ---------------------------------------------------------------- the camera

func test_panning_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map.center_lng += 0.0002; map._camera_dirty = true)).is_true()

func test_zooming_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map.zoom += 0.3; map._camera_dirty = true)).is_true()

## A pinch past the zoom limits overshoots and springs back (MapPoc._zoom_elastic) with the zoom itself unchanged.
func test_a_zoom_spring_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map._zoom_elastic = 0.2; map._camera_dirty = true)).is_true()

func test_rotating_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map.bearing += 15.0; map._camera_dirty = true)).is_true()

func test_tilting_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map.pitch -= 5.0; map._camera_dirty = true)).is_true()

## The home key (SGODOT-261): the camera flies home and the homestead's card opens.
func test_the_home_key_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map.go_home_view())).is_true()

# ---------------------------------------------------------------- the view

func test_resizing_the_view_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): viewport.size = Vector2i(360, 740))).is_true()

## The view moves on screen (a safe area, a host's inset): the same camera, the pins at other points in it.
func test_moving_the_view_lays_the_pins_out() -> void:
	var at := city.global_position
	assert_bool(await _lays_out(func(): city.position += Vector2(0, 30))).is_true()
	assert_vector(city.global_position).is_not_equal(at)

## The names change with the language (CityMapView._name): switched with the map still.
func test_switching_the_language_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): TranslationServer.set_locale("zh_CN"))).is_true()

# ---------------------------------------------------------------- the pins' data

func test_selecting_and_deselecting_lay_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): city.select(_entry(TEA)))).is_true()
	assert_float(float(city.markers[TEA].rect.size.x)).is_greater(UiMapDestination.DISC)   # packs at its selected size
	assert_bool(await _lays_out(func(): city.clear_selection())).is_true()

## A server reply (P0: the view replaced) that marks a pin packed away: the marks arrive (set_marks) and a marked pin
## always goes in (不知火舞 on 234 A2), so it shows.
func test_a_server_reply_that_marks_a_pin_lays_the_pins_out() -> void:
	await _settle()
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var hidden: Array = city.live_pois.filter(func(e):
		var p = map.geo_to_screen(float(e.lat), float(e.lng))
		return not city._shown_last.has(str(e.id)) and p != null and screen.grow(-40).has_point(p))
	assert_array(hidden).is_not_empty()
	var poi := str(hidden[0].id)
	var saved := rt.session.view
	var marked := saved.duplicate(true)
	marked["map_markers"] = [{"place": poi, "kind": "request"}]
	assert_bool(await _lays_out(func(): rt.session.view = marked, 3)).is_true()
	assert_bool(city._shown_last.has(poi)).override_failure_message("the marked pin is still packed away").is_true()
	rt.session.view = saved

## The outposts' online counts (P0 presence): their pins are replaced (set_places) and their count says the new one
## (q(137) ③: the top-right count).
func test_new_online_counts_lay_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map._online[TEA] = 3; map._set_outpost_places())).is_true()
	assert_int((city.markers[TEA].dest as UiMapDestination).online).is_equal(3)
	map._online.erase(TEA)
	map._set_outpost_places()

func test_new_pois_lay_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): city._merge_pois(CityMapData.normalize([{"id": "poi_new", "name": "New Cafe",
		"maki": "cafe", "lat": map.center_lat + 0.0004, "lng": map.center_lng}])))).is_true()

func test_a_filter_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): city.set_filter("pond"))).is_true()
	assert_bool(await _lays_out(func(): city.set_filter(""))).is_true()

## A city switch (Journey; P0 stays in Shanghai, P0Map._switch_city): the city view's entries are the new city's.
func test_a_city_switch_lays_the_pins_out() -> void:
	var saved: Dictionary = map.region
	# Another city (since SGODOT-275 the city list is the one around the camera, so name one).
	var other: Array = [FarmRegions.load_default().region("los_angeles")]
	assert_str(str(other[0].get("id", ""))).is_not_equal(str(saved.get("id", "")))
	assert_bool(await _lays_out(func(): map.region = other[0]; city.region_changed())).is_true()
	map.region = saved
	city.region_changed()

## The player's own avatar moves on screen (the pins give way to it): the camera still.
func test_the_players_own_pin_moving_lays_the_pins_out() -> void:
	assert_bool(await _lays_out(func(): map.set_self_at(map.center_lat + 0.0003, map.center_lng), 3)).is_true()

## The player's own name shows or folds with the map still (its own yield, the last layout's): space pins give way to
## the body with its name while shown (SGODOT-269), so the pins are laid out again (亚瑟 on #189).
func test_the_players_own_name_folding_lays_the_pins_out() -> void:
	var fm: FarmMarkers = map.farm_markers
	_look(map.home_lat, map.home_lng)   # the avatar and its name on screen
	await _settle()
	assert_bool((fm._buttons["self"] as Control).visible).is_true()
	await _pops_done(fm)   # its name pops in, scaled by the zoom boost
	assert_bool(await _lays_out(func(): pass)).is_false()   # settled: nothing to lay out
	assert_bool(await _lays_out(func(): fm.yield_self_label(true))).is_true()
	fm.yield_self_label(false)

# ---------------------------------------------------------------- A1: the packing order

## Each candidate's key is made once: the order is the one the comparison made, with a selection, marks and pins shown
## last time all counting.
func test_the_packing_order_is_unchanged() -> void:
	var marked := rt.session.view.duplicate(true)
	marked["map_markers"] = [{"place": TEA, "kind": "request"}, {"place": "pond_san_francisco_03", "kind": "new"}]
	rt.session.view = marked
	city.select(_entry("poi7"))
	await _settle()
	var seen := {}
	var candidates := []
	for e in city.entries + city.live_pois:
		if seen.has(str(e.id)): continue
		seen[str(e.id)] = true
		candidates.append({"entry": e, "id": str(e.id)})
	assert_int(candidates.size()).is_greater(50)
	var before := candidates.duplicate()
	before.sort_custom(func(a, b): return city._pack_key(a) < city._pack_key(b))
	var after := candidates.duplicate()
	city._pack_order(after)
	assert_array(after.map(func(c): return c.id)).is_equal(before.map(func(c): return c.id))
	city.clear_selection()

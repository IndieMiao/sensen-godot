extends GdUnitTestSuite
## SGODOT-261 (用户 via 奕星): the map's space pins — every MapDestination: ponds, the four outposts by role and the
## Homestead pin away from home — did not grow when tapped as the other pins do, and jumped when Go entered the place.
## Selecting one now plays the same jelly as every pin (CityMapView._animate_focus scaling the whole marker), and the
## shrink back after a close or Go is smooth. The jump: the pin ignored the jelly only while it was selected, and the
## selection is cleared at once when the card closes, so the first frame of the shrink drew the disc at FOCUS_SCALE.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
## One pin of each kind: a pond, the outposts by role, and the farm's own pin (drawn while the player is away).
const PINS := ["pond_shanghai_05", "sh_tea_1", "sh_tackle_1", "sh_market_1", "sh_post_1", "home"]

var map: Node

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	# Away at a pond, so the Homestead pin is on the map too (P0 map: at home the avatar is the farm's mark).
	P0Runtime.ensure().here = {"space": "pond", "place": "pond_shanghai_01"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	map = (load(P0_MAP) as PackedScene).instantiate()
	viewport.add_child(map)
	for i in 3: await get_tree().process_frame
	map.set_process(false)   # the test moves the camera itself
	map._sync_here()
	map._set_outpost_places()

func after_test() -> void:
	AppRouter._navigation_pending = false
	if is_instance_valid(map) and map.rt and map.rt.ui.has_modal(): map.rt.ui.close_modal()
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after() -> void:
	P0Runtime.free_instance_for_tests()

## The pin on screen at street level, settled in (not still popping in).
func _pin(id: String) -> Dictionary:
	var city: CityMapView = map.city_map
	var entry: Dictionary = city.entries.filter(func(e): return str(e.get("id", "")) == id)[0]
	map.center_lat = float(entry.lat)
	map.center_lng = float(entry.lng)
	map.zoom = 15.0
	map.bearing = 0.0
	map._update_cameras()
	map._sync_farm_markers()
	city._update_markers()
	var marker: Dictionary = city.markers[id]
	assert_object(marker.get("dest")).is_instanceof(UiMapDestination)
	if marker.get("pop_tween") is Tween: (marker.pop_tween as Tween).kill()
	marker.pop = 1.0
	city._apply_marker_scale(marker)
	return marker

## The pin's drawn scale on each frame for `seconds`: [whole pin (the marker's node), its disc alone].
func _record(marker: Dictionary, seconds: float) -> Array:
	var out := []
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		out.append([(marker.node as Control).scale.x, (marker.dest as UiMapDestination).focus])
	return out

static func _wholes(frames: Array) -> Array: return frames.map(func(f): return snappedf(float(f[0]), 0.001))

## Tapping a pin (CityMapView.select, what a tap on it calls): the whole pin grows to FOCUS_SCALE with the jelly every
## pin plays — its scale is the marker's focus on every frame, as a landmark's or a POI's — and the disc does not
## grow inside it on its own.
func test_each_space_pin_grows_when_selected_as_every_pin_does() -> void:
	var city: CityMapView = map.city_map
	for id in PINS:
		var marker := _pin(id)
		city.select(marker.entry)
		var frames := await _record(marker, 0.4)
		for f in frames: assert_float(float(f[1])).override_failure_message("%s: its disc scaled alone" % id).is_equal_approx(1.0, 1e-6)
		assert_float(float(frames[-1][0])).override_failure_message("%s did not grow: %s" % [id, _wholes(frames)]) \
			.is_equal_approx(CityMapView.FOCUS_SCALE, 0.001)
		assert_float((marker.node as Control).scale.x).is_equal_approx(float(marker.focus), 1e-6)   # the shared jelly
		city.clear_selection()
		await _record(marker, 0.25)
		if map.rt.ui.has_modal(): map.rt.ui.close_modal()
		await get_tree().process_frame

## Show on map flies and selects before the pin is made (the map just opened, or the place was off screen): the pin
## plays the same jelly once it is made, as on a tap.
func test_a_space_pin_selected_before_it_is_made_grows_once_made() -> void:
	var city: CityMapView = map.city_map
	for id in PINS:
		_pin(id)
		city._free_marker(id)
		city.markers.erase(id)
		city.select(city.entries.filter(func(e): return str(e.get("id", "")) == id)[0])   # no pin yet: nothing to scale
		city._update_markers()   # the pin is made, selected
		var marker: Dictionary = city.markers[id]
		var frames := await _record(marker, 0.45)
		assert_float(float(frames[-1][0])).override_failure_message("%s did not grow once made: %s" % [id, _wholes(frames)]) \
			.is_equal_approx(CityMapView.FOCUS_SCALE, 0.001)
		city.clear_selection()
		await _record(marker, 0.25)
		if map.rt.ui.has_modal(): map.rt.ui.close_modal()
		await get_tree().process_frame

## The same focus draws a space pin and a landmark at the same scale: one selection look for every pin.
func test_a_space_pin_and_a_landmark_scale_alike() -> void:
	var city: CityMapView = map.city_map
	var marker := _pin("sh_tea_1")
	var art := {"node": Control.new(), "focus": CityMapView.FOCUS_SCALE, "pop": 1.0}
	add_child(auto_free(art.node))
	marker.focus = CityMapView.FOCUS_SCALE
	city._apply_marker_scale(marker)
	city._apply_marker_scale(art)
	assert_float((marker.node as Control).scale.x).is_equal_approx((art.node as Control).scale.x, 1e-6)
	marker.focus = 1.0
	city._apply_marker_scale(marker)

## Closing the card (×, a tap outside, Back): the pin shrinks back smoothly — never larger than the frame before, the
## disc never alone — and ends at its own size.
func test_each_space_pin_shrinks_back_smoothly_when_deselected() -> void:
	var city: CityMapView = map.city_map
	for id in PINS:
		var marker := _pin(id)
		city.select(marker.entry)
		await _record(marker, 0.4)
		map.rt.ui.close_modal()   # the card's × / a tap outside: its close clears the selection
		var frames := await _record(marker, 0.3)
		assert_dict(city.selected).is_empty()
		_assert_smooth_shrink(id, frames)

## Go on the card: the pin shrinks back smoothly as the place opens (int12: it jumped). Navigation is held so the test
## stays on the map: Go's own work up to opening the place runs as on a tap.
func test_each_space_pin_shrinks_back_smoothly_on_go() -> void:
	var city: CityMapView = map.city_map
	for id in PINS:
		var marker := _pin(id)
		city.select(marker.entry)
		await _record(marker, 0.4)
		var go := map.rt.ui._modal.find_child("Primary", true, false) as UiCommandButton
		assert_object(go).override_failure_message("%s: no Go on its card" % id).is_not_null()
		AppRouter._navigation_pending = true   # Go goes as far as the router
		go.activated.emit()   # what a tap on Go sends
		var frames := await _record(marker, 0.3)
		AppRouter._navigation_pending = false
		assert_bool(map.rt.ui.has_modal()).is_false()
		_assert_smooth_shrink(id, frames)

func _assert_smooth_shrink(id: String, frames: Array) -> void:
	var last := CityMapView.FOCUS_SCALE + 0.001
	for f in frames:
		assert_float(float(f[1])).override_failure_message("%s jumped: its disc drew at %.3f alone" % [id, float(f[1])]) \
			.is_equal_approx(1.0, 1e-6)
		assert_float(float(f[0])).override_failure_message("%s grew while shrinking: %s" % [id, _wholes(frames)]) \
			.is_less_equal(last + 1e-6)
		last = float(f[0])
	assert_float(float(frames[0][0])).override_failure_message("%s was not at its selected size: %s" % [id, _wholes(frames)]) \
		.is_greater(1.2)
	assert_float(last).is_equal_approx(1.0, 1e-6)

## Today's Show on map still pulses only a space pin's disc (Figma 1802:118612); a selection after it scales the pin.
func test_show_on_map_still_pulses_only_the_disc() -> void:
	var city: CityMapView = map.city_map
	var marker := _pin("sh_market_1")
	city.pulse_pin("sh_market_1", 0.4)
	var frames := await _record(marker, 0.3)
	assert_float(frames.map(func(f): return float(f[1])).max()).is_greater(1.05)   # the disc pulsed
	for f in frames: assert_float(float(f[0])).is_equal_approx(1.0, 1e-6)   # the name kept its size
	await _record(marker, 0.2)
	city.select(marker.entry)
	await _record(marker, 0.4)
	assert_float((marker.node as Control).scale.x).is_equal_approx(CityMapView.FOCUS_SCALE, 0.001)
	assert_float((marker.dest as UiMapDestination).focus).is_equal_approx(1.0, 1e-6)

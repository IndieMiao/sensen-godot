extends GdUnitTestSuite
## int11 / int12 hand test: the map ran slow and hot. CityMapView._update_markers runs every frame, and since the pond
## pins' names came from P0 (pin_tag → _pond_info) and their marks from city_pin_markers, each frame copied the whole
## view several times (P0Session.current() is a deep copy, P0Logic.project): 1.17 ms a frame on a desktop against
## int9's 0.27. The map's per-frame paths read the received view as it is; only the runtime projects it, once a frame.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

class _Counting extends P0Session:   # counts the copies the map asks for
	var copies := 0
	func current() -> Dictionary:
		copies += 1
		return super.current()

var map: Node

func before() -> void:
	P0Runtime.ensure().here = {"space": "home", "place": ""}
	map = (load(P0_MAP) as PackedScene).instantiate()
	add_child(map)
	for i in 5: await get_tree().process_frame

func after() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()
	if is_instance_valid(map): map.free()
	P0Runtime.free_instance_for_tests()

func test_the_maps_per_frame_paths_copy_no_view() -> void:
	var rt := map.get("rt") as P0Runtime
	var before_session := rt.session
	var counting := _Counting.new()
	counting.view = {"skills": {"fishing": {"level": 1}}, "map_markers": []}   # a received view: current() would copy it
	counting._received_ms = Time.get_ticks_msec() - 5000
	rt.session = counting
	var city: CityMapView = map.get("city_map")
	var ponds: Array = city.entries.filter(func(e): return str(e.get("kind", "")) == "pond")
	assert_array(ponds).is_not_empty()
	for e in ponds: assert_str(city._dest_text(e)).is_not_empty()   # a pond pin's short name (q(137)), from its style
	city._update_markers()
	map.call("city_pin_markers")
	assert_int(counting.copies).is_equal(0)
	rt.session = before_session
	counting.free()

## The pins' fields are set every frame: an unchanged plate keeps its style box (no restyle, no relayout) and a name is
## measured once.
func test_a_destination_pin_restyles_only_on_a_change() -> void:
	var pin := UiMapDestination.new(null, "Reed Pond · Beginner pond · 0.8 km", true)
	add_child(auto_free(pin))
	var box := pin._label_box.get_theme_stylebox(&"panel")
	pin.plate = true
	assert_object(pin._label_box.get_theme_stylebox(&"panel")).is_same(box)
	pin.plate = false
	assert_object(pin._label_box.get_theme_stylebox(&"panel")).is_not_same(box)
	var size := UiMapDestination.label_size_for("Tea House")
	assert_vector(UiMapDestination.label_size_for("Tea House")).is_equal(size)
	assert_bool(UiMapDestination._label_sizes.has("Tea House|p")).is_true()
	# a short name is measured once too (q(137)), apart from the plate's
	assert_vector(UiMapDestination.label_size_for("Tea House", false)).is_equal(UiMapDestination.label_size_for("Tea House", false))
	assert_bool(UiMapDestination._label_sizes.has("Tea House|s")).is_true()

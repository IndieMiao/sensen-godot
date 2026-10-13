extends GdUnitTestSuite
## h1 (the user on 10-13 via 奕星; 不知火舞 on 279): every pin and city bubble comes and goes as the POI art does (7dbe7eb)
## — out of its point in 0.22 s (TRANS_BACK), into it in 0.12 s (TRANS_QUAD) — and only when it really shows or hides.
## The bubble or pin itself is placed whole (or hidden) at once, for its tap and everything that reads its rect; a ghost
## does the moving. A going pin's ghost is its disc alone: its name and marks go at once.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Outposts := preload("res://modules/p0/p0_outposts.gd")

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func _look(m: Node, lat: float, lng: float, z: float) -> void:
	m.center_lat = lat
	m.center_lng = lng
	m._set_zoom(z)
	m.pitch = 0.0
	m._zoom_elastic = 0.0

func _home_bubble(city: CityMapView) -> Dictionary:
	for id in city.bubbles:
		if str(city.bubbles[id].name.text) == "San Francisco": return city.bubbles[id]
	return {}

func test_a_bubble_pops_out_of_its_point_and_shrinks_back_into_it() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	_look(m, 37.77, -122.42, 6.0)
	city._update_bubbles()
	var home := _home_bubble(city)
	assert_dict(home).is_not_empty()
	var node: Control = home.node
	assert_bool(node.visible).is_true()
	assert_bool(home.node_on).is_true()   # _update_bubbles hands its settled bubbles to _pop_bubbles
	for id in city.bubbles:   # every ghost the size of its bubble
		var bb: Dictionary = city.bubbles[id]
		if bb.get("node_ghost", {}).has("node") and is_instance_valid(bb.node_ghost.node):
			assert_vector((bb.node_ghost.node as Control).size).is_equal((bb.node as Control).size)
	await get_tree().create_timer(CityMapView.POP_IN_S + 0.1).timeout
	for g in city._ghosts.duplicate(): city._drop_ghost(g)
	# comes: whole at once (its tap, its rect), clear while a ghost grows out of the dot over it
	node.visible = false
	city._pop_bubbles()
	for g in city._ghosts.duplicate(): city._drop_ghost(g)
	node.visible = true
	city._pop_bubbles()
	assert_vector(node.scale).is_equal(Vector2.ONE)
	assert_float(node.modulate.a).is_equal(0.0)
	var ghost: Control = home.node_ghost.node
	assert_float(ghost.scale.x).is_less(0.01)
	assert_vector(ghost.pivot_offset).is_equal(Vector2(node.size.x * 0.5, -CityMapView.BUBBLE_DROP))   # out of the dot
	assert_vector(ghost.position).is_equal(node.position)
	assert_int(ghost.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(city.activate_bubble_at(node.get_global_rect().get_center())).is_true()   # takes the tap at once
	# a pass that keeps it as it is plays nothing again (no flicker)
	var ghosts := city._ghosts.size()
	for i in 3: city._pop_bubbles()
	assert_int(city._ghosts.size()).is_equal(ghosts)
	await get_tree().create_timer(CityMapView.POP_IN_S + 0.1).timeout
	assert_bool(is_instance_valid(ghost)).is_false()
	assert_float(node.modulate.a).is_equal(1.0)
	# goes: hidden at once (no tap on it), a ghost shrinking where it stood, following the map
	node.visible = false
	city._pop_bubbles()
	var going: Control = home.node_ghost.node
	assert_float(going.scale.x).is_equal(1.0)
	assert_bool(city.activate_bubble_at(going.get_global_rect().get_center())).is_false()
	_look(m, 37.6, -122.2, 6.0)
	city._move_ghosts()
	var at = m.geo_to_screen(float(home.geo.x), float(home.geo.y))
	assert_vector(going.position).is_equal_approx((at as Vector2) - city.global_position - going.pivot_offset, Vector2.ONE * 0.01)
	await get_tree().create_timer(CityMapView.POP_OUT_S + 0.1).timeout
	assert_bool(is_instance_valid(going)).is_false()
	assert_float(node.modulate.a).is_equal(1.0)

func test_a_going_pin_leaves_its_disc_alone_to_shrink() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var o := P0Outposts.find("sh_tea_1")
	city._shown_last.clear()
	city._hidden_until.clear()
	m.center_lat = float(o.lat)
	m.center_lng = float(o.lng)
	m.zoom = 15.0
	m.bearing = 0.0
	m._update_cameras()
	m.p0_frame(m.rt.session.view, 0.016)
	city._update_markers()
	var marker: Dictionary = {}
	for mk in city.displayed:
		if mk.has("dest") and str(mk.entry.id) == "sh_tea_1": marker = mk
	assert_dict(marker).is_not_empty()
	await get_tree().create_timer(CityMapView.POP_IN_S + 0.1).timeout   # popped in
	assert_bool((marker.dest as UiMapDestination).name_shown).is_true()
	city._set_marker_shown(marker, false)
	assert_bool(marker.node.visible).is_false()   # gone at once: name, marks and taps with it
	var ghost: Control = marker.ghost.node
	assert_bool(str(ghost.name).begins_with("PinGhost")).is_true()
	var disc: UiMapDestination = ghost.get_child(0)
	assert_bool(disc.name_shown).is_false()
	assert_str(disc.mark).is_empty()
	assert_vector(ghost.position).is_equal(marker.node.position)   # on its point
	await get_tree().create_timer(CityMapView.POP_OUT_S + 0.1).timeout
	assert_bool(is_instance_valid(ghost)).is_false()
	city._set_marker_shown(marker, true)   # back: the pin itself pops again, no ghost
	assert_bool(marker.node.visible).is_true()
	assert_bool(city._ghosts.has(marker.get("ghost", {}))).is_false()

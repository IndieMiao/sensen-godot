extends GdUnitTestSuite
## The map's power quick wins (perf plan 10-16, SGODOT-260 / 292). Q4: the map's sun draws no real-time shadows —
## nothing on the map takes one. Q5: inside an explored city one fog hole covers the screen, and the veil, a
## full-screen shader that would draw nothing there, is hidden; it comes back the moment the screen leaves the hole.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const MapFogLayer := preload("res://modules/map/map_fog_layer.gd")
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const SF := "gn-5391959"

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

func _home_sf(rt: P0Runtime) -> Dictionary:
	var saved: Dictionary = rt.session.view
	var v := saved.duplicate(true)
	v["now"] = 1_000_000_000.0
	v["travel"] = {home = SF, here = SF, visits = {}, passes = {}, stamps = [], fallback = {near3 = [], near10 = []}, explorer = 0}
	rt.session.view = v
	return saved

func _look(m: Node, lat: float, lng: float, z: float, flat := true) -> void:
	m.center_lat = lat
	m.center_lng = lng
	m._set_zoom(z)
	if flat: m.pitch = 0.0
	m._zoom_elastic = 0.0
	m._update_cameras()

func test_the_maps_sun_casts_no_shadows() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	var sun: DirectionalLight3D = m.get_node("Sun")
	assert_bool(sun.shadow_enabled).is_false()
	# and nothing on the map was relying on one: what the map's world draws casts none — set off (the avatars), or
	# drawn transparent (the landmarks' billboards and their silhouette shadows: alpha, no cut), which casts nothing
	for n in m.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		assert_bool(g is SpriteBase3D and (g as SpriteBase3D).alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED) \
			.override_failure_message("%s casts" % m.get_path_to(g)).is_true()

func test_a_screen_inside_one_holes_core_is_covered() -> void:
	var screen := Rect2(0, 0, 360, 800)
	var half_diag := Vector2(180, 400).length()   # 438.6
	assert_bool(MapFogLayer.covers([{at = Vector2(180, 400), r = 500.0}], screen)).is_true()
	# the corners in the feather: the shader still draws a trace of veil there
	assert_bool(MapFogLayer.covers([{at = Vector2(180, 400), r = half_diag + 10.0}], screen)).is_false()
	assert_bool(MapFogLayer.covers([{at = Vector2(180, 400), r = 300.0}], screen)).is_false()
	# off to one side: the far corners are out
	assert_bool(MapFogLayer.covers([{at = Vector2(-200, 400), r = 500.0}], screen)).is_false()
	# two holes tiling the screen between them do not count
	assert_bool(MapFogLayer.covers([{at = Vector2(180, 200), r = 300.0}, {at = Vector2(180, 600), r = 300.0}], screen)).is_false()
	assert_bool(MapFogLayer.covers([], screen)).is_false()

func test_the_veil_hides_inside_an_explored_city_and_returns_outside() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _home_sf(rt)
	var fog: ColorRect = m.city_map.fog
	_look(m, 37.7558, -122.4345, 15.0)   # street zoom in San Francisco
	m.city_map._update_fog()
	assert_bool(fog.visible).is_false()
	m.city_map._update_fog()   # the same holes again: the cached path keeps it hidden
	assert_bool(fog.visible).is_false()
	_look(m, 36.0, -120.3, 5.0)   # California: the rest of the state under the veil
	m.city_map._update_fog()
	assert_bool(fog.visible).is_true()
	m.city_map._update_fog()
	assert_bool(fog.visible).is_true()
	_look(m, 37.7558, -122.4345, 15.0)
	m.city_map._update_fog()
	assert_bool(fog.visible).is_false()
	rt.session.view = saved

## Tilted (from z 8) the hole is an ellipse; where covers() says the screen is clear, the shader's own sum agrees at
## every 8 px of it, and where it says not, some pixel still has veil.
func test_covered_matches_the_shader_on_a_tilted_map() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var saved := _home_sf(rt)
	var c: Dictionary = P0Clusters.get_cluster(P0Clusters.cluster_of_region(SF))
	var seen := {true: 0, false: 0}
	for z in [9.0, 10.5, 11.5, 12.5, 13.5]:
		_look(m, float(c.lat), float(c.lng), z, false)
		var holes: Array = m.fog_holes()
		var at: Vector2 = -m.city_map.global_position   # the layer's origin in the view's px
		var rect := Rect2(at, Vector2(360, 800))
		var covered := MapFogLayer.covers(holes, rect)
		seen[covered] += 1
		var veil := 0.0
		for x in range(0, 361, 8):
			for y in range(0, 801, 8):
				var p: Vector2 = at + Vector2(x, y)
				var clear := 0.0
				for h in holes:
					var edge := minf(MapFogLayer.FEATHER, maxf(1.0, float(h.get("r_min", h.r))))
					clear = maxf(clear, 1.0 - smoothstep(-edge, 0.0, MapFogLayer.edge_distance(h, p)))
				veil = maxf(veil, 1.0 - clear)
		if covered: assert_float(veil).override_failure_message("z %.1f: covered, yet veil %.3f" % [z, veil]).is_less(0.002)
		else: assert_float(veil).override_failure_message("z %.1f: not covered, yet no veil" % z).is_greater(0.0)
	assert_int(seen[true]).override_failure_message("no zoom inside the city").is_greater(0)
	rt.session.view = saved

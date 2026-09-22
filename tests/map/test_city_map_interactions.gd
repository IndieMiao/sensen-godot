extends GdUnitTestSuite

func before_test() -> void:
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())

func after_test() -> void:
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	add_child(auto_free(viewport))
	var map := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	viewport.add_child(map)
	return map

func test_dense_city_markers_keep_exact_anchors_and_collapse_overlaps_deterministically() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var landmark: Dictionary = CityMapData.landmarks("los_angeles")[1]
	city.entries = [landmark]
	var pois := []
	for i in 20:
		pois.append({"id":str(i), "name":"Cafe %d" % i, "lat":landmark.lat + i * 0.00001,
			"lng":landmark.lng, "maki":"cafe", "rank":1})
	city.live_pois = CityMapData.normalize(pois)
	for frame in 40:
		m.center_lat = landmark.lat + sin(frame * 0.3) * 0.0003
		m.center_lng = landmark.lng + cos(frame * 0.2) * 0.0004
		m.zoom = 14.0 + frame * 0.02
		m.bearing = frame * 3.0
		m._update_cameras()
		if frame == 10: city.select(landmark)
		if frame == 20: city.clear_selection()
		city._update_markers()
		# 20 cafés stacked on the observatory collapse into the landmark alone.
		# What shows sits exactly on its geographic anchor; nothing is relocated.
		assert_int(city.displayed.size()).is_equal(1)
		assert_str(str(city.displayed[0].entry.id)).is_equal(str(landmark.id))
		for marker in city.displayed:
			var world := MapGeoMath.geo_to_world(marker.entry.lat, marker.entry.lng, m.anchor_lat, m.anchor_lng)
			var expected: Vector2 = m.cam.unproject_position(world) - city.global_position
			assert_float(marker.node.position.distance_to(expected)).is_less(0.001)
			assert_bool(marker.node.visible).is_true()

func test_marker_packing_prefers_rank_keeps_incumbents_and_never_shows_fallback_pins() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.entries = []
	var lat: float = m.home_lat + 0.02 # away from the farm so player footprints stay clear
	var lng: float = m.home_lng + 0.02
	m.center_lat = lat
	m.center_lng = lng
	m.zoom = 16.0
	m._update_cameras()
	m._sync_farm_markers()
	city.live_pois = [
		{"id": "pin", "kind": "poi", "name": "Mystery", "lat": lat, "lng": lng, "art": "place", "rank": 1},
		{"id": "z_win", "kind": "poi", "name": "Ramen", "lat": lat, "lng": lng, "art": "restaurant", "rank": 1},
		{"id": "a_lose", "kind": "poi", "name": "Cafe", "lat": lat, "lng": lng, "art": "cafe", "rank": 2},
	]
	city._update_markers()
	var shown: Array = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_array(shown).contains_exactly(["z_win"])
	assert_bool(city.markers.has("pin")).is_false() # fallback pins never become markers
	# Incumbency: an equal-rank newcomer with a smaller id still loses to the shown marker.
	city.live_pois.append({"id": "a_new", "kind": "poi", "name": "New", "lat": lat, "lng": lng, "art": "bakery", "rank": 1})
	city._update_markers()
	shown = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_array(shown).contains_exactly(["z_win"])
	# Artwork is a world-space billboard with a soft ground shadow, so 3D avatars
	# and buildings occlude each other by depth.
	assert_object(city.markers["z_win"].sprite).is_instanceof(Sprite3D)
	assert_bool(city.markers["z_win"].sprite.visible).is_true()
	assert_bool(city.markers["z_win"].shadow.visible).is_true()
	# Below the city-detail zoom band no provider POI renders at all.
	m.zoom = 12.0
	m._update_cameras()
	city._update_markers()
	assert_array(city.displayed).is_empty()

func test_city_pois_yield_to_player_footprints() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.entries = []
	m.center_lat = m.home_lat
	m.center_lng = m.home_lng
	m.zoom = 16.0
	m._update_cameras()
	m._sync_farm_markers()
	assert_array(m.farm_markers.blocker_rects()).is_not_empty()
	city.live_pois = [{"id": "onp", "kind": "poi", "name": "Blocked", "lat": m.home_lat, "lng": m.home_lng, "art": "restaurant", "rank": 1}]
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "onp")).is_false()
	# Away from people the same POI shows again.
	city.live_pois[0].lat = m.home_lat + 0.004
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "onp")).is_true()

func test_city_owners_never_cluster_clamp_or_shift_for_selection() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var markers: FarmMarkers = m.farm_markers
	var bp := FarmBlueprint.load_choice(FarmChoice.load())
	for id in ["overlap_a", "overlap_b"]: markers.put(id, bp, id, false, "preset_a")
	m.center_lat = bp.overlay.center.x
	m.center_lng = bp.overlay.center.y
	m.zoom = 15
	m._update_cameras()
	for selected in ["", "overlap_a", "overlap_b", ""]:
		markers.selected_id = selected
		markers.expanded_avatar_id = selected
		markers.sync(m.cam, m.anchor_lat, m.anchor_lng, Rect2(1, 1, 2, 2))
		for id in ["overlap_a", "overlap_b"]:
			var expected := MapGeoMath.geo_to_world(bp.overlay.center.x, bp.overlay.center.y, m.anchor_lat, m.anchor_lng)
			assert_vector(markers.world_positions[id]).is_equal(expected)
			var anchor: Vector2 = m.cam.unproject_position(expected) - markers.global_position
			var target: Button = markers._avatar_targets[id]
			assert_float((target.position + Vector2(target.size.x / 2, target.size.y - 2)).distance_to(anchor)).is_less(0.001)
			assert_bool(target.visible).is_true()
			assert_bool(markers._badges[id].visible).is_false()
			assert_bool(target.get_child(0).visible).is_equal(id != selected)
		assert_bool(markers.miniature.visible).is_false()

func test_partial_empty_and_failed_tile_results_retain_known_pois_and_coordinates() -> void:
	var m := _map()
	await get_tree().process_frame
	var city: CityMapView = m.city_map
	city._request = 11
	city._on_pois(11, JSON.stringify({"features":[{"id":"a", "name":"Cafe", "lat":34.1, "lng":-118.3, "maki":"cafe"}]}))
	city._on_pois(10, JSON.stringify({"features":[{"id":"stale", "name":"Old request", "lat":34, "lng":-118}]}))
	assert_int(city.live_pois.size()).is_equal(1)
	for payload in [{"features":[]}, {"features":[], "error":"loading"}, {"features":[], "error":"unavailable"}]:
		city._on_pois(11, JSON.stringify(payload))
		assert_int(city.live_pois.size()).is_equal(1)
	city._on_pois(11, JSON.stringify({"features":[{"id":"a", "name":"咖啡店", "lat":34.10002, "lng":-118.30002, "maki":"cafe"},
		{"id":"b", "name":"Restaurant", "lat":34.101, "lng":-118.3, "maki":"restaurant"}]}))
	var cafe: Dictionary = city.live_pois.filter(func(p): return p.id == "a")[0]
	assert_str(cafe.name).is_equal("咖啡店")
	assert_float(cafe.lat).is_equal(34.1)
	assert_float(cafe.lng).is_equal(-118.3)
	assert_int(city.live_pois.size()).is_equal(2)
	assert_str(city.status.text).is_empty()

func test_poi_cache_is_bounded_without_erasing_visible_entries() -> void:
	var m := _map()
	await get_tree().process_frame
	var city: CityMapView = m.city_map
	for batch in 8:
		var incoming := []
		for i in 100: incoming.append({"id":str(batch * 100 + i), "name":"Place", "lat":34, "lng":-118})
		city._merge_pois(CityMapData.normalize(incoming))
	assert_int(city.live_pois.size()).is_equal(CityMapView.POI_CACHE_LIMIT)
	assert_bool(city.live_pois.any(func(p): return p.id == "799")).is_true()

func test_selection_builds_only_one_matching_actor_without_moving_camera() -> void:
	var m := _map()
	await get_tree().create_timer(0.7).timeout
	var ids: Array = m.farm_markers.points.keys().filter(func(id): return id != "self")
	assert_int(ids.size()).is_greater(1)
	var center := Vector2(m.center_lat, m.center_lng)
	var zoom: float = m.zoom
	m._select_city_player(ids[0])
	m._select_city_player(ids[1])
	for i in 180:
		await get_tree().process_frame
		if m.farm_markers.expanded_avatar_id == ids[1]: break
	var remote: Array = m._pawns.filter(func(p): return p.cohort != "self")
	assert_int(remote.size()).is_equal(1)
	assert_str(remote[0].cohort).is_equal("farm:" + ids[1])
	assert_str(m.farm_markers.expanded_avatar_id).is_equal(ids[1])
	assert_array(remote[0].rig.desired_config().changed_slots(SeededOutfit.config_for(m.farm_markers.points[ids[1]].avatar_ref))).is_empty()
	assert_vector(Vector2(m.center_lat, m.center_lng)).is_equal(center)
	assert_float(m.zoom).is_equal(zoom)
	assert_object(m.nearby_panel).is_null()
	assert_bool(m.farm_markers.miniature.visible).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(0)
	assert_bool(m.is_back_navigation_locked()).is_true()
	await get_tree().process_frame
	assert_int(m._pawns.filter(func(p): return p.cohort != "self").size()).is_equal(0)
	assert_str(m.farm_markers.expanded_avatar_id).is_empty()

func test_cancelled_pending_selection_cannot_resurrect_a_rig() -> void:
	var m := _map()
	await get_tree().process_frame
	var id: String = m.farm_markers.points.keys().filter(func(p): return p != "self")[0]
	m._select_city_player(id)
	m._clear_farm_selection()
	for i in 20: await get_tree().process_frame
	assert_int(m._pawns.filter(func(p): return p.cohort != "self").size()).is_equal(0)
	assert_str(m.farm_markers.selected_id).is_empty()
	assert_str(m.farm_markers.expanded_avatar_id).is_empty()

func test_popup_squashes_and_settles_without_changing_geographic_parent() -> void:
	var holder := Node3D.new()
	add_child(auto_free(holder))
	holder.position = Vector3(103, 0, -45)
	var popup := MapAvatarPopup.new()
	holder.add_child(popup)
	popup.pop()
	assert_float(popup.scale.y).is_less(0.1)
	popup.animation.pause()
	popup.animation.custom_step(0.20)
	assert_float(popup.scale.y).is_greater(1.1)
	holder.scale = Vector3.ONE * 200
	popup.animation.custom_step(0.10)
	assert_float(popup.scale.x).is_greater(1.1)
	assert_float(popup.scale.y).is_less(0.9)
	popup.animation.custom_step(0.23)
	assert_float(popup.scale.distance_to(Vector3.ONE)).is_less(0.001)
	assert_vector(popup.position).is_equal(Vector3.ZERO)
	assert_vector(holder.position).is_equal(Vector3(103, 0, -45))

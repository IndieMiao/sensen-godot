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
	city.live_pois.append({"id": "a_new", "kind": "poi", "name": "New", "lat": lat, "lng": lng, "art": "cafe", "rank": 1})
	city._update_markers()
	shown = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_array(shown).contains_exactly(["z_win"])
	# Artwork is a world-space billboard with a soft ground shadow, so 3D avatars
	# and buildings occlude each other by depth.
	assert_object(city.markers["z_win"].sprite).is_instanceof(Sprite3D)
	assert_bool(city.markers["z_win"].sprite.visible).is_true()
	assert_bool(city.markers["z_win"].shadow.visible).is_true()
	# 阴影是素材自身的剪影：同贴图、半透明墨色、billboard，任意视角不歪。
	var z_shadow: Sprite3D = city.markers["z_win"].shadow
	assert_object(z_shadow.texture).is_same(city.markers["z_win"].sprite.texture)
	assert_int(z_shadow.billboard).is_equal(BaseMaterial3D.BILLBOARD_ENABLED)
	assert_float(z_shadow.modulate.a).is_less(0.5)
	# Below the city-detail zoom band no provider POI renders at all.
	m.zoom = 12.0
	m._update_cameras()
	city._update_markers()
	assert_array(city.displayed).is_empty()

func test_marker_packing_diversifies_dining_and_keeps_first_seen_rank() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.entries = []
	var lat: float = m.home_lat + 0.02
	var lng: float = m.home_lng + 0.02
	m.center_lat = lat
	m.center_lng = lng
	m.zoom = 16.0
	m._update_cameras()
	m._sync_farm_markers()
	# 四家分散的餐饮把配额吃满后，与第五家餐饮同点的商店优先拿到空间。
	city.live_pois = [
		{"id": "a_d1", "kind": "poi", "name": "D1", "lat": lat, "lng": lng - 0.004, "art": "restaurant", "rank": 1},
		{"id": "a_d2", "kind": "poi", "name": "D2", "lat": lat, "lng": lng - 0.002, "art": "cafe", "rank": 1},
		{"id": "a_d3", "kind": "poi", "name": "D3", "lat": lat, "lng": lng + 0.002, "maki": "fast-food", "rank": 1},
		{"id": "a_d4", "kind": "poi", "name": "D4", "lat": lat, "lng": lng + 0.004, "art": "chinese_restaurant", "rank": 1},
		{"id": "b_shop", "kind": "poi", "name": "Shop", "lat": lat + 0.002, "lng": lng, "art": "shop", "rank": 5},
		{"id": "z_d5", "kind": "poi", "name": "D5", "lat": lat + 0.002, "lng": lng, "art": "restaurant", "rank": 1},
	]
	city._update_markers()
	var shown: Array = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_array(shown).contains(["a_d1", "a_d2", "a_d3", "a_d4", "b_shop"])
	assert_bool(shown.has("z_d5")).is_false()
	# 餐饮筛选下配额不生效：同点只剩餐饮时 z_d5 直接上位。
	city.filter = "food"
	city._update_markers()
	shown = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_bool(shown.has("z_d5")).is_true()
	city.filter = "all"
	# rank 保持首见值：回包里同一 POI 的 filterrank 漂移不再挤掉在位标记。
	city._merge_pois([{"id": "a_d1", "kind": "poi", "name": "D1", "lat": lat, "lng": lng - 0.004, "art": "restaurant", "rank": 9}])
	assert_int(int(city.live_pois.filter(func(p): return str(p.id) == "a_d1")[0].rank)).is_equal(1)
	# 非餐饮不吃中档 zoom 的 rank 阈值：z14 下 rank5 商店照样补位，rank3 餐饮仍被收紧。
	m.zoom = 14.0
	m._update_cameras()
	city.live_pois = [
		{"id": "s_mid", "kind": "poi", "name": "S", "lat": lat, "lng": lng, "art": "shop", "rank": 5},
		{"id": "d_mid", "kind": "poi", "name": "D", "lat": lat + 0.004, "lng": lng, "art": "restaurant", "rank": 3},
	]
	city._update_markers()
	shown = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_bool(shown.has("s_mid")).is_true()
	assert_bool(shown.has("d_mid")).is_false()
	# 低 zoom 全景由高价值非餐饮填补：rank≤3 放行，rank4 与所有餐饮不上图。
	m.zoom = 11.0
	m._update_cameras()
	city.live_pois = [
		{"id": "s_low", "kind": "poi", "name": "SL", "lat": lat, "lng": lng, "maki": "school", "rank": 3},
		{"id": "s_low4", "kind": "poi", "name": "SL4", "lat": lat + 0.01, "lng": lng, "art": "shop", "rank": 4},
		{"id": "d_low", "kind": "poi", "name": "DL", "lat": lat - 0.01, "lng": lng, "art": "restaurant", "rank": 1},
	]
	city._update_markers()
	shown = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_bool(shown.has("s_low")).is_true()
	assert_bool(shown.has("s_low4")).is_false()
	assert_bool(shown.has("d_low")).is_false()

func test_landmarks_cull_each_other_but_ignore_player_footprints() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var lat: float = m.home_lat + 0.02
	var lng: float = m.home_lng + 0.02
	m.center_lat = lat
	m.center_lng = lng
	m.zoom = 16.0
	m._update_cameras()
	m._sync_farm_markers()
	city.live_pois = []
	# 两个地标同点：id 序靠前者在位，另一个整颗让位（带出现/消失动画的通用路径）。
	city.entries = [
		{"id": "a_lm", "kind": "landmark", "name": "A", "lat": lat, "lng": lng, "art": "hollywood_sign"},
		{"id": "b_lm", "kind": "landmark", "name": "B", "lat": lat, "lng": lng, "art": "griffith_observatory"},
	]
	city._update_markers()
	var shown: Array = city.displayed.map(func(mk): return str(mk.entry.id))
	assert_array(shown).contains_exactly(["a_lm"])
	# 地标不给玩家足迹让位：挪到自己农场正上方仍然显示。
	m.center_lat = m.home_lat
	m.center_lng = m.home_lng
	m._update_cameras()
	m._sync_farm_markers()
	city.entries = [{"id": "on_self", "kind": "landmark", "name": "L", "lat": m.home_lat, "lng": m.home_lng, "art": "hollywood_sign"}]
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "on_self")).is_true()

func test_culled_marker_waits_out_the_reappear_cooldown() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.entries = []
	var lat: float = m.home_lat + 0.02
	var lng: float = m.home_lng + 0.02
	m.center_lat = lat
	m.center_lng = lng
	m.zoom = 16.0
	m._update_cameras()
	m._sync_farm_markers()
	city.live_pois = [{"id": "poi_p", "kind": "poi", "name": "P", "lat": lat, "lng": lng, "art": "restaurant", "rank": 1}]
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "poi_p")).is_true()
	# 一个地标扫过它的位置：在位者被挤掉并进入重现冷却。
	city.entries = [{"id": "lm", "kind": "landmark", "name": "LM", "lat": lat, "lng": lng, "art": "hollywood_sign"}]
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "poi_p")).is_false()
	# 地标离开后冷却未到，marker 不立刻回来——这是拖动防闪烁的核心。
	city.entries = []
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "poi_p")).is_false()
	# 冷却按墙钟计（Time.get_ticks_msec）；无头跑帧的游戏时间快于墙钟，
	# 所以这里按墙钟轮询等待而不是 create_timer。
	var deadline := Time.get_ticks_msec() + 450
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	city._update_markers()
	assert_bool(city.displayed.any(func(mk): return str(mk.entry.id) == "poi_p")).is_true()

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

func test_city_owner_pins_collapse_overlaps_without_shifting_anchors() -> void:
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
	# 三个 pin 同点堆叠：3D 的自己永不被盖，其余折叠进幸存者名牌的 +N。
	markers.selected_id = ""
	markers.expanded_avatar_id = ""
	markers.sync(m.cam, m.anchor_lat, m.anchor_lng, Rect2(1, 1, 2, 2))
	assert_array(markers.visible_farm_ids).contains_exactly(["self"])
	var expected := MapGeoMath.geo_to_world(bp.overlay.center.x, bp.overlay.center.y, m.anchor_lat, m.anchor_lng)
	var anchor: Vector2 = m.cam.unproject_position(expected) - markers.global_position
	var self_target: Button = markers._avatar_targets["self"]
	assert_float((self_target.position + Vector2(self_target.size.x / 2, self_target.size.y - 2)).distance_to(anchor)).is_less(0.001)
	# 洛杉矶夹具农场也会folded进来，数量随夹具变化——只锁定"名字 +N"的形态。
	assert_bool(str(markers._owner_labels["self"].text).begins_with("My Farm +")).is_true()
	for id in ["overlap_a", "overlap_b"]:
		assert_vector(markers.world_positions[id]).is_equal(expected)
		assert_bool(markers._avatar_targets[id].visible).is_false()
		assert_bool(markers._badges[id].visible).is_false()
	# 选中被折叠的玩家：其 pin 无条件回到精确锚点，自己也不消失。
	markers.selected_id = "overlap_a"
	markers.expanded_avatar_id = "overlap_a"
	markers.sync(m.cam, m.anchor_lat, m.anchor_lng, Rect2(1, 1, 2, 2))
	var a_target: Button = markers._avatar_targets["overlap_a"]
	assert_bool(a_target.visible).is_true()
	assert_float((a_target.position + Vector2(a_target.size.x / 2, a_target.size.y - 2)).distance_to(anchor)).is_less(0.001)
	assert_bool(markers._avatar_targets["self"].visible).is_true()
	assert_bool(markers._avatar_targets["overlap_b"].visible).is_false()
	assert_bool(a_target.get_child(0).visible).is_false()
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

func test_selected_marker_label_expands_to_the_full_name() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.entries = []
	var lat: float = m.home_lat + 0.02
	var lng: float = m.home_lng + 0.02
	m.center_lat = lat
	m.center_lng = lng
	m.zoom = 16.0
	m._update_cameras()
	m._sync_farm_markers()
	var long_name := "La Brea Tar Pits and Museum"
	city.live_pois = [{"id": "long", "kind": "poi", "name": long_name, "lat": lat, "lng": lng, "maki": "lodging", "rank": 1}]
	city._update_markers()
	# 未选中：名牌按缺省 48 宽，长名允许省略。
	var label: Label = city.markers["long"].label
	assert_float(label.size.x).is_equal_approx(48.0, 0.5)
	city.select(city.live_pois[0])
	city._update_markers()
	# 选中：全名显示不再截断；超过上限宽度就按词折行，名牌变高而不是无限变宽。
	assert_str(label.text).is_equal(long_name)
	assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
	assert_int(label.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_float(label.size.x).is_less_equal(city.LABEL_MAX_W)
	assert_float(label.size.y).is_greater(20.0)
	# 名牌跟随图标居中，即使贴近屏幕边缘也不挪。
	m.center_lng = lng - 0.0035
	m._update_cameras()
	city._update_markers()
	var node: Control = city.markers["long"].node
	assert_float(node.position.x).is_greater(city.size.x - 80.0)
	assert_float(label.position.x).is_equal_approx(-label.size.x * 0.5, 0.01)
	# 点击热区只含贴图与名牌：放大占位框里、贴图右上方的空地点不中，点空白能取消。
	var marker: Dictionary = city.markers["long"]
	var empty := Vector2(marker.rect.end.x - 2.0, marker.rect.position.y + 2.0)
	assert_bool(marker.rect.has_point(empty)).is_true()
	assert_bool(city.activate_at(empty + city.global_position)).is_false()
	assert_bool(city.activate_at(node.position + Vector2(0, -10) + city.global_position)).is_true()

func test_player_card_offers_a_visit_jump_and_clears_with_selection() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var visits: Array = []
	var deselects: Array = []
	city.player_visit_requested.connect(func(id): visits.append(str(id)))
	city.player_deselected.connect(func(): deselects.append(true))
	city.select_player({"id": "player:f1", "farm_id": "f1", "kind": "player", "name": "Mia"}, null)
	assert_bool(city.info.visible).is_true()
	assert_str(city.info_title.text).is_equal("Mia")
	assert_bool(city.info_action.visible).is_true()
	assert_str(city.info_action.text).is_equal(L10n.text("Visit Farm"))
	# 卡上的跳转按钮带出该农场的访客跳转请求。
	city._on_info_action()
	assert_array(visits).contains_exactly(["f1"])
	# 关卡片（点 X / 返回键）同步通知宿主清掉 pin 选中与 3D 角色。
	assert_bool(city.consume_back()).is_true()
	assert_array(deselects).has_size(1)
	assert_bool(city.info.visible).is_false()
	# 居民卡把行动按钮换回“拜访居民”，不受玩家卡影响。
	var resident := {"id": "npc", "kind": "resident", "name": "Ivy", "place": "nursery", "status": "Talk", "lat": 34.09, "lng": -118.3}
	city.select(resident)
	assert_str(city.info_action.text).is_equal(L10n.text("Visit resident"))
	city._on_info_action()
	assert_array(visits).has_size(1) # 居民路径不再发玩家跳转

func test_poi_icons_follow_maki_and_pick_by_name_hash() -> void:
	var a := {"id": "1", "kind": "poi", "name": "Señor Fish", "maki": "restaurant"}
	var again := {"id": "2", "kind": "poi", "name": "Señor Fish", "maki": "restaurant-seafood"}
	# 同名永远同图；同义 maki 共用同一组图标。
	assert_object(CityMapData.art_texture(a)).is_same(CityMapData.art_texture(again))
	assert_str(CityMapData.art_texture(a).resource_path).contains("icons/restaurant_")
	var seen := {}
	for i in 12:
		seen[CityMapData.art_texture({"id": str(i), "kind": "poi", "name": "Diner %d" % i, "maki": "fast-food"}).resource_path] = true
	assert_int(seen.size()).is_greater(1)
	# 每种 maki 的全部图标（共 125 张）必须随包，否则哈希落空。
	for key in CityMapData.ICON_VARIANTS:
		for n in range(1, int(CityMapData.ICON_VARIANTS[key]) + 1):
			assert_bool(ResourceLoader.exists("%s%s_%d.webp" % [CityMapData.ICON_PATH, key, n])).override_failure_message("missing %s_%d" % [key, n]).is_true()
	# 低频/无意义 maki 没有图标，不上图；地标仍用建筑贴图。
	assert_str(CityMapData.icon_key({"maki": "marker"})).is_empty()
	assert_str(CityMapData.icon_key({"maki": "bridge"})).is_empty()
	assert_str(CityMapData.icon_key({"maki": "supermarket"})).is_equal("grocery")
	assert_str(CityMapData.icon_key({"maki": "restaurant-pizza"})).is_equal("restaurant-pizza")
	var landmark := {"id": "lm", "kind": "landmark", "name": "Griffith", "art": "griffith_observatory"}
	assert_str(CityMapData.art_texture(landmark).resource_path).contains("griffith_observatory.png")

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

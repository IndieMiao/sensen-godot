extends "res://tools/dev/game_ui_observer.gd"
## Isolated HTTP actions; this bootstrap never ships in the Journey update.
func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	super._ready()
	set_process(false)
	Localization.select_language("zh_CN")
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://ui_qa_account.json"))
	if ApiClient.install_key() != str(account.key):
		FileAccess.open(ApiClient.INSTALL_KEY_PATH, FileAccess.WRITE).store_string(str(account.key))
		FarmChoice.clear()
	var outfit := AvatarConfig.from_json_text(FileAccess.get_file_as_string("res://gallery_outfit.json"))
	assert(outfit != null and Avatar.save_outfit(outfit) == OK)
	var host := "10.0.2.2" if OS.get_name() == "Android" else "127.0.0.1"
	Net.use_transport(ApiClient.make_http_transport(self), "http://%s:3196/v1" % host)
	if not await Net.boot():
		push_error("GAME_UI_QA_LOGIN_FAILED")
		return
	FarmRegions.save_choice(Net.session.region_id)
	FarmChoice.save_choice(Net.session.farm_choice())
	var map_scene := (load(AppRouter.MAP) as PackedScene).instantiate()
	get_tree().root.add_child(map_scene)
	get_tree().current_scene = map_scene
	set_process(true)


var _motion_frames: Array = []
var _trace_at := 0

func _process(dt: float) -> void:
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path.contains("map_poc") and scene.city_map:
		_capture_motion(scene)
	super._process(dt)
	if elapsed != 0: return
	if not scene or not scene.scene_file_path.contains("map_poc") or not scene.city_map: return
	var data = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("state.json")))
	if not data is Dictionary: return
	var city: CityMapView = scene.city_map
	data.city = {
		"filter":city.filter, "selected":city.selected, "poi_count":city.live_pois.size(), "pois":city.live_pois,
		"list_visible":city.list_panel.visible, "status":city.status.text,
		"ui_layout":{"dock":_rect(city.dock), "filters":_rect(city.get_node("MapFilters")), "title":_rect(city.get_node("MapCity")), "round_visual":32, "portrait_visual":36},
		"sheets":{"neighbours":is_instance_valid(scene.nearby_panel), "list_bounds":_rect(city.list_panel), "info_action":_rect(city.info_action)},
		"info_layout":{"bounds":_rect(city.info), "art":_rect(city.info_art)},
		"markers":[], "players":[], "actors":[],
		"selected_player":scene.farm_markers.selected_id, "expanded_player":scene.farm_markers.expanded_avatar_id,
		"farm_miniature":scene.farm_markers.miniature.visible,
		"fps":Engine.get_frames_per_second(),
		"map_area":_rect_from(Rect2(city.global_position+Vector2(0,CityMapView.CONTENT_TOP),Vector2(city.size.x,city.dock.position.y-CityMapView.CONTENT_TOP-12)))
	}
	for marker in city.displayed:
		var rect: Rect2 = marker.rect
		var expected := MapGeoMath.geo_to_world(marker.entry.lat, marker.entry.lng, scene.anchor_lat, scene.anchor_lng)
		data.city.markers.append({"id":marker.entry.id, "kind":marker.entry.kind,
			"bounds":_rect_from(Rect2(rect.position+city.global_position,rect.size)),
			"anchor":_screen(scene.cam,expected), "offset":marker.node.position.distance_to(scene.cam.unproject_position(expected)-city.global_position)})
	for id in scene.farm_markers.visible_farm_ids:
		var target: Button = scene.farm_markers._avatar_targets[id]
		var entry: Dictionary = scene.farm_markers.points[id]
		var world := MapGeoMath.geo_to_world(entry.center.x, entry.center.y, scene.anchor_lat, scene.anchor_lng)
		data.city.players.append({"id":id, "bounds":_rect(target), "anchor":_screen(scene.cam,world),
			"portrait":id != "self" and target.get_child(0).visible})
	for pawn in scene._pawns:
		data.city.actors.append({"cohort":pawn.cohort, "visible":pawn.node.visible,
			"anchor":_screen(scene.cam,pawn.node.position), "popup":_xyz(pawn.popup.scale) if pawn.has("popup") else []})
	FileAccess.open(OUTPUT.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(data))

func _capture_motion(scene: Node) -> void:
	# Per-frame read-only proof of screen projection and model pop. Ring buffer
	# is written at most once/second; this observer is excluded from Journey.
	var city: CityMapView = scene.city_map
	var frame := {"ticks":Time.get_ticks_msec(), "touches":scene._touch_count, "zoom":scene.zoom,
		"lat":scene.center_lat, "lng":scene.center_lng, "markers":[], "players":[], "actors":[]}
	for marker in city.displayed:
		var world := MapGeoMath.geo_to_world(marker.entry.lat, marker.entry.lng, scene.anchor_lat, scene.anchor_lng)
		var expected: Vector2 = scene.cam.unproject_position(world) - city.global_position
		frame.markers.append({"id":marker.entry.id,"kind":marker.entry.kind,"shown":marker.node.visible,
			"anchor":[expected.x,expected.y],"offset":marker.node.position.distance_to(expected)})
	for id in scene.farm_markers.visible_farm_ids:
		var entry: Dictionary = scene.farm_markers.points[id]
		var world := MapGeoMath.geo_to_world(entry.center.x, entry.center.y, scene.anchor_lat, scene.anchor_lng)
		var expected: Vector2 = scene.cam.unproject_position(world) - scene.farm_markers.global_position
		var target: Button = scene.farm_markers._avatar_targets[id]
		var actual := target.position + Vector2(target.size.x/2, target.size.y-2)
		frame.players.append({"id":id,"anchor":[expected.x,expected.y],"offset":actual.distance_to(expected),"shown":target.visible})
	for pawn in scene._pawns:
		if pawn.has("popup"):
			frame.actors.append({"id":pawn.cohort,"scale":_xyz(pawn.popup.scale), "shown":pawn.node.visible,
				"offset":pawn.node.position.distance_to(MapGeoMath.geo_to_world(pawn.lat,pawn.lng,scene.anchor_lat,scene.anchor_lng))})
	_motion_frames.append(frame)
	if _motion_frames.size() > 240: _motion_frames.pop_front()
	if Time.get_ticks_msec() - _trace_at >= 1000:
		_trace_at = Time.get_ticks_msec()
		FileAccess.open(OUTPUT.path_join("motion.json"),FileAccess.WRITE).store_string(JSON.stringify(_motion_frames))

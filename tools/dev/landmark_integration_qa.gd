extends "res://tools/dev/game_ui_observer.gd"
## Isolated fixture + read-only scene tree inspection. Never included in Journey.
var frames: Array = []

func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	super._ready()
	process_priority = 100
	set_process(false)
	_boot.call_deferred()

func _boot() -> void:
	var transport := func(_method, _path, _headers, _body):
		return ApiClient.Response.new(true, 200, {"count": 0, "entries": []})
	Net.use_transport(transport, "https://landmark-qa.invalid/v1")
	Net.client.token = "isolated-landmark-fixture"
	Net.session.player_id = "landmark-local-player"
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://gallery_farm.json"))
	fixture.farm_id = "landmark-local-farm"
	assert(Net.session._adopt(fixture))
	FarmChoice.save_choice(Net.session.farm_choice())
	FarmRegions.save_choice("los_angeles")
	var map := (load(AppRouter.MAP) as PackedScene).instantiate()
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	set_process(true)

func _process(dt: float) -> void:
	var scene := AppRouter.top_instance()
	if scene == null: scene = get_tree().current_scene
	var sample: Dictionary = {}
	if scene is GriffithObservatory:
		var pan = scene.camera_pan
		var synced: bool = scene.navigation_ready()
		sample = {"ticks": Time.get_ticks_msec(), "position": _xyz(scene._player.position),
			"camera": _xyz(scene._camera.position), "camera_size": scene._camera.size,
			"zoom": pan.zoom, "velocity": _xyz(pan.velocity), "zoom_velocity": pan.zoom_velocity,
			"active": pan.active(), "pointer_count": pan.pointers.size(), "dragged": pan.dragged,
			"multi": pan.multi, "path_remaining": scene._path.size() - scene._path_i,
			"overview": scene._overview, "navigation_ready": synced,
			"navigation_distance": scene._player.position.distance_to(NavigationServer3D.map_get_closest_point(scene._nav_map, scene._player.position)) if synced else -1,
			"hold_enabled": pan.hold_enabled, "network_booted": Net.booted_once,
			"camera_current": get_viewport().get_camera_3d() == scene._camera,
			"nav_map_count": NavigationServer3D.get_maps().size(), "targets": {}}
		if synced:
			for target in [["garden",Vector3(-3,0,3)],["main",Vector3(-0.4,0.5,-1.8)],["west",Vector3(-9.1,0.5,-3)],["cafe",Vector3(10.2,0.5,0.1)]]:
				var point := NavigationServer3D.map_get_closest_point(scene._nav_map, target[1])
				sample.targets[target[0]] = {"world": _xyz(point), "screen": _screen(scene._camera, point)}
		frames.append(sample)
		if frames.size() > 240: frames.pop_front()
	super._process(dt)
	if elapsed != 0: return
	var path := OUTPUT.path_join("state.json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	data.stack_depth = AppRouter.instance_depth()
	data.transparent = get_viewport().transparent_bg
	data.nav_map_count = NavigationServer3D.get_maps().size()
	if not sample.is_empty(): data.landmark = sample
	if scene and scene.scene_file_path == AppRouter.MAP and scene.city_map:
		data.map_selection = scene.city_map.selected
		data.map_info = {"bounds": _rect(scene.city_map.info), "visible": scene.city_map.info.visible}
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data))
	FileAccess.open(OUTPUT.path_join("landmark-motion.json"), FileAccess.WRITE).store_string(JSON.stringify(frames))

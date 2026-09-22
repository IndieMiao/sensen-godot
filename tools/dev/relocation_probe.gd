extends Node
## QA-only observer. All gameplay below is driven through actual UI or world taps.
const OUTPUT := "user://relocation-proof"
var elapsed := 0.0
var map_scene: Node
var started := false

func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	Localization.select_language("zh_CN")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if FileAccess.file_exists(OUTPUT.path_join("state.json")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("state.json")))
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://relocation_account.json"))
	if ApiClient.install_key() != str(account.key):
		FileAccess.open(ApiClient.INSTALL_KEY_PATH, FileAccess.WRITE).store_string(str(account.key))
		FarmChoice.clear()
	var host := "10.0.2.2" if OS.get_name() == "Android" else "127.0.0.1"
	Net.use_transport(ApiClient.make_http_transport(self), "http://%s:3192/v1" % host)
	if not await Net.boot():
		push_error("RELOCATION_QA_LOGIN_FAILED")
		return
	FarmRegions.save_choice("shanghai")
	FarmChoice.save_choice(Net.session.farm_choice())
	map_scene = (load(AppRouter.MAP) as PackedScene).instantiate()
	get_tree().root.add_child(map_scene)
	get_tree().current_scene = map_scene
	started = true
	AppRouter.open_instance(AppRouter.FARM, {"session": Net.session})

func _process(dt: float) -> void:
	if not started: return
	elapsed += dt
	if elapsed < 0.15: return
	elapsed = 0
	var scene := AppRouter.top_instance() if AppRouter.top_instance() else map_scene
	if not is_instance_valid(scene): return
	var data := {"scene": scene.scene_file_path, "depth": AppRouter.instance_depth(),
		"navigation_pending": AppRouter._navigation_pending, "farm_id": Net.session.farm_id, "version": Net.session.version, "error": Net.session.last_error_code,
		"layout": Net.session.layout_patch_id, "terrain": Net.session.farm_terrain.get("source", {}),
		"wallet": Net.session.state.get("wallet", 0), "cells": Net.session.state.get("cells", {}),
		"state": Net.session.state, "relocation": Net.session.relocation, "instance_id": scene.get_instance_id(),
		"controls": [], "phase": "", "fps": Engine.get_frames_per_second()}
	_controls(scene, data.controls)
	if scene.scene_file_path == AppRouter.MAP:
		data.relocation_mode = scene._relocation_mode
		data.preview = scene._relocation_preview.preview if is_instance_valid(scene._relocation_preview) else {}
		data.selection = scene._placement_location
		data.status = scene.location_status.text
		data.selecting = scene._placement_mode
		data.busy = scene._placing_busy
		data.selection_targets = {}
		for entry in [["valid", 31.2341, 121.4704], ["unavailable", 31.2341, 121.4712]]:
			var point: Vector3 = MapGeoMath.geo_to_world(entry[1], entry[2], scene.anchor_lat, scene.anchor_lng)
			var screen: Vector2 = get_viewport().get_screen_transform() * scene.cam.unproject_position(point)
			data.selection_targets[entry[0]] = [screen.x, screen.y]
	elif scene.scene_file_path == AppRouter.FARM and scene.mover != null:
		data.position = [scene.mover.position.x, scene.mover.position.z]
		data.moving = scene.mover.is_moving()
		data.camera = {"near": scene.cam.near, "far": scene.cam.far, "size": scene.cam.size}
		data.joined = scene.online != null and scene.online.joined
		data.mine = _rect(scene._mine_pick_rect())
		data.activity_busy = scene._activity_busy
		data.work_mode = scene.work_mode
		data.action_busy = scene.runner.is_busy() or scene._in_flight > 0
		data.work_targets = []
		for j in range(25, 39):
			for i in range(22, 38):
				var cell := Vector2i(i, j)
				if not scene.bp.mask_has("cultivable", cell): continue
				var point: Vector2 = scene.cam.unproject_position(scene.bp.cell_to_world(cell))
				if not scene._camera_play_area().grow(-12).has_point(point): continue
				var screen: Vector2 = get_viewport().get_screen_transform() * point
				data.work_targets.append({"id": "%d,%d" % [i, j], "screen": [screen.x, screen.y]})
		data.activities = []
		if scene.farm_activities:
			for target in scene.farm_activities.targets.values():
				var point: Vector2 = scene.cam.unproject_position(target.position + Vector3(0, target.height * 0.5, 0))
				var screen: Vector2 = get_viewport().get_screen_transform() * point
				data.activities.append({"id": target.id, "kind": target.kind, "label": target.label,
					"screen": [screen.x, screen.y], "visible": scene._camera_play_area().has_point(point)})
		if scene.fishing_panel:
			data.phase = scene.fishing_panel.phase if scene.fishing_panel.visible else "closed"
			data.fishing_message = scene.fishing_panel._status.text
			data.fishing_busy = scene.fishing_panel.busy
	var file := FileAccess.open(OUTPUT.path_join("state.tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("state.tmp")), ProjectSettings.globalize_path(OUTPUT.path_join("state.json")))

func _rect(rect: Rect2) -> Array:
	var screen := get_viewport().get_screen_transform() * rect
	return [screen.position.x, screen.position.y, screen.size.x, screen.size.y]

func _controls(node: Node, output: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is BaseButton and node.is_visible_in_tree():
		output.append({"name": str(node.name), "text": node.text if node is Button else "",
			"tooltip": node.tooltip_text, "disabled": node.disabled, "bounds": _rect(node.get_global_rect())})
	for child in node.get_children(): _controls(child, output)

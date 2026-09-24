extends Node
## Isolated bootstrap and read-only Godot UI/scene-tree inspection; excluded from releases.
const OUTPUT := "user://pond-proof"
var _elapsed := 0.0

func _ready() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	Localization.select_language("zh_CN")
	_boot.call_deferred()

func _boot() -> void:
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pond_qa_account.json"))
	if ApiClient.install_key() != str(account.key):
		FileAccess.open(ApiClient.INSTALL_KEY_PATH, FileAccess.WRITE).store_string(str(account.key))
		FarmChoice.clear()
	var host := "10.0.2.2" if OS.get_name() == "Android" else "127.0.0.1"
	Net.use_transport(ApiClient.make_http_transport(self), "http://%s:3201/v1" % host)
	if not await Net.boot(): push_error("POND_QA_LOGIN_FAILED"); return
	FarmRegions.save_choice(Net.session.region_id)
	FarmChoice.save_choice(Net.session.farm_choice())
	var map: Node = load(AppRouter.MAP).instantiate()
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	set_process(true)

func _rect(control: Control) -> Array:
	var rect := control.get_global_rect()
	var parent := control.get_parent()
	while parent:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	rect = get_viewport().get_screen_transform() * rect
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _walk(node: Node, controls: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is CanvasItem and not node.is_visible_in_tree(): return
	if node is BaseButton:
		controls.append({"name": str(node.name), "text": node.text if node is Button else "", "disabled": node.disabled, "bounds": _rect(node)})
	for child in node.get_children(): _walk(child, controls)

func _screen(camera: Camera3D, point: Vector3) -> Array:
	var p: Vector2 = get_viewport().get_screen_transform() * camera.unproject_position(point)
	return [p.x, p.y]

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .10: return
	_elapsed = 0
	var scene := AppRouter.top_instance()
	if scene == null: scene = get_tree().current_scene
	if scene == null: return
	var controls := []
	_walk(scene, controls)
	var data := {"ticks": Time.get_ticks_msec(), "scene": scene.scene_file_path, "controls": controls,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"stack_depth": AppRouter.instance_depth(), "farm_id": Net.session.farm_id, "bag": Net.session.state.get("bag", {}),
		"wallet": Net.session.state.get("wallet", 0), "cells": Net.session.state.get("cells", {}), "unconfirmed": Net.session.has_unconfirmed_command(),
		"fps": Engine.get_frames_per_second()}
	if scene is FishingPondScene:
		data.pond = {"id": scene.entry.id, "template": scene.entry.template_id, "geometry_ready": scene._geometry_ready,
			"joined": scene.online.joined if scene.online else false, "room": scene.online.room if scene.online else "", "position": [scene.mover.position.x,scene.mover.position.z],
			"moving": scene.mover.is_moving(), "camera": [scene.cam.position.x,scene.cam.position.y,scene.cam.position.z],
			"camera_size": scene.cam.size,"zoom":scene.camera_pan.zoom,"velocity":scene.camera_pan.velocity.length(),"pointers":scene.camera_pan.pointers.size(),
			"overview":scene._overview,"notice":scene.notice.text,"targets":[]}
		for p in [Vector3(3,0,-2),Vector3(8,0,-2),Vector3(6,0,-10),Vector3(7,0,-5),Vector3(4,0,-9)]:
			data.pond.targets.append({"world":[p.x,p.z],"screen":_screen(scene.cam,p),"wet":FishingModel.contains(str(scene.entry.id),p,0,scene.site_spec),"walkable":scene.mover.bp.is_walkable(scene.mover.bp.world_to_cell(p))})
		var panel: FishingPanel = scene.fishing_panel
		data.phase = panel.phase if panel.visible else "closed"
		data.model = panel.model
		data.fishing = Net.session.state.get("fishing", {})
		data.busy = panel.busy
		data.fishing_message = panel._status.text
	elif scene.scene_file_path == AppRouter.MAP and scene.city_map:
		var city: CityMapView = scene.city_map
		data.map = {"selected":city.selected,"ponds":city.pond_locations,"filter":city.filter,"markers":[],"pose":[scene.center_lat,scene.center_lng,scene.zoom,scene.bearing],"status":city.status.text}
		for marker in city.displayed:
			data.map.markers.append({"id":marker.entry.id,"kind":marker.entry.kind,"bounds":_rect(marker.node)})
	FileAccess.open(OUTPUT.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(data))

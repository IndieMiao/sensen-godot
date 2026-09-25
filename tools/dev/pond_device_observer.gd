extends Node
## Temporary read-only scene tree, excluded from the final installed APK.
## Does not replace identity, session, input, clock, materials or gameplay state.
var _elapsed := 0.0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://pond-device-proof"))
	process_mode = Node.PROCESS_MODE_ALWAYS

func _rect(control: Control) -> Array:
	var rect := control.get_global_rect()
	var parent := control.get_parent()
	while parent:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	rect = get_viewport().get_screen_transform() * rect
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func _walk(node: Node, controls: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is CanvasItem and not node.is_visible_in_tree(): return
	if node is BaseButton:
		controls.append({"name":str(node.name),"text":node.text if node is Button else "", "disabled":node.disabled,"bounds":_rect(node)})
	for child in node.get_children(): _walk(child,controls)

func _screen(cam: Camera3D, point: Vector3) -> Array:
	var p := get_viewport().get_screen_transform() * cam.unproject_position(point)
	return [p.x,p.y]

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .2: return
	_elapsed = 0
	var scene := AppRouter.top_instance()
	if scene == null: scene = get_tree().current_scene
	if scene == null: return
	var controls := []
	_walk(get_tree().root,controls)
	var data := {"process_id":OS.get_process_id(),"ticks":Time.get_ticks_msec(),"scene":scene.scene_file_path,"controls":controls,
		"logged_in":Net.logged_in(),"has_farm":Net.session.has_farm(),"fps":Engine.get_frames_per_second(),
		"method":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(get_viewport().get_visible_rect()),
		"webview_plugin":Engine.has_singleton("GodotWebView"),"map_plugin":Engine.has_singleton("GodotMap")}
	if scene is FishingPondScene:
		var ap := scene._rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
		data.pond = {"id":scene.entry.id,"template":scene.entry.template_id,"geometry_ready":scene._geometry_ready,
			"joined":scene.online.joined if scene.online else false,"position":[scene.player.position.x,scene.player.position.z],
			"camera":str(scene.cam.transform),"camera_size":scene.cam.size,"zoom":scene.camera_pan.zoom,"overview":scene._overview,
			"clip":ap.current_animation,"animation_time":ap.current_animation_position if ap.is_playing() else -1,
			"water_shader_sha256":FileAccess.get_sha256(scene.get_node(str(scene.entry.id)).water_material.shader.resource_path),
			"targets":[]}
		for p in [Vector3(3,0,-2),Vector3(8,0,-2),Vector3(6,0,-10),Vector3(7,0,-5),Vector3(4,0,-9)]:
			data.pond.targets.append({"world":[p.x,p.z],"screen":_screen(scene.cam,p),"walkable":scene.mover.bp.is_walkable(scene.mover.bp.world_to_cell(p))})
	elif scene.scene_file_path == AppRouter.MAP and scene.city_map:
		data.map = {"ponds":scene.city_map.pond_locations,"selected":scene.city_map.selected,"pose":[scene.center_lat,scene.center_lng,scene.zoom,scene.bearing]}
	FileAccess.open("user://pond-device-proof/state.json",FileAccess.WRITE).store_string(JSON.stringify(data))

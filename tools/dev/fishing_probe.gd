extends Node
## Device-only observer. ADB uses the real controls' scene-tree bounds for touchscreen input.
const OUTPUT := "user://fishing-proof"
var scene: Node3D
var elapsed := 0.0
var phase_log: Array = []
var _last_phase := ""
var _switching := false

func _ready() -> void:
	Engine.max_fps = 60
	Localization.select_language("zh_CN")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for stale in ["command", "state.json"]:
		if FileAccess.file_exists(OUTPUT.path_join(stale)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT.path_join(stale)))
	var file := "res://fishing_account.json" if FileAccess.file_exists("res://fishing_account.json") else "res://output/fishing-2026-09-18/private/account.json"
	var account: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	var host := "10.0.2.2" if OS.get_name() == "Android" else "127.0.0.1"
	Net.use_transport(ApiClient.make_http_transport(self), "http://%s:3181/v1" % host)
	Net.client.token = str(account.token)
	Net.session.player_id = str(account.player)
	Net.online_available = true
	if not await Net.session.refresh():
		push_error("FISHING_QA_REFRESH_FAILED")
		get_tree().quit(1)
		return
	scene = AppRouter.push_instance(AppRouter.FARM, {"session": Net.session, "blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))})
	print("FISHING_PROBE_READY")

func _process(dt: float) -> void:
	if not is_instance_valid(scene) or _switching: return
	var panel: FishingPanel = scene.fishing_panel
	var phase := panel.phase if panel.visible else "closed"
	if phase != _last_phase:
		phase_log.append({"phase": phase, "at": Time.get_ticks_msec(), "site": panel.site_id})
		_last_phase = phase
	elapsed += dt
	if elapsed < 0.1: return
	elapsed = 0
	if FileAccess.file_exists(OUTPUT.path_join("command")):
		var command := FileAccess.get_file_as_string(OUTPUT.path_join("command")).strip_edges()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("command")))
		if command == "street": _street()
		elif command.begins_with("visit:") and scene is JourneyStreet: scene._go_fishing(command.trim_prefix("visit:"), Vector3.INF)
		elif command == "bag":
			if scene is JourneyStreet: scene._open_bag()
			else: scene._open_life()
		elif command == "disconnect": scene.online._disconnected("QA_FISHING_TRANSPORT")
	var data := {"phase": phase, "busy": panel.busy, "site": panel.site_id, "message": panel._status.text,
		"position": [scene.mover.position.x, scene.mover.position.z], "joined": scene.online.joined,
		"moving": scene.mover.is_moving(), "wallet": Net.session.state.get("wallet", 0), "bag": Net.session.state.get("bag", {}),
		"fishing": Net.session.state.get("fishing", {}), "model": panel.model, "unconfirmed": Net.session.has_unconfirmed_command(), "error": Net.session.last_error_code,
		"heading": panel._notice_heading.text, "notice_kind": panel._notice_kind,
		"feedback": {"particles": panel._gauge._particles, "progress": panel._gauge._display_progress, "meter_width": panel._gauge.meter_rect().size.x, "screen": _rect_of(panel._root)},
		"phases": phase_log, "controls": [], "remote_fishing": [], "water_targets": []}
	if is_instance_valid(scene.fishing_view):
		var view: FishingPresentation = scene.fishing_view
		data.presentation = {"pull": view.pull, "hand": [view.hand_position.x, view.hand_position.y, view.hand_position.z],
			"tip": [view.rod_tip.x, view.rod_tip.y, view.rod_tip.z], "float": [view.bobber_position.x, view.bobber_position.y, view.bobber_position.z],
			"gauge": _rect_of(panel._gauge), "action": _rect_of(panel._primary), "notice": _rect_of(panel._message_card)}
	for entry in scene.online.crowd.rigs:
		if is_instance_valid(entry.get("fishing_view")):
			var view: FishingPresentation = entry.fishing_view
			data.remote_fishing.append({"id": entry.id, "phase": view._phase, "pull": view.pull, "target": [view._landing.x, view._landing.z], "tip": [view.rod_tip.x, view.rod_tip.y, view.rod_tip.z], "visible": entry.root.visible})
	for id in FishingModel.data().sites:
		if FishingModel.site(id).space != ("street" if scene is JourneyStreet else "farm"): continue
		var spec := FishingModel.site(id)
		var points: Array = spec.path if spec.has("path") else [spec.center, [float(spec.center[0]) + float(spec.radii[0]) * 0.8, spec.center[1]], [float(spec.center[0]) - float(spec.radii[0]) * 0.8, spec.center[1]]]
		for index in points.size():
			var world := Vector3(points[index][0], 0, points[index][1])
			var screen: Vector2 = get_viewport().get_screen_transform() * scene.cam.unproject_position(world)
			data.water_targets.append({"site": id, "index": index, "point": points[index], "screen": [screen.x, screen.y]})
	_controls(scene, data.controls)
	var file := FileAccess.open(OUTPUT.path_join("state.tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("state.tmp")), ProjectSettings.globalize_path(OUTPUT.path_join("state.json")))

func _controls(node: Node, values: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is Control and node.is_visible_in_tree():
		if node is BaseButton or node is SpinBox or node == scene.fishing_panel._message_card:
			var rect: Rect2 = get_viewport().get_screen_transform() * node.get_global_rect()
			values.append({"name": str(node.name), "text": node.text if node is Button else "", "disabled": node.disabled if node is BaseButton else false,
				"bounds": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	for child in node.get_children(): _controls(child, values)

func _street() -> void:
	_switching = true
	if scene.fishing_panel.visible: await scene.fishing_panel.close()
	scene = AppRouter.push_instance(AppRouter.STREET, {"session": Net.session})
	_switching = false

func _rect_of(control: Control) -> Array:
	var rect := get_viewport().get_screen_transform() * control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

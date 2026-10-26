extends Node
## Temporary read-only observation of normal public gameplay; no account, transport or state injection.
var elapsed := 0.0
const OUTPUT := "user://game-ui-proof"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if FileAccess.file_exists(OUTPUT.path_join("state.json")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("state.json")))

func _rect_from(area: Rect2) -> Array:
	var rect := get_viewport().get_screen_transform() * area
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _rect(control: Control) -> Array:
	var rect := get_viewport().get_screen_transform() * control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _walk(node: Node, values: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is CanvasItem and not node.is_visible_in_tree(): return
	if node is BaseButton:
		values.append({"name": str(node.name), "path": str(node.get_path()), "text": node.text if node is Button else "",
			"disabled": node.disabled, "tooltip": node.tooltip_text, "bounds": _visible_rect(node)})
	for child in node.get_children(): _walk(child, values)

func _screen(cam: Camera3D, point: Vector3) -> Array:
	var screen: Vector2 = get_viewport().get_screen_transform() * cam.unproject_position(point)
	return [screen.x, screen.y]

func _process(dt: float) -> void:
	elapsed += dt
	if elapsed < 0.1: return
	elapsed = 0
	var scene := AppRouter.top_instance()
	if scene == null: scene = get_tree().current_scene
	if scene == null: return
	var controls: Array = []
	_walk(scene, controls)
	var data := {"ticks": Time.get_ticks_msec(), "scene": scene.scene_file_path, "controls": controls,
		"logged_in": Net.logged_in(), "has_farm": Net.session.has_farm(), "offline": Net.session.offline,
		"error": Net.session.last_error_code, "version": Net.session.version, "farm_id": Net.session.farm_id,
		"navigation_pending": AppRouter._navigation_pending, "wallet": Net.session.state.get("wallet", -1), "cells": Net.session.state.get("cells", {}),
		"inventory": Net.session.state.get("inventory", {}), "bag": Net.session.state.get("bag", {}),
		"fishing": Net.session.state.get("fishing", {}), "unconfirmed": Net.session.has_unconfirmed_command()}
	if scene.scene_file_path.contains("map_poc"):
		var actual_camera := get_viewport().get_camera_3d()
		data.map_pose = {"lat": scene.center_lat, "lng": scene.center_lng, "zoom": scene.zoom, "anchor_lat": scene.anchor_lat, "anchor_lng": scene.anchor_lng, "native": scene.map.camera_info() if scene.map else "", "owns_camera": actual_camera == scene.cam, "touches": scene._touch_count, "drag": scene._drag_accum_px}
	data.ui_density = {"icon_logical": [GameUi.icon("backpack").get_width(), GameUi.icon("backpack").get_height()], "icon_pixels": GameUi.icon("backpack").get_image().get_width()}
	data.character_previews = []
	for preview in scene.find_children("*", "TextureRect", true, false):
		if preview is BagCharacterPreview and preview.is_visible_in_tree(): data.character_previews.append({"logical": [preview.size.x, preview.size.y], "pixels": [preview.viewport.size.x, preview.viewport.size.y], "rendering": preview.viewport.render_target_update_mode})
	data.bag_panels = []
	for bag in scene.find_children("*", "Control", true, false):
		if bag is BagPanel and bag.is_visible_in_tree(): data.bag_panels.append({"page": bag.page, "mode": bag.mode, "selected": bag.selected_stack, "columns": bag.grid.columns if bag.grid else 0, "bounds": _rect(bag), "search": _rect(bag.search) if bag.search else [], "query": bag.query})
	data.hand_stats = CharacterModel.main_hand_stats(Net.session.state)
	data.slots = CharacterModel.SLOTS
	data.labels = []
	_labels(scene, data.labels)
	data.joined = scene.get("online") != null and scene.online.joined
	data.busy = bool(scene.get("busy")) if scene.get("busy") != null else false
	data.scrolls = []
	_scrolls(scene, data.scrolls)
	data.world_targets = {}
	data.viewport = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	data.screen_bounds = _rect_from(get_viewport().get_visible_rect())
	data.reflections = []
	for reflection in scene.find_children("PlanarBankReflection", "Node3D", true, false):
		data.reflections.append({"site": reflection.get_parent().site_id, "captures": reflection._captures, "enabled": reflection.material.get_shader_parameter("has_bank_reflection")})
	if scene.get("mover") != null:
		data.position = [scene.mover.position.x, scene.mover.position.z]
		data.moving = scene.mover.is_moving()
		data.remaining_path = scene.mover.remaining_path().map(func(p): return [p.x, p.z])
		data.fishing_pending = scene.get("_fishing_pending")
		data.fishing_plan = scene.get("_fishing_plan")
		data.fps = Engine.get_frames_per_second()
		data.camera = {"position": _xyz(scene.cam.global_position), "size": scene.cam.size, "near": scene.cam.near, "far": scene.cam.far}
		data.water_targets = []
		for id in FishingModel.data().sites:
			var spec := FishingModel.site(id)
			if spec.space != ("street" if scene is JourneyStreet else "farm"): continue
			var center: Array = spec.center if spec.has("center") else spec.path[1]
			data.water_targets.append({"site": id, "screen": _screen(scene.cam, Vector3(center[0], 0, center[1]))})
	if scene.scene_file_path.contains("farm/farm"):
		data.player_screen = _screen(scene.cam, scene.player.global_position)
		data.avatar_indicator = {"visible": scene._focus_button.visible, "rect": _rect(scene._focus_button), "portrait_pixels": scene._focus_button.portrait.texture.get_image().get_size() if scene._focus_button.portrait.texture else Vector2i.ZERO}
		data.player_focus_screen = _screen(scene.cam, scene.player.global_position + Vector3.UP * 0.7)
		data.camera_center = _xyz(scene._camera_center)
		data.work_mode = scene.work_mode
		data.action_busy = scene.runner.is_busy() or scene._in_flight > 0
		data.farm_targets = []
		for y in scene.bp.grid.y:
			for x in scene.bp.grid.x:
				var cell := Vector2i(x, y)
				if not scene.bp.mask_has("cultivable", cell): continue
				var world: Vector3 = scene.bp.cell_to_world(cell)
				if world.distance_to(scene.mover.position) > 4.5: continue
				var screen: Vector2 = scene.cam.unproject_position(world)
				if not scene._camera_play_area().grow(-24).has_point(screen): continue
				data.farm_targets.append({"id": "%d,%d" % [x,y], "screen": _screen(scene.cam,world), "distance": world.distance_to(scene.mover.position)})
		data.modal = GameUi.modal_is_open(scene)
		data.world_area = _rect_from(scene._camera_play_area())
		data.plot_layout = scene.bp.layout_patch_id
		data.geo_layout = scene.geo_blueprint.layout_patch_id
		var rect: Rect2 = get_viewport().get_screen_transform() * scene._mine_pick_rect()
		data.world_targets.mine = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		var route: Array[Vector3] = scene.grid.point_path(scene.mover.position, scene.mine_approach())
		var previous: Vector3 = scene.mover.position
		var area: Rect2 = scene._camera_play_area().grow(-32)
		for destination in route:
			for index in range(1, maxi(2, ceili(previous.distance_to(destination) / 0.4) + 1)):
				var point := previous.move_toward(destination, float(index) * 0.4)
				var projected: Vector2 = scene.cam.unproject_position(point)
				if point.distance_to(scene.mover.position) > 0.7 and area.has_point(projected):
					var screen: Vector2 = get_viewport().get_screen_transform() * projected
					data.world_targets.mine_waypoint = [screen.x - 5, screen.y - 5, 10, 10]
			previous = destination
	elif scene.scene_file_path.contains("mine/"):
		data.mine = Net.session.state.get("mine", {})
		data.world = scene.online.world if scene.get("online") else {}
		for id in scene.targets:
			var target: Dictionary = scene.targets[id]
			if not target.has("model") or not is_instance_valid(target.model): continue
			var rect: Rect2 = get_viewport().get_screen_transform() * scene._model_pick_rect(target.model)
			if rect.has_area(): data.world_targets[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if scene.get("fishing_panel") != null:
		var panel: FishingPanel = scene.fishing_panel
		data.phase = panel.phase if panel.visible else "closed"
		data.site = panel.site_id
		data.model = panel.model
		data.busy = panel.busy
		data.message = panel._status.text
		data.heading = panel._notice_heading.text
		data.notice_kind = panel._notice_kind
		data.feedback = {"particles": panel._gauge._particles, "progress": panel._gauge._display_progress,
			"meter_width": panel._gauge.meter_rect().size.x, "screen": _rect(panel._root)}
		data.joined = scene.online != null and scene.online.joined
		data.position = [scene.mover.position.x, scene.mover.position.z]
		data.moving = scene.mover.is_moving()
		data.remaining_path = scene.mover.remaining_path().map(func(p): return [p.x, p.z])
		data.fishing_pending = scene.get("_fishing_pending")
		data.fishing_plan = scene.get("_fishing_plan")
		data.fps = Engine.get_frames_per_second()
		data.camera = {"position": _xyz(scene.cam.global_position), "size": scene.cam.size, "near": scene.cam.near, "far": scene.cam.far}
		data.water_targets = []
		for id in FishingModel.data().sites:
			var spec := FishingModel.site(id)
			if spec.space != ("street" if scene is JourneyStreet else "farm"): continue
			var center: Array = spec.center if spec.has("center") else spec.path[1]
			data.water_targets.append({"site": id, "screen": _screen(scene.cam, Vector3(center[0], 0, center[1]))})
		if is_instance_valid(scene.fishing_view):
			var view: FishingPresentation = scene.fishing_view
			data.presentation = {"pull": view.pull, "hand": _xyz(view.hand_position), "tip": _xyz(view.rod_tip), "float": _xyz(view.bobber_position),
				"rope_start": _xyz(view.line_points[0]), "rope_end": _xyz(view.line_points[-1]),
				"gauge": _rect(panel._gauge), "action": _rect(panel._primary), "notice": _rect(panel._message_card),
				"notice_visible": panel._message_card.visible, "fps": Engine.get_frames_per_second()}
		data.fish_routes = {}
		if scene is JourneyStreet:
			var area: Rect2 = scene._world_area().grow(-24)
			area.position += scene.ui.global_position
			for id in FishingModel.data().sites:
				if FishingModel.site(id).space != "street": continue
				var route: Array[Vector3] = scene.mover.grid.point_path(scene.mover.position, FishingModel.stand(id))
				var previous: Vector3 = scene.mover.position
				var best: Variant = null
				for destination in route:
					var length := previous.distance_to(destination)
					for index in range(1, maxi(2, ceili(length / 0.4) + 1)):
						var point := previous.move_toward(destination, float(index) * 0.4)
						if scene.cam.is_position_behind(point): continue
						var screen: Vector2 = scene.cam.unproject_position(point)
						if area.has_point(screen) and point.distance_to(scene.mover.position) > 0.5:
							best = {"point": _screen(scene.cam, point), "position": [point.x, point.z]}
					previous = destination
				data.fish_routes[id] = best
	var file := FileAccess.open(OUTPUT.path_join("state.tmp"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("state.tmp")), ProjectSettings.globalize_path(OUTPUT.path_join("state.json")))

func _xyz(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func _visible_rect(node: Control) -> Array:
	var rect := node.get_global_rect()
	var parent := node.get_parent()
	while parent:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	rect = rect.intersection(get_viewport().get_visible_rect())
	rect = get_viewport().get_screen_transform() * rect
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _labels(node: Node, labels: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is CanvasItem and not node.is_visible_in_tree(): return
	if node is Label and not node.text.is_empty(): labels.append(node.text)
	for child in node.get_children(): _labels(child, labels)

func _scrolls(node: Node, result: Array) -> void:
	if node is CanvasLayer and not node.visible: return
	if node is CanvasItem and not node.is_visible_in_tree(): return
	if node is ScrollContainer: result.append({"name": str(node.name), "bounds": _rect(node), "offset": node.scroll_vertical})
	for child in node.get_children(): _scrolls(child, result)

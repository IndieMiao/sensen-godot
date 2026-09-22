extends Node
## Read-only scene geometry for host ADB input. Never dispatches gameplay actions.

var elapsed := 0.0
var sending := false
var touches: Array = []
var launch_id := ""
var motion: Array = []
var resident_motion: Array = []
var motion_elapsed := 0.0
var was_moving := false
var feedback_events: Array = []
var feedback_key := ""
var camera_samples: Array = []
var camera_was_moving := false
var gesture_events: Array = []
var queue_events: Array = []
var queue_key := ""

func _ready() -> void:
	launch_id = str(Time.get_unix_time_from_system())
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		gesture_events.append({"ticks_ms": Time.get_ticks_msec(), "pointer": event.index, "pressed": event.pressed, "canceled": event.canceled})
		if gesture_events.size() > 100: gesture_events.pop_front()
	if event is InputEventScreenTouch and event.pressed:
		var point: Vector2 = get_viewport().get_screen_transform() * event.position
		touches.append({"ticks_ms": Time.get_ticks_msec(), "screen": [point.x, point.y]})
		if touches.size() > 100: touches.pop_front()

func _process(delta: float) -> void:
	motion_elapsed += delta
	if motion_elapsed >= 0.05:
		motion_elapsed = 0
		_record_motion()
		_record_feedback()
		_record_camera()
	elapsed += delta
	if elapsed < 1 or sending: return
	elapsed = 0
	sending = true
	_publish()

func _publish() -> void:
	# Observe input before newly pushed scenes consume their ongoing gestures.
	get_parent().move_child(self, -1)
	var scene := AppRouter.top_instance()
	if scene == null: scene = get_tree().current_scene
	var controls: Array = []
	if scene: _walk(scene, controls)
	var snapshot := {"launch_id": launch_id, "ticks_ms": Time.get_ticks_msec(), "scene": str(scene.get_path()) if scene else "",
		"controls": controls, "touches": touches.duplicate(true), "motion": motion.duplicate(true), "state": Net.session.state,
		"version": Net.session.version, "offline": Net.session.offline,
		"fps": Engine.get_frames_per_second(), "native_map_plugin": Engine.has_singleton("GodotMap")}
	if scene and scene.scene_file_path == AppRouter.MAP:
		snapshot.map_fallback = scene.map == null or scene._header_locked
		snapshot.map_camera = _map_camera(scene)
		if scene.get("farm_markers") != null:
			var markers: FarmMarkers = scene.farm_markers
			var character_scales := {}
			var base_scale: float = maxf(scene._cam_distance() / scene.CHAR_DIST_PER_SCALE, 0.001)
			for pawn in scene._pawns:
				if pawn.node.visible:
					character_scales[str(pawn.cohort).trim_prefix("farm:")] = pawn.node.scale.x / base_scale
			var owner_screen: Vector2 = get_viewport().get_screen_transform() * (markers._selected_anchor + markers.global_position)
			var model_screen: Vector2 = get_viewport().get_screen_transform() * scene.cam.unproject_position(markers.miniature.position)
			snapshot.social = {"selected": markers.selected_id, "expanded": markers.expanded_ids.duplicate(),
				"owner_screen": [owner_screen.x, owner_screen.y], "model_screen": [model_screen.x, model_screen.y],
				"character_scales": character_scales, "plot_outline_visible": scene.farm_overlay and scene.farm_overlay.is_visible_in_tree(),
				"visible_characters": markers.visible_farm_ids.duplicate(), "model_visible": markers.miniature.is_visible_in_tree(),
				"model_type": markers.miniature.get_class(), "model_scale": _vector(markers.miniature.scale),
				"model_position": _vector(markers.miniature.position)}
	var place: JourneyPlace = scene if scene is JourneyPlace else (scene.get("journey_scene") as JourneyPlace if scene else null)
	if place: snapshot.world = _world(place)
	if scene is JourneyStreet:
		snapshot.world = _street_world(scene)
	elif scene and scene.scene_file_path == AppRouter.MINE:
		snapshot.world = _mine_world(scene)
	elif scene and scene.get("hints") is PlotHints:
		var hints := scene.hints as PlotHints
		snapshot.world = {"place": "farm", "controls": [], "moving": scene.mover.is_moving(),
			"busy": scene.runner.is_busy() or scene._in_flight > 0, "camera_pan": _vector(scene.camera_pan.offset),
			"camera": _vector(scene.cam.position), "zoom": scene.camera_pan.zoom, "player": _vector(scene.player.position)}
		snapshot.world.queued = hints.queued.map(func(cell): return FarmBlueprint._cs(cell))
		snapshot.world.animation = scene._rig.get_node("AnimationPlayer").current_animation
		_ground_controls(scene.cam, scene.bp, Vector3.ZERO, scene._camera_play_area(), snapshot.world.controls, scene)
		for id in hints._targets:
			if not hints.cells.has(id): continue
			var point: Vector2 = get_viewport().get_screen_transform() * (hints._targets[id] + hints.global_position)
			snapshot.world.controls.append({"path": "plot:" + str(id), "text": "", "tooltip": "", "button": true,
				"disabled": false, "rect": [point.x - 2, point.y - 2, 4, 4], "source": "rendered_plot_hint",
				"action": NextStep.step_for(hints.cells[id], hints.now_ms)})
		_farm_mine_entrance(scene, snapshot.world)
	snapshot.feedback_events = feedback_events.duplicate(true)
	snapshot.queue_events = queue_events.duplicate(true)
	snapshot.camera_samples = camera_samples.duplicate(true)
	snapshot.gesture_events = gesture_events.duplicate(true)
	snapshot.resident_motion = resident_motion.duplicate(true)
	await Net.client.request("POST", "/qa/journey/scene", snapshot)
	sending = false

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _record_camera() -> void:
	var scene := AppRouter.top_instance()
	if scene == null: scene = get_tree().current_scene
	if scene == null: return
	if scene.get("journey_map") != null:
		var moving: bool = scene._touch_count > 0 or absf(scene._zoom_vel) > 0.001 or absf(scene._zoom_elastic) > 0.001 or scene._fling_vel.length() > 0.001
		if moving or camera_was_moving:
			var sample := _map_camera(scene)
			sample.ticks_ms = Time.get_ticks_msec()
			sample.place = "map"
			camera_samples.append(sample)
			if camera_samples.size() > 240: camera_samples.pop_front()
		camera_was_moving = moving
		return
	var place := scene.get("journey_scene") as JourneyPlace
	var source: Node = place if place else scene
	var controller = source.get("camera_pan")
	if controller == null: return
	var moving: bool = controller.active() or controller.moving()
	if moving or camera_was_moving:
		camera_samples.append({"ticks_ms": Time.get_ticks_msec(), "place": place.place_id if place else ("street" if source is JourneyStreet else ("mine" if source.scene_file_path == AppRouter.MINE else "farm")),
			"pan": _vector(controller.offset), "zoom": controller.zoom, "velocity": _vector(controller.velocity),
			"zoom_velocity": controller.zoom_velocity, "pointers": controller.pointers.size(),
			"camera_size": source.cam.size, "player": _vector(source.player.position)})
		if camera_samples.size() > 240: camera_samples.pop_front()
	camera_was_moving = moving

func _map_camera(scene: Node) -> Dictionary:
	return {"zoom": scene.zoom, "elastic": scene._zoom_elastic, "pitch": scene.pitch,
		"region": str(scene.region.get("id", "")), "center": [scene.center_lat, scene.center_lng],
		"home": [scene.home_lat, scene.home_lng], "anchor": [scene.anchor_lat, scene.anchor_lng],
		"zoom_velocity": scene._zoom_vel, "velocity": _vector(scene._fling_vel), "pointers": scene._touch_count}

func _record_feedback() -> void:
	var scene := AppRouter.top_instance()
	if scene == null: return
	var place := scene.get("journey_scene") as JourneyPlace
	var hints: PlotHints = place.ground_feedback if place else scene.get("hints") as PlotHints
	if hints and scene.get("runner") != null:
		var queued: Array = hints.queued.map(func(cell): return FarmBlueprint._cs(cell))
		var key := JSON.stringify(queued)
		if key != queue_key:
			queue_key = key
			queue_events.append({"ticks_ms": Time.get_ticks_msec(), "queued": queued, "visible": hints.is_visible_in_tree()})
			if queue_events.size() > 120: queue_events.pop_front()
	if hints == null or not hints._destination_visible: return
	var key := str(scene.get_instance_id()) + str(hints._destination) + str(hints._reachable)
	if key == feedback_key: return
	feedback_key = key
	feedback_events.append({"ticks_ms": Time.get_ticks_msec(), "destination": _vector(hints._destination),
		"reachable": hints._reachable, "visible": hints.is_visible_in_tree(), "age": hints._age})
	if feedback_events.size() > 60: feedback_events.pop_front()

func _record_motion() -> void:
	var scene := AppRouter.top_instance()
	if scene == null: return
	var place: JourneyPlace = scene if scene is JourneyPlace else scene.get("journey_scene") as JourneyPlace
	var source: Node = place if place else scene
	var mover := source.get("mover") as PlayerMover
	if mover == null: return
	var moving := mover.is_moving()
	var mine := source.scene_file_path == AppRouter.MINE
	var mine_busy: bool = mine and (source.busy or not source._dig_target.is_empty())
	if moving or was_moving or mine_busy or (place and place.busy) or (source is JourneyStreet and source.busy) or (source.get("runner") != null and source.runner.is_busy()):
		var rig: Node = place.rig if place else (source.rig if mine else source.get("_rig") as Node)
		var animation := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer if rig else null
		motion.append({"ticks_ms": Time.get_ticks_msec(), "scene": str(scene.get_path()),
			"place": place.place_id if place else ("street" if source is JourneyStreet else ("mine" if mine else "farm")), "position": [mover.position.x, mover.position.z],
			"moving": moving, "speed": mover.speed, "world_scale": mover.world_scale,
			"busy": place.busy if place else (source.busy if source is JourneyStreet else mine_busy),
			"animation": animation.current_animation if animation else "",
			"animation_position": animation.current_animation_position if animation and not animation.current_animation.is_empty() else 0.0})
		if mine:
			motion[-1].floor = source.current_floor()
			motion[-1].pending = source.pending_target
			motion[-1].dig_target = source._dig_target
			motion[-1].dig_elapsed = source._dig_elapsed
		if motion.size() > 120: motion.pop_front()
	was_moving = moving
	if source is JourneyStreet and source.residents:
		for slot in source.residents.moments:
			var moment: ResidentMoment = source.residents.moments[slot]
			var animation := moment.actor.get_node_or_null("AnimationPlayer") as AnimationPlayer
			resident_motion.append({"ticks_ms": Time.get_ticks_msec(), "scene": "street", "resident": slot,
				"position": _vector(moment.actor.position), "phase": moment.phase,
				"animation": animation.current_animation if animation else "",
				"animation_position": animation.current_animation_position if animation and not animation.current_animation.is_empty() else 0,
				"player_distance": moment.actor.position.distance_to(source.player.position)})
			if resident_motion.size() > 400: resident_motion.pop_front()
	if place:
		for moment in place.resident_moments.values():
			if not moment.active(): continue
			var animation := moment.actor.get_node_or_null("AnimationPlayer") as AnimationPlayer
			resident_motion.append({"ticks_ms": Time.get_ticks_msec(), "resident": str(moment.actor.name),
				"position": _vector(moment.actor.position), "phase": moment.phase,
				"activity": place.resident_activities.get(str(moment.actor.name), ""),
				"animation": animation.current_animation if animation else "",
				"animation_position": animation.current_animation_position if animation and not animation.current_animation.is_empty() else 0,
				"player_distance": moment.actor.position.distance_to(place.player.position)})
			if resident_motion.size() > 400: resident_motion.pop_front()

func _walk(node: Node, result: Array) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is CanvasLayer and not node.visible: return
	if node is Window and not node.visible: return
	if node is BaseButton or node is Label or node is LineEdit or node is SpinBox or node is TouchStick:
		var control := node as Control
		var rect := control.get_global_rect()
		var parent := control.get_parent()
		while parent:
			if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
			parent = parent.get_parent()
		rect = rect.intersection(get_viewport().get_visible_rect())
		if rect.has_area():
			var screen := get_viewport().get_screen_transform() * rect
			result.append({"path": str(node.get_path()), "text": str(node.value) if node is SpinBox else str(node.get("text")), "tooltip": control.tooltip_text,
				"button": node is BaseButton or node is LineEdit or node is SpinBox or node is TouchStick, "disabled": node.disabled if node is BaseButton else (not node.editable if node is LineEdit or node is SpinBox else false),
				"rect": [screen.position.x, screen.position.y, screen.size.x, screen.size.y]})
	for child in node.get_children(): _walk(child, result)

func _farm_mine_entrance(farm: Node, world: Dictionary) -> void:
	var entrance := farm.get("mine_entrance") as Node3D
	if not is_instance_valid(entrance) or not farm.has_method("_mine_pick_rect"): return
	world.mine_entrance = {"position": _vector(entrance.position), "pending": farm._mine_pending,
		"visible": entrance.is_visible_in_tree(), "button_visible": false,
		"player_distance": farm.player.position.distance_to(entrance.position)}
	if farm.visitor or not entrance.is_visible_in_tree() or farm.hud.modal_open(): return
	var rect: Rect2 = farm._mine_pick_rect()
	if not rect.has_area(): return
	var point := get_viewport().get_screen_transform() * rect.get_center()
	world.controls.append({"path": "body:mine_entrance", "text": "", "tooltip": L10n.text("Starter mine"),
		"button": true, "disabled": world.busy or farm.session == null or farm.session.offline or farm.session.has_unconfirmed_command(),
		"rect": [point.x - 2, point.y - 2, 4, 4], "source": "camera_projected_mine_entrance"})

func _mine_world(mine: Node) -> Dictionary:
	var state: Dictionary = mine.mine_state()
	var mover := mine.mover as PlayerMover
	var camera := mine.cam as Camera3D
	var can_act: bool = mine._can_act()
	var result := {"place": "mine", "floor": mine.current_floor(), "run": int(state.get("run", 0)),
		"cleared": mine.cleared(), "completed": mine.completed(), "cleared_floors": state.get("cleared_floors", []).duplicate(),
		"broken": mine.broken().duplicate(), "elevator_unlocked": bool(state.get("elevator_unlocked", false)),
		"player": _vector(mine.player.position), "moving": mover.is_moving() if mover else false,
		"busy": mine.busy or not mine._dig_target.is_empty() or (mine.session != null and mine.session.has_unconfirmed_command()),
		"command_busy": mine.busy, "can_act": can_act, "pending": mine.pending_target,
		"dig": {"target": mine._dig_target, "elapsed": mine._dig_elapsed, "duration": mine.DIG_SECONDS, "progress": mine.progress.value},
		"animation": mine._anim, "camera_pan": _vector(mine.camera_pan.offset), "camera": _vector(camera.position),
		"zoom": mine.camera_pan.zoom, "camera_size": camera.size, "controls": [], "markers": {}, "path": []}
	if mover:
		for point in mover.remaining_path(): result.path.append(_vector(point))
		result.navigation = {"cell_m": mover.bp.cell_m, "walkable": mover.bp.masks.walkable,
			"joystick": [mover.joystick.x, mover.joystick.y], "speed": mover.speed}
		for y in mover.bp.grid.y:
			for x in mover.bp.grid.x:
				var cell := Vector2i(x, y)
				if not mover.bp.is_walkable(cell): continue
				var world := mover.bp.cell_to_world(cell)
				var point := camera.unproject_position(world)
				if not mine.world_area().has_point(point) or not mine._pick_target(point).is_empty(): continue
				var screen := get_viewport().get_screen_transform() * point
				result.controls.append({"path": "walk:%d,%d" % [x, y], "world": _vector(world), "text": "", "tooltip": "", "button": true,
					"disabled": not can_act, "rect": [screen.x - 2, screen.y - 2, 4, 4], "source": "camera_projected_ground"})
	if mine.get("combat") != null:
		result.combat = {"paused": mine._paused, "focused": mine._focused, "cooldown": mine.combat.cooldown,
			"invulnerability": mine.combat.invulnerability, "grace": mine.combat.grace, "enemies": {},
			"sending": mine._combat_sending, "pending": mine.prediction.pending.size(),
			"swing_left": mine.combat._swing_left, "weapon_visible": is_instance_valid(mine._weapon_model) and mine._weapon_model.is_visible_in_tree(),
			"predicted_hp": CharacterModel.hp(mine._combat_view), "stalled": mine._combat_stalled()}
		for id in mine.combat.enemies:
			var enemy: Dictionary = mine.combat.enemies[id]
			result.combat.enemies[id] = {"position": _vector(enemy.node.position), "hp": enemy.hp,
				"max_hp": enemy.spec.hp, "move_speed": enemy.spec.move_speed, "stun_resistant": enemy.spec.stun_resistant,
				"phase": enemy.phase, "timer": enemy.timer, "direction": _vector(enemy.direction)}
	for id in mine.targets:
		var target: Dictionary = mine.targets[id]
		var button := target.button as Button
		var anchor := camera.unproject_position(target.world)
		result.markers[id] = {"world": _vector(target.world), "body": _vector(target.body), "approach": _vector(target.approach),
			"anchor": [anchor.x, anchor.y], "visible": button.is_visible_in_tree(), "disabled": button.disabled,
			"error": anchor.distance_to(button.get_global_rect().get_center())}
		var body := camera.unproject_position(target.body)
		if not camera.is_position_behind(target.body) and mine.world_area().has_point(body) and mine._pick_target(body) == id:
			var screen := get_viewport().get_screen_transform() * body
			result.controls.append({"path": "body:" + str(id), "text": "", "tooltip": button.tooltip_text, "button": true,
				"disabled": button.disabled or not can_act, "rect": [screen.x - 2, screen.y - 2, 4, 4], "source": "camera_projected_mine_body"})
		if not button.is_visible_in_tree(): continue
		var center := button.get_global_rect().get_center()
		if mine._pick_target(center) != id: continue
		var screen := get_viewport().get_screen_transform() * center
		result.controls.append({"path": "mine:" + str(id), "text": "", "tooltip": button.tooltip_text, "button": true,
			"disabled": button.disabled or not can_act, "rect": [screen.x - 2, screen.y - 2, 4, 4], "source": "camera_projected_mine_target"})
	return result

func _world(place: JourneyPlace) -> Dictionary:
	var result := {"place": place.place_id, "player": [place.player.position.x, place.player.position.z],
		"moving": place.mover.is_moving(), "busy": place.busy or place.session.has_unconfirmed_command(),
		"pending": place.pending_target, "controls": [], "projects": {}, "camera_pan": _vector(place.camera_pan.offset),
		"camera": _vector(place.cam.position), "zoom": place.camera_pan.zoom, "markers": {}, "display_project": place.display_project}
	result.meal = {"recipe": place.served_recipe, "visible": is_instance_valid(place.served_dish) and place.served_dish.is_visible_in_tree(),
		"phase": place.meal_moment.phase if place.meal_moment and not place._meal_residents.is_empty() else "idle",
		"target": place.served_target, "position": _vector(place.served_dish.position) if is_instance_valid(place.served_dish) else [],
		"participants": place._meal_residents.duplicate()}
	result.activities = place.resident_activities.duplicate()
	result.residents = {}
	for actor in place.cast.get_children(): result.residents[str(actor.name)] = _vector(actor.position)
	for id in place.targets:
		var target: Dictionary = place.targets[id]
		var anchor := place.cam.unproject_position(target.world)
		result.markers[id] = {"anchor": [anchor.x, anchor.y], "alpha": target.button.modulate.a,
			"error": anchor.distance_to(target.button.get_global_rect().get_center())}
		var body := place.cam.unproject_position(target.body)
		var area := Rect2(place.ui.global_position + Vector2(0, place.header.size.y + 8), Vector2(place.ui.size.x, place.ui.size.y - place.header.size.y - 64))
		var in_mode := place.display_project.is_empty() or str(id).begins_with("display:" + place.display_project + ":")
		if not place.panel.visible and in_mode and area.grow(-22).has_point(body) and not place.cam.is_position_behind(target.body):
			var screen := get_viewport().get_screen_transform() * body
			result.controls.append({"path": "object:" + str(id), "text": "", "tooltip": "", "button": true,
				"disabled": place.busy or place.session.offline or place.session.has_unconfirmed_command(),
				"rect": [screen.x - 2, screen.y - 2, 4, 4], "source": "camera_projected_object"})
	if not place.panel.visible:
		_ground_controls(place.cam, place.nav, JourneyPlace.NAV_ORIGIN,
			Rect2(place.ui.global_position + Vector2(0, place.header.size.y + 12), Vector2(place.ui.size.x, place.ui.size.y - place.header.size.y - 76)), result.controls, place)
	for id in JourneyProgress.data().projects:
		if JourneyProgress.data().projects[id].place == place.place_id:
			result.projects[id] = JourneyProgress.project_stage(place.session.state, str(id))
	if place.active_panel is DecorationPanel and place.panel.visible:
		var editor := place.active_panel as DecorationPanel
		result.arrangement = {"selected": editor.selected_prop, "dirty": editor.dirty, "preview": editor.preview()}
		var bounds: Dictionary = DecorationLayout.data().bounds_q
		for z in range(int(bounds.min_z), int(bounds.max_z) + 1):
			for x in range(int(bounds.min_x), int(bounds.max_x) + 1):
				var q := Vector2i(x, z)
				if not DecorationLayout.is_valid(DecorationLayout.with_position(editor.preview(), editor.selected_prop, q)): continue
				var world := DecorationLayout.world_position(DecorationLayout.entry(editor.selected_prop, q))
				var point := place.cam.unproject_position(world)
				if place.panel.get_global_rect().grow(12).has_point(point): continue
				if point.y < place.ui.global_position.y + 110 or point.y > place.ui.global_position.y + place.ui.size.y - 60: continue
				if not get_viewport().get_visible_rect().grow(-12).has_point(point): continue
				var screen := get_viewport().get_screen_transform() * point
				result.controls.append({"path": "ground:%d,%d" % [x, z], "text": "", "tooltip": "", "button": true, "disabled": false,
					"rect": [screen.x - 2, screen.y - 2, 4, 4], "source": "camera_projected_legal_ground"})
	return result

func _ground_controls(camera: Camera3D, blueprint: FarmBlueprint, origin: Vector3, area: Rect2, controls: Array, scene: Node) -> void:
	for z in blueprint.grid.y:
		for x in blueprint.grid.x:
			var cell := Vector2i(x, z)
			if scene is JourneyPlace:
				if scene.panel.visible: continue
			elif not scene is JourneyStreet and scene._is_plot(cell): continue
			var world := blueprint.cell_to_world(cell) + origin
			var point := camera.unproject_position(world)
			if not area.grow(-20).has_point(point): continue
			var covered := false
			if scene is JourneyPlace:
				for target in scene.targets.values():
					if target.button.visible and target.button.get_global_rect().grow(10).has_point(point): covered = true
					var object_point := camera.unproject_position(target.body)
					if object_point.distance_to(point) < 34: covered = true
			elif scene is JourneyStreet:
				for target in scene.targets.values():
					if target.button.visible and target.button.get_global_rect().grow(20).has_point(point): covered = true
					if target.has("body") and camera.unproject_position(target.body).distance_to(point) < 34: covered = true
			elif scene.hints.pick(point) != null: covered = true
			if covered: continue
			var screen := get_viewport().get_screen_transform() * point
			controls.append({"path": ("walk:" if blueprint.is_walkable(cell) else "blocked:") + "%d,%d" % [x, z],
				"text": "", "tooltip": "", "button": true, "disabled": false,
				"rect": [screen.x - 2, screen.y - 2, 4, 4], "source": "camera_projected_ground"})

func _street_world(street: JourneyStreet) -> Dictionary:
	var result := {"place": "street", "layout": street.layout.source.layout_patch_id,
		"player": _vector(street.player.position), "moving": street.mover.is_moving(),
		"busy": street.busy or street.session.has_unconfirmed_command() or (street.active_panel and street.active_panel.busy), "pending": street.pending,
		"dialogue": street.dialogue.visible, "selected_slot": street.selected_slot, "residents": {}, "commons": {},
		"camera_pan": _vector(street.camera_pan.offset), "camera": _vector(street.cam.position), "zoom": street.camera_pan.zoom,
		"camera_size": street.cam.size, "camera_base_size": street._base_size,
		"controls": [], "markers": {}, "entrances": {}, "path": []}
	for id in street.layout.entrances: result.entrances[id] = _vector(street.layout.entrances[id])
	for slot in street.residents.moments:
		var moment: ResidentMoment = street.residents.moments[slot]
		result.residents[slot] = {"position": _vector(moment.actor.position), "phase": moment.phase}
	for slot in street.layout.commons: result.commons[slot] = _vector(street.layout.commons[slot].position)
	result.gatherings = {}
	for theme in street.layout.gatherings:
		var venue: Dictionary = street.layout.gatherings[theme]
		var table := street.gatherings.get_node("Gathering_" + str(theme))
		result.gatherings[theme] = {"position": _vector(venue.position), "approach": _vector(venue.approach),
			"guests": venue.guests.map(func(p): return _vector(p)), "hosted": table.get_meta("hosted"),
			"retained_piece": table.has_node("RetainedPiece")}
	for point in street.mover.remaining_path(): result.path.append(_vector(point))
	for id in street.targets:
		var target: Dictionary = street.targets[id]
		var button: Button = target.button
		var anchor := street.cam.unproject_position(target.world)
		result.markers[id] = {"anchor": [anchor.x, anchor.y], "alpha": button.modulate.a,
			"visible": button.visible, "error": anchor.distance_to(button.get_global_rect().get_center())}
		if target.has("body") and not street.dialogue.visible and not street.cam.is_position_behind(target.body):
			var body := street.cam.unproject_position(target.body)
			if street._world_area().grow(-12).has_point(body - street.ui.global_position):
				var point := get_viewport().get_screen_transform() * body
				result.controls.append({"path": "body:" + str(id), "text": "", "tooltip": "", "button": true,
					"disabled": button.disabled, "rect": [point.x - 2, point.y - 2, 4, 4], "source": "camera_projected_resident_body"})
		if not button.visible: continue
		var point := get_viewport().get_screen_transform() * button.get_global_rect().get_center()
		result.controls.append({"path": "street:" + str(id), "text": "", "tooltip": "", "button": true,
			"disabled": button.disabled, "rect": [point.x - 2, point.y - 2, 4, 4], "source": "camera_projected_street_target"})
	_ground_controls(street.cam, street.layout.nav, Vector3.ZERO, street._world_area(), result.controls, street)
	return result

extends Node

var output := ""
var errors: Array[String] = []

func _ready() -> void:
	output = OS.get_environment("SENSEN_JOURNEY_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(60).timeout.connect(func():
		push_error("Journey smoke timed out")
		get_tree().quit(1))
	call_deferred("_run")

func _run() -> void:
	get_tree().root.content_scale_size = Vector2i(360, 640)
	get_tree().root.size = Vector2i(360, 640)
	if Net.session.farm_id.is_empty():
		if not await Net.session.ensure_farm("shanghai", "sh_a", 2):
			push_error("Cannot create smoke farm")
			get_tree().quit(1)
			return
	FarmRegions.save_choice("shanghai")
	FarmChoice.save("sh_a", 2)
	AppRouter.go_to_map()
	await get_tree().create_timer(3).timeout
	var map := get_tree().current_scene
	if map.get("journey_map") == null:
		errors.append("Map did not show journey places")
	else:
		for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
			get_tree().root.content_scale_size = size
			get_tree().root.size = size
			await get_tree().create_timer(0.2).timeout
			var rects: Array[Rect2] = []
			for id in map.journey_map.buttons:
				var b: Button = map.journey_map.buttons[id]
				if not b.visible: errors.append("Place not visible: " + id)
				for rect in rects:
					if rect.intersects(b.get_global_rect()): errors.append("Place overlaps: " + id)
				rects.append(b.get_global_rect())
			await _capture("map-%dx%d" % [size.x, size.y])
		_tap(map.journey_map.buttons.nursery.get_global_rect().get_center())
		await get_tree().create_timer(0.5).timeout
		var place := AppRouter.top_instance()
		if place == null or place.get("journey_scene") == null:
			errors.append("Map tap did not enter nursery")
		else:
			var journey: JourneyPlace = place.journey_scene
			if not journey.targets.has("nursery_west"):
				errors.append("Smoke account has already claimed the tested node")
			else:
				var wood := int(Net.session.state.journey.wood)
				_tap(journey.targets.nursery_west.button.get_global_rect().get_center())
				await get_tree().create_timer(5).timeout
				if int(Net.session.state.journey.wood) != wood + 1: errors.append("World tap did not gather exactly one wood")
				if journey.targets.has("nursery_west"): errors.append("Collected timber stayed visible")
				await Net.session.refresh()
				if not Net.session.state.journey.exploration.collected.has("nursery_west"): errors.append("Collection was not persisted")
				await _capture("gathered")
			_tap(journey.targets.resident.button.get_global_rect().get_center())
			await get_tree().create_timer(5).timeout
			if not JourneyProgress.fact(Net.session.state, "met_nursery"): errors.append("Resident tap did not record the meeting")
			await _capture("resident")
	var report := {"passed": errors.is_empty(), "errors": errors, "source": "native input + HTTP + PostgreSQL", "natural_clock": true}
	FileAccess.open(output.path_join("smoke-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("JOURNEY_SMOKE ", JSON.stringify(report))
	get_tree().quit(0 if errors.is_empty() else 1)

func _tap(point: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	var up := down.duplicate() as InputEventScreenTouch
	up.pressed = false
	Input.parse_input_event(up)

func _capture(id: String) -> void:
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(output.path_join(id + ".png"))

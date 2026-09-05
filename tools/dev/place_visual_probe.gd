extends Node
## Run with --scene res://tools/dev/place_visual_probe.tscn, never --script.
## Synthetic fixtures exercise real scene rendering; they do not validate chapter progression.

const PLACE := preload("res://scenes/place/place.tscn")
const SIZES := [Vector2i(360, 640), Vector2i(390, 844)]
const PLACES := ["nursery", "bistro", "courtyard"]

var _output := "res://output/place-visual-probe"
var _chapters: Array[int] = [0, 3, 6]
var _panels: Array[String] = ["people"]
var _errors: Array[String] = []
var _captures: Array = []
var _blocked_requests: Array[String] = []

func _enter_tree() -> void:
	# Net schedules boot before the main scene enters. Stop that deferred call before any await.
	Net.booting = true
	Net.use_transport(_reject_http, "https://place-probe.invalid/v1")
	Net.booted_once = true

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--place-probe-out="):
			_output = arg.trim_prefix("--place-probe-out=")
		elif arg == "--place-probe-all-panels":
			_panels = ["people", "choices", "project", "growth", "decorations", "kitchen", "journal", "events"]
		elif arg.begins_with("--place-probe-chapter="):
			var value := arg.trim_prefix("--place-probe-chapter=")
			if not value.is_valid_int() or int(value) < 0 or int(value) > 6:
				push_error("place-probe-chapter must be an integer from 0 through 6")
				get_tree().quit(2)
				return
			_chapters = [int(value)]
	call_deferred("_run")

func _reject_http(method: String, url: String, _headers: PackedStringArray, _body: String) -> ApiClient.Response:
	_blocked_requests.append("%s %s" % [method, url])
	return ApiClient.Response.new(false, 0, {}, "Visual probe rejects all network requests")

func _run() -> void:
	_output = ProjectSettings.globalize_path(_output)
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		push_error("Cannot create visual probe output: %s" % _output)
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Place visual probe requires a graphical renderer for actual scene pixels")
		get_tree().quit(2)
		return
	for chapter in _chapters:
		for size in SIZES:
			get_tree().root.content_scale_size = size
			get_tree().root.size = size
			await _settle(5)
			for place_id in PLACES:
				for panel in _panels:
					await _capture(str(place_id), chapter, size, panel)
	if not _blocked_requests.is_empty():
		_errors.append("Scene attempted network requests; all were blocked")
	var report := {
		"purpose": "visual_regression_only", "state_source": "synthetic_fixture",
		"chapter_progression_verified": false, "physical_device_verified": false,
		"scene": "res://scenes/place/place.tscn", "requested_panels": _panels,
		"captures": _captures, "errors": _errors, "blocked_requests": _blocked_requests,
		"passed": _errors.is_empty(),
	}
	var report_path := _output.path_join("report.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	else:
		_errors.append("Cannot write report.json")
	print("PLACE_VISUAL_PROBE_REPORT ", report_path)
	print("PLACE_VISUAL_PROBE_RESULT ", JSON.stringify({"passed": _errors.is_empty(), "errors": _errors, "captures": _captures.size()}))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _capture(place_id: String, chapter: int, size: Vector2i, requested_panel := "people") -> void:
	var state := _fixture(chapter)
	var label := "%s-d%d-%dx%d" % [place_id, chapter, size.x, size.y]
	if requested_panel != "people": label += "-" + requested_panel
	if not PlaceCatalog.available(place_id, state):
		_captures.append({"id": label, "skipped": "Place is locked in this chapter"})
		return
	var session := FarmSession.new(ApiClient.new("https://place-probe.invalid/v1", _reject_http))
	session.player_id = "qa-visual-only-player"
	session._adopt({
		"farm_id": "qa-visual-only-farm", "layout_patch_id": "sh_a", "blueprint_revision": 2,
		"region_id": "sh_jingan", "version": 1, "server_time": state.clock.last_effective_now,
		"state": state, "derived": {
			"player_day_id": state.clock.player_day_id, "days_elapsed": 0,
			"weather_day_index": chapter, "field_condition": state.clock.field_condition,
			"chapter_index": chapter, "opens_new_chapter": false,
			"next_chapter_opens_at": null, "ripe_cells": [],
		},
	})
	Net.session = session
	var place := PLACE.instantiate()
	place.call("setup", {"place_id": place_id, "session": session})
	add_child(place)
	if not place._tab_buttons.has(requested_panel):
		remove_child(place)
		place.queue_free()
		await _settle(3)
		return
	place.select_tab(requested_panel)
	await _settle(45)
	var checks: Array[String] = []
	var ui_errors: Array[String] = []
	var ui: Control = place.get("root")
	var panel: Control = place.get("body")
	var scenery: Node3D = place.get("scenery")
	var selected_tab := str(place.get("selected_tab"))
	if selected_tab != requested_panel: checks.append("Requested panel did not open: %s" % selected_tab)
	if ui == null or panel == null or scenery == null:
		checks.append("Real place scene did not build its UI and scenery")
	var image := get_viewport().get_texture().get_image()
	var pixels := {}
	if image == null or image.is_empty():
		checks.append("Viewport returned an empty image")
	else:
		if image.get_size() != size:
			checks.append("Screenshot size %s does not match requested %s" % [image.get_size(), size])
		if ui and panel:
			_ui_bounds(ui, Rect2(Vector2.ZERO, Vector2(size)), ui_errors)
			checks.append_array(ui_errors)
			var world_rect := Rect2(12, 76, size.x - 24, maxf(0, panel.get_global_rect().position.y - 88))
			pixels = _world_pixels(image, world_rect)
			if not bool(pixels.get("passed", false)):
				checks.append("Visible scene pixels failed nonblank geometry check")
		var png_path := _output.path_join(label + ".png")
		if image.save_png(png_path) != OK:
			checks.append("Could not write screenshot")
		else:
			print("PLACE_VISUAL_PROBE_PNG ", png_path)
	if scenery and scenery.get_child_count() == 0:
		checks.append("Scenery has no rendered mesh children")
	_captures.append({
		"id": label, "chapter": chapter, "place_id": place_id,
		"size": [size.x, size.y], "png": _output.path_join(label + ".png"),
		"state_source": "synthetic_fixture", "nursery": state.nursery, "selected_tab": selected_tab,
		"world_pixels": pixels, "ui_bounds_passed": ui != null and panel != null and ui_errors.is_empty(), "errors": checks,
	})
	for error in checks: _errors.append("%s: %s" % [label, error])
	remove_child(place)
	place.queue_free()
	await _settle(3)

func _settle(frames: int) -> void:
	for index in frames: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _ui_bounds(node: Node, viewport_rect: Rect2, errors: Array[String]) -> void:
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree(): return
		var bounds := control.get_global_rect()
		if bounds.size.x > 0 and bounds.size.y > 0:
			var scroll := _scroll_ancestor(control)
			if scroll:
				var clip := scroll.get_global_rect()
				# Vertical content outside a ScrollContainer is expected; horizontal overflow is not.
				if bounds.intersects(clip) and (bounds.position.x < clip.position.x - 1 or bounds.end.x > clip.end.x + 1):
					errors.append("Horizontal scroll-content overflow: %s %s" % [control.get_path(), bounds])
			elif not viewport_rect.grow(1).encloses(bounds):
				errors.append("Control outside viewport: %s %s" % [control.get_path(), bounds])
	for child in node.get_children(): _ui_bounds(child, viewport_rect, errors)

func _scroll_ancestor(node: Node) -> ScrollContainer:
	var parent := node.get_parent()
	while parent:
		if parent is ScrollContainer: return parent as ScrollContainer
		parent = parent.get_parent()
	return null

func _world_pixels(image: Image, requested: Rect2) -> Dictionary:
	var region := Rect2i(requested).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if region.size.x < 80 or region.size.y < 80:
		return {"passed": false, "reason": "Less than 80 pixels of scene remain between header and panel"}
	var background := image.get_pixel(2, region.position.y)
	var colors := {}
	var sampled := 0
	var changed := 0
	for y in range(region.position.y, region.end.y, 3):
		for x in range(region.position.x, region.end.x, 3):
			var color := image.get_pixel(x, y)
			var distance := Vector3(color.r - background.r, color.g - background.g, color.b - background.b).length()
			sampled += 1
			if distance > 0.09 and color.a > 0.95: changed += 1
			colors["%d/%d/%d" % [int(color.r * 15), int(color.g * 15), int(color.b * 15)]] = true
	var ratio := float(changed) / maxf(1, sampled)
	return {
		"passed": ratio >= 0.06 and colors.size() >= 16,
		"region": [region.position.x, region.position.y, region.size.x, region.size.y],
		"sampled_pixels": sampled, "geometry_pixel_ratio": ratio, "quantized_colors": colors.size(),
	}

static func _fixture(chapter: int) -> Dictionary:
	var now := int(Time.get_unix_time_from_datetime_string("2026-09-05T04:00:00")) * 1000 + chapter * 86400000
	var day := Time.get_datetime_string_from_unix_time(now / 1000).split("T")[0]
	var weather := ["sunny", "rain", "sunny", "sunny", "sunny", "wind", "sunny"]
	var seed_lots := {}
	var produce := {}
	for crop in ["R", "L", "C", "H"]:
		seed_lots[crop] = {"bought": 0 if chapter == 0 else 2, "bound": 6 if crop == "R" and chapter == 0 else (3 if crop == "L" else 0)}
		produce[crop] = 0 if chapter == 0 else (6 if crop == "R" or crop == "L" else 4)
	var residents := {}
	for id in ["nursery_keeper", "bistro_owner", "restorer"]:
		var met: bool = chapter > 0 and (id != "restorer" or chapter >= 5)
		residents[id] = {
			"points": 0 if not met else (50 if chapter == 6 and id != "restorer" else 19),
			"first_met_day": day if met else null, "talked_day": null,
			"gifts_given": 1 if met else 0, "request_done": chapter == 6,
			"shared_event_done": chapter == 6 and id != "restorer", "choice_memories": {},
		}
	var chapters := []
	var chapter_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/chapters.json"))
	var economy_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/economy.json"))
	for index in 7:
		var flags := {}
		if index < chapter:
			for fact in chapter_data.chapters[index].min_facts: flags[fact] = true
		elif index == 0: flags.farm_created = true
		chapters.append({
			"status": "done" if index < chapter else ("active" if index == chapter else "locked"),
			"activated_day": day if index <= chapter else null, "step_flags": flags, "grants_issued": index <= chapter,
		})
	var cells := {}
	for index in 12:
		cells["%d,%d" % [index % 3 + 2, index / 3 + 2]] = {
			"state": "wild" if chapter == 0 or index >= 9 else "tilled", "crop": null,
			"care_weather": null, "care_done_at": null, "ready_at": null,
			"careful": false, "tutorial": false,
		}
	return {
		"clock": {"player_day_id": day, "chapter_index": chapter, "weather_day_index": chapter,
			"field_condition": weather[chapter], "last_effective_now": now},
		"qa": {"scale": 1, "anchor_real": now, "anchor_effective": now, "offset_ms": 0, "weather": {}},
		"wallet": 60 if chapter == 0 else 287, "inventory": {"seeds": seed_lots, "produce": produce,
			"dishes": {"salad": 2 if chapter >= 3 else 0, "tea": 1 if chapter >= 4 else 0}},
		"cells": cells, "beds_unlocked": 3, "tools": {"row_tool": false},
		"growth_choice": {"intent": null, "purchase": null, "locked_at": null, "transaction_id": null},
		"stall": {"day": day, "settled": 0}, "buyback": {"day": day, "sold": 0, "week_total": 0},
		"seedling_packs": {"days": []}, "engineering": {"reserved": {},
			"submitted": economy_data.engineering_quota.duplicate() if chapter == 6 else {}},
		"nursery": {"stage": "built" if chapter == 6 else ("cleared" if chapter >= 4 else "derelict"),
			"appearance": "a" if chapter >= 5 else null},
		"residents": residents, "chapters": chapters,
		"requests_done": ["d0_tutorial_buyback", "d1_bistro_lettuce", "d3_nursery_basket", "d5_restorer_salads"] if chapter == 6 else (["d0_tutorial_buyback", "d1_bistro_lettuce"] if chapter >= 3 else []),
		"life_choices": {"1": "gift", "2": "keep", "3": "gift", "4": "keep", "5": "gift"} if chapter == 6 else {},
		"sales_facts": {}, "subsidies_claimed": ["weather_story"] if chapter >= 3 else [],
		"xp": {"total": 0 if chapter == 0 else 180, "first_clear_cells": [], "first_harvest_crops": [],
			"first_weather": [], "first_recipes": [], "harvest_counted": {"day": day, "plants": 0}, "care_bonus_day": null},
		"handbook": [],
	}

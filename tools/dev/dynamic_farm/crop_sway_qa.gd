extends Node
## C-141 crop sway on one's own parcel (ported from the C-140 prototype, attachment-1155), for frame-rate measurement
## and the review recording on the emulator. Like own_parcel_qa.gd it opens `sensen/dynamic_farm/qa_parcel` with
## `own_parcel` on the device save, but first writes a save whose whole core is planted with carrots (core obstacles
## cleared, the protected path and spawn ring left free, as tilling allows), then walks the player round a loop with the stick and switches the
## sway between off (the plant layers on the imported StandardMaterial3D, as before C-141) and on.
##
## The build bakes the mode in (`sensen/dynamic_farm/crop_sway_qa_mode`); `user://crop_sway_qa.json` can override it:
##   {"mode": "measure"}  warm up, then sway off / on / off / on, `phase_s` (30) each; wall-clock frame times, draw
##                        calls and primitives per phase go to the log (`CROP_SWAY_FPS`) and
##                        `user://crop_sway_result.json`.
##   {"mode": "baseline"} the same walk and phases on the parcel without carrots (what the field itself costs).
##   {"mode": "record"}   stand still with sway on, walk with it on, then off, then on at a closer zoom; a small
##                        tag names the state. Some columns are left unripe so only ripe carrots sway. Runs on game
##                        time (the scene steps at most 0.1 s a frame) and saves every frame to `user://frames/`,
##                        so a slow emulator still gives a real-speed video at 10 frames per game second.
##   {"mode": "shots"}    C-208: the record field, the player standing at the start: stills at zoom 1, 0.6 and 1.4
##                        with the sway off (the plant layers on the imported material, as C-139 drew them), then
##                        one at zoom 1 with it on, to user://shots/<name>.png; then the app quits. Two builds give
##                        the same stills, so a change in what the carrots draw shows as a frame difference.
## `vsync` (true) false asks for an uncapped frame rate. Staged only by gather_qa_apk.sh with
## GATHER_QA_ENTRY=sway; never the main scene of a delivered package.
const SCENE_PATH := "res://scenes/dynamic_farm/dynamic_farm.tscn"
const PARCEL_SETTING := "sensen/dynamic_farm/qa_parcel"
const CONFIG_PATH := "user://crop_sway_qa.json"
## The staged build's default mode (gather_qa_apk.sh, GATHER_QA_SWAY_MODE).
const MODE_SETTING := "sensen/dynamic_farm/crop_sway_qa_mode"
const RESULT_PATH := "user://crop_sway_result.json"
const SAVE_DIR := "user://dynamic_farm_local"
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
## A waypoint is reached this close (m); one the player cannot get nearer to for STUCK_S is skipped.
const ARRIVE_M := 0.4
const STUCK_S := 3.0
## Shots (C-208): [name, sway, zoom] in order; each is saved this many frames after its zoom and sway change (the redraw
## and the camera settle first).
const SHOTS := [["off-zoom1", false, 1.0], ["off-zoom0.6", false, 0.6], ["off-zoom1.4", false, 1.4], ["on-zoom1", true, 1.0]]
const SHOT_SETTLE_FRAMES := 6

var config := {"mode": "measure", "vsync": true, "warmup_s": 15.0, "phase_s": 30.0}
var scene: Node
var farming: Node
var loop: Array[Vector3] = []
var waypoint := 0
var best_gap := INF
var stuck_s := 0.0
var walking := false
var started := false
var clock := 0.0
## Measure: [{name, sway, until}], the running phase's samples and every phase's result.
var phases: Array = []
var phase := -1
var samples := {}
var results: Array = []
var tag: Label
var carrots := {}
## The plant layers' sway materials, put back when the sway is switched on again.
var sway_materials := []
var next_beat := 0.0
## Wall-clock time: Godot caps a frame's delta (8 physics steps), so on a slow device delta falls behind real time.
var started_us := 0
var last_us := 0
var frame_index := 0
## Shots: the still being taken and frames drawn since it was set up.
var shot := 0
var shot_frames := 0

func _ready() -> void:
	var raw_config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	config.mode = str(ProjectSettings.get_setting(MODE_SETTING, config.mode))
	if raw_config is Dictionary: config.merge(raw_config, true)
	if not bool(config.vsync):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var path := str(ProjectSettings.get_setting(PARCEL_SETTING, ""))
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	if not raw is Dictionary:
		push_error("QA parcel missing: " + path)
		return
	var data := Data.decode(raw)
	if not data.ok:
		push_error("QA parcel invalid: " + str(data.get("error")))
		return
	var walk := Walk.new(data)
	_plant(data, walk, str(config.mode) in ["record", "shots"], str(config.mode) == "baseline")
	_plan_loop(data, walk)
	scene = (load(SCENE_PATH) as PackedScene).instantiate()
	scene.setup({"farm": raw, "dataset": raw.get("dataset_version"), "block_id": raw.get("block_id"), "own_parcel": true})
	scene.back_requested.connect(func(): get_tree().quit())
	scene.preview_error.connect(func(message): push_error(message))
	add_child(scene)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("CROP_SWAY_QA start ", JSON.stringify({"mode": config.mode, "vsync": config.vsync, "carrots": carrots,
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "api": RenderingServer.get_video_adapter_api_version(),
		"window": DisplayServer.window_get_size(), "loop": loop.size()}))

## The save: every core cell outside the protected path holds a carrot, ripe unless `mixed` leaves the western
## fifth of the core young (stages 2 to 5 by row); every core obstacle is cleared. `empty` plants nothing.
func _plant(data: Dictionary, walk: RefCounted, mixed: bool, empty := false) -> void:
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var state := ParcelFarm.empty_state()
	state.welcomed_at = now
	var plan := Scenery.plan(data, walk)
	if plan.ok:
		for item: Dictionary in plan.core_obstacles.layout: state.cleared.append(ParcelFarm.key(item.cell))
	var path := Space.protected_path(data)
	var core: Array = data.cells.filter(func(c): return c.zone == "core")
	var min_x := 1 << 20
	var max_x := -1
	for c: Dictionary in core:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
	var unripe_below := min_x + (max_x - min_x + 1) / 5 if mixed else min_x
	var hour := 3600 * 1000
	carrots = {"ripe": 0, "growing": 0}
	for c: Dictionary in core:
		var cell := Vector2i(c.x, c.y)
		if path.has(cell) or empty: continue
		var key := ParcelFarm.key(cell)
		state.tilled.append(key)
		var crop := {"crop": "crop_carrot", "planted_at": now - 120000, "ripe_at": now - 60000}
		if cell.x < unripe_below:
			# A fifth of the growing time per stage (ParcelCropArt.stage_of): rows land on stages 2 to 5.
			var share := 0.15 + 0.2 * float(posmod(cell.y, 4))
			crop = {"crop": "crop_carrot", "planted_at": now - int(share * hour), "ripe_at": now + int((1.0 - share) * hour)}
			carrots.growing += 1
		else:
			carrots.ripe += 1
		state.crops[key] = crop
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(SAVE_DIR.path_join(str(data.block_id).validate_filename() + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"block_id": data.block_id, "farm_version": 1, "farm": state}))
	file.close()

## A rectangle through the core at a quarter and three quarters of its extent, corners snapped to core cells.
func _plan_loop(data: Dictionary, walk: RefCounted) -> void:
	var core: Array = data.cells.filter(func(c): return c.zone == "core")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Dictionary in core:
		lo = lo.min(Vector2(c.x, c.y))
		hi = hi.max(Vector2(c.x, c.y))
	for corner: Vector2 in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.75, 0.75), Vector2(0.25, 0.75)]:
		var want := lo + (hi - lo) * corner
		var best: Vector2i
		var best_d := INF
		for c: Dictionary in core:
			var d := Vector2(c.x, c.y).distance_squared_to(want)
			if d < best_d:
				best_d = d
				best = Vector2i(c.x, c.y)
		loop.append(walk.point(best))

func _process(delta: float) -> void:
	if scene == null: return
	if farming == null: farming = scene.get("_farming")
	if not started:
		if farming == null or not farming.loaded() or not bool(scene.get("_ready_sent")): return
		started = true
		started_us = Time.get_ticks_usec()
		last_us = started_us
		if str(config.mode) == "record": _start_record()
		elif str(config.mode) == "shots": DirAccess.make_dir_recursive_absolute("user://shots")
		else: _start_measure()
	var now_us := Time.get_ticks_usec()
	var frame_ms := (now_us - last_us) / 1000.0
	last_us = now_us
	# Record mode follows game time, the scene's own clamped step (dynamic_farm.gd: at most 0.1 s a frame).
	if str(config.mode) == "record": clock += clampf(delta, 0.0, 0.1)
	else: clock = (now_us - started_us) / 1000000.0
	if clock >= next_beat:
		next_beat += 5.0
		print("CROP_SWAY_BEAT ", JSON.stringify({"clock": snappedf(clock, 0.1), "fps": Engine.get_frames_per_second(),
			"phase": phases[phase].name if phase >= 0 and phase < phases.size() else "", "sway": farming.sway}))
	if str(config.mode) == "record": _record_step()
	elif str(config.mode) == "shots": _shots_step()
	else: _measure_step(frame_ms)
	scene.set("_movement", _steer(delta) if walking else Vector2.ZERO)

## Stick input toward the current waypoint, in the camera's screen axes like the scene's own stick.
func _steer(delta: float) -> Vector2:
	var at: Vector3 = scene.player_position()
	var to := loop[waypoint] - at
	to.y = 0
	if to.length() < ARRIVE_M or stuck_s > STUCK_S:
		waypoint = (waypoint + 1) % loop.size()
		best_gap = INF
		stuck_s = 0.0
		to = loop[waypoint] - at
		to.y = 0
	if to.length() < best_gap - 0.05:
		best_gap = to.length()
		stuck_s = 0.0
	else:
		stuck_s += delta
	var camera: Camera3D = scene.get("_camera")
	var right := camera.global_basis.x
	right.y = 0
	var forward := -camera.global_basis.z
	forward.y = 0
	var dir := to.normalized()
	return Vector2(dir.dot(right.normalized()), -dir.dot(forward.normalized())).normalized()

## On: the sway material, shakes from walking. Off: the imported material the plant layers drew with before C-141.
func _set_sway(on: bool) -> void:
	farming.set_sway(on)
	var layers: Array = farming.get("_crop_art")._stages
	if sway_materials.is_empty():
		for layer in layers: sway_materials.append(null if layer == null else layer.material_override)
	for i in layers.size():
		if layers[i] != null: layers[i].material_override = sway_materials[i] if on else null
	if tag != null: tag.text = "Sway ON" if on else "Sway OFF"

func _start_measure() -> void:
	var t := float(config.warmup_s)
	phases.append({"name": "warmup", "sway": false, "until": t})
	for i in 4:
		t += float(config.phase_s)
		phases.append({"name": ("off" if i % 2 == 0 else "on") + str(i / 2 + 1), "sway": i % 2 == 1, "until": t})
	walking = true
	_begin_phase(0)

func _begin_phase(index: int) -> void:
	phase = index
	_set_sway(phases[index].sway)
	samples = {"frame": PackedFloat32Array(), "gpu": PackedFloat32Array(), "cpu": PackedFloat32Array(),
		"fps": PackedFloat32Array(), "draws": PackedFloat32Array(), "primitives": PackedFloat32Array(), "since": clock,
		"next_fps": clock + 1.0}

func _measure_step(frame_ms: float) -> void:
	if phase < 0 or phase >= phases.size(): return
	# Skip the first half second of a phase: the material switch and the redraw land there.
	if clock - float(samples.since) > 0.5:
		var vp := get_viewport().get_viewport_rid()
		samples.frame.append(frame_ms)
		samples.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		samples.cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		samples.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		samples.primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if clock >= float(samples.next_fps):
			samples.fps.append(Performance.get_monitor(Performance.TIME_FPS))
			samples.next_fps = float(samples.next_fps) + 1.0
	if clock < float(phases[phase].until): return
	if phases[phase].name != "warmup": _finish_phase()
	if phase + 1 < phases.size():
		_begin_phase(phase + 1)
		return
	phase = phases.size()
	walking = false
	var summary := {"mode": config.mode, "vsync": config.vsync, "carrots": carrots,
		"crop_instances": farming.get("_crop_art").counts(), "phases": results,
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "window": DisplayServer.window_get_size()}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, " "))
	file.close()
	print("CROP_SWAY_DONE ", JSON.stringify(summary))

func _finish_phase() -> void:
	var frames: PackedFloat32Array = samples.frame
	var elapsed := 0.0
	for ms in frames: elapsed += ms
	var result := {"phase": phases[phase].name, "sway": phases[phase].sway, "frames": frames.size(),
		"fps_avg": frames.size() * 1000.0 / maxf(elapsed, 0.001), "frame_ms_avg": elapsed / maxf(frames.size(), 1),
		"frame_ms_p99": _percentile(frames, 0.99), "fps_1pct_low": 1000.0 / maxf(_slowest_mean(frames, 0.01), 0.001),
		"time_fps_avg": _mean(samples.fps), "gpu_ms_avg": _mean(samples.gpu), "gpu_ms_p99": _percentile(samples.gpu, 0.99),
		"cpu_render_ms_avg": _mean(samples.cpu), "draw_calls_avg": _mean(samples.draws),
		"primitives_avg": _mean(samples.primitives), "shakes": int(farming.sway_triggers)}
	results.append(result)
	print("CROP_SWAY_FPS ", JSON.stringify(result))

static func _mean(values: PackedFloat32Array) -> float:
	var total := 0.0
	for v in values: total += v
	return total / maxf(values.size(), 1)

static func _percentile(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(share * sorted.size()), sorted.size() - 1)]

## Mean of the slowest `share` of frames (ms): its reciprocal is the "1% low" frame rate.
static func _slowest_mean(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var count := maxi(1, int(ceil(sorted.size() * share)))
	var total := 0.0
	for i in count: total += sorted[sorted.size() - 1 - i]
	return total / count

## Record (game seconds): 0-5 still, sway on; 5-22 walking, on; 22-34 walking, off; 34-52 walking closer, on; then
## the app quits. The camera stays on the player; every frame goes to user://frames/ as JPEG.
func _start_record() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	tag = Label.new()
	tag.add_theme_font_size_override(&"font_size", 14)
	tag.add_theme_color_override(&"font_color", Color.WHITE)
	tag.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	tag.add_theme_constant_override(&"outline_size", 4)
	tag.position = Vector2(16, 140)
	layer.add_child(tag)
	DirAccess.make_dir_recursive_absolute("user://frames")
	_set_sway(true)

func _record_step() -> void:
	var on := clock < 22.0 or clock >= 34.0
	if bool(farming.sway) != on: _set_sway(on)
	walking = clock >= 5.0 and clock < 52.0
	if clock >= 34.0 and float(scene.get("_zoom")) != 0.6:
		scene.set("_zoom", 0.6)
	scene.set("_focus", scene.player_position())
	# The last drawn frame (this frame's state draws after _process).
	var image := get_viewport().get_texture().get_image()
	if image != null: image.save_jpg("user://frames/%05d.jpg" % frame_index, 0.88)
	frame_index += 1
	if clock >= 54.0:
		print("CROP_SWAY_RECORDED ", frame_index)
		get_tree().quit()

## Shots: each still's sway and zoom are set, the camera held on the standing player, and the frame drawn
## SHOT_SETTLE_FRAMES later saved; after the last one the app quits.
func _shots_step() -> void:
	if shot >= SHOTS.size(): return
	var take: Array = SHOTS[shot]
	if shot_frames == 0: _set_sway(bool(take[1]))
	scene.set("_zoom", float(take[2]))
	scene.set("_focus", scene.player_position())
	shot_frames += 1
	if shot_frames <= SHOT_SETTLE_FRAMES: return
	var image := get_viewport().get_texture().get_image()
	if image != null: image.save_png("user://shots/%s.png" % take[0])
	print("CROP_SWAY_SHOT ", JSON.stringify({"name": take[0], "sway": take[1], "zoom": take[2],
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}))
	shot += 1
	shot_frames = 0
	if shot >= SHOTS.size():
		print("CROP_SWAY_SHOTS ", SHOTS.size())
		get_tree().quit()

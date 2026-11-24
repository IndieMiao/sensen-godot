extends SceneTree
## C-112 map camera (geo_native_camera.gd): farm-dev's inertia, double tap, two-finger tilt and flights, and the
## tilted ground projection checked against a Godot Camera3D placed as farm-dev's map_poc.gd places its camera.
## No native map: picking stays with Mapbox and is not exercised here.
const CameraInput := preload("res://modules/dynamic_farm/map/geo_native_camera.gd")
const MapPage := preload("res://scenes/dynamic_farm/dynamic_farm_map.gd")
const ClaimApi := preload("res://modules/dynamic_farm/map/claim_api.gd")
const SIZE := Vector2(400, 800)
class Native extends MapBridge:
	var poses: Array = []
	func set_camera(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> void: poses.append([lat, lng, zoom, bearing, pitch])
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", text)

func _run() -> void:
	_ground_matches_camera()
	_grab_ground()
	_inertia()
	_pinch()
	_tilt()
	_disabled_mid_gesture()
	_mouse_copies()
	await _double_tap()
	await _flight()
	_area()
	await _native_pose()
	print("DYNAMIC MAP CAMERA ", checks - failures, "/", checks)
	quit(1 if failures else 0)

func camera(zoom := 17.0) -> Control:
	var c: Control = CameraInput.new(); root.add_child(c)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT); c.position = Vector2.ZERO; c.size = SIZE
	c.set_process(false) # Tests step the inertia themselves.
	c.center = PackedFloat64Array([-122.43, 37.77]); c.zoom = zoom
	return c

func touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new(); e.index = index; e.position = at; e.pressed = pressed
	return e

func drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new(); e.index = index; e.position = at
	return e

func near(a: PackedFloat64Array, b: PackedFloat64Array, tolerance: float) -> bool:
	return absf(a[0] - b[0]) < tolerance and absf(a[1] - b[1]) < tolerance

## The tilted projection equals a pinhole camera of Mapbox's 36.87° fov, 1.5 view heights from the centre.
func _ground_matches_camera() -> void:
	var c := camera()
	c.pitch = 0.0
	check(c.ground_offset(Vector2(37, -120)) == Vector2(37, -120), "flat: a screen offset is the ground offset")
	check(near(c.screen_geo(SIZE * 0.5), c.center, 1e-9), "the screen centre is the camera centre")
	var view := SubViewport.new(); view.size = Vector2i(SIZE); root.add_child(view)
	var eye := Camera3D.new(); view.add_child(eye)
	eye.fov = 36.87; eye.keep_aspect = Camera3D.KEEP_HEIGHT; eye.near = 1.0; eye.far = 100000.0
	var worst := 0.0
	for pitch in [20.0, 45.0, 60.0]:
		c.pitch = pitch
		var d := 1.5 * SIZE.y; var phi := deg_to_rad(pitch)
		eye.position = Vector3(0, d * cos(phi), d * sin(phi)); eye.look_at(Vector3.ZERO, Vector3(0, 0, -1))
		for point in [Vector2(0, 0), Vector2(400, 0), Vector2(120, 300), Vector2(200, 400), Vector2(0, 800), Vector2(390, 700)]:
			var hit = Plane(Vector3.UP, 0.0).intersects_ray(eye.project_ray_origin(point), eye.project_ray_normal(point))
			var ground: Vector2 = c.ground_offset(point - SIZE * 0.5)
			worst = maxf(worst, (Vector2(hit.x, hit.z) - ground).length() / maxf(1.0, Vector2(hit.x, hit.z).length()))
	check(worst < 1e-3, "tilted ground points match a Camera3D at farm-dev's fov (worst relative error %s)" % str(worst))
	c.pitch = 70.0
	var top: Vector2 = c.ground_offset(Vector2(0, -SIZE.y * 0.5))
	check(is_finite(top.y) and top.y < 0 and top.length() < 40.0 * SIZE.y, "70°: the top edge still lands on the ground ahead")
	view.queue_free(); c.queue_free()

## A drag keeps the ground point it pressed under the finger, flat or tilted.
func _grab_ground() -> void:
	for pitch in [0.0, 45.0]:
		var c := camera(); c.pitch = pitch
		var from := Vector2(150, 500); var to := Vector2(260, 380)
		var grabbed: PackedFloat64Array = c.screen_geo(from)
		c._gui_input(touch(0, from, true))
		for i in range(1, 11): c._gui_input(drag(0, from.lerp(to, i / 10.0)))
		check(near(c.screen_geo(to), grabbed, 2e-7), "pitch %d°: the ground point pressed stays under the finger" % pitch)
		c._gui_input(touch(0, to, false)); c.queue_free()

func _inertia() -> void:
	var c := camera()
	var moved := [0]
	c.user_moved.connect(func(): moved[0] += 1)
	var tapped := [0]
	c.tapped.connect(func(_p): tapped[0] += 1)
	c._gui_input(touch(0, Vector2(200, 400), true))
	for i in range(1, 9): c._gui_input(drag(0, Vector2(200 + 20 * i, 400)))
	c._gui_input(touch(0, Vector2(360, 400), false))
	check(tapped[0] == 0 and moved[0] > 0, "a drag moves the map and is not a tap")
	check(c._fling.x < -c.FLING_MIN_SPEED and absf(c._fling.y) < 1e-3, "lifting the finger keeps the drag's velocity")
	var lon: float = c.center[0]
	c._step_fling(1.0 / 60.0)
	check(c.center[0] < lon, "the map keeps sliding the way it was dragged")
	var speed: float = c._fling.length()
	c._step_fling(1.0 / 60.0)
	check(c._fling.length() < speed, "and slows down")
	for i in 600: c._step_fling(1.0 / 60.0)
	check(c._fling == Vector2.ZERO, "and stops")
	# A new touch stops the slide where it is.
	c._gui_input(touch(0, Vector2(200, 400), true))
	for i in range(1, 9): c._gui_input(drag(0, Vector2(200, 400 + 20 * i)))
	c._gui_input(touch(0, Vector2(200, 560), false))
	c._gui_input(touch(0, Vector2(100, 100), true))
	check(c._fling == Vector2.ZERO, "a touch stops the inertia")
	var held: PackedFloat64Array = c.center.duplicate()
	c._step_fling(1.0 / 60.0)
	check(c.center == held, "while the finger is down the map holds still")
	c._gui_input(touch(0, Vector2(100, 100), false))
	check(tapped[0] == 1, "that touch, lifted without moving, is a tap")
	# Disabled input (a claim or a farm loading) ends the slide.
	c._fling = Vector2(500, 0); c.input_enabled = false; lon = c.center[0]
	c._step_fling(1.0 / 60.0)
	check(c._fling == Vector2.ZERO and c.center[0] == lon, "no inertia while the map's input is disabled")
	c.queue_free()

func _pinch() -> void:
	var c := camera(16.0)
	c._gui_input(touch(0, Vector2(200, 300), true)); c._gui_input(touch(1, Vector2(200, 500), true))
	for i in range(1, 6): c._gui_input(drag(1, Vector2(200, 500 + 20 * i)))
	check(c.zoom > 16.0, "spreading two fingers zooms in")
	c._gui_input(touch(1, Vector2(200, 600), false))
	for i in range(1, 6): c._gui_input(drag(0, Vector2(200 + 15 * i, 300)))
	c._gui_input(touch(0, Vector2(275, 300), false))
	check(c._fling == Vector2.ZERO, "the last finger of a pinch does not throw the map")
	check(c._zoom_vel > 0.0, "the pinch's zoom keeps going after the fingers lift")
	var level: float = c.zoom
	c._step_fling(1.0 / 60.0)
	check(c.zoom > level, "zoom inertia")
	for i in 600: c._step_fling(1.0 / 60.0)
	check(c._zoom_vel == 0.0 and c.zoom <= c.MAX_ZOOM, "and it stops, within the zoom range")
	c.queue_free()

func _tilt() -> void:
	var c := camera()
	var moved := [0]
	c.user_moved.connect(func(): moved[0] += 1)
	c._gui_input(touch(0, Vector2(150, 500), true)); c._gui_input(touch(1, Vector2(250, 500), true))
	for i in range(1, 6):
		c._gui_input(drag(0, Vector2(150, 500 - 10 * i))); c._gui_input(drag(1, Vector2(250, 500 - 10 * i)))
	check(is_equal_approx(c.pitch, 10.0) and moved[0] > 0, "two fingers moved up 50 px tilt the map 10° (got %.2f)" % c.pitch)
	for i in range(1, 6):
		c._gui_input(drag(0, Vector2(150, 450 + 10 * i))); c._gui_input(drag(1, Vector2(250, 450 + 10 * i)))
	check(is_equal_approx(c.pitch, 0.0), "moved back down, it lies flat again")
	for i in range(1, 6): c._gui_input(drag(0, Vector2(150, 500 + 100 * i))); c._gui_input(drag(1, Vector2(250, 500 + 100 * i)))
	check(c.pitch == 0.0, "never below flat")
	for i in range(1, 30): c._gui_input(drag(0, Vector2(150, 1000 - 100 * i))); c._gui_input(drag(1, Vector2(250, 1000 - 100 * i)))
	check(c.pitch == c.MAX_PITCH, "never above %d°" % c.MAX_PITCH)
	c._gui_input(touch(0, Vector2(150, 0), false)); c._gui_input(touch(1, Vector2(250, 0), false))
	c.set_pitch(10.0); c._gui_input(touch(0, Vector2(150, 500), true)); c._gui_input(touch(1, Vector2(250, 500), true))
	for i in range(1, 6): c._gui_input(drag(0, Vector2(150, 500 - 10 * i))); c._gui_input(drag(1, Vector2(250, 500 + 10 * i)))
	check(is_equal_approx(c.pitch, 10.0), "a vertical pinch (one finger up, one down) does not tilt")
	c.queue_free()

## V-272: the map turns its input off (a map error makes the selector busy) while a finger is down, so the lift is
## never seen. The next tap must still pick and the next drag must not jump.
func _disabled_mid_gesture() -> void:
	var c := camera()
	var tapped: Array = []
	c.tapped.connect(func(p): tapped.append(p))
	c._gui_input(touch(0, Vector2(100, 100), true))
	c.input_enabled = false
	c._gui_input(touch(0, Vector2(100, 100), false)) # Not handled while disabled.
	c.input_enabled = true
	check(c._touches.is_empty(), "turning input off drops the finger that was down")
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(touch(0, Vector2(200, 400), false))
	check(tapped.size() == 1 and tapped[0] == Vector2(0.5, 0.5), "the first tap after input comes back still picks")
	# The review's steps (V-272): a drag cut short by input going off, then a tap elsewhere.
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(drag(0, Vector2(200, 300)))
	c.input_enabled = false; c._gui_input(touch(0, Vector2(200, 300), false)); c.input_enabled = true
	c._gui_input(touch(0, Vector2(100, 700), true)); c._gui_input(touch(0, Vector2(100, 700), false))
	check(tapped.size() == 2 and tapped[1] == Vector2(0.25, 0.875), "after a drag cut short, the next tap still picks (V-272)")
	# Two fingers down when input goes off: the next one-finger drag pans from where it presses, with no jump.
	c._gui_input(touch(0, Vector2(150, 500), true)); c._gui_input(touch(1, Vector2(250, 500), true))
	c.input_enabled = false; c.input_enabled = true
	var from := Vector2(150, 500); var to := Vector2(260, 380)
	var grabbed: PackedFloat64Array = c.screen_geo(from)
	c._gui_input(touch(0, from, true))
	for i in range(1, 11): c._gui_input(drag(0, from.lerp(to, i / 10.0)))
	check(not c._pinch and near(c.screen_geo(to), grabbed, 2e-7), "after a gesture cut short, a drag pans from where it presses")
	c._gui_input(touch(0, to, false)); c.queue_free()

func mouse(at: Vector2, pressed: bool, device := InputEvent.DEVICE_ID_EMULATION) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = at; e.pressed = pressed; e.device = device
	return e

## V-279: with emulate_mouse_from_touch Godot's Input dispatches a finger's emulated mouse press (device
## DEVICE_ID_EMULATION) before its touch. It must not become a second pointer, marked as emulated or not (the
## tester's repro sends it as device 0). Headless Input.parse_input_event does not reach the GUI, so the order is fed here.
func _mouse_copies() -> void:
	for device in [InputEvent.DEVICE_ID_EMULATION, 0]:
		var c := camera(18.0)
		var tapped := [0]
		c.tapped.connect(func(_p): tapped[0] += 1)
		c._last_touch_ms = Time.get_ticks_msec() - 1000 # The last finger lifted a second ago.
		var at := Vector2(150, 675)
		c._gui_input(mouse(at, true, device)); c._gui_input(touch(0, at, true)); c._gui_input(mouse(at, false, device)); c._gui_input(touch(0, at, false))
		check(tapped[0] == 1 and c._touches.is_empty() and not c._pinch, "device %d: a tap with its mouse copy picks once and leaves no pointer" % device)
		c._last_touch_ms = Time.get_ticks_msec() - 1000
		var from := Vector2(200, 600); var to := Vector2(200, 400)
		var grabbed: PackedFloat64Array = c.screen_geo(from)
		c._gui_input(mouse(from, true, device)); c._gui_input(touch(0, from, true))
		for i in range(1, 11): c._gui_input(drag(0, from.lerp(to, i / 10.0)))
		c._gui_input(mouse(to, false, device)); c._gui_input(touch(0, to, false))
		check(c.zoom == 18.0 and c.pitch == 0.0 and near(c.screen_geo(to), grabbed, 2e-7) and c._touches.is_empty(), "device %d: a one-finger drag with its mouse copy only pans (zoom %.2f, pitch %.1f)" % [device, c.zoom, c.pitch])
		c.queue_free()
	# A real mouse still drags the map on the desktop.
	var m := camera(18.0)
	m._last_touch_ms = Time.get_ticks_msec() - 1000
	var start: PackedFloat64Array = m.center.duplicate()
	m._gui_input(mouse(Vector2(200, 400), true, 0))
	var motion := InputEventMouseMotion.new(); motion.position = Vector2(260, 400); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	m._gui_input(motion); m._gui_input(mouse(Vector2(260, 400), false, 0))
	check(m.center[0] < start[0] and m._touches.is_empty(), "a real mouse drag still pans")
	m.queue_free()

func _double_tap() -> void:
	var c := camera(17.0); c.set_process(true)
	var tapped: Array = []
	c.tapped.connect(func(p): tapped.append(p))
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(touch(0, Vector2(200, 400), false))
	c._gui_input(touch(0, Vector2(210, 410), true)); c._gui_input(touch(0, Vector2(210, 410), false))
	check(tapped.size() == 1 and tapped[0] == Vector2(0.5, 0.5), "the first tap of a double tap still picks; the second does not")
	await create_timer(0.4).timeout
	check(is_equal_approx(c.zoom, 18.0), "a double tap zooms in one level (got %.3f)" % c.zoom)
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(touch(0, Vector2(200, 400), false))
	c._last_tap_ms -= 400
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(touch(0, Vector2(200, 400), false))
	check(tapped.size() == 3 and is_equal_approx(c.zoom, 18.0), "taps further apart than 0.3 s are two taps")
	c._gui_input(touch(0, Vector2(100, 400), true)); c._gui_input(touch(0, Vector2(100, 400), false))
	c._gui_input(touch(0, Vector2(300, 400), true)); c._gui_input(touch(0, Vector2(300, 400), false))
	check(tapped.size() == 5, "taps 200 px apart are two taps")
	c.zoom = c.MAX_ZOOM
	c._last_tap_ms = 0
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(touch(0, Vector2(200, 400), false))
	c._gui_input(touch(0, Vector2(200, 400), true)); c._gui_input(touch(0, Vector2(200, 400), false))
	await create_timer(0.4).timeout
	check(c.zoom == c.MAX_ZOOM, "a double tap at the closest zoom stays there")
	c.queue_free()

func _flight() -> void:
	var c := camera(15.0); c.set_process(true)
	var moved := [0]
	c.user_moved.connect(func(): moved[0] += 1)
	c.fly_to(-122.41, 37.78, 18.0)
	check(c.flying() and absf(c.center[0] + 122.43) < 1e-6, "a flight starts where the camera is")
	await create_timer(c.FLIGHT_MAX_S + 0.3).timeout
	check(not c.flying() and near(c.center, PackedFloat64Array([-122.41, 37.78]), 1e-9) and c.zoom == 18.0, "and lands exactly on the target")
	check(moved[0] == 0, "a flight is not the player's move")
	c.fly_to(-122.45, 37.75, 17.0)
	await create_timer(0.2).timeout
	c._gui_input(touch(0, Vector2(200, 400), true))
	var held: PackedFloat64Array = c.center.duplicate()
	await create_timer(0.3).timeout
	check(not c.flying() and c.center == held, "a touch stops a flight where it is")
	c._gui_input(touch(0, Vector2(200, 400), false))
	c.set_pitch(30.0); c.frame_center(-122.42, 37.76, 18.0)
	check(c.pitch == 30.0 and c.center[0] == -122.42, "framing keeps the tilt")
	c.queue_free()

func _area() -> void:
	var c := camera(17.0)
	var flat: Array = MapPage.area_bbox(c)
	var corner: PackedFloat64Array = c.screen_geo(Vector2.ZERO)
	var opposite: PackedFloat64Array = c.screen_geo(SIZE)
	check(is_equal_approx(flat[0], corner[0]) and is_equal_approx(flat[3], corner[1]) and is_equal_approx(flat[2], opposite[0]) and is_equal_approx(flat[1], opposite[1]), "flat: the area is the screen's corners")
	c.set_pitch(45.0)
	var tilted: Array = MapPage.area_bbox(c)
	check(tilted[3] > flat[3] and tilted[1] < c.center[1], "tilted: the area reaches further north, ahead of the camera")
	c.zoom = 13.0; c.set_pitch(70.0)
	var far: Array = MapPage.area_bbox(c)
	check(far[2] - far[0] <= ClaimApi.MAX_BBOX_SPAN and far[3] - far[1] <= ClaimApi.MAX_BBOX_SPAN and far[0] < c.center[0] and c.center[0] < far[2] and far[1] < c.center[1] and c.center[1] < far[3], "a far tilted view is held to the claim API's span around the centre")
	c.queue_free()

func _native_pose() -> void:
	var c := camera(17.0); var native := Native.new(); c.bridge = native; c.set_process(true)
	c.set_pitch(25.0)
	await process_frame; await process_frame
	var pose: Array = native.poses.back()
	check(native.poses.size() >= 1 and is_equal_approx(pose[4], 25.0) and pose[3] == 0.0 and is_equal_approx(pose[2], 17.0), "the native camera gets the tilt, north up")
	c.queue_free()

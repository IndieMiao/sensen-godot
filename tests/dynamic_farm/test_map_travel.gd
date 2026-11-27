extends SceneTree
## C-188: the avatar's trip on the dynamic farm map (map_travel.gd) after C-187's design v2 (D-437): the config against the
## motion spec's table, the route's geometry, the timeline (exit, framing, walk, arrival, iris, way back), skip, Back,
## the farm wait and reduced motion; then the map's wiring: Go walks to Washington Square before the room opens, the
## room's loading layer stands on the iris colour, the way back opens the iris from the pin, a room that fails sends the
## avatar home, Back while walking calls the trip off, a tap skips it, Enter my farm walks home and opens the farm.
## Time is stepped by hand (the layer's own _process is off), so every phase is checked at a known moment.
const MapTravel := preload("res://scenes/dynamic_farm/map_travel.gd")
const TownEntry := preload("res://scenes/dynamic_farm/town_entry.gd")
const Android := preload("res://scenes/map_poc/map_bridge_android.gd")
const RouterFixture := preload("res://tests/dynamic_farm/app_router_fixture.gd")
const LoadingLayer := preload("res://modules/ui/loading_overlay.gd")
const OWN_FARM := "sensen/dynamic_farm/own_farm"
const FAKE_CLAIMS := "sensen/dynamic_farm/fake_claims"
## Home about 0.25 km south-east of the Washington Square pin.
const HOME_GEO := [-122.4085, 37.7990]
const STEP := 0.01

## A flat camera: 100 000 px a degree round its centre.
class FakeCamera extends Control:
	var center := PackedFloat64Array([-122.4094, 37.7999])
	var zoom := 17.0
	var flights: Array = []
	var moves := false
	func geo_screen(lon: float, lat: float) -> Vector2:
		return size * 0.5 + Vector2((lon - center[0]) * 100000.0, -(lat - center[1]) * 100000.0)
	func fly_to(lon: float, lat: float, level: float) -> void: flights.append([lon, lat, level])
	func flying() -> bool: return false
	func moving() -> bool: return moves
	func stop() -> void: pass
	func _changed() -> void: pass
	var input_enabled := true
class FakePin extends Node:
	var pin := UiMapDestination.new()
	var poses: Array = []
	func _init() -> void: add_child(pin)
	func set_travel_pose(lift: float, pop: float) -> void:
		poses.append([lift, pop]); pin.focus = pop
class Plugin extends Node:
	func has_java_method(method: String) -> bool:
		return method in ["setMapOcclusionColor", "getMapVisibilityState", "setMapVisible", "setGodotSurfaceOpaque"]
	func setMapOcclusionColor(_rgb: String) -> void: pass
	func setGodotSurfaceOpaque(_value: bool) -> void: pass
	func setMapVisible(_value: bool) -> void: pass
	func getMapVisibilityState() -> String: return "{}"
class Selector extends Node:
	signal changed
	var busy := false
	var manifest := {"dataset_version": "r8"}
	var selection := {"block_id": "p-home"}
	var taps := 0
	var farms := 0
	func tap(_point: Vector2, _zoom: float) -> void: taps += 1
	func open_farm(_release := "") -> void: farms += 1; busy = true
	func pause() -> void: pass
	func activate() -> void: pass
	func home_release(v: String) -> String: return v
class Claims extends Node:
	var mine := {"parcel_id": "p-home", "center": HOME_GEO, "dataset_version": "r8"}
	var busy := false
	func has_home() -> bool: return not mine.is_empty()
	func status(id: String) -> String: return "mine" if id == "p-home" else "none"
	func start() -> void: pass
	func pause() -> void: pass
class Router extends Node:
	var sync_loads := true
	var top: Node
	var page: Node
	var opened: Array = []
	var push := true
	func top_instance() -> Node: return top
	func open_instance(path: String, args: Dictionary) -> void:
		opened.append([path, args])
		await get_tree().process_frame
		if push: top = Node.new(); add_child(top); page.suspend()
	func back() -> void:
		top.queue_free(); top = null; page.resume()
## The real map's UI, travel and handlers on fakes; its render only places the pin and the avatar.
class MapPage extends "res://scenes/dynamic_farm/dynamic_farm_map.gd":
	func _ready() -> void:
		_build_ui()
		_camera = FakeCamera.new(); _camera.size = Vector2(400, 800); add_child(_camera); move_child(_camera, 0)
		_hud.size = Vector2(400, 800); _travel.size = _hud.size; _entry.size = _hud.size
		_travel.process_mode = Node.PROCESS_MODE_DISABLED
	func _render() -> void:
		if _selector == null: return
		_render_entry(); _render_travel()
		_card.visible = not _travel_card
		if not _selector.busy and _travel.heading(MapTravel.HOME) and _travel.phase != MapTravel.Phase.CLOSED and _farm_waiting.is_empty():
			_travel.cancel.call_deferred(false)

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	_config()
	_geometry()
	await _timeline()
	await _map()
	await _loading_backdrop()
	print("MAP_TRAVEL checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## Table 4 of the motion spec (attachment-1658) and the PM's anchors (C-188#13), all in the config.
func _config() -> void:
	var c := MapTravel.settings()
	_check(not c.is_empty(), "the trip's config reads (%s)" % MapTravel.CONFIG)
	var spec := {"card_exit_ms": 160, "route_draw_ms": 360, "route_bulge": 0.18, "route_dash_px": 9, "route_gap_px": 6,
		"route_under_px": 7, "route_px": 3, "walk_base_s": 0.9, "walk_per_km_s": 0.8, "walk_min_s": 1.2, "walk_max_s": 2.4,
		"hop_hz": 3, "hop_px": 4, "arrive_scale": 1.18, "arrive_pop_ms": 220, "ripple_ms": 420, "ripple_scale": 1.8,
		"iris_close_ms": 380, "iris_open_ms": 320, "token_idle_ms": 1600, "token_idle_px": 2, "token_pop_ms": 160,
		"token_pop_scale": 1.1, "token_lift_px": 6, "dest_bob_ms": 800, "dest_bob_px": 2, "iris_delay_ms": 120,
		"top_fade_ms": 120, "land_pop_ms": 160, "land_from_scale": 0.6, "skip_ms": 120, "cancel_ms": 200, "reduced_fade_ms": 120}
	for key in spec: _check(is_equal_approx(float(c.get(key, -1)), float(spec[key])), "config %s = %s (D-437)" % [key, spec[key]])
	_check(Color(str(c.iris_color)) == Color("E7F0DF"), "the iris is the map's occlusion colour #E7F0DF")
	_check(Color(str(c.route_color)) == Color("7DAA32") and absf(Color(str(c.route_under_color)).a - 0.9) < 0.01, "route: #7DAA32 over 90 % white")
	_check(c.fit_padding == {"top": 140.0, "bottom": 160.0, "left": 48.0, "right": 48.0} and c.fit_zoom == [15.0, 18.0], "framing: 140/160/48 padding, zoom 15–18")
	for key in ["token_offset_pin", "token_offset_home", "iris_center_pin"]: _check(c.get(key) is Array and c[key].size() == 2, "anchor %s is configurable" % key)
	var source := FileAccess.get_file_as_string("res://scenes/dynamic_farm/map_travel.gd")
	var used := RegEx.create_from_string("cfg\\.([a-z_]+)|_ms\\(\"([a-z_]+)\"\\)|_vec\\(\"([a-z_]+)\"\\)")
	var missing: Array = []
	for m in used.search_all(source):
		var key := m.get_string(1) + m.get_string(2) + m.get_string(3)
		if key != "get" and key != "is_empty" and not c.has(key) and key not in missing: missing.append(key)
	_check(missing.is_empty(), "every key the layer reads is in the config (missing %s)" % [missing])

func _geometry() -> void:
	var c := MapTravel.settings()
	_check(is_equal_approx(MapTravel.walk_ms(c, 0.3), 1200.0), "0.3 km walks 1.2 s (0.9 + 0.24, at least 1.2)")
	_check(is_equal_approx(MapTravel.walk_ms(c, 1.0), 1700.0), "1 km walks 1.7 s")
	_check(is_equal_approx(MapTravel.walk_ms(c, 5.0), 2400.0), "far walks at most 2.4 s")
	for pair in [[Vector2(0, 100), Vector2(200, 100)], [Vector2(200, 100), Vector2(0, 100)], [Vector2(0, 0), Vector2(100, 300)], [Vector2(100, 300), Vector2(0, 0)]]:
		var cp := MapTravel.control_point(pair[0], pair[1], 0.18)
		var mid: Vector2 = (pair[0] + pair[1]) * 0.5
		_check(cp.y <= mid.y and is_equal_approx(cp.distance_to(mid), 0.18 * pair[0].distance_to(pair[1])), "the arc bulges 0.18 × its length towards the top (%s → %s)" % pair)
	var straight := PackedVector2Array([Vector2.ZERO, Vector2(60, 0)])
	var pieces := MapTravel.dashes(straight, 9.0, 6.0)
	_check(pieces.size() == 4 and is_equal_approx(pieces[0][-1].x, 9.0) and is_equal_approx(pieces[1][0].x, 15.0), "dashes 9 apart by 6 (%d)" % pieces.size())
	var screen := Vector2(400, 800)
	var safe := MapTravel.safe_rect(c, screen)
	_check(safe == Rect2(48, 140, 304, 500), "the safe area leaves the top bar and the card")
	_check(is_equal_approx(MapTravel.fit_zoom(c, screen, 17.0, Vector2(0, 0), Vector2(608, 0)), 16.0), "two ends 2 × the safe width apart: one zoom level out")
	_check(MapTravel.fit_zoom(c, screen, 17.0, Vector2(0, 0), Vector2(1, 1)) == 17.0 and MapTravel.fit_zoom(c, screen, 13.0, Vector2.ZERO, Vector2(10000, 0)) == 15.0,
		"framing keeps the zoom for one point and stays within 15–18")
	_check(is_equal_approx(MapTravel.arc(0.5), 0.5) and MapTravel.pop_curve(0.5) > 1.0 and is_equal_approx(MapTravel.standard(1.0), 1.0), "the v3 curves")

func _step(t: Control, ms: float) -> void:
	var n := ceili(ms / (STEP * 1000.0))
	for i in n: t._process(STEP)

func _travel_on(camera: Control, town: Node) -> Control:
	var t := MapTravel.new()
	t.process_mode = Node.PROCESS_MODE_DISABLED
	t.size = Vector2(400, 800)
	root.add_child(t)
	t.add_child(t.make_iris())
	t.iris.size = t.size
	t.camera = camera
	t.places = {"home": {"geo": HOME_GEO, "pin": null}, "town": {"geo": [TownEntry.LON, TownEntry.LAT], "pin": town}}
	t.shown = true
	return t

func _timeline() -> void:
	var camera := FakeCamera.new(); camera.size = Vector2(400, 800); root.add_child(camera)
	var town := FakePin.new(); root.add_child(town)
	MapTravel.at = MapTravel.HOME
	var t := _travel_on(camera, town)
	var top := Control.new(); root.add_child(top); t.fade_in.assign([top])
	var log: Array = []
	t.closed.connect(func(p): log.append(["closed", p]))
	t.cancelled.connect(func(p): log.append(["cancelled", p]))
	t.card_gone.connect(func(): log.append(["card"]))
	_step(t, 50)
	var home_tip: Vector2 = camera.geo_screen(HOME_GEO[0], HOME_GEO[1]) + Vector2(12, -35)
	_check(t.token.visible and t.token.position.distance_to(home_tip - Vector2(17, 17)) <= 2.01, "the avatar stands at the top right of home (±2 idle float)")
	camera.moves = true
	_step(t, 400)
	_check(t.token.position.is_equal_approx(home_tip - Vector2(17, 17)), "the idle float holds still while the map moves")
	camera.moves = false
	var card := Control.new(); root.add_child(card)
	for i in 3: await process_frame # past the first frames, whose tweens do not advance yet
	_check(t.depart("town", card), "Go sets off from home to Washington Square")
	_check(t.walking() and t.heading("town") and not t.depart("home"), "one trip at a time")
	_step(t, 100)
	await create_timer(0.12).timeout
	_check(card.modulate.a < 1.0 and log.is_empty(), "the card fades out first (card_exit_ms)")
	_step(t, 70)
	_check(log == [["card"]] and t.phase == MapTravel.Phase.WALK and camera.flights.is_empty(), "then walks; both ends on screen: no flight")
	_step(t, 120)
	_check(t.token.scale.x > 1.05, "the avatar pops to 1.1 before it walks")
	_step(t, 600)
	var at_mid: Vector2 = t.token.position
	var start := home_tip - Vector2(17, 17)
	var pin_at: Vector2 = camera.geo_screen(TownEntry.LON, TownEntry.LAT)
	_check(at_mid.distance_to(start) > 40.0 and at_mid.distance_to(pin_at) > 40.0, "half way it is between home and the pin")
	var a := home_tip + Vector2(0, 23); var b := pin_at + Vector2(16, -52) + Vector2(0, 23)
	var mid := (a + b) * 0.5
	_check((at_mid + Vector2(17, 17)).y < mid.y, "on an arc above the straight line")
	_check(town.poses.any(func(p): return absf(p[0]) > 0.5 and p[1] == 1.0), "the pin floats while it waits")
	await process_frame
	_check(t._route_left, "the dashed route is drawn")
	_step(t, 700)
	_check(t.phase == MapTravel.Phase.ARRIVE, "it arrives after token_pop_ms + 1.2 s")
	_check(not t.iris.visible, "the iris waits iris_delay_ms")
	_step(t, 100)
	_check(town.poses[-1][1] > 1.1, "the pin pops at the arrival")
	_step(t, 200)
	_check(t.iris.visible and (t.iris.material as ShaderMaterial).get_shader_parameter("radius") > 0.0, "then closes on the pin")
	_check(is_equal_approx((t.iris.material as ShaderMaterial).get_shader_parameter("center").distance_to(pin_at + Vector2(0, -20)), 0.0), "centred on the pin's disc")
	_step(t, 320)
	_check(log[-1] == ["closed", "town"] and MapTravel.at == "town" and t.phase == MapTravel.Phase.CLOSED, "closed: the room may open; the avatar is at the pin")
	_check(town.poses[-1] == [0.0, 1.0], "the pin is back to its own size")
	_check(not t.token.visible, "nothing of the map shows under the closed iris")
	# The way back (R-01..R-03).
	t.come_back("town", "town")
	_check(t.iris.visible and top.modulate.a == 0.0 and not t.token.visible, "back on the map: the iris covers it, the top bar is hidden")
	_step(t, 250)
	_check(top.modulate.a > 0.0 and top.modulate.a < 1.0, "the top bar fades in at the end of the iris")
	_step(t, 100)
	_check(not t.iris.visible and t.token.visible and t.token.scale.x < 1.0, "the avatar lands after the iris (from 0.6)")
	_step(t, 200)
	_check(t.phase == MapTravel.Phase.IDLE and top.modulate.a == 1.0 and t.token.scale.x == 1.0, "and stands at the pin")
	var town_tip: Vector2 = pin_at + Vector2(16, -52)
	_check(t.token.position.distance_to(town_tip - Vector2(17, 17)) <= 2.01, "the avatar's anchor is the pin's top right (token_offset_pin)")
	# A tap while walking: the end in skip_ms.
	_check(t.depart("home"), "home again")
	_step(t, 600)
	t.skip()
	_check(t.phase == MapTravel.Phase.SKIP, "a tap skips")
	_step(t, 130)
	_check(t.phase == MapTravel.Phase.ARRIVE, "and it is there skip_ms later")
	_step(t, 600)
	_check(log[-1] == ["closed", "home"] and MapTravel.at == "home", "the iris closes on home")
	# Long frames back on the map (the scene switch, a slow phone): shut for open_hold_frames, then max_step_ms a frame.
	t.come_back("home", "home")
	t._process(1.0)
	_check(t.phase == MapTravel.Phase.OPEN and (t.iris.material as ShaderMaterial).get_shader_parameter("radius") == 0.0, "the first frames back keep the iris shut (open_hold_frames)")
	t._process(1.0); t._process(1.0)
	_check(t.phase == MapTravel.Phase.OPEN and is_equal_approx(t._t, 100.0), "a 1 s frame moves the iris on by max_step_ms only")
	_step(t, 600)
	# Back while walking: back where it left.
	_check(t.depart("town"), "out again")
	_step(t, 900)
	_check(t.cancel(), "Back while walking calls it off")
	_check(t.phase == MapTravel.Phase.CANCEL, "the avatar walks back")
	_step(t, 210)
	_check(t.phase == MapTravel.Phase.IDLE and MapTravel.at == "home" and log[-1] == ["cancelled", "home"], "home again, the trip cancelled")
	await process_frame
	_check(not t.iris.visible and not t._route_left, "no iris, no route left")
	# The farm wait (Enter my farm): held at the arrival until the farm is read; Back still cancels then.
	t.depart("home"); t.hold = true
	_step(t, 170)
	_check(t.phase == MapTravel.Phase.ARRIVE, "setting off where it stands goes straight to the iris")
	_step(t, 1000)
	_check(t.phase == MapTravel.Phase.ARRIVE and not t.iris.visible, "held: the iris waits for the farm")
	t.hold = false
	_step(t, 400)
	_check(log[-1] == ["closed", "home"], "the farm read: the iris closes on home (iris_close_ms)")
	t.come_back("home", "home"); _step(t, 600)
	MapTravel.at = "town"
	t.depart("home"); t.hold = true
	_step(t, 3000)
	_check(t.phase == MapTravel.Phase.ARRIVE and t.cancel() and MapTravel.at == "town", "Back while the farm loads: back where it left")
	# Framing: an end outside the safe area flies the camera first.
	MapTravel.at = "home"
	camera.center = PackedFloat64Array([TownEntry.LON + 0.002, TownEntry.LAT])
	t.depart("town"); _step(t, 170)
	_check(camera.flights.size() == 1 and camera.flights[0][2] >= 15.0 and camera.flights[0][2] <= 18.0, "an end off the safe area: fly_to frames both (%s)" % [camera.flights])
	t.cancel(false)
	_check(MapTravel.at == "home" and t.phase == MapTravel.Phase.IDLE, "a cancel without its walk back")
	camera.center = PackedFloat64Array([-122.4094, 37.7999])
	# Reduced motion: no route, no walk, a 120 ms fade.
	UiMotion.reduced = true
	t.depart("town"); _step(t, 170)
	_check(t.phase == MapTravel.Phase.ARRIVE, "reduced: straight to the end, no route or walk")
	_step(t, 60)
	_check(t.iris.visible and t.iris.modulate.a > 0.2 and t.iris.modulate.a < 0.8, "reduced: the cover fades in")
	_step(t, 80)
	_check(log[-1] == ["closed", "town"], "reduced: 120 ms later the room may open")
	t.come_back("town", "town"); _step(t, 60)
	_check(t.iris.modulate.a < 0.8 and top.modulate.a == 1.0, "reduced: the cover fades out, the top bar is there")
	_step(t, 100)
	_check(t.phase == MapTravel.Phase.IDLE and t.token.visible and t.token.scale.x == 1.0, "reduced: the avatar is simply there")
	UiMotion.reduced = false
	t.shown = false; _step(t, 20)
	_check(not t.token.visible, "no home (or no own farm): no avatar")
	for n in [t, camera, town, top, card]: n.queue_free()
	await process_frame

func _map() -> void:
	ProjectSettings.set_setting(OWN_FARM, true)
	ProjectSettings.set_setting(FAKE_CLAIMS, true)
	MapTravel.at = MapTravel.HOME; MapTravel.home_parcel = ""
	var plugin := Plugin.new(); root.add_child(plugin)
	var bridge := Android.new(); bridge._plugin = plugin
	var router := Router.new(); var real_router := RouterFixture.install(root, router)
	var page := MapPage.new(); root.add_child(page)
	router.page = page
	var selector := Selector.new(); page.add_child(selector)
	var claims := Claims.new(); page.add_child(claims)
	page._selector = selector; page._claims = claims; page._bridge = bridge
	page._render()
	var t: Control = page._travel
	_check(t.get_parent() == page._hud and t.get_index() > page._entry.get_index(), "the avatar draws over the pins")
	_check(t.iris.get_parent() == page._hud and t.iris.get_index() == page._hud.get_child_count() - 1, "the iris covers the map's panels and keys")
	_check(t.shown and MapTravel.home_parcel == "p-home" and t.places.has("home") and t.places.has(page.TOWN), "home and the pin are the avatar's places")
	# Go on the Washington Square card.
	page._entry.open_card()
	page._open_town()
	_check(t.heading(page.TOWN) and router.opened.is_empty(), "Go walks to the pin before the room opens")
	page._on_map_tap(Vector2(0.5, 0.5))
	_check(selector.taps == 0 and t.phase == MapTravel.Phase.SKIP, "a tap while walking skips instead of picking a building")
	_step(t, 200)
	_check(not page._entry.is_open(), "the place card closed as the trip set off")
	_check(page.is_back_navigation_locked() and t.phase == MapTravel.Phase.ARRIVE, "Back past the arrival waits for the room")
	_step(t, 600)
	await process_frame
	_check(router.opened.size() == 1 and router.opened[0][0] == page.ROOM, "the iris closed: the room opens")
	var args: Dictionary = router.opened[0][1]
	_check(args.get(LoadingLayer.BACKDROP) == Color(page.OCCLUSION_COLOR), "its loading layer stands on the iris colour")
	await process_frame
	await process_frame
	_check(page._suspended and page._inside == page.TOWN and MapTravel.at == page.TOWN, "the room is up; the avatar is at the pin")
	router.back()
	_check(t.phase == MapTravel.Phase.OPEN and page._inside.is_empty(), "back from the room: the iris opens from the pin")
	_step(t, 600)
	_check(t.phase == MapTravel.Phase.IDLE and t.token.visible and MapTravel.at == page.TOWN, "the avatar stays at the pin")
	# Enter my farm from the pin: the walk home, then the farm once read.
	page._enter_farm()
	_check(selector.farms == 1 and t.heading(MapTravel.HOME) and t.hold, "Enter my farm reads the farm and walks home meanwhile")
	_step(t, 2500)
	_check(t.phase == MapTravel.Phase.ARRIVE and router.opened.size() == 1, "home before the farm is read: it waits")
	selector.busy = false
	page._open_host({"dataset_version": "r8", "block_id": "p-home"})
	_step(t, 600)
	await process_frame
	_check(router.opened.size() == 2 and router.opened[1][0] == page.HOST and router.opened[1][1].get("own_parcel") == true, "the iris closed on home: the own farm opens")
	await process_frame
	await process_frame
	router.back()
	_step(t, 600)
	_check(MapTravel.at == MapTravel.HOME and t.phase == MapTravel.Phase.IDLE, "back from the farm, at home")
	# Back while walking.
	page._entry.open_card(); page._open_town()
	_step(t, 600)
	_check(page.is_back_navigation_locked() and t.phase == MapTravel.Phase.CANCEL, "Back while walking calls the trip off")
	_step(t, 250)
	_check(MapTravel.at == MapTravel.HOME and router.opened.size() == 2 and page._preloading.is_empty(), "nothing opened, the avatar is home")
	# A room that cannot open: the iris opens again and the avatar goes home.
	router.push = false
	page._entry.open_card(); page._open_town()
	_step(t, 2500)
	await process_frame
	await process_frame
	_check(router.opened.size() == 3 and not page._suspended and t.phase == MapTravel.Phase.OPEN and MapTravel.at == MapTravel.HOME,
		"the room failed: the iris opens, the avatar is back home")
	_step(t, 600)
	# A farm read that fails calls the trip home off.
	router.push = true
	MapTravel.at = page.TOWN
	page._enter_farm()
	_step(t, 300)
	selector.busy = false; page._render()
	await process_frame
	_check(MapTravel.at == page.TOWN and t.phase == MapTravel.Phase.IDLE and not page._travel_card, "the farm read failed: back at the pin, the card back")
	# The app leaves for the background mid-walk.
	MapTravel.at = MapTravel.HOME
	page._entry.open_card(); page._open_town()
	_step(t, 500)
	var opened := router.opened.size()
	page._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(t.phase == MapTravel.Phase.IDLE and MapTravel.at == MapTravel.HOME, "a walk left for the background is called off")
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_step(t, 600)
	await process_frame
	var walk_back := [t.phase, MapTravel.at, t.iris.visible, t.token.visible, page._travel_card, router.opened.size()]
	_check(walk_back == [MapTravel.Phase.IDLE, MapTravel.HOME, false, true, false, opened], "back from the background: home, nothing opened (%s)" % [walk_back])
	# C-207: the same between the arrival and the iris closed (ARRIVE).
	page._entry.open_card(); page._open_town()
	_step(t, 1700)
	_check(t.phase == MapTravel.Phase.ARRIVE and t.iris.visible, "at the pin, the iris closing")
	page._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(t.phase == MapTravel.Phase.IDLE and MapTravel.at == MapTravel.HOME and not t.iris.visible, "an arrival left for the background is called off")
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_step(t, 600)
	await process_frame
	var arrive_back := [t.phase, MapTravel.at, t.iris.visible, t.token.visible, page._travel_card, router.opened.size()]
	_check(arrive_back == walk_back, "back from the background: as after a walk (%s)" % [arrive_back])
	# Held at home for the farm read (Enter my farm): called off too; the read that lands later opens nothing.
	MapTravel.at = page.TOWN
	selector.busy = false
	page._enter_farm()
	_step(t, 2500)
	_check(t.phase == MapTravel.Phase.ARRIVE and t.hold and selector.busy, "held at home for the farm")
	page._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(t.phase == MapTravel.Phase.IDLE and MapTravel.at == page.TOWN and page._drop_farm, "the wait left for the background is called off")
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	selector.busy = false
	page._open_host({"dataset_version": "r8", "block_id": "p-home"})
	_step(t, 600)
	await process_frame
	_check(router.opened.size() == opened and MapTravel.at == page.TOWN and t.phase == MapTravel.Phase.IDLE and not page._drop_farm,
		"back from the background: at the pin, the late farm read opens nothing")
	page.queue_free(); plugin.queue_free()
	await process_frame
	RouterFixture.restore(root, router, real_router)
	ProjectSettings.set_setting(OWN_FARM, null)
	ProjectSettings.set_setting(FAKE_CLAIMS, null)

## The room's loading layer after a trip (AppRouter's default one, given the backdrop): Loading on the iris colour, no
## paper or map picture; without it the layer is as it was.
func _loading_backdrop() -> void:
	for case in [[Color("E7F0DF"), Color("E7F0DF"), false], [null, GameUi.PAPER, true]]:
		var layer: CanvasLayer = LoadingLayer.new()
		layer.english = true
		if case[0] != null: layer.backdrop = case[0]
		root.add_child(layer)
		var background: ColorRect = layer.get_child(0)
		var picture: TextureRect = background.get_child(0)
		_check(background.color == case[1] and picture.visible == case[2] and layer.message.text == "Loading...",
			"the loading layer on %s: picture %s" % [case[1].to_html(false), case[2]])
		layer.queue_free()
	await process_frame

extends Node3D
## The Aquatic Park pier (C-232, 0.4.7): the dynamic farm's second 3D space after the Washington Square room, opened from
## its map pin (town_entry.gd pier()). The model is SEN-C-233's (PIER_SCENE); this scene reads only its root's
## `Entrance` marker and four metadata contours, local x/z in metres (C-233#72): `walk_polygon` (where one walks),
## `stand_polygon` (the band along the edge one fishes from), `fish_edge` (the open line along it, from the inner curve
## round the belvedere to the outer one) and `water_polygon` (the water a line may land in). The whole edge fishes
## (the owner on SEN-C-233#50: no single fishing spot, a tap on the water casts): a tap on the water walks the player to
## the nearest point of `fish_edge` and casts toward the tap; a tap on the deck walks there; a drag is the floating
## joystick; two fingers pinch. One player here: other players at the pier are for later (the save holds only this
## player's line, no spot is held).
## Fishing goes through the home's parcel save (store: read / send, as the room's keepers): ParcelFishingPanel and
## FishingPresentation (the P0 pond's pose, rod, line, float, landing arc), the walking camera unchanged (LOCK-24 ①:
## the farm's scale, pitch and yaw). The first visit sends `visit_pier` (the Starter Rod, once); the bait chip picks
## the bait in the bag for the next cast. The top bar's back (or Android Back) returns to the map.
## Without the model (a build before SEN-C-233 lands) a plain straight pier stands in, with the same four contours.
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Fishing = preload("res://modules/dynamic_farm/parcel_fishing.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const Entry = preload("res://scenes/dynamic_farm/town_entry.gd")
const PierPanel = preload("res://scenes/dynamic_farm/parcel_fishing_panel.gd")
const CameraRules = preload("res://modules/farm/farm_camera.gd")
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
const PIER_SCENE := "res://scenes/aquatic_park/aquatic_park_pier.tscn"
const CITY := "San Francisco"
## The walk's cell (FarmBlueprint): fine enough for a 2.4 m deck.
const CELL_M := 0.25
## A cast lands MIN_CAST_M–MAX_CAST_M from where the player stands, toward the tap.
const MIN_CAST_M := 1.5
const MAX_CAST_M := 5.0
## Within this of the edge point counts as there.
const ARRIVE_M := 0.15
const ZOOM_RANGE := Vector2(0.8, 1.4)
## The P0 pond's float and line at the walking scale.
const FLOAT_SCALE := 1.6
const CATCH_POP := 1.5
const LINE_PX := 1.5
const LINE_INK := Color("#2F3A33B3")
## The stand-in pier (no SEN-C-233 model): a deck 2.4 m wide and 16 m long out from the entrance, water round it.
const STAND_IN_WATER_Y := -1.45

var store: RefCounted
var parcel_id := ""
var place_name := Entry.PIER.title
var farm := {}
var farm_version := -1
## Server time minus this device's clock at the last answer.
var server_offset := 0
var busy := false
var pier: Node3D
var walk_polygon := PackedVector2Array()
var stand_polygon := PackedVector2Array()
var fish_edge := PackedVector2Array()
var water_polygon := PackedVector2Array()
var water_y := STAND_IN_WATER_Y
var entrance := Vector3.ZERO
var bp: FarmBlueprint
var grid: BlueprintGrid
var actor: P0Actor
var cam: Camera3D
var panel: PierPanel
var view: FishingPresentation
var toast: ToastLayer
## The bait for the next cast ("" none), picked on the bait chip from what the bag holds.
var bait := ""
## A tap on the water waiting for the player to reach its edge point: {origin, target}.
var plan := {}
var _hud: CanvasLayer
var _pad: Control
var _top: HBoxContainer
var _bait_key: UiGlassButton
var _bait_count: Label
var _focus := Vector3.ZERO
var _normal_size := 7.0
var _zoom := 1.0
var _pinch = ElasticZoom.new(ZOOM_RANGE.x, ZOOM_RANGE.y)
var _leaving := false
var _suspended := false
var _joy := Vector2.ZERO

func setup(args: Dictionary) -> void:
	store = args.get("store") as RefCounted
	parcel_id = str(args.get("parcel_id", ""))

func _ready() -> void:
	name = "ParcelPier"
	_build_world()
	_build_walk()
	_build_actor()
	_build_hud()
	panel = PierPanel.new()
	panel.name = "PierFishing"
	add_child(panel)
	panel.closed.connect(_end_fishing)
	_read_farm()

# ---------------------------------------------------------------- world
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.54, 0.75, 0.83)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.93, 0.95, 1.0)
	e.ambient_light_energy = 0.64
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-43, 34, 0)
	sun.light_color = Color(1, 0.954, 0.86)
	sun.light_energy = 0.97
	sun.shadow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	cam = Camera3D.new()
	cam.name = "PierCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)
	cam.make_current()
	_normal_size = CameraRules.close_view_size(get_viewport().get_visible_rect().size) * CameraRules.P0_VIEW_K
	var packed := load(PIER_SCENE) as PackedScene if ResourceLoader.exists(PIER_SCENE) else null
	pier = packed.instantiate() as Node3D if packed != null else null
	if pier != null and read_contours(pier):
		add_child(pier)
	else:
		if pier != null: pier.free()
		pier = stand_in()
		read_contours(pier)
		add_child(pier)

## The model's contours and entrance (C-233#72); false when one is missing or too short.
func read_contours(node: Node3D) -> bool:
	for key in ["walk_polygon", "stand_polygon", "fish_edge", "water_polygon"]:
		var v = node.get_meta(key, null)
		if not v is PackedVector2Array or (v as PackedVector2Array).size() < (2 if key == "fish_edge" else 3): return false
	walk_polygon = node.get_meta("walk_polygon")
	stand_polygon = node.get_meta("stand_polygon")
	fish_edge = node.get_meta("fish_edge")
	water_polygon = node.get_meta("water_polygon")
	var mark := node.get_node_or_null("Entrance") as Node3D
	entrance = mark.position if mark != null else Vector3(walk_polygon[0].x, 0, walk_polygon[0].y)
	var bay := node.get_node_or_null("Bay") as Node3D
	water_y = bay.position.y if bay != null else float(node.get_meta("water_y", STAND_IN_WATER_Y))
	return true

## A plain pier for builds without SEN-C-233's model: a deck from the entrance at z 0 out to z −16, 2.4 m wide, water
## round it 1.45 m down; the same four contours.
static func stand_in() -> Node3D:
	var root := Node3D.new()
	root.name = "StandInPier"
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 0.3, 16.0)
	deck.mesh = box
	deck.position = Vector3(0, -0.15, -8.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.77, 0.74, 0.63)
	box.material = wood
	root.add_child(deck)
	var bay := MeshInstance3D.new()
	bay.name = "Bay"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var sea := StandardMaterial3D.new()
	sea.albedo_color = Color(0.28, 0.63, 0.73)
	plane.material = sea
	bay.mesh = plane
	bay.position = Vector3(0, STAND_IN_WATER_Y, -8.0)
	root.add_child(bay)
	var mark := Marker3D.new()
	mark.name = "Entrance"
	mark.position = Vector3(0, 0, -0.5)
	root.add_child(mark)
	root.set_meta("walk_polygon", PackedVector2Array([Vector2(-1.1, 0), Vector2(1.1, 0), Vector2(1.1, -15.9), Vector2(-1.1, -15.9)]))
	root.set_meta("stand_polygon", PackedVector2Array([Vector2(-1.1, -1), Vector2(1.1, -1), Vector2(1.1, -15.9), Vector2(-1.1, -15.9)]))
	root.set_meta("fish_edge", PackedVector2Array([Vector2(-0.9, -1), Vector2(-0.9, -15.7), Vector2(0.9, -15.7), Vector2(0.9, -1)]))
	root.set_meta("water_polygon", PackedVector2Array([Vector2(-20, 0.5), Vector2(-1.25, 0.5), Vector2(-1.25, -16.1), Vector2(1.25, -16.1),
		Vector2(1.25, 0.5), Vector2(20, 0.5), Vector2(20, -28), Vector2(-20, -28)]))
	return root

# ---------------------------------------------------------------- walking
## The deck as a FarmBlueprint grid (as PondWalk builds a pond's): a cell walks when its centre is inside walk_polygon.
func _build_walk() -> void:
	var box := Rect2(walk_polygon[0], Vector2.ZERO)
	for p in walk_polygon: box = box.expand(p)
	bp = FarmBlueprint.new()
	bp.layout_patch_id = "aquatic_park_pier"
	bp.cell_m = CELL_M
	bp.cell_mm = roundi(CELL_M * 1000)
	var lo := Vector2i(floori(box.position.x / CELL_M), floori(-box.end.y / CELL_M))
	var hi := Vector2i(floori(box.end.x / CELL_M), floori(-box.position.y / CELL_M))
	var rows := PackedStringArray()
	for j in range(lo.y, hi.y + 1):
		var row := ""
		for i in range(lo.x, hi.x + 1):
			var w := Vector2((i + 0.5) * CELL_M, -(j + 0.5) * CELL_M)
			row += "1" if Geometry2D.is_point_in_polygon(w, walk_polygon) else "0"
		rows.append(row)
	bp.grid_origin = lo
	bp.grid = hi - lo + Vector2i.ONE
	bp.play_area_m = maxf(box.size.x, box.size.y)
	bp.play_area_mm = roundi(bp.play_area_m * 1000)
	bp.masks = {"walkable": rows}
	bp.anchors = {"spawn": bp.world_to_cell(entrance)}
	grid = BlueprintGrid.new(bp)

func _build_actor() -> void:
	actor = P0Actor.new()
	actor.name = "Player"
	add_child(actor)
	actor.setup(bp, grid, cam, walkable_point(entrance))
	_focus = actor.position
	_place_camera()

## The nearest point the walk can stand on (a cell's centre inside walk_polygon), or `p` itself when it can.
func walkable_point(p: Vector3) -> Vector3:
	var c := bp.world_to_cell(p)
	if bp.is_walkable(c): return Vector3(p.x, 0, p.z)
	var best := Vector3.INF
	for j in bp.grid.y:
		for i in bp.grid.x:
			var cell := bp.grid_origin + Vector2i(i, j)
			if not bp.is_walkable(cell): continue
			var w := bp.cell_to_world(cell)
			if best == Vector3.INF or w.distance_squared_to(p) < best.distance_squared_to(p): best = w
	return best if best != Vector3.INF else Vector3(p.x, 0, p.z)

## Where to stand and where the line lands for a tap on the water at `tap` (x/z on the water): the nearest point of
## fish_edge, and the tap moved to between MIN_CAST_M and MAX_CAST_M from it, kept on the water (backed toward the edge
## until it is). {} when no edge point casts there.
func cast_plan(tap: Vector3) -> Dictionary:
	var t := Vector2(tap.x, tap.z)
	if fish_edge.size() < 2 or not Geometry2D.is_point_in_polygon(t, water_polygon): return {}
	var origin := fish_edge[0]
	for i in fish_edge.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(t, fish_edge[i], fish_edge[i + 1])
		if q.distance_squared_to(t) < origin.distance_squared_to(t): origin = q
	var dir := (t - origin).normalized() if t.distance_to(origin) > 0.01 else Vector2.ZERO
	if dir == Vector2.ZERO: return {}
	var reach := clampf(t.distance_to(origin), MIN_CAST_M, MAX_CAST_M)
	while reach >= 0.6:
		var land := origin + dir * reach
		if Geometry2D.is_point_in_polygon(land, water_polygon) and not Geometry2D.is_point_in_polygon(land, walk_polygon):
			var stand := walkable_point(Vector3(origin.x, 0, origin.y))
			return {"origin": stand, "target": Vector3(land.x, water_y, land.y)}
		reach -= 0.25
	return {}

## Walks the player to `p` on the deck (the nearest walkable point); false when there is no way.
func walk_to(p: Vector3) -> bool:
	return actor.mover.set_target_position(walkable_point(p))

func _process(dt: float) -> void:
	if _suspended or actor == null: return
	if not is_instance_valid(view):
		actor.set_input(_joy)
	actor.step(dt)
	if not plan.is_empty() and not actor.mover.is_moving():
		var at := Vector2(actor.position.x, actor.position.z)
		var want := Vector2(plan.origin.x, plan.origin.z)
		if at.distance_to(want) <= ARRIVE_M + CELL_M: _begin_fishing()
		else: plan = {}
	if _pinch.step(dt): _set_zoom(_pinch.value)
	var size := get_viewport().get_visible_rect().size
	var safe := Rect2(size * Vector2(0.23, 0.26), size * Vector2(0.54, 0.48))
	_focus += CameraRules.follow_shift(cam, actor.position, safe)
	if _joy.is_zero_approx() and not actor.mover.is_moving(): _focus = _focus.lerp(actor.position, minf(dt * 2.8, 1.0))
	_place_camera()
	if is_instance_valid(view) and panel.visible: panel.player_rect = actor.screen_box(cam)   # the gauge keeps off the player

func _place_camera() -> void:
	cam.size = _normal_size * _zoom
	CameraRules.place(cam, _focus)
	CameraRules.fit_ground_depth(cam, water_y - 0.5, 5.0)

func _set_zoom(z: float) -> void:
	_zoom = z

# ---------------------------------------------------------------- input
func p0_joystick(v: Vector2) -> void:
	_joy = v
	if not v.is_zero_approx(): plan = {}

func p0_zoom(f: float, _at := Vector2.INF) -> void:
	_pinch.pinch(f)
	_set_zoom(_pinch.value)

func p0_zoom_end() -> void: _pinch.release()

func p0_recenter() -> void:
	_focus = actor.position

## A screen point on a horizontal plane at height y (the deck 0, the water water_y); INF when the ray misses.
func ground_at(screen: Vector2, y: float) -> Vector3:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001: return Vector3.INF
	var t := (y - from.y) / dir.y
	return from + dir * t if t > 0.0 else Vector3.INF

## A tap: on the deck walks there; on the water walks to its edge point and casts toward it. Returns whether it did.
func tap_scene(screen: Vector2, double := false) -> bool:
	if _leaving or busy or is_instance_valid(view): return false
	var deck := ground_at(screen, 0.0)
	if deck.is_finite() and Geometry2D.is_point_in_polygon(Vector2(deck.x, deck.z), walk_polygon):
		plan = {}
		return walk_to(deck)
	var water := ground_at(screen, water_y)
	if water.is_finite():
		var p := cast_plan(water)
		if not p.is_empty():
			plan = p
			if Vector2(actor.position.x, actor.position.z).distance_to(Vector2(p.origin.x, p.origin.z)) <= ARRIVE_M:
				_begin_fishing()
				return true
			if walk_to(p.origin): return true
			plan = {}
	if double: p0_recenter()
	return false

# ---------------------------------------------------------------- fishing
## The bait the chip picked, if the bag still has one (else none).
func selected_bait() -> Variant:
	return bait if bait != "" and int(farm.get("bag", {}).get(bait, 0)) > 0 else null

func _begin_fishing() -> void:
	var p := plan
	plan = {}
	if p.is_empty() or is_instance_valid(view) or farm.is_empty(): return
	actor.stand_still()
	actor.face(p.target)
	actor.lock(true)
	view = FishingPresentation.new()
	view.close_up = false   # LOCK-24 ①: the walking camera, no side close-up
	view.float_scale = FLOAT_SCALE
	view.line_px = LINE_PX
	view.line_color = LINE_INK
	view.catch_pop = CATCH_POP
	view.water_y = water_y + 0.02
	add_child(view)
	panel.landing = p.target
	panel.site_id = "aquatic_park"   # the presentation looks for a FishingWater of this name (the bay has none)
	view.configure(panel, actor, actor.rig, cam, [])
	_bait_key.visible = false
	panel.open_parcel(self, p.target, place_name)

func _end_fishing() -> void:
	if is_instance_valid(view): view.finish()
	view = null
	if actor: actor.lock(false)
	_refresh_bait()

## The parcel save's commands from the pier (the panel's cast, reel and line-in; the first visit's gift).
func send(commands: Array) -> Dictionary:
	if store == null: return {"ok": false, "code": "NETWORK"}
	busy = true
	var result: Dictionary = await store.send(farm_version, commands)
	busy = false
	_adopt(result)
	if not result.get("ok", false) and str(result.get("code", "")) == "VERSION_CONFLICT" and result.has("farm"):
		busy = true
		result = await store.send(farm_version, commands)
		busy = false
		_adopt(result)
	return result

func server_now() -> int: return Time.get_ticks_msec() + server_offset

func _adopt(result: Dictionary) -> void:
	if result.has("server_time"): server_offset = int(result.server_time) - Time.get_ticks_msec()
	if result.get("farm") is Dictionary:
		var next := ParcelFarm.normalize(result.farm)
		if not next.is_empty():
			farm = next
			farm_version = int(result.get("farm_version", farm_version))
	if is_inside_tree(): _refresh_bait()

## The save as it stands (no welcome gift); the first visit sends `visit_pier` for the Starter Rod.
func _read_farm() -> void:
	if store == null: return
	var result: Dictionary = await store.read()
	if not is_inside_tree(): return
	_adopt(result)
	if farm.is_empty():
		toast.show_toast("Could not reach your farm.", ToastLayer.Severity.REFUSED)
		return
	if Fishing.fishing_of(farm.get("fishing")).gifted_at == null:
		var gift: Dictionary = await send([{"type": "visit_pier"}])
		if gift.get("ok", false):
			var rod := str(ParcelFarm.rules().fishing.starter_rod)
			toast.show_toast("Received %s ×1" % ParcelItems.name_of(rod), ToastLayer.Severity.SUCCESS, "", 0.0, ParcelItems.icon_of(rod))

# ---------------------------------------------------------------- bait chip
## The baits the bag holds, in the rules' order.
func baits_in_bag() -> Array:
	var out := []
	for id in ParcelFarm.rules().get("fishing", {}).get("baits", {}):
		if int(farm.get("bag", {}).get(id, 0)) > 0: out.append(id)
	return out

## The chip shows the bait for the next cast and how many are left; a tap picks the next one (none after the last).
func cycle_bait() -> void:
	var have := baits_in_bag()
	if have.is_empty():
		bait = ""
	else:
		var at := have.find(bait)
		bait = have[at + 1] if at + 1 < have.size() else ""
	_refresh_bait()

func _refresh_bait() -> void:
	if _bait_key == null: return
	var have := baits_in_bag()
	if bait != "" and not have.has(bait): bait = ""
	_bait_key.visible = not have.is_empty() and not is_instance_valid(view)
	_bait_key.icon = ParcelItems.icon_of(bait) if bait != "" else P0Logic.icon("hook")
	_bait_key.tooltip_text = ParcelItems.name_of(bait) if bait != "" else "No bait"
	_bait_count.text = "×%d" % int(farm.get("bag", {}).get(bait, 0)) if bait != "" else ""

# ---------------------------------------------------------------- leaving
func leave() -> void:
	if _leaving: return
	if is_instance_valid(view) and panel.visible:
		await panel.close()
	_leaving = true
	var router := get_node_or_null("/root/AppRouter")
	if router != null and router.top_instance() == self: router.pop_instance()

## Android Back: fishing stops first; otherwise back to the map.
func is_back_navigation_locked() -> bool:
	if is_instance_valid(view) and panel.visible:
		panel.close()
		return true
	leave()
	return true

func suspend() -> void:
	_suspended = true
	if panel and panel.visible: panel.interrupt()
	if _hud: _hud.hide()

func resume() -> void:
	_suspended = false
	if _hud: _hud.show()
	cam.make_current()

# ---------------------------------------------------------------- HUD
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "PierHud"
	_hud.layer = 20
	add_child(_hud)
	var root := Control.new()
	root.name = "Root"
	root.theme = UiKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_pad = TouchPad.new()
	_pad.name = "TouchPad"
	_pad.set("pier", self)
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_pad)
	_top = _top_bar()
	root.add_child(_top)
	_bait_key = UiGlassButton.new(P0Logic.icon("hook"))
	_bait_key.name = "Bait"
	_bait_key.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_bait_key.position = Vector2(UiTokens.SIZE_SCREEN_EDGE, -UiTokens.SIZE_SCREEN_EDGE - 120)
	_bait_key.pressed.connect(cycle_bait)
	_bait_key.visible = false
	root.add_child(_bait_key)
	_bait_count = UiKit.label("", UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
	_bait_count.name = "BaitCount"
	_bait_count.position = Vector2(30, 26)
	_bait_key.add_child(_bait_count)
	toast = ToastLayer.new()
	toast.name = "Toasts"
	root.add_child(toast)

## The room's top bar (parcel_outpost.gd): a Ø36 glass back and a glass capsule with the place over the city.
func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.theme = UiKit.theme()
	bar.add_theme_constant_override(&"separation", UiTokens.SPACE_S3)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = UiTokens.SIZE_SCREEN_EDGE - (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	bar.offset_right = -UiTokens.SIZE_SCREEN_EDGE
	bar.offset_top = UiTokens.SIZE_SCREEN_SAFE_INSET + _safe_top()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := UiGlassButton.new(null, UiGlassButton.Glyph.BACK)
	back.name = "Back"
	back.tooltip_text = "Back"
	back.pressed.connect(leave)
	bar.add_child(back)
	var chip := UiGlassCapsule.new()
	chip.name = "Place"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.text = place_name
	chip.detail = CITY
	chip.label().name = "Title"
	chip.label().theme_type_variation = UiTokens.STYLE_TYPE_LABEL_ON_DARK
	chip.label().text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	chip.detail_label().name = "City"
	chip.detail_label().text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	bar.add_child(chip)
	return bar

func _safe_top() -> float:
	if not (OS.has_feature("android") or OS.has_feature("ios")) or not is_inside_tree(): return 0.0
	var view_size := get_viewport().get_visible_rect().size
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(), view_size, 0.0).y

## The scene band as the room's (parcel_outpost.gd TouchPad): a press-and-drag is the floating joystick, a short tap
## walks or casts, a double tap recenters, two fingers pinch; GestureArbiter keeps farm-dev's thresholds.
class TouchPad extends Control:
	var pier: Node
	var arb := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _notification(what: int) -> void:
		if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
			var pinching := arb.is_pinching()
			arb.reset()
			queue_redraw()
			if pier != null:
				pier.p0_joystick(Vector2.ZERO)
				if pinching: pier.p0_zoom_end()
	func _gui_input(e: InputEvent) -> void:
		if pier == null: return
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			pier.p0_zoom(0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
			pier.p0_zoom_end()
			return
		for o in arb.feed(e, Time.get_ticks_msec()):
			match o.kind:
				&"joystick_move":
					pier.p0_joystick(o.vector)
					queue_redraw()
				&"joystick_end":
					pier.p0_joystick(Vector2.ZERO)
					queue_redraw()
				&"tap":
					if pier.tap_scene(get_global_transform() * o.pos, bool(o.double)): arb.consume_tap()
				&"pinch": pier.p0_zoom(o.factor)
				&"pinch_end": pier.p0_zoom_end()
	func _draw() -> void:
		var start := arb.origin()
		var now := arb.position()
		if not arb.is_steering() or now.distance_to(start) < GestureArbiter.TAP_SLOP: return
		var radius := arb.stick_radius
		draw_circle(start, radius, Color(1, 1, 1, 0.35))
		draw_arc(start, radius, 0, TAU, 48, Color(0.37, 0.66, 0.35, 0.7), 2.0)
		var k := start + ((now - start).limit_length(radius))
		draw_circle(k, radius * 0.45, Color(0.98, 0.97, 0.94, 0.95))
		draw_circle(k, radius * 0.3, Color(0.5, 0.78, 0.42))

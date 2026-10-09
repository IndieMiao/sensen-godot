extends Node3D
## A map pond for P0 (ponds live at fixed map locations): the old polished pond world — daylight sky,
## PondScenery, the PR #4 water (FishingWater: caustics, foam, lilies, shore stones, reflection), the
## pond nav grid — and the old fishing presentation (pose, rod, line, float, landing arc; the pond camera frames it)
## driven by P0FishingPanel. Movement, HUD and results follow the new UI flow from P0Runtime.

const FarmCamera = preload("res://modules/farm/farm_camera.gd")

## Pond shapes → P0 fishing sites, kept only for the cast command's old `site` field. The server ignores it and
## takes the template from its own table for the pond the player is at (p0_place, q(36): Reed Pond is a Pond).
const SITE_FOR_TEMPLATE := {"meander": "river"}
const ARRIVE_M := 0.35   # how close (flat) to a cast origin counts as standing on it

var rt: P0Runtime
var entry: Dictionary = {}
var site_spec: Dictionary = {}
var site := "pond"
var bp: FarmBlueprint
var grid: BlueprintGrid
var cam: Camera3D
var environment: Environment
var world_env: WorldEnvironment
var actor: P0Actor
var panel: P0FishingPanel
var view: FishingPresentation
var _focus := Vector3(6, 0, -6)
var _cam_follow := P0Follow.new()
var _zoom := 1.0
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
const PinReason := preload("res://modules/p0/p0_pin_reason.gd")
var _pinch = ElasticZoom.new(0.8, 1.4)   # the farm's range, rubber band past 0.8 / 1.4
var _zoom_at := Vector2.INF            # the last pinch centre (screen)
var _band := Rect2()                   # the last camera band seen with no panel up
var _opening := true                   # the opening shot: framed low in the band until the first step or pinch
var _parked := false                   # after a cast: the camera holds still, the meadow clamp waits (不知火舞)
var _settling := false                 # … then eases back in once the safe box first moves the camera
## The farm's pitch (camera unification, 奕星 2026-10-09); the pond keeps its own yaw 0, looking straight up the pond.
const PITCH_DEG := FarmCamera.PITCH_DEG
const DISTANCE := 40.0
## The opening shot puts the player's feet this far above the band's bottom edge (不知火舞 on 231).
const OPENING_LIFT := 40.0
var _plan: Dictionary = {}
var _hint_req := ""     # the request this pond's ! is for (q(103)): its progress floats and its completion toast
var _hint_have := -1    # that request's count before the next catch

## The catalog pond id: the session sends it with the entry read and every command from here (q(36)).
func p0_place() -> String:
	return str(entry.get("id", ""))

static func site_for(template_id: String) -> String:
	return str(SITE_FOR_TEMPLATE.get(template_id, "pond"))

func setup(args: Dictionary) -> void:
	entry = SystemPonds.location(str(args.get("pond_id", "")))

func _ready() -> void:
	P0Runtime.mark("%s _ready start" % name)
	if entry.is_empty():
		push_error("P0 pond: unknown pond id")
		return
	site_spec = SystemPonds.site(entry)
	site = site_for(str(entry.get("template_id", "")))
	get_viewport().transparent_bg = false
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("d8e9ad")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e4f0ff")
	environment.ambient_light_energy = 0.65
	environment.sky = preload("res://assets/ponds/art/pond_daylight_sky.tres")
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "PondSun"
	sun.rotation_degrees = Vector3(-55, -137, 0)
	sun.light_color = Color("fff3dc")
	sun.light_energy = 1.15
	sun.light_specular = 0.13
	sun.shadow_enabled = true
	sun.shadow_blur = 3.0
	sun.shadow_opacity = 0.82
	sun.light_angular_distance = 1.0
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.05
	cam.far = 80
	add_child(cam)
	cam.make_current()
	add_child(PondScenery.build(entry))
	var water := FishingWater.build(str(entry.id), site_spec)
	water.water_material.set_shader_parameter("sun_direction", sun.global_basis.z.normalized())
	add_child(water)
	bp = SystemPonds.blueprint(entry)
	grid = BlueprintGrid.new(bp)
	actor = P0Actor.new()
	add_child(actor)
	actor.setup(bp, grid, cam)
	_focus = actor.position   # the opening shot frames once the HUD has laid out the band
	panel = P0FishingPanel.new()
	add_child(panel)
	panel.opened.connect(_begin_fishing)
	panel.closed.connect(_end_fishing)
	_update_camera()
	rt = P0Runtime.ensure()
	rt.attach(self)
	rt.ui.set_mode("fish", "Shanghai · " + str(entry.get("name", "Pond")))
	_arrival_hint()

func _exit_tree() -> void:
	_end_fishing()
	if rt: rt.detach(self)

func p0_surface() -> String: return "pond"

# ---------------------------------------------------------------- frame
func p0_joystick(v: Vector2) -> void:
	if actor: actor.set_input(v)
	if v != Vector2.ZERO: _plan = {}

## Old pond taps: water → walk to the nearest bank spot and cast there; grass → walk there.
func p0_tap(screen: Vector2) -> void:
	if panel.visible: return
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.001: return
	var point := origin + dir * (-origin.y / dir.y)
	if FishingModel.contains(str(entry.id), point, 0, site_spec):
		var a := _action_state(rt.session.current())
		if a.get("enabled", false) and str(a.cmd.get("type", "")) == "cast": _go_cast(point)
		elif str(a.cmd.get("type", "")) == "energy_card": rt._on_action(a.cmd)
		else: rt.ui.toast(str(a.get("sub", "")))
	else:
		_plan = {}
		actor.mover.set_target_position(point)

func p0_frame(v: Dictionary, dt: float) -> void:
	if panel.visible:   # the fishing presentation owns the rig; the camera only pans to frame the cast
		_frame_fishing(dt)
		return
	actor.step(dt)
	# Walking to the cast origin finished: open the panel and cast.
	if not _plan.is_empty() and not actor.mover.is_moving():
		var plan := _plan
		_plan = {}
		if _at(plan.origin): _open_panel(plan)
	_follow(dt)
	rt.ui.player_screen = cam.unproject_position(actor.position + Vector3(0, 0.9, 0))   # the radial fans out from here
	rt.ui.set_action(_action_state(v))
	# At the pond: "Your creel is your bag…" (§14.2 minute 5–9); "Casting uses 5 Energy" comes with the first cast (P0Guide).
	if not rt.ui.has_modal(): rt.ui.teach("creel")

## Away from the bank the key still casts: it walks to the nearest bank spot first (the old Go fishing).
func _action_state(v: Dictionary) -> Dictionary:
	var a := P0Logic.fish_action(v, rt.ui.selected_bait, site)
	# On the way to the shore (李白 q(44) ②): pressing again does nothing; not greyed (不知火舞, PR #12), no auto-cast.
	if not _plan.is_empty(): return {"icon": "rod", "verb": "Cast", "sub": "On the way", "enabled": true, "amber": false, "cmd": {}, "need": 0}
	if not a.get("enabled", false) or str(a.cmd.get("type", "")) != "cast": return a
	# Away from the bank the key keeps `Cast · 5 Energy` and walks there first (李白 q(44) ①).
	return a

func p0_action(cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) == "cast": _go_cast(Vector3.INF)

func _go_cast(point: Vector3) -> void:
	var plan := FishingModel.plan(str(entry.id), actor.position, point, grid, site_spec)
	if plan.is_empty():
		rt.ui.toast("Can't reach the water from here")
		return
	if _at(plan.origin):
		_open_panel(plan)
	elif actor.mover.set_target_position(plan.origin):
		_plan = plan
	else:
		rt.ui.toast("Can't reach that spot")

## Standing on a cast origin: measured flat, because the actor's height follows the ground (a raised bank) while a
## planned origin sits at y 0 — in 3D the walk-to-the-bank arrival missed and the first Cast never cast (int5 test 11).
func _at(origin: Vector3) -> bool:
	return Vector2(actor.position.x - origin.x, actor.position.z - origin.z).length() < ARRIVE_M

func p0_energy_verb() -> String: return "Cast"

func _open_panel(plan: Dictionary) -> void:
	actor.face(plan.target)
	panel.open_p0(rt, str(entry.id), site_spec, plan.target, site, "Shanghai · " + str(entry.get("name", "Pond")))

func _begin_fishing(_id: String) -> void:
	actor.lock(true)
	rt.ui.set_surface("busy")
	view = FishingPresentation.new()
	view.close_up = false   # camera unification: no side close-up, the pond camera pans (用户 via 奕星, 不知火舞)
	view.float_scale = FLOAT_SCALE   # the float and the line read at the walking scale (不知火舞)
	view.float_ring = FLOAT_RING
	view.line_px = LINE_PX
	view.line_color = LINE_INK
	view.catch_pop = CATCH_POP   # the landed fish reads at the walking scale in flight (美术总监 / 不知火舞 on 231)
	add_child(view)
	view.configure(panel, actor, actor.rig, cam, [])
	_opening = false

func _end_fishing() -> void:
	if is_instance_valid(view):
		view.finish()
		# The cast's framing stays (不知火舞 on #143): the camera holds until the safe box moves it, and only then does
		# the walking band's clamp come back — eased, as from the far bank it can sit about 2 m off (苏烈 on #143).
		_cam_follow.hold()
		_parked = true
	view = null
	if actor: actor.lock(false)
	if rt and rt.world == self: rt.ui.set_surface("pond")

## Server events for this world: the cast lands, the catch settles, a refusal resets the panel.
func p0_event(ev: Dictionary, _v: Dictionary) -> bool:
	match str(ev.get("kind", "")):
		"cast":
			if panel.visible: panel.on_cast(ev)
		"cast_refused":
			if panel.visible: panel.on_refused()
		"catch":
			if panel.visible:
				_settle(ev, panel.on_catch(ev), rt.last_first_catch_xp)
				return true
		"fish_abort":
			if panel.visible: panel.on_abort()
		"send_failed":
			if panel.visible: panel.on_send_failed(ev.cmd)
	return false

## After the landing arc (or the ripples), close the panel and let the runtime show the result card or float (FISH-3 /
## FISH-5): an escape's at the cast point; a landed fish's reply floats — held by the runtime while the fish flew, so
## `+25 XP` no longer crosses it — rise from over the player's head now that it is in the hand, and a first catch's
## Caught! card comes CARD_AFTER_FLOATS_S after them (不知火舞 on 231 / #154, q(49)).
func _settle(ev: Dictionary, delay: float, first_xp: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree(): return
	var land := panel.landing
	if panel.visible: panel.close()
	var at := cam.unproject_position(land) if not cam.is_position_behind(land) else Vector2.INF
	var floats := rt.take_catch_floats()
	if str(ev.get("result", "")) == "landed":
		at = over_head()
		floats.append_array(_request_progress())
	rt.ui.queue_floats(floats, at)
	rt.last_first_catch_xp = first_xp
	rt._on_catch(ev, rt.last_xp_lines, at, CARD_AFTER_FLOATS_S if not floats.is_empty() else 0.0)

# ---------------------------------------------------------------- the pond's ! (q(103), SGODOT-268)
## A pond wearing the Request ! says why once per visit: an Info toast with the pin card's reason line
## (`Pond Catch · Pond Crucian 0/2`), after the TipCard of the arrival (q(49)). The surface's tip is asked for in the
## frames around the attach, so the hint first waits ARRIVAL_HINT_DELAY_S, then while a tip is up or waits.
const ARRIVAL_HINT_DELAY_S := 0.4
const ARRIVAL_HINT_WAIT_S := 12.0   # TipCards close within 5 s; never hold the hint past this
func _arrival_hint() -> void:
	# Straight into a pond (a dev boot, a cold start back in place) the first view may not have come yet.
	if rt.session.current().is_empty(): await rt.session.state_changed
	if not is_inside_tree(): return
	# The request and its count are taken at once, so a fish landed while the tip is still up counts too.
	var why := PinReason.reason(rt.session.current(), p0_place())
	if str(why.get("state", "")) != "request": return
	_hint_req = str(why.get("request", ""))
	_hint_have = int(PinReason.request_of(rt.session.current(), _hint_req).get("have", -1)) if _hint_req != "" else -1
	await get_tree().create_timer(ARRIVAL_HINT_DELAY_S).timeout
	var waited := 0.0
	while is_inside_tree() and rt.ui.tip_pending() and waited < ARRIVAL_HINT_WAIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not is_inside_tree(): return
	why = PinReason.reason(rt.session.current(), p0_place())   # still worn: a fish landed meanwhile may have completed it
	if str(why.get("state", "")) == "request" and str(why.get("text", "")) != "": rt.ui.toast(str(why.text), 0.0, true)

## What a landed fish did to that request: a progress float under `Pond Crucian ×1` (`Pond Catch 1/2`, ink, no
## icon) while it is short; on the catch that completes it, a Success toast instead (`Pond Catch · 2/2 · Deliver at
## the Stall`), after the catch's Caught! card and level banner. Nothing for a fish it does not take, or past the count.
func _request_progress() -> Array:
	if _hint_req == "": return []
	var r := PinReason.request_of(rt.session.current(), _hint_req)
	var said := request_progress(r, _hint_have)
	_hint_have = int(r.get("have", _hint_have))
	if said.has("float"):
		return [{kind = "request", key = "request:" + _hint_req, text = str(said.float), tone = UiFloatText.Tone.ITEM}]
	if said.has("toast"):
		var done := str(said.toast)
		get_tree().create_timer(CARD_AFTER_FLOATS_S + 0.05).timeout.connect(func(): rt.ui.toast_success_when_clear(done, true))
	return []

## r = PinReason.request_of after a landed fish, before = the request's count before it: {float: `Pond Catch 1/2`}
## while it is still short, {toast: `Pond Catch · 2/2 · Deliver at the Stall`} on the catch that completes it, else {}.
static func request_progress(r: Dictionary, before: int) -> Dictionary:
	var have := int(r.get("have", -1))
	var qty := int(r.get("qty", 0))
	if r.is_empty() or have <= before or before >= qty: return {}
	var title := str(r.get("title", ""))
	if have < qty: return {float = "%s %d/%d" % [title, have, qty]}
	return {toast = "%s · %d/%d · %s" % [title, have, qty, str(r.get("deliver", ""))]}

## Where a landed fish's floats rise (不知火舞 on 231): FLOAT_OVER_HEAD_PX above the top of the player's head on screen
## (the top of the outfit — hair or hat — at the middle of the figure).
const FLOAT_OVER_HEAD_PX := 8.0
## A first catch's Caught! card follows its floats by this much (不知火舞 on #154): only the order matters — the floats
## over the head, the card in the lower half — and waiting for them to play out read as a stall.
const CARD_AFTER_FLOATS_S := 0.5
func over_head() -> Vector2:
	var box := DressingCamera.merged_aabb(actor.rig) if actor.rig != null else AABB()
	var top := Vector3(actor.position.x, box.end.y if box.has_volume() else actor.position.y + HEAD_M, actor.position.z)
	return cam.unproject_position(top) - Vector2(0, FLOAT_OVER_HEAD_PX)

# ---------------------------------------------------------------- camera (old pond framing + safe box)
func _follow(_dt: float) -> void:
	var before := _focus
	_focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), _dt)
	if not _cam_follow.held: _opening = false   # walking: the safe box follows from where the opening left it
	if _parked and not _focus.is_equal_approx(before):   # the safe box moved the camera: the clamp comes back, eased
		_parked = false
		_settling = true
	if _pinch.step(_dt): _set_zoom(_pinch.value)   # springing back from past a limit, about the same point
	else: _update_camera(_dt)

## Camera unification (用户 via 奕星, 2026-10-09, as the mine in #129): the farm's size and pitch, and the screen kept on
## the decorated meadow (不知火舞 on 231) — flush with its sides, and the band between the HUD's second row and the
## quick bar / key on it; along an axis the meadow can't fill the band holds the middle.
## `dt` < 0 (a pinch step): the clamp applies at once.
func _update_camera(dt := -1.0) -> void:
	var view := get_viewport().get_visible_rect().size
	cam.size = view_size(view, _zoom)
	var band := _camera_band(rt.ui if rt != null else null)
	if band.has_area() and not _parked:
		if _opening: _focus = opening_focus(actor.position, cam.size, view, band)
		var target := clamp_focus(_focus, cam.size, view, band, PondScenery.MEADOW)
		if _settling and dt >= 0.0:
			_focus = _focus.lerp(target, 1.0 - exp(-dt * FISH_EASE))
			_settling = _focus.distance_to(target) > 0.005
		else:
			_focus = target
			_settling = false
	place(cam, _focus)

static func view_size(view: Vector2, zoom: float) -> float:
	return FarmCamera.player_scale_size(view, PITCH_DEG) / zoom

## The opening shot (不知火舞 on 231, 2026-10-09): the player centred across, feet OPENING_LIFT above the band's bottom
## edge (the main key / quick bar), so from a bank the water beyond fills the band instead of the grass behind them.
## Inside P0Follow's safe box, so the first steps move the player, not the camera.
static func opening_focus(player: Vector3, size: float, view: Vector2, band: Rect2) -> Vector3:
	var px := view.x / size
	var nearer := (band.end.y - OPENING_LIFT - view.y * 0.5) / px / sin(deg_to_rad(PITCH_DEG))   # ground metres below the centre row
	return Vector3(player.x, player.y, player.z - nearer)

## While fishing (camera unification, 不知火舞 on 231): the walking camera pans so the point midway between the player
## and the float sits in the middle of the fishing band — under the bite notice, above the guide line over the Hook
## key — with FLOAT_ROOM px left on the reel gauge's side of the float and FLOAT_EDGE on the other, then the meadow
## clamps it. Size, pitch and yaw stay as walking; the pan eases at the old close-up's rate.
const FLOAT_ROOM := 100.0
const FLOAT_EDGE := 24.0
const FISH_EASE := 7.0
const PLAYER_HALF_M := 0.3   # the player's box on screen: feet to head (HEAD_M), this far either side
const HEAD_M := 1.8
const FLOAT_SCALE := 1.6
## No ink ring around the float: the user's demo test read it as a black ring (SGODOT-263 ①; it came with #143).
const FLOAT_RING := false
const CATCH_POP := 1.5
const LINE_PX := 1.5
const LINE_INK := Color("#2F3A33B3")   # ink, 70 %
static func fishing_focus(player: Vector3, landing: Vector3, focus_y: float, size: float, view: Vector2, band: Rect2) -> Vector3:
	var px := view.x / size
	var pitch := deg_to_rad(PITCH_DEG)
	var mid := (player + landing) * 0.5
	var c := band.get_center()
	var x := mid.x - (c.x - view.x * 0.5) / px
	var float_x := view.x * 0.5 + (landing.x - x) * px   # screen x with that focus (yaw 0: x maps straight across)
	var body_x := view.x * 0.5 + (player.x - x) * px
	var body := Rect2(body_x - PLAYER_HALF_M * px, 0.0, PLAYER_HALF_M * px * 2.0, 1.0)
	var lo := FLOAT_EDGE
	var hi := view.x - FLOAT_EDGE
	if P0FishingPanel.gauge_side(float_x, body, view.x) > 0: hi = view.x - FLOAT_ROOM
	else: lo = FLOAT_ROOM
	x -= (clampf(float_x, lo, hi) - float_x) / px
	var up := (view.y * 0.5 - c.y) / px   # the band's middle above the screen's, on the camera's up axis
	var z := mid.z + (up - (mid.y - focus_y) * cos(pitch)) / sin(pitch)
	return Vector3(x, focus_y, z)

## The player's box on screen, feet to head, for the reel gauge to keep clear of.
static func player_box(camera: Camera3D, player: Vector3, view: Vector2) -> Rect2:
	var feet := camera.unproject_position(player)
	var head := camera.unproject_position(player + Vector3.UP * HEAD_M)
	var half := PLAYER_HALF_M * view.x / camera.size
	var r := Rect2(feet, Vector2.ZERO).expand(head)
	return Rect2(r.position.x - half, r.position.y, r.size.x + half * 2.0, r.size.y)

## The band under the bite notice at its two-line height (the reel prompt): the notice grows from one line to two at the
## bite, and the cast's framing must not drift with it.
const NOTICE_H := 68.0
func _fishing_band() -> Rect2:
	var top: Control = panel._message_card
	var bottom: Control = panel._guide
	var view := get_viewport().get_visible_rect().size
	if top == null or bottom == null: return Rect2(Vector2.ZERO, view)
	var notice := top.get_global_rect()
	var y0 := notice.position.y + maxf(notice.size.y, NOTICE_H)
	return Rect2(0.0, y0, view.x, bottom.get_global_rect().position.y - y0)

func _frame_fishing(dt: float) -> void:
	var view := get_viewport().get_visible_rect().size
	var band := _fishing_band()
	var target := fishing_focus(actor.position, panel.landing, _focus.y, cam.size, view, band)
	target = clamp_focus(target, cam.size, view, band, PondScenery.MEADOW)
	_focus = _focus.lerp(target, 1.0 - exp(-dt * FISH_EASE))
	place(cam, _focus)
	panel.player_rect = player_box(cam, actor.position, view)

static func place(camera: Camera3D, focus: Vector3) -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = focus + Vector3(0, sin(pitch), cos(pitch)) * DISTANCE
	camera.look_at(focus, Vector3.UP)

## The focus that keeps `band` (screen) inside `art` (x, z on the ground). Yaw 0 and orthographic, so a screen column
## is one world x and a screen row one ground z: the sides stop flush with art's x edges, the band's top row on its
## far edge and its bottom row on its near edge.
static func clamp_focus(focus: Vector3, size: float, view: Vector2, band: Rect2, art: Rect2) -> Vector3:
	var half := size * 0.5
	var px := view.x / size   # px per metre (KEEP_WIDTH)
	var pitch := deg_to_rad(PITCH_DEG)
	var lift := focus.y / tan(pitch)   # the focus sits on a raised bank: the centre row meets the ground beyond it
	var ahead := (view.y * 0.5 - band.position.y) / px / sin(pitch)   # ground metres from the centre row to the band's top …
	var behind := (view.y * 0.5 - band.end.y) / px / sin(pitch)       # … and to its bottom (negative: nearer)
	var x := clamp_or_centre(focus.x, art.position.x + half, art.end.x - half)
	var z := clamp_or_centre(focus.z, art.position.y + lift + ahead, art.end.y + lift + behind)
	return Vector3(x, focus.y, z)

static func clamp_or_centre(v: float, lo: float, hi: float) -> float:
	return (lo + hi) * 0.5 if lo > hi else clampf(v, lo, hi)

## The band from P0Ui, kept from before a panel or the fishing panel opened: either folds the quick bar and the key away,
## which would stretch it and move the pond behind them (苏烈 on #129). Empty until the HUD has laid out: the first frame
## is not clamped, since the whole screen as the band is deeper than the meadow and would centre the opening shot on it.
func _camera_band(ui: P0Ui) -> Rect2:
	var fishing := panel != null and panel.visible
	if ui != null and ui.is_node_ready() and not ui.has_modal() and not fishing: _band = ui.camera_band()
	return _band

## Zoom about the last pinch centre: the ground point under the fingers stays put (ScenePan's focal pinch).
func _set_zoom(value: float) -> void:
	_zoom = value
	if cam == null or not is_inside_tree(): return   # not placed yet: the next frame frames it
	var before = ElasticZoom.ground_at(cam, _zoom_at, _focus.y)
	var dt := get_process_delta_time() if _settling else -1.0   # still easing back after a cast: keep easing
	_update_camera(dt)
	var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, _zoom_at, _focus.y))
	if d != Vector3.ZERO:
		_focus += d
		_update_camera(dt)

func p0_zoom(f: float, at := Vector2.INF) -> void:
	if panel.visible: return   # the cast's framing holds while fishing
	if _parked:   # a pinch after a cast brings the walking band's clamp back, eased like a step (不知火舞 on #143)
		_parked = false
		_settling = true
	_zoom_at = at
	_pinch.pinch(f)
	_cam_follow.hold()   # the pinched framing stays until the player walks
	_opening = false
	_set_zoom(_pinch.value)
func p0_zoom_end() -> void: _pinch.release()
func p0_recenter() -> void:
	_focus = actor.position
	_cam_follow.held = false

func p0_anchor() -> Vector2:
	return cam.unproject_position(actor.position + Vector3(0, 2.0, 0))

func is_back_navigation_locked() -> bool:
	if rt != null and rt.ui.close_top_layer(): return true   # Inbox, radial, a dragged slot over the pond first
	if panel and panel.visible:
		panel.close()
		return true
	return rt != null and rt.root_back()   # the pond as the root scene (dev entry pond:<id>) leaves for the map itself

func suspend() -> void:
	_end_fishing()
	panel.hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	cam.current = false
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	get_viewport().transparent_bg = false
	world_env.environment = environment
	cam.make_current()
	if rt: rt.attach(self)

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"goto":
			actor.teleport(Vector3(float(step[1]), 0, float(step[2])))
			_reopen()
		"shore":
			# stand at the plan origin nearest the spawn, facing the water
			var plan := FishingModel.plan(str(entry.id), actor.position, Vector3.INF, grid, site_spec)
			if not plan.is_empty():
				actor.teleport(plan.origin)
				actor.face(plan.target)
				_reopen()
		"cast": _go_cast(Vector3.INF)
		"castat": _go_cast(Vector3(float(step[1]), 0, float(step[2])))   # castat:x:z — a cast at that water point
		"zoom":   # zoom:0.8 — a pinch to that zoom, fingers lifted (the whole-pond shot)
			p0_zoom(_pinch.value / float(step[1]))
			p0_zoom_end()
		_: return false
	return true

## A teleport frames like the opening shot.
func _reopen() -> void:
	_opening = true
	_parked = false
	_cam_follow.hold()

func p0_until(name: String) -> bool:
	match name:
		"bite": return panel.visible and panel.phase == "hook"
		"reel": return panel.visible and panel.phase == "playing"
		"result": return panel.visible and panel.phase == "result"
		"idle": return not panel.visible
	return false

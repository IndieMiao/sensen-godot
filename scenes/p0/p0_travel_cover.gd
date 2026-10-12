class_name P0TravelCover
extends CanvasLayer
## The cross-city flight's cover (q(147), SGODOT-299; 不知火舞 on 299 31c4ceb5): over the map and the HUD while the camera
## flies, so the map, its pins and the HUD's keys take nothing. The route and its plane (§11.8 / MAP-7, the user on 10-12;
## 不知火舞's v2 on 299) draw on their own layer, over the map's pins and bubbles and under the HUD and the pill: an arc
## from the city left to the city ahead bowing up by a fifth of their distance, re-drawn every frame from where the map
## puts them, primary green dashed (3 px, 8 / 6, round ends), an 8 px dot at each end in a 2 px cream ring; it fades in
## over 0.2 s at 0.5 s and out over the landing's 0.5 s. The plane (i-plane, 279 a4ab1287: a top view, nose right, ink
## in a cream outline, 28 px) flies it 0.5–2.5 s, nose along it. A cream pill 8 px under the HUD's second row names the
## city ahead (14 Bold) over its distance rolling from 0 to the real km (q(132): `1,758 km`); under it `Tap to skip`
## (11, secondary) once the take-off's first 0.5 s are past — a tap anywhere then asks to land (skip_requested), the
## press that sent Fly is not taken for one.

signal skip_requested

const P0Travel := preload("res://modules/p0/p0_travel.gd")

## Above P0Ui's layer (10): the HUD's keys sit under it.
const LAYER := 11

var title: Label
var distance: Label
var hint: Label
var pill: PanelContainer
## Under P0Ui (10), over the map's own HUD (its pins and bubbles).
const ROUTE_LAYER := 5

var route_view: Control
## The two cities where the map draws them (screen px; INF while it cannot) and the flight's seconds.
var from_at := Vector2.INF
var to_at := Vector2.INF
var _t := 0.0
var _plane: Texture2D
var _km := 0
var _skippable := false

func _init() -> void:
	name = "P0TravelCover"
	layer = LAYER
	var shield := Control.new()
	shield.name = "Shield"
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.gui_input.connect(_on_input)
	add_child(shield)
	var under := CanvasLayer.new()
	under.name = "RouteLayer"
	under.layer = ROUTE_LAYER
	add_child(under)
	route_view = Control.new()
	route_view.name = "Route"
	route_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	route_view.draw.connect(_draw_route)
	under.add_child(route_view)
	_plane = GameUi.icon("i-plane")
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 6)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shield.add_child(column)
	pill = PanelContainer.new()
	pill.name = "Pill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.COLOR_SURFACE
	box.set_corner_radius_all(UiTokens.RADIUS_PILL)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = 8
	pill.add_theme_stylebox_override("panel", box)
	column.add_child(pill)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 0)
	pill.add_child(lines)
	title = GameUi.label("", 14, UiTokens.COLOR_TEXT)
	title.name = "City"
	title.add_theme_font_override("font", load(UiTokens.FONT_BOLD_PATH))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(title)
	distance = GameUi.label("", 12, UiTokens.COLOR_SECONDARY)
	distance.name = "Distance"
	distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(distance)
	hint = GameUi.label("Tap to skip", 11, UiTokens.COLOR_SECONDARY)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	column.add_child(hint)

## The city ahead, its distance and where the pill hangs (px from the top: 8 under the HUD's second row).
func open(city: String, km: int, top: float) -> void:
	_km = maxi(0, km)
	title.text = city
	(get_node("Shield/Column") as Control).offset_top = top
	show_progress(0.0)

## t: the flight's seconds so far. The distance rolls up with the plane, 0.5–2.5 s (in place before landing);
## the hint and skipping come in after the take-off's first 0.5 s.
func show_progress(t: float) -> void:
	distance.text = "%s km" % P0Travel.grouped(roundi(_km * P0TravelFlight.plane_progress(t)))   # with the plane (v2)
	_skippable = t >= P0TravelFlight.UP_S
	hint.modulate.a = 1.0 if _skippable else 0.0

## Where the map draws the two cities now (INF: not drawn), at `t` seconds of the flight.
func show_route(from: Vector2, to: Vector2, t: float) -> void:
	from_at = from
	to_at = to
	_t = t
	route_view.queue_redraw()

const ROUTE_COLOR := UiTokens.COLOR_PRIMARY
const CREAM := Color("FBF8EF")
const ROUTE_WIDTH := 3.0
const DASH := 8.0
const GAP := 6.0
const END_DOT := 4.0   # radius: 8 px across, in a 2 px cream ring
const PLANE_SIZE := 28.0

## The arc's control point: a quadratic curve through `a` and `b` whose middle stands a fifth of their distance above
## the straight line between them (screen y runs down: "above" is the normal pointing up).
static func arc_control(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var length := d.length()
	if length < 0.001: return a
	var n := Vector2(d.y, -d.x) / length
	if n.y > 0.0 or (is_zero_approx(n.y) and n.x > 0.0): n = -n
	return (a + b) * 0.5 + n * 0.2 * length * 2.0   # the curve's middle is halfway to its control point

static func arc_at(a: Vector2, c: Vector2, b: Vector2, s: float) -> Vector2:
	return a * (1.0 - s) * (1.0 - s) + c * 2.0 * (1.0 - s) * s + b * s * s

static func arc_tangent(a: Vector2, c: Vector2, b: Vector2, s: float) -> Vector2:
	return (c - a) * 2.0 * (1.0 - s) + (b - c) * 2.0 * s

## The route's and the plane's opacity at `t`: in over 0.2 s from 0.5 s, out over the landing's 0.5 s.
static func route_alpha(t: float) -> float:
	if t < P0TravelFlight.UP_S: return 0.0
	var a := clampf((t - P0TravelFlight.UP_S) / 0.2, 0.0, 1.0)
	var landing := P0TravelFlight.UP_S + P0TravelFlight.FLY_S
	if t > landing: a = minf(a, 1.0 - clampf((t - landing) / P0TravelFlight.DOWN_S, 0.0, 1.0))
	return a

## Where the plane is now (INF when it is not drawn) and its heading, radians.
func plane_pose() -> Array:
	if from_at == Vector2.INF or to_at == Vector2.INF or route_alpha(_t) <= 0.0: return [Vector2.INF, 0.0]
	var c := arc_control(from_at, to_at)
	var s := P0TravelFlight.plane_progress(_t)
	return [arc_at(from_at, c, to_at, s), arc_tangent(from_at, c, to_at, s).angle()]

func _draw_route() -> void:
	var alpha := route_alpha(_t)
	if alpha <= 0.0 or from_at == Vector2.INF or to_at == Vector2.INF: return
	var c := arc_control(from_at, to_at)
	var color := Color(ROUTE_COLOR, alpha)
	# dashes along the curve, 8 on / 6 off, round ends
	var points: Array = []
	for i in 65: points.append(arc_at(from_at, c, to_at, i / 64.0))
	var walked := 0.0
	for i in range(1, points.size()):
		var p0: Vector2 = points[i - 1]
		var p1: Vector2 = points[i]
		var seg := p0.distance_to(p1)
		var at := 0.0
		while at < seg:
			var phase := fmod(walked + at, DASH + GAP)
			var step := minf(seg - at, (DASH - phase) if phase < DASH else (DASH + GAP - phase))
			if phase < DASH:
				var u := p0.lerp(p1, at / seg)
				var v := p0.lerp(p1, (at + step) / seg)
				route_view.draw_line(u, v, color, ROUTE_WIDTH, true)
				route_view.draw_circle(u, ROUTE_WIDTH * 0.5, color)
				route_view.draw_circle(v, ROUTE_WIDTH * 0.5, color)
			at += maxf(step, 0.01)
		walked += seg
	for end in [from_at, to_at]:
		route_view.draw_circle(end, END_DOT + 2.0, Color(CREAM, alpha))
		route_view.draw_circle(end, END_DOT, color)
	var pose := plane_pose()
	if pose[0] == Vector2.INF or _plane == null: return
	# i-plane's nose points right (0°): turned by the route's heading its nose runs along it
	route_view.draw_set_transform(pose[0], float(pose[1]), Vector2.ONE)
	var box := Rect2(Vector2.ONE * -PLANE_SIZE * 0.5, Vector2.ONE * PLANE_SIZE)
	route_view.draw_texture_rect(_plane, box, false, Color(1, 1, 1, alpha))
	route_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func skippable() -> bool:
	return _skippable

func _on_input(e: InputEvent) -> void:
	var released := (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed) \
		or (e is InputEventMouseButton and not (e as InputEventMouseButton).pressed)
	if released and _skippable: skip_requested.emit()

extends Control
## C-188 (the owner on SEN-Q-283: "在地块之间的移动可以按照 187 的方案以头像的形式进行曲线移动"): the player's avatar on the
## dynamic farm map and its trip from where it stands to a 3D space, after SEN-C-187's design v2 (D-437: storyboard
## attachment-1657, motion spec attachment-1658, prototype attachment-1660). Godot overlay only: no Mapbox layer, no
## request, nothing saved; where the avatar stands lives in this run's memory (`at`, home after a cold start).
## PM on C-188#13 (C-187#71): only real trips (home → a place with a 3D space, and back home through Enter my farm); the
## avatar sits at the top right of the existing round pin or of the home's point (offsets in the config); the pins
## (LOCK-24) are not changed.
##   depart(to)     the card leaves (card_exit_ms), the camera frames both ends when one is outside the safe area (fly_to),
##                  the dashed route draws, the avatar pops, hops along the arc, the pin pops with a ripple, then the iris
##                  closes on the pin in the map's occlusion colour and `closed` asks the map to open the scene.
##   skip()         a tap while walking: the avatar reaches the end in skip_ms.
##   cancel()       Back while walking: the avatar goes back to where it left (cancel_ms); `cancelled`.
##   come_back()    back on the map: the iris opens from the pin, the top fades in and the avatar lands.
## UiMotion.reduced (the 减少动效 switch): no route, walk, pops, idle float or framing; the iris becomes a 120 ms fade.
## Every number is in CONFIG (motion spec table 4 and the PM's anchors).
signal closed(place: String)
signal cancelled(place: String)
## The card faded out (card_exit_ms): the map takes it away.
signal card_gone
## Nothing under way any more (back on the map, or the trip called off): the map's keys work again.
signal settled

const CONFIG := "res://assets/map/map_travel.json"
const TownEntry := preload("res://scenes/dynamic_farm/town_entry.gd")
const HOME := "home"
const AVATAR_IMAGE := "res://assets/ui/kit_images/player_portrait.png"
## Where the avatar stands, in this run only (nothing is saved): home after a cold start; with it the home it belongs to.
static var at := HOME
static var home_parcel := ""

enum Phase { IDLE, EXIT, FRAME, WALK, SKIP, ARRIVE, CLOSED, CANCEL, OPEN }

## The config (CONFIG); empty when it could not be read, and then nothing travels (the map's old hard cuts).
var cfg := {}
## geo_screen, size, zoom, fly_to, flying, moving (geo_native_camera.gd).
var camera: Control
## The map's places: key → {"geo": [lon, lat], "pin": the place's node (TownEntry, with pin and set_travel_pose) or null}.
## Home is a point with no pin.
var places := {}
## The avatar shows (a home, the map's own farm entry, the HUD up).
var shown := false
## Held at the arrival, before the iris: the map waits for its farm read (Enter my farm).
var hold := false
## Faded in on the way back (R-02): the map's top bar and hint.
var fade_in: Array[CanvasItem] = []
var phase := Phase.IDLE
var token: Control
var iris: ColorRect
var _ripple: Control
var _from := HOME
var _to := HOME
var _t := 0.0
## The iris's own time in ARRIVE: it waits while `hold` is on, the pin's pop does not.
var _iris_t := 0.0
var _walk_ms := 0.0
var _wk := 0.0
var _wk0 := 0.0
var _still := false
var _card: CanvasItem
var _card_tween: Tween
var _clock := 0.0
var _route_left := false

func _init() -> void:
	name = "Travel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cfg = settings()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The ripple under the pins (the pins draw at z 0, the map's camera draws nothing on a phone).
	_ripple = Control.new(); _ripple.name = "Ripple"; _ripple.z_index = -1
	_ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE; _ripple.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ripple.draw.connect(_draw_ripple); add_child(_ripple)
	token = _make_token(); token.hide(); add_child(token)

## The iris over the whole map, its panels and keys: the map adds it last (make_iris) so it covers them.
func make_iris() -> ColorRect:
	iris = ColorRect.new(); iris.name = "Iris"; iris.hide(); iris.z_index = 3
	iris.mouse_filter = Control.MOUSE_FILTER_STOP; iris.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color;
uniform vec2 center;
uniform vec2 rect;
uniform float radius;
void fragment() {
	float d = distance(UV * rect, center);
	COLOR = vec4(tint.rgb, tint.a * smoothstep(radius - 1.0, radius + 1.0, d));
}"""
	var mat := ShaderMaterial.new(); mat.shader = shader
	if enabled(): mat.set_shader_parameter("tint", Color(str(cfg.iris_color)))
	iris.material = mat
	return iris

static func settings() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG)) if FileAccess.file_exists(CONFIG) else null
	if not parsed is Dictionary:
		push_warning("map_travel: %s could not be read; the map opens its places without the trip" % CONFIG)
		return {}
	return parsed

func enabled() -> bool: return not cfg.is_empty()
## Anything under way (a trip, its cover, the way back).
func busy() -> bool: return phase != Phase.IDLE
## Walking or about to: a tap skips, Back cancels.
func walking() -> bool: return phase in [Phase.EXIT, Phase.FRAME, Phase.WALK, Phase.SKIP]
## On the way to `place`.
func heading(place: String) -> bool: return phase in [Phase.EXIT, Phase.FRAME, Phase.WALK, Phase.SKIP, Phase.ARRIVE, Phase.CLOSED] and _to == place
func destination() -> String: return _to
func origin() -> String: return _from

## Sets off from where the avatar stands to `to`; `card` (the place's card) fades out first. False when it cannot go.
func depart(to: String, card: CanvasItem = null, card_sheet: Control = null) -> bool:
	if not enabled() or busy() or not places.has(to) or not places.has(at): return false
	_from = at; _to = to; _still = _from == _to; hold = false
	_walk_ms = walk_ms(cfg, _km(_from, _to))
	_wk = 0.0
	_card = card
	if card != null:
		_card_tween = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_card_tween.tween_property(card, "modulate:a", 0.0, _ms("card_exit_ms"))
		if card_sheet != null:
			card_sheet.pivot_offset = card_sheet.size * 0.5
			_card_tween.parallel().tween_property(card_sheet, "scale", Vector2.ONE * 0.94, _ms("card_exit_ms"))
	_go(Phase.EXIT)
	return true

## A tap while walking: straight to the end.
func skip() -> void:
	if phase in [Phase.EXIT, Phase.FRAME]:
		_card_done(); _wk = 0.0
		if _still or UiMotion.reduced: _arrive(); return
		_wk0 = 0.0; _go(Phase.SKIP)
	elif phase == Phase.WALK:
		_wk0 = _wk; _go(Phase.SKIP)

## Back while walking (or waiting for the farm at the end): back to where it left. False when it cannot be cancelled.
func cancel(animated := true) -> bool:
	var waiting := phase == Phase.ARRIVE and hold and _iris_t <= 0.0
	if not walking() and not waiting: return false
	_card_done(); _pose_pin(_to, 0.0, 1.0)
	if phase in [Phase.WALK, Phase.SKIP] and animated and not UiMotion.reduced and _wk > 0.0:
		_wk0 = _wk; _go(Phase.CANCEL)
	else:
		_finish_cancel()
	return true

## Back on the map: the iris opens from `iris_place`; the avatar lands at `token_place` (the place it went to, or where it
## left when the place could not open).
func come_back(iris_place: String, token_place: String) -> void:
	if not enabled(): return
	_to = iris_place
	at = token_place
	_card_done()
	for item in fade_in: item.modulate.a = 0.0
	_go(Phase.OPEN)
	_set_iris(0.0, 1.0)

## Drops a trip without a sound (the app went to the background mid-walk, the map is leaving).
func reset() -> void:
	if walking() or phase == Phase.CANCEL: _finish_cancel(); return
	if phase == Phase.OPEN: _end_open()

func _go(next: Phase) -> void:
	phase = next; _t = 0.0; _iris_t = 0.0
	if next == Phase.FRAME: _frame()
	if next == Phase.SKIP: _pose_pin(_to, 0.0, 1.0)

func _process(dt: float) -> void:
	_clock += dt * 1000.0
	if not enabled(): return
	_t += dt * 1000.0
	# A place gone mid-walk (the pin hidden, the home given up): the trip is off.
	if (walking() or phase == Phase.CANCEL) and not (places.has(_from) and places.has(_to)):
		_finish_cancel(); return
	match phase:
		Phase.EXIT:
			if _t >= float(cfg.card_exit_ms):
				_card_done()
				if _still or UiMotion.reduced: _arrive()
				else: _go(Phase.FRAME)
		Phase.FRAME:
			if camera == null or not camera.flying(): _go(Phase.WALK)
		Phase.WALK:
			var walk := _t - float(cfg.token_pop_ms)
			_wk = arc(clampf(walk / _walk_ms, 0.0, 1.0))
			_pose_pin(_to, sin(TAU * maxf(walk, 0.0) / float(cfg.dest_bob_ms)) * float(cfg.dest_bob_px), 1.0)
			if walk >= _walk_ms: _arrive()
		Phase.SKIP:
			_wk = lerpf(_wk0, 1.0, standard(clampf(_t / float(cfg.skip_ms), 0.0, 1.0)))
			if _t >= float(cfg.skip_ms): _arrive()
		Phase.CANCEL:
			_wk = lerpf(_wk0, 0.0, standard(clampf(_t / float(cfg.cancel_ms), 0.0, 1.0)))
			if _t >= float(cfg.cancel_ms): _finish_cancel()
		Phase.ARRIVE:
			_step_arrive(dt * 1000.0)
		Phase.OPEN:
			_step_open()
	_place()

func _arrive() -> void:
	_wk = 1.0
	_go(Phase.ARRIVE)
	if iris != null: iris.show()
	_set_iris(INF, 0.0)

## T-08 / T-09: the pin pops (1 → arrive_scale → 1) with a ripple, iris_delay_ms later the iris closes on it. Reduced
## motion, or setting off where it stands: no pop, the iris (or its fade) at once.
func _step_arrive(dt_ms: float) -> void:
	var quiet := _still or UiMotion.reduced
	var delay := 0.0 if quiet else float(cfg.iris_delay_ms)
	if not hold and _t >= delay: _iris_t += dt_ms
	if not quiet:
		var pop := clampf(_t / float(cfg.arrive_pop_ms), 0.0, 1.0)
		_pose_pin(_to, 0.0, 1.0 + (float(cfg.arrive_scale) - 1.0) * sin(PI * pop))
	var length := float(cfg.reduced_fade_ms) if UiMotion.reduced else float(cfg.iris_close_ms)
	var k := clampf(_iris_t / length, 0.0, 1.0)
	if UiMotion.reduced: _set_iris(0.0, k)
	else: _set_iris(_reach(_iris_center(_to)) * (1.0 - exit_curve(k)), 1.0)
	_ripple.queue_redraw()
	if _iris_t >= length:
		_pose_pin(_to, 0.0, 1.0)
		at = _to
		phase = Phase.CLOSED
		_ripple.queue_redraw()
		closed.emit(_to)

## R-01..R-03: the iris opens (or fades) from the place, the top fades in at the end, then the avatar lands.
func _step_open() -> void:
	var reduced := UiMotion.reduced
	var length := float(cfg.reduced_fade_ms) if reduced else float(cfg.iris_open_ms)
	var k := clampf(_t / length, 0.0, 1.0)
	if reduced: _set_iris(0.0, 1.0 - k)
	else: _set_iris(_reach(_iris_center(_to)) * standard(k), 1.0)
	var top := 1.0 if reduced else clampf((_t - (length - float(cfg.top_fade_ms))) / float(cfg.top_fade_ms), 0.0, 1.0)
	for item in fade_in: item.modulate.a = top
	if _t >= length + (0.0 if reduced else float(cfg.land_pop_ms)): _end_open()

func _end_open() -> void:
	for item in fade_in: item.modulate.a = 1.0
	if iris != null: iris.hide()
	phase = Phase.IDLE
	settled.emit()

func _finish_cancel() -> void:
	_card_done(); _pose_pin(_to, 0.0, 1.0)
	at = _from; _wk = 0.0; hold = false
	if iris != null: iris.hide()
	phase = Phase.IDLE
	queue_redraw(); _ripple.queue_redraw()
	cancelled.emit(_from)
	settled.emit()

func _card_done() -> void:
	if _card_tween != null: _card_tween.kill(); _card_tween = null
	if _card == null: return
	_card = null
	card_gone.emit()

## T-03: when an end is outside the safe area (fit_padding), the camera flies to frame both (fit_zoom), the rest after it.
func _frame() -> void:
	if camera == null or not (places.has(_from) and places.has(_to)): return
	var a := _token_center(_from); var b := _token_center(_to)
	var safe := safe_rect(cfg, camera.size)
	if safe.has_point(a) and safe.has_point(b): return
	var ga: Array = places[_from].geo; var gb: Array = places[_to].geo
	var view := fit_zoom(cfg, camera.size, camera.zoom, a, b)
	camera.fly_to((float(ga[0]) + float(gb[0])) * 0.5, (float(ga[1]) + float(gb[1])) * 0.5, view)

## The avatar, the route and the destination's pin for this frame (they follow the map when it is dragged or zoomed).
func _place() -> void:
	var visible_now := shown and enabled() and phase != Phase.CLOSED and places.has(at if phase in [Phase.IDLE, Phase.OPEN] else _from)
	var center := Vector2.INF
	var scale_now := 1.0
	match phase:
		Phase.IDLE:
			center = _token_center(at)
			if not UiMotion.reduced and camera != null and not camera.moving():
				center.y += sin(TAU * _clock / float(cfg.token_idle_ms)) * float(cfg.token_idle_px)
		Phase.EXIT, Phase.FRAME:
			center = _token_center(_from)
		Phase.WALK, Phase.SKIP, Phase.CANCEL:
			# T-05: up token_lift_px and to token_pop_scale (pop) before it walks; it stays so until it arrives.
			var pop := pop_curve(clampf(_t / float(cfg.token_pop_ms), 0.0, 1.0)) if phase == Phase.WALK else 1.0
			var lift := float(cfg.token_lift_px) * pop
			scale_now = 1.0 + (float(cfg.token_pop_scale) - 1.0) * pop
			var walk := _t - float(cfg.token_pop_ms)
			var hop := absf(sin(PI * float(cfg.hop_hz) * walk / 1000.0)) * float(cfg.hop_px) if phase == Phase.WALK and walk > 0.0 else 0.0
			var tip := _point_on_route(_wk)
			center = tip - Vector2(0, _tip_drop() + lift + hop)
		Phase.ARRIVE, Phase.OPEN:
			center = _token_center(_to if phase == Phase.ARRIVE else at)
			if phase == Phase.OPEN:
				var length := float(cfg.reduced_fade_ms) if UiMotion.reduced else float(cfg.iris_open_ms)
				if not UiMotion.reduced:
					var land := clampf((_t - length) / float(cfg.land_pop_ms), 0.0, 1.0)
					scale_now = lerpf(float(cfg.land_from_scale), 1.0, pop_curve(land))
					visible_now = visible_now and _t >= length
	token.visible = visible_now and center.x != INF and Rect2(Vector2.ZERO, size).grow(64).has_point(center)
	if token.visible:
		var r := float(cfg.token_radius_px)
		token.pivot_offset = Vector2(r, r)
		token.position = center - Vector2(r, r)
		token.scale = Vector2.ONE * scale_now
	if phase in [Phase.WALK, Phase.SKIP, Phase.CANCEL] or _route_left: queue_redraw()

## The dashed route (T-04): drawn from where the avatar left to where it goes, the part already walked taken away.
func _draw() -> void:
	_route_left = false
	if phase != Phase.WALK or UiMotion.reduced or _still: return
	var drawn := standard(clampf(_t / float(cfg.route_draw_ms), 0.0, 1.0))
	if drawn <= _wk: return
	var a := _tip(_from); var b := _tip(_to)
	if a.x == INF or b.x == INF: return
	var points := route_points(a, b, float(cfg.route_bulge), _wk, drawn)
	var dash := float(cfg.route_dash_px); var gap := float(cfg.route_gap_px)
	for pass_ in [[float(cfg.route_under_px), Color(str(cfg.route_under_color))], [float(cfg.route_px), Color(str(cfg.route_color))]]:
		for piece in dashes(points, dash, gap):
			draw_polyline(piece, pass_[1], pass_[0], true)
			draw_circle(piece[0], pass_[0] * 0.5, pass_[1])
			draw_circle(piece[piece.size() - 1], pass_[0] * 0.5, pass_[1])
	_route_left = true

## T-08's ripple round the pin it reached: a white disc from the pin's size to ripple_scale, fading out.
func _draw_ripple() -> void:
	if phase != Phase.ARRIVE or _still or UiMotion.reduced: return
	var k := clampf(_t / float(cfg.ripple_ms), 0.0, 1.0)
	if k >= 1.0: return
	var c := _iris_center(_to)
	if c.x == INF: return
	var r := UiMapDestination.DISC * 0.5 if _pin_of(_to) != null else float(cfg.token_radius_px)
	draw_ripple_disc(_ripple, c, r * lerpf(1.0, float(cfg.ripple_scale), k), float(cfg.ripple_alpha) * (1.0 - k))

static func draw_ripple_disc(item: CanvasItem, center: Vector2, radius: float, alpha: float) -> void:
	item.draw_circle(center, radius, Color(1, 1, 1, alpha), true, -1.0, true)

func _set_iris(radius: float, alpha: float) -> void:
	if iris == null: return
	var mat := iris.material as ShaderMaterial
	var center := _iris_center(_to)
	if center.x == INF: center = size * 0.5
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("rect", iris.size if iris.size != Vector2.ZERO else size)
	mat.set_shader_parameter("radius", maxf(radius, 0.0) if radius != INF else 1e9)
	iris.modulate.a = alpha
	iris.visible = alpha > 0.0 and radius < _reach(center)

## The farthest screen corner from `center`: an iris this wide shows the whole map.
func _reach(center: Vector2) -> float:
	var far := 0.0
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]: far = maxf(far, center.distance_to(corner))
	return far + 2.0

func _pin_of(place: String) -> Node:
	return places.get(place, {}).get("pin") as Node

func _pose_pin(place: String, lift: float, pop: float) -> void:
	var pin := _pin_of(place)
	if pin != null and pin.has_method("set_travel_pose"): pin.set_travel_pose(lift, pop)

## A place's anchor on the screen (the pin's geographic point, the home's centre); INF when not on the ground.
func _anchor(place: String) -> Vector2:
	if camera == null or not places.has(place): return Vector2.INF
	var geo: Array = places[place].geo
	return camera.geo_screen(float(geo[0]), float(geo[1]))

## The avatar's centre at a place: the top right of its round pin (token_offset_pin, grown with the pin) or of the
## home's point (token_offset_home).
func _token_center(place: String) -> Vector2:
	var anchor := _anchor(place)
	if anchor.x == INF: return anchor
	var pin := _pin_of(place)
	if pin == null: return anchor + _vec("token_offset_home")
	var grow: float = pin.pin.focus if "pin" in pin and pin.pin != null else 1.0
	return anchor + _vec("token_offset_pin") * grow

## The avatar's tail tip at a place: the route's ends.
func _tip(place: String) -> Vector2:
	var c := _token_center(place)
	return c if c.x == INF else c + Vector2(0, _tip_drop())

func _tip_drop() -> float: return float(cfg.token_radius_px) + float(cfg.token_tail_px)

## The iris's (and the ripple's) centre: the middle of the round pin, or the home's point.
func _iris_center(place: String) -> Vector2:
	var anchor := _anchor(place)
	if anchor.x == INF or _pin_of(place) == null: return anchor
	return anchor + _vec("iris_center_pin")

func _point_on_route(t: float) -> Vector2:
	var a := _tip(_from); var b := _tip(_to)
	if a.x == INF or b.x == INF: return _tip(_to) if t >= 1.0 else _tip(_from)
	return bezier(a, control_point(a, b, float(cfg.route_bulge)), b, t)

func _km(a: String, b: String) -> float:
	var ga: Array = places[a].geo; var gb: Array = places[b].geo
	return TownEntry.km_between(Vector2(float(ga[1]), float(ga[0])), Vector2(float(gb[1]), float(gb[0])))

func _vec(key: String) -> Vector2:
	var v: Array = cfg[key]
	return Vector2(float(v[0]), float(v[1]))

func _ms(key: String) -> float: return float(cfg[key]) / 1000.0

## The avatar: a white disc with a shadow and a tail pointing down, the player's portrait inside (prototype token()).
func _make_token() -> Control:
	var t := Control.new(); t.name = "Avatar"; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enabled(): return t
	var r := float(cfg.token_radius_px)
	var ring := float(cfg.token_ring_px)
	var tail := float(cfg.token_tail_px)
	t.size = Vector2(r * 2.0, r * 2.0 + tail)
	var disc := Panel.new(); disc.name = "Disc"; disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size = Vector2(r * 2.0, r * 2.0)
	var box := StyleBoxFlat.new(); box.bg_color = UiTokens.COLOR_SURFACE_RAISED; box.set_corner_radius_all(int(r))
	box.anti_aliasing = true; box.shadow_color = Color(str(cfg.token_shadow)); box.shadow_size = int(cfg.token_shadow_px)
	disc.add_theme_stylebox_override(&"panel", box); t.add_child(disc)
	var point := Polygon2D.new(); point.name = "Tail"; point.color = UiTokens.COLOR_SURFACE_RAISED; point.antialiased = true
	point.polygon = PackedVector2Array([Vector2(r - 5.0, r * 2.0 - 2.0), Vector2(r + 5.0, r * 2.0 - 2.0), Vector2(r, r * 2.0 + tail)])
	t.add_child(point)
	var face := Panel.new(); face.name = "Face"; face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	face.position = Vector2(ring, ring); face.size = Vector2(r - ring, r - ring) * 2.0
	var round := StyleBoxFlat.new(); round.bg_color = UiTokens.COLOR_SURFACE; round.set_corner_radius_all(int(r)); round.anti_aliasing = true
	face.add_theme_stylebox_override(&"panel", round); t.add_child(face)
	var picture := TextureRect.new(); picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = load(AVATAR_IMAGE); picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.add_child(picture)
	return t

## T-06's walking time: walk_base_s + walk_per_km_s × km, between walk_min_s and walk_max_s; in ms.
static func walk_ms(c: Dictionary, km: float) -> float:
	return 1000.0 * clampf(float(c.walk_base_s) + float(c.walk_per_km_s) * km, float(c.walk_min_s), float(c.walk_max_s))

## The arc's control point: route_bulge × the distance off the middle, towards the top of the screen.
static func control_point(a: Vector2, b: Vector2, bulge: float) -> Vector2:
	var v := b - a
	var length := v.length()
	if length < 0.001: return a
	var n := Vector2(v.y, -v.x) / length
	if n.y > 0.0: n = -n
	return (a + b) * 0.5 + n * bulge * length

static func bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * c + t * t * b

## The arc's points from t0 to t1 (48 steps over the whole arc, as the prototype).
static func route_points(a: Vector2, b: Vector2, bulge: float, t0: float, t1: float) -> PackedVector2Array:
	var c := control_point(a, b, bulge)
	var out := PackedVector2Array()
	var steps := maxi(2, ceili(48.0 * (t1 - t0)))
	for i in steps + 1: out.append(bezier(a, c, b, lerpf(t0, t1, float(i) / steps)))
	return out

## A polyline cut into dash-long pieces gap apart.
static func dashes(points: PackedVector2Array, dash: float, gap: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var piece := PackedVector2Array()
	var on := true
	var left := dash
	if points.size() > 0: piece.append(points[0])
	for i in range(1, points.size()):
		var p := points[i - 1]; var q := points[i]
		var seg := p.distance_to(q)
		while seg > 0.0001:
			var step := minf(seg, left)
			p = p.move_toward(q, step); seg -= step; left -= step
			if on: piece.append(p)
			if left <= 0.0001:
				if on and piece.size() > 1: out.append(piece)
				on = not on; left = dash if on else gap
				piece = PackedVector2Array([p]) if on else PackedVector2Array()
	if on and piece.size() > 1: out.append(piece)
	return out

## The area both ends must be in (fit_padding off each edge).
static func safe_rect(c: Dictionary, screen: Vector2) -> Rect2:
	var pad: Dictionary = c.fit_padding
	return Rect2(float(pad.left), float(pad.top), screen.x - float(pad.left) - float(pad.right), screen.y - float(pad.top) - float(pad.bottom))

## The zoom that frames screen points a and b (seen at `zoom`) in the safe area, within fit_zoom.
static func fit_zoom(c: Dictionary, screen: Vector2, zoom: float, a: Vector2, b: Vector2) -> float:
	var safe := safe_rect(c, screen)
	var d := (b - a).abs()
	var factor := INF
	if d.x > 1.0: factor = minf(factor, safe.size.x / d.x)
	if d.y > 1.0: factor = minf(factor, safe.size.y / d.y)
	var level := zoom if factor == INF else zoom + log(factor) / log(2.0)
	return clampf(level, float(c.fit_zoom[0]), float(c.fit_zoom[1]))

## The motion spec's curves (UI v3, SEN-C-84 图 14): standard cubic out, exit cubic in, pop back out, arc quad in-out.
static func standard(t: float) -> float: return 1.0 - pow(1.0 - t, 3.0)
static func exit_curve(t: float) -> float: return t * t * t
static func pop_curve(t: float) -> float:
	var c1 := 1.70158; var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
static func arc(t: float) -> float: return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

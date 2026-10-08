extends "res://scenes/map_poc/map_poc.gd"
## The P0 map: the old map scene and city view as they are (Mapbox tiles, 3D landmarks, POI
## declutter, pond pins and their info card, the farm miniature), with only the entry points
## rewired to P0. Shanghai is fixed, the homestead sits at a fixed spot, pond pins come from the
## bundled catalog, and nothing here talks to the old farm server or writes the old app's choices.

const P0_FARM := "res://scenes/p0/p0_farm.tscn"
const P0_POND := "res://scenes/p0/p0_pond.tscn"
const P0_REGION := "shanghai"
## The homestead's map footprint: the Hengshan Road layout, between Pebble Pond and Reed Pond.
const P0_FARM_CHOICE := {"layout_patch_id": "sh_a", "revision": 2}
## The home-set outposts (tackle shop, tea house, travel post, market square) come from the shared
## outpost table; Go opens the outpost room above the map like a pond (SGODOT-227).
const P0_OUTPOST := "res://scenes/p0/p0_outpost.tscn"
const NEAREST_POND := "pond_shanghai_05"   # Reed Pond, the closest to home
## Online counts on the outpost pins (GET /p0/presence), refreshed while the map is on top.
const PRESENCE_S := 15.0
## Show on map lands this close (the outpost / pond pins and the homestead read at this zoom).
const SHOW_ZOOM := 15.5

var rt: P0Runtime
var _presence: HTTPRequest
var _online := {}   # outpost id → players online across its rooms

func _initial_region_id() -> String:
	return P0_REGION

func _ready() -> void:
	rt = P0Runtime.ensure()
	own_farm_name = "Homestead"   # the player's own pin (不知火舞 on 234: My Farm → Homestead)
	super._ready()
	rt.attach(self)
	for child in $HUD/SafeArea/Root.get_children():
		if child.name == "AccountButton" or child is LanguageButton: child.hide()

# ---------------------------------------------------------------- homestead and ponds
func _resolve_farm_choice() -> Dictionary:
	return P0_FARM_CHOICE.duplicate(true)

func _server_has_no_farm() -> bool:
	return false

func _open_my_farm() -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	_clear_farm_selection()
	_reset_gesture()
	P0Runtime.nav_started()
	AppRouter.open_instance(P0_FARM, {})

func _on_city_pond_requested(entry: Dictionary) -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	var pond := SystemPonds.location(str(entry.get("id", "")))
	if pond.is_empty(): return
	_reset_gesture()
	P0Runtime.nav_started()
	AppRouter.open_instance(P0_POND, {"pond_id": pond.id})

## Touch screens have no hover; the farm marker's "Select My Farm" tooltip only shows up under the
## emulator's resting pointer.
func _enter_farm_home(r: Dictionary) -> void:
	super._enter_farm_home(r)
	if farm_markers:
		for c in farm_markers.find_children("*", "Control", true, false): (c as Control).tooltip_text = ""

func _install_city_map() -> void:
	super._install_city_map()
	if city_map:
		# MAP-1 (§10.6.1; 不知火舞 on 234): P0's two-row HUD and Bag take the map's own chrome — no city title, filters,
		# place list or compass, no Map / Farm / Me dock, no + / −; the recenter key stays over Bag. Ponds say Go.
		city_map.host_chrome = true
		city_map.bottom_inset = UiTokens.SIZE_QUICK_BAR_BOTTOM + UiTokens.SIZE_QUICK_BAR_H
		city_map.pond_action = "Go"
	if city_map and not city_map.bundled_ponds:
		city_map.preload_ponds(SystemPonds.data().locations.filter(func(e): return str(e.region_id) == P0_REGION))
		_set_outpost_places()
		city_map.place_requested.connect(_on_place_requested)
		_start_presence()
		# A pond's bank is generated off the main thread while its info card is read, so Enter is quick.
		city_map.entry_selected.connect(func(e: Dictionary): if str(e.get("kind", "")) == "pond": _prewarm_pond(str(e.id)))
		get_tree().create_timer(2.0).timeout.connect(_prewarm_pond.bind(NEAREST_POND))

func _prewarm_pond(id: String) -> void:
	var pond := SystemPonds.location(id)
	if not pond.is_empty(): WaterShore.prewarm(id, SystemPonds.site(pond))

func _set_outpost_places() -> void:
	city_map.set_places(P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))))

func _on_place_requested(entry: Dictionary) -> void:
	var outpost := P0Outposts.find(str(entry.get("id", "")))
	if outpost.is_empty(): return
	city_map.dismiss_overlays()
	_open_outpost(str(outpost.id))

## Go: the outpost room opens above the map (the player walks in at the door); leaving it returns here.
func _open_outpost(id: String) -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	if not ResourceLoader.exists(P0_OUTPOST):
		if str(P0Outposts.find(id).get("role", "")) == "tackle": rt.ui.open_kai_greeting()   # until the room scene lands
		return
	_reset_gesture()
	P0Runtime.nav_started()
	AppRouter.open_instance(P0_OUTPOST, {"outpost_id": id})

# ---------------------------------------------------------------- outpost online counts
func _start_presence() -> void:
	if is_instance_valid(_presence): return
	_presence = HTTPRequest.new()
	_presence.timeout = 8.0
	add_child(_presence)
	_presence.request_completed.connect(_on_presence)
	var timer := Timer.new()
	timer.wait_time = PRESENCE_S
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_poll_presence)
	_poll_presence()

func _poll_presence() -> void:
	if not is_instance_valid(_presence) or not is_visible_in_tree() or rt == null: return
	if _presence.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	var headers := PackedStringArray(["x-p0-player: " + rt.session.player_id])
	if rt.session.access_key != "": headers.append("x-p0-key: " + rt.session.access_key)   # the demo server's key
	_presence.request(rt.session.base_url + "/p0/presence", headers)

func _on_presence(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or city_map == null: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not (data.get("outposts") is Dictionary): return
	var online := {}
	for id in data.outposts: online[str(id)] = int(data.outposts[id].get("online", 0))
	if online == _online: return
	_online = online
	_set_outpost_places()

## The city view's own controls: the recenter key brings the camera back to the player without changing the zoom
## (不知火舞 on 234); outfit and city switching are not in P0 (their buttons are gone with the old chrome).
func _city_action(action: String) -> void:
	match action:
		"recenter": fly_to(home_lat, home_lng)
		"outfit": rt.ui.toast("Outfits come later")
		"city": rt.ui.toast("P0 is set in Shanghai")
		_: super._city_action(action)

## The player's own pin: its card says Go home · Free (MAP-1 §10.6.1); a second tap closes it.
func _own_pin_pressed() -> void:
	if city_map == null or farm_markers == null or not farm_markers.points.has("self"): return
	var open := str(city_map.selected.get("id", "")) == "player:self"
	_clear_farm_selection()
	city_map.dismiss_overlays()
	if open: return
	var at: Vector2 = farm_markers.points.self.center
	city_map.select_player({"id": "player:self", "farm_id": "self", "kind": "player", "name": own_farm_name,
		"lat": at.x, "lng": at.y}, farm_markers.portrait_texture("self"), "Go home · Free")

func _on_city_visit_requested(farm_id: String) -> void:
	if farm_id == "self":
		city_map.dismiss_overlays()
		_open_my_farm()
	else: super._on_city_visit_requested(farm_id)

# ---------------------------------------------------------------- the opening view (MAP-1, 不知火舞 on 234)
## Opening the map frames the home set: the smallest view in z12–16 holding the player's own avatar, each role's
## outpost nearest home and every pin wearing a marker (the first session's Reed Pond), labels and all, inside the
## safe frame — under the HUD's second row + 16, over Bag − 16, 16 from the sides. Not even z12 holds them: z12 on the
## avatar. Recenter keeps the zoom; Show on map and the camera kept on return are unchanged.
const FRAME_ZOOM_MAX := 16.0
const FRAME_ZOOM_MIN := 12.0
const FRAME_PAD := 16.0

func _frame_home() -> void:
	frame_home_set.call_deferred()   # the city view has its size once the frame lays it out

func frame_home_set() -> void:
	if city_map == null or city_map.size.y <= 0.0 or not is_inside_tree(): return
	var items := home_set_items()
	var safe := frame_safe_rect()
	var mid := Vector2.ZERO
	for it in items: mid += Vector2(float(it.lat), float(it.lng))
	mid /= maxf(1.0, items.size())
	var steps := int(round((FRAME_ZOOM_MAX - FRAME_ZOOM_MIN) * 10.0))
	for i in steps + 1:
		_look(mid, FRAME_ZOOM_MAX - i * 0.1)
		for k in 3:   # centre the set in the frame: with the map's pitch its middle is not the screen's
			var box := _frame_box(items)
			var shift := safe.get_center() - box.get_center()
			if shift.length() < 1.0: break
			_pan_by(shift)
		if safe.encloses(_frame_box(items)): return
	_look(Vector2(home_lat, home_lng), FRAME_ZOOM_MIN)

## What the opening view must hold: {lat, lng, rect} — the own avatar, the home set's outposts, the marked pins.
func home_set_items() -> Array:
	var out: Array = [{lat = home_lat, lng = home_lng, self_pin = true}]
	var nearest := {}   # role -> outpost
	for o in P0Outposts.all():
		var e := P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))
		var r := str(o.role)
		if not nearest.has(r) or city_map._home_distance(e) < city_map._home_distance(nearest[r]): nearest[r] = e
	out.append_array(nearest.values())
	var marked := city_pin_markers()
	for e in city_map.entries:
		if marked.has(str(e.get("id", ""))) and not out.any(func(x): return str(x.get("id", "")) == str(e.id)):
			out.append((e as Dictionary).merged({marker = marked[str(e.id)]}, true))
	return out

## The safe frame in screen space: under the HUD's second row + 16, over Bag − 16, 16 from the sides.
func frame_safe_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var top := rt.ui.safe_top() + UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + FRAME_PAD
	var bottom := vp.y - rt.ui.safe_bottom() - UiTokens.SIZE_QUICK_BAR_BOTTOM - UiTokens.SIZE_QUICK_BAR_H - FRAME_PAD
	return Rect2(FRAME_PAD, top, vp.x - FRAME_PAD * 2.0, bottom - top)

func _frame_box(items: Array) -> Rect2:
	var box := Rect2()
	var first := true
	for it in items:
		var p = geo_to_screen(float(it.lat), float(it.lng))
		if p == null: continue
		var fp: Rect2 = FarmMarkers.self_footprint(zoom) if it.get("self_pin", false) else city_map.pin_footprint(it)
		var r := Rect2((p as Vector2) + fp.position, fp.size)
		box = r if first else box.merge(r)
		first = false
	return box

func _look(at: Vector2, z: float) -> void:
	center_lat = at.x
	center_lng = at.y
	_set_zoom(z)
	_update_cameras()

## Moves the view so what is on screen moves by `shift` (screen px).
func _pan_by(shift: Vector2) -> void:
	var c = geo_to_screen(center_lat, center_lng)
	if c == null: return
	var ground = _ground_point((c as Vector2) - shift)
	if not ground is Vector3: return
	var g := MapGeoMath.world_to_geo(ground, anchor_lat, anchor_lng)
	_look(g, zoom)

## The place chip on the map (MAP-1): back to where the player is (P0Runtime.return_to).
func p0_return(route: String) -> void:
	if route.begins_with("pond:"): _on_city_pond_requested({"id": route.trim_prefix("pond:")})
	elif route.begins_with("outpost:"): _open_outpost(route.trim_prefix("outpost:"))
	else: _open_my_farm()

func _switch_city(r: Dictionary) -> void:
	if str(r.get("id", "")) == P0_REGION: super._switch_city(r)

func fly_to_city(id: String) -> void:
	if id == P0_REGION: super.fly_to_city(id)

# ---------------------------------------------------------------- old server / account hooks off
func _on_net_booted(_ok: bool) -> void: pass
func _on_net_booted_guest(_ok: bool) -> void: pass
func _on_account_changed(_signed_in: bool) -> void: pass
## P0 has no nearby list, but the region must count as set up: map_poc's resume rebuilds the region UI when
## _nearby_region differs, which flies the camera back to the homestead (int5 hand test 31: back from an outpost
## the map must stay where it was).
func _refresh_nearby() -> void: _nearby_region = str(region.get("id", ""))
func _refresh_city_counts() -> void: pass
func _open_account() -> void: pass

# ---------------------------------------------------------------- stacking
func resume() -> void:
	super.resume()
	rt.attach(self)
	_poll_presence.call_deferred()   # back from a room: refresh the outpost online counts
	var next := rt.after_leave
	rt.after_leave = ""
	match next:
		"farm": _open_my_farm.call_deferred()      # FISH-4 Go home · Free
		"tackle": show_place.call_deferred("outpost:tackle")   # FISH-5 Tackle Shop: the camera goes to Old Kai's pin
		_:
			# Show on map (SGODOT-225): P0Runtime._leave_then("show:<target>") from Today, NeedSource, the Energy card.
			if next.begins_with("show:"): show_place.call_deferred(next.trim_prefix("show:"))

## Show on map (SGODOT-225; LOCK-08, guidance only, nothing is entered): the camera flies to the target's pin and
## selects it — "outpost:<role>" an outpost, "pond:<id>" a catalog pond, "home" the homestead (fly only: its pin
## would offer Enter). "map" (Browse the map) and unknown targets leave the camera where the player left it.
func show_place(target: String) -> void:
	if city_map == null: return
	var entry := place_for(target)
	if entry.is_empty(): return
	_reset_gesture()
	_city_bounds()   # city-wide pan bounds, else the homestead's 450 m box pulls the camera back
	fly_to(float(entry.lat), float(entry.lng))
	_set_zoom(SHOW_ZOOM)
	_camera_dirty = true
	if target != "home": city_map.select(entry)

## Show from a panel opened on the map (Today, the Energy card, a NeedSource): every target is a pin here; a homestead
## target (plots, stall, stove …) is the homestead's.
func p0_show_spot(where: String) -> void:
	show_place(P0Ui.map_target(where))

## The pin a Show on map target points at ({lat, lng} plus the city-map entry for outposts and ponds), or {}.
func place_for(target: String) -> Dictionary:
	if target == "home": return {"lat": home_lat, "lng": home_lng}
	if target.begins_with("outpost:"):
		var o := P0Outposts.by_role(target.trim_prefix("outpost:"))
		return {} if o.is_empty() else P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))
	if target.begins_with("pond:"): return SystemPonds.location(target.trim_prefix("pond:"))
	return {}

func p0_surface() -> String: return "map"

## Map markers the client knows before the server's map_markers come (蒙恬 on #83, q(48)): while the tutorial Pond
## Catch is on the stall's board and still short of its fish, the beginner pond Today points at wears the Request ! —
## so the first session's map shows it at the city level beside the Tackle Shop, 200 m away (CityMapView packs marker
## pins first). Read off the board like the guide (P0Guide.tutorial), not req_done: that keeps only the last 20.
func city_pin_markers() -> Dictionary:
	var v: Dictionary = rt.session.current() if rt != null and rt.session != null else {}
	var t := P0Guide.tutorial(v)
	if t.is_empty() or int(t.get("have", 0)) >= int(t.get("qty", 1)): return {}   # handed in, or off to the stall
	return {NEAREST_POND: "request"}

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"farm": _open_my_farm()
		"pond": _on_city_pond_requested({"id": step[1]})
		"shop":
			if city_map: city_map.select(P0Outposts.place_entry(P0Outposts.by_role(step[1] if step.size() > 1 else "tackle")))
		"listpick":   # as a tap on the place list: select the outpost and fly the camera to it
			var e := P0Outposts.place_entry(P0Outposts.by_role(step[1] if step.size() > 1 else "post"))
			if city_map:
				city_map.select(e)
				city_map.focus_requested.emit(e)
		"outpost": _open_outpost(step[1])
		"enter":
			if city_map: city_map._on_info_action()
		"zoom":
			_set_zoom(float(step[1]))
			_camera_dirty = true
		"online":   # online:sh_tea_1:3 — the presence count an outpost pin says, for shots
			_online[step[1]] = int(step[2])
			_set_outpost_places()
		"center":   # center:31.228:121.478 (the city overview) — where the camera looks, for shots
			center_lat = float(step[1])
			center_lng = float(step[2])
			_camera_dirty = true
		_: return false
	return true

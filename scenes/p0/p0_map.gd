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
const PondCard := preload("res://modules/p0/p0_pond_card.gd")
## Online counts on the outpost pins (GET /p0/presence), refreshed while the map is on top.
const PRESENCE_S := 15.0
## Show on map lands this close (the outpost / pond pins and the homestead read at this zoom).
const SHOW_ZOOM := 15.5

var rt: P0Runtime
var _presence: HTTPRequest
var _online := {}   # outpost id → players online across its rooms
var _marks_sig := ""

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
		city_map.destination_style = _destination_style
		city_map.host_card = _own_card
		_style_locate(city_map.recenter)
	if city_map and not city_map.bundled_ponds:
		city_map.preload_ponds(SystemPonds.data().locations.filter(func(e): return str(e.region_id) == P0_REGION))
		_set_outpost_places()
		city_map.place_requested.connect(_on_place_requested)
		_start_presence()
		# A pond's bank is generated off the main thread while its card is read, so Go is quick.
		city_map.entry_selected.connect(func(e: Dictionary): if str(e.get("kind", "")) == "pond": _prewarm_pond(str(e.id)))
		city_map.entry_selected.connect(_on_entry_selected)
		city_map.pin_tag = _pin_tag
		get_tree().create_timer(2.0).timeout.connect(_prewarm_pond.bind(NEAREST_POND))

# ---------------------------------------------------------------- pond card (TUT-3-04, q(48))
## Where Distance is measured from: the place the player last was (the place chip), home by default.
func _origin() -> Vector2:
	var here: Dictionary = rt.here if rt else {}
	match str(here.get("space", "home")):
		"outpost":
			var o := P0Outposts.find(str(here.get("place", "")))
			if not o.is_empty(): return Vector2(float(o.lat), float(o.lng))
		"pond":
			var p := SystemPonds.location(str(here.get("place", "")))
			if not p.is_empty(): return Vector2(float(p.lat), float(p.lng))
	return Vector2(home_lat, home_lng)

func _pond_info(entry: Dictionary) -> Dictionary:
	if rt == null: return {}
	var km := P0PlaceSheet.km_between(_origin(), Vector2(float(entry.lat), float(entry.lng)))
	return PondCard.info(rt.session.current(), str(entry.id), km)

## "Reed Pond · Beginner pond · 0.8 km" (q(48)); outposts keep their "· N online" tag.
func _pin_tag(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) != "pond": return ""
	var tag := str(_pond_info(entry).get("tag", ""))
	# The pond the player is at says no distance, as its card shows no Distance there (q(80)).
	if is_here("pond", str(entry.get("id", ""))) and tag.contains(" · "): tag = tag.substr(0, tag.rfind(" · "))
	return tag

func _on_entry_selected(entry: Dictionary) -> void:
	if rt == null: return
	if str(entry.get("kind", "")) == "place":
		var spec := place_card(entry)
		if spec.is_empty(): return
		city_map.info.hide()
		_open_place_card(entry, spec)
		return
	if str(entry.get("kind", "")) != "pond": return
	var info := _pond_info(entry)
	if info.is_empty(): return   # a pond P0 does not know keeps the city view's own card
	city_map.info.hide()
	_open_pond_card(entry, info)

## The pond card (P0PlaceSheet, Figma TUT-3-04 482:193): header (name / Beginner or template), the beginner line,
## Distance and Recommended, Details › (the pond's fish list), Go. At the pond the player is at (q(80)): no Distance,
## and Back to <pond> re-enters it through the loading cover. Tapping outside closes it and clears the selection.
func _open_pond_card(entry: Dictionary, info: Dictionary) -> void:
	var id := str(entry.id)
	var to_fish := [false]
	var spec := P0PlaceSheet.for_here(info, is_here("pond", id))
	P0PlaceSheet.open(rt.ui, spec,
		func():
			rt.ui.close_modal()
			_on_city_pond_requested(entry),
		func():
			to_fish[0] = true
			_open_pond_fish(entry),
		func():
			if not to_fish[0] and city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection(),
		"pond_card")

## Whether the player is at this place now (the place chip's place, P0Runtime.here): q(80)'s Back to <name>.
func is_here(space: String, place: String) -> bool:
	return rt != null and str(rt.here.get("space", "")) == space and str(rt.here.get("place", "")) == place

## Details ›: the pond's fish list (q(48) c): caught fish in colour with their name, the rest as a silhouette with
## the Fishing level they need. ×, Back and a tap outside all go back to the pond card (P0Ui.back_modal, the layered
## way back of 亚瑟 on #37; 哪吒 on #95); from the card they close it.
func _open_pond_fish(entry: Dictionary) -> void:
	var ui := rt.ui
	var info := _pond_info(entry)
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 18, 16, 20 + ui.safe_bottom()))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	panel.add_child(col)
	col.add_child(UiObjectHeader.new({"title": str(info.get("title", "")), "state": "%s fish" % ("Pond" if str(info.get("subtitle", "")) == "Beginner" else str(info.get("subtitle", "")))}))
	for f in PondCard.fish_rows(ui.view, str(entry.id)):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var icon := UiKit.icon(P0Logic.icon(str(f.id)), 32)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not f.caught: icon.modulate = Color(0.13, 0.15, 0.14)   # silhouette
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override(&"separation", 2)
		text.add_child(UiKit.label(str(f.name), UiTokens.STYLE_C14_XB))
		if not f.caught: text.add_child(UiKit.label("Fishing Lv%d" % int(f.level), UiTokens.STYLE_C12_XB, UiTokens.COLOR_SECONDARY))
		row.add_child(text)
		col.add_child(row)
	holder.add_child(panel)
	var back := [false]   # lambdas capture locals by value: share the flag through an array
	var close := UiCloseButton.new()
	close.pressed.connect(func():
		back[0] = true
		_open_pond_card(entry, info))
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	var id := str(entry.id)
	holder.tree_exiting.connect(func():
		if not back[0] and city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection())
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = "pond_fish"
	ui._modal_back = func():   # set after _open_modal, which clears it
		back[0] = true
		_open_pond_card(entry, info)

func _prewarm_pond(id: String) -> void:
	var pond := SystemPonds.location(id)
	if not pond.is_empty(): WaterShore.prewarm(id, SystemPonds.site(pond))

func _set_outpost_places() -> void:
	var places: Array = P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, int(_online.get(str(o.id), 0))))
	if away(): places.append(home_entry())   # away from home the farm wears its Homestead pin (不知火舞 on 234)
	city_map.set_places(places)

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

# ---------------------------------------------------------------- destination pins and place cards (SGODOT-234 A2)
const HOME_PIN := "home"
## The outposts' MapDestination icons by role (不知火舞 on 234): tea pot, tackle rod, market board, post travel.
const PIN_ICONS := {"tea": "pot", "tackle": "rod", "market": "board", "post": "travel"}
## Away from home the avatar stands left of the pin of the place it is at, level with its disc (Figma 1802:118849).
const AVATAR_BESIDE := Vector2(-44, 0)
var _here_sig := ""

## Ponds P0 knows, outposts and the homestead open P0PlaceSheet, not the city view's info panel; landmarks and POIs
## keep that name card.
func _own_card(entry: Dictionary) -> bool:
	match str(entry.get("kind", "")):
		"pond": return not _pond_info(entry).is_empty()
		"place": return not place_card(entry).is_empty()
	return false

## MapDestination 1795:103793 (LOCK-24): outposts by role, ponds, and the homestead's pin with its name on a plate.
## Landmarks and POIs keep the city view's own pins.
func _destination_style(entry: Dictionary) -> Dictionary:
	match str(entry.get("kind", "")):
		"pond": return {"icon": P0Logic.icon("pond")}
		"place":
			if str(entry.get("id", "")) == HOME_PIN: return {"icon": P0Logic.icon("home"), "plate": true}
			var o := P0Outposts.find(str(entry.get("id", "")))
			if not o.is_empty(): return {"icon": P0Logic.icon(str(PIN_ICONS.get(str(o.role), "travel")))}
	return {}

## Whether the player is away from the homestead — at a pond or an outpost (the place chip's place). At home, in the
## farmhouse or the mine, the avatar is the homestead's mark and no Homestead pin is drawn (不知火舞 on 234).
func away() -> bool:
	return rt != null and str(rt.here.get("space", "home")) in ["pond", "outpost"]

func avatar_shift() -> Vector2:
	return AVATAR_BESIDE if away() else Vector2.ZERO

## The homestead's pin, drawn only while the player is away (its avatar stands at the place it is at).
func home_entry() -> Dictionary:
	return {"id": HOME_PIN, "kind": "place", "name": "Homestead", "category": "Your farm", "lat": home_lat,
		"lng": home_lng, "art_path": str(P0Outposts.PIN_ART.tackle), "action": "Go home · Free",
		"action_icon": "footprints", "filter": "pond", "tag": ""}

## The avatar stands where the player is (the place chip, P0Runtime.here) and the farm wears its pin while away.
## Cheap to call every frame: it acts when the place or the homestead's point changes.
func _sync_here() -> void:
	if rt == null or city_map == null: return
	var at := _origin()
	var sig := "%s|%s|%.7f|%.7f" % [rt.here.get("space", ""), rt.here.get("place", ""), home_lat, home_lng]
	if sig == _here_sig: return
	_here_sig = sig
	set_self_at(at.x, at.y)
	if farm_markers:
		farm_markers.self_label_off = away()   # the avatar is not the homestead's mark there
		if away(): farm_markers.anchor_shift["self"] = AVATAR_BESIDE
		else: farm_markers.anchor_shift.erase("self")
	_set_outpost_places()
	_marks_sig = ""   # the homestead's mark moves between the avatar and its pin

## The place card spec (q(80), P0PlaceSheet): an outpost — its name, data category, Distance, Online now (no row at
## 0), Go; the homestead — Homestead, Your farm, Distance, Go home · Free. At the place the player is at: no Distance,
## Back to <name>. {} for a place P0 does not know.
func place_card(entry: Dictionary) -> Dictionary:
	var id := str(entry.get("id", ""))
	var to := Vector2(float(entry.get("lat", 0.0)), float(entry.get("lng", 0.0)))
	var distance := ["Distance", P0PlaceSheet.distance_text(P0PlaceSheet.km_between(_origin(), to))]
	if id == HOME_PIN:
		return P0PlaceSheet.for_here({"title": "Homestead", "subtitle": "Your farm", "facts": [distance],
			"primary": "Go home · Free"}, not away())
	var o := P0Outposts.find(id)
	if o.is_empty(): return {}
	var facts: Array = [distance]
	var online := int(_online.get(id, 0))
	if online > 0: facts.append(["Online now", str(online)])
	return P0PlaceSheet.for_here({"title": str(o.name), "subtitle": str(o.category), "facts": facts, "primary": "Go"},
		is_here("outpost", id))

## Go / Back to: the homestead's opens the farm, an outpost's its room (re-entered through the loading cover when the
## player was there, q(80)). Tapping outside closes the card and clears the selection.
func _open_place_card(entry: Dictionary, spec: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	P0PlaceSheet.open(rt.ui, spec,
		func():
			rt.ui.close_modal()
			if id == HOME_PIN: _open_my_farm()
			else: _open_outpost(id),
		Callable(),
		func():
			if city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection(),
		"place_card")

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
		"recenter":
			var at := _origin()
			fly_to(at.x, at.y)
		"outfit": rt.ui.toast("Outfits come later")
		"city": rt.ui.toast("P0 is set in Shanghai")
		_: super._city_action(action)

## MapLocateButton 1793:103795 (LOCK-24): the recenter key as a 44 round button styled like Close (color/surface,
## 1 px color/border) with a light shadow, the 22 i-locate in its own colours.
func _style_locate(b: Button) -> void:
	b.theme = UiKit.theme()
	b.theme_type_variation = UiTokens.BUTTON_CLOSE_ROUND
	for state in [&"normal", &"hover", &"focus", &"disabled", &"pressed", &"hover_pressed"]:
		b.remove_theme_stylebox_override(state)   # the map's own 32 disc
		var sb := b.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if sb != null:
			sb.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
			sb.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
			sb.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override(StringName("icon_%s_color" % state), Color.WHITE)   # the glyph's own ink and green
	b.icon = P0Logic.icon("locate")
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override(&"icon_max_width", 22)
	b.custom_minimum_size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)

## The player's own avatar: the card of the place the player is at (q(80): Back to <name>) — the homestead's at home,
## the pond's or the outpost's when it stands beside their pin.
func _own_pin_pressed() -> void:
	if city_map == null or rt == null: return
	_clear_farm_selection()
	city_map.dismiss_overlays()
	var place := str(rt.here.get("place", ""))
	match str(rt.here.get("space", "home")):
		"pond":
			var p := SystemPonds.location(place)
			if not p.is_empty():
				city_map.select((p as Dictionary).merged({"kind": "pond"}))
				return
		"outpost":
			var o := P0Outposts.find(place)
			if not o.is_empty():
				city_map.select(P0Outposts.place_entry(o, int(_online.get(place, 0))))
				return
	_open_place_card(home_entry(), place_card(home_entry()))

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
	# A farm booted as the root scene (the first session lands on the farm, q(44)) leaves by swapping the root for a
	# fresh map, so no resume: a Show on map from there points at its pin instead of the opening view (int9 S1).
	if _take_after_leave(): return
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
		if safe.encloses(_frame_box(items)):
			_update_cameras()   # the trials moved only the Godot camera: now the map, pawns and markers follow
			return
	_look(Vector2(home_lat, home_lng), FRAME_ZOOM_MIN)
	_update_cameras()

## What the opening view must hold: {lat, lng, rect} — the own avatar, the home set's outposts, the marked pins.
func home_set_items() -> Array:
	var at := _origin()
	var out: Array = [{lat = at.x, lng = at.y, self_pin = true, shift = avatar_shift()}]
	if away(): out.append(home_entry())
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
		var r := Rect2((p as Vector2) + fp.position + (it.get("shift", Vector2.ZERO) as Vector2), fp.size)
		box = r if first else box.merge(r)
		first = false
	return box

## One trial view: the Godot camera only (刘邦 on #92: a hundred full updates in a frame would push the native map's
## camera and the marker sync each time).
func _look(at: Vector2, z: float) -> void:
	center_lat = at.x
	center_lng = at.y
	_set_zoom(z)
	_place_camera()

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
	_take_after_leave()

## What the world just left asked for (P0Runtime._leave_then), on resume or on a fresh map (_frame_home); true when
## it moves the camera or the player, so the opening view is not framed over it.
func _take_after_leave() -> bool:
	if rt == null: return false
	var next := rt.after_leave
	rt.after_leave = ""
	match next:
		"farm": _open_my_farm.call_deferred()      # FISH-4 Go home · Free
		"tackle": show_place.call_deferred("outpost:tackle")   # FISH-5 Tackle Shop: the camera goes to Old Kai's pin
		_:
			# Show on map (SGODOT-225): P0Runtime._leave_then("show:<target>") from Today, NeedSource, the Energy card.
			# Browse the map (show:map) and unknown targets point nowhere: a fresh map frames its opening view (亚瑟 on #96).
			if not next.begins_with("show:") or place_for(next.trim_prefix("show:")).is_empty(): return false
			show_place.call_deferred(next.trim_prefix("show:"))
	return true

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

## Map marks (plan §9.5.2, q(48)): ✓ deliverable, ! request, ◆ new, in priority order. One list badges the pins
## (CityMapView.set_marks: the first five on screen) and packs them first with whole labels (#83's _marker_of, through
## city_pin_markers), so a badge and its pin never disagree (亚瑟 on 234).
func p0_frame(view: Dictionary, _dt: float) -> void:
	if city_map == null: return
	_sync_here()
	var list := pin_marks(view)
	var home := home_mark(view)
	# Away, the homestead's ✓ hangs on its pin (deliverable, the highest mark, so first); at home on the avatar.
	if away() and home != "": list.push_front({"id": HOME_PIN, "state": home})
	var sig := JSON.stringify(list) + home
	if sig == _marks_sig: return
	_marks_sig = sig
	city_map.set_marks(list)
	if farm_markers: farm_markers.set_mark("self", CityMapView.status_badge(home) if home != "" and not away() else null)

const MARK_STATES := {"deliver": "deliverable", "request": "request", "new": "new"}

## The pins' marks [{id, state}]: the server's view.map_markers whenever it sends them (蒙恬, SGODOT-232 U6), else
## the ones the client knows before then (tutorial_marks).
static func pin_marks(view: Dictionary) -> Array:
	return marks_from(view) if view.has("map_markers") else tutorial_marks(view)

## [{id, state}] from view.map_markers: place ids are the pins' ids (catalog pond ids, outpost ids); "home" is the
## homestead's farm pin, which FarmMarkers draws (home_mark).
static func marks_from(view: Dictionary) -> Array:
	var out: Array = []
	for m in view.get("map_markers", []):
		if not (m is Dictionary): continue
		var state := str(MARK_STATES.get(str(m.get("kind", "")), ""))
		var place := str(m.get("place", ""))
		if state != "" and place != "" and place != "home": out.append({"id": place, "state": state})
	return out

## Map markers the client knows before the server's map_markers come (蒙恬 on #83, q(48)): while the tutorial Pond
## Catch is on the stall's board and still short of its fish, the beginner pond Today points at wears the Request ! —
## so the first session's map shows it at the city level beside the Tackle Shop, 200 m away (CityMapView packs marker
## pins first). Read off the board like the guide (P0Guide.tutorial), not req_done: that keeps only the last 20.
static func tutorial_marks(view: Dictionary) -> Array:
	var t := P0Guide.tutorial(view)
	if t.is_empty() or int(t.get("have", 0)) >= int(t.get("qty", 1)): return []   # handed in, or off to the stall
	return [{"id": NEAREST_POND, "state": "request"}]

## CityMapView asks once per update (#83): the same marks by pin id, the first (highest) mark per pin.
func city_pin_markers() -> Dictionary:
	var v: Dictionary = rt.session.current() if rt != null and rt.session != null else {}
	var out := {}
	var list := pin_marks(v)
	if away() and home_mark(v) != "": list.push_front({"id": HOME_PIN, "state": home_mark(v)})
	for m in list:
		if not out.has(str(m.id)): out[str(m.id)] = str(m.state)
	return out

## The homestead's mark ("deliverable" when a Stall Board request can be handed in; 蒙恬's server only sends
## deliver for home), drawn on the farm pin by FarmMarkers; "" for none.
static func home_mark(view: Dictionary) -> String:
	for m in view.get("map_markers", []):
		if m is Dictionary and str(m.get("place", "")) == "home": return str(MARK_STATES.get(str(m.get("kind", "")), ""))
	return ""

## Today's "Show on map" (SGODOT-232 U6): a short pulse on that place's pin.
func pulse_place(place: String) -> void:
	if city_map: city_map.pulse_pin(place)

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"farm": _open_my_farm()
		"pond": _on_city_pond_requested({"id": step[1]})
		"pondcard", "pondfish":   # the pond card as after tapping the pin; pondfish then opens Details ›
			var e := SystemPonds.location(step[1]).duplicate(true)
			e["kind"] = "pond"
			if city_map: city_map.select(e)
			if step[0] == "pondfish": _open_pond_fish(e)
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
		"pin":   # pin:home / pin:sh_tea_1 — a tap on that pin (its card), the Homestead pin only while away
			var hit: Array = city_map.entries.filter(func(e): return str(e.get("id", "")) == step[1]) if city_map else []
			if not hit.is_empty(): city_map.select(hit[0])
		"tapself": _own_pin_pressed()   # a tap on the player's own avatar: the card of where the player is
		"recenter": _city_action("recenter")   # the MapLocateButton: back to the player, the zoom kept
		"center":   # center:31.228:121.478 (the city overview) — where the camera looks, for shots
			center_lat = float(step[1])
			center_lng = float(step[2])
			_camera_dirty = true
		_: return false
	return true

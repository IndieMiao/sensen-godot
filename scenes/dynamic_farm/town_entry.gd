extends Control
## The dynamic farm map's one place pin (C-115; the owner on C-103#17: "在旧金山放一个固定3D空间入口,形式与交互都参考
## farm-dev"; moved to Washington Square Park on C-115#30: "同意吧空间入口放到新的区域附近", beside C-130's North Beach
## starter area): farm-dev's Travel Post pin, drawn as farm-dev draws an outpost on its city map
## (UiMapDestination with the post's i-travel glyph and the short name, LOCK-24's MapDestination) and carded as farm-dev
## cards it (P0PlaceSheet's place card, rebuilt from the same kit pieces without P0Ui: the header, the Distance fact,
## Go, × above the corner, a tap outside closes). Selected, the pin grows as CityMapView's does. Go asks the map to
## open the room (parcel_outpost.tscn). Without a home the card says so and has no Go: Jasmine and Scott trade through
## the home's parcel save. The map owns the tap: it asks hit() before its own building pick.
## C-232 (0.4.7): the same pin and card for the Aquatic Park pier (`pier()`, P0's coast pond glyph; Go opens
## parcel_pier.tscn). The owner's "no place icons on the map" (C-103#17) stays: each pin is a fixed 3D space's entry, not a
## POI. Each entry keeps its own place in `lat` / `lon`, its glyph and copy; the constants below stay Washington Square's.
signal go_requested
signal card_changed(open: bool)

## Washington Square Park, North Beach, San Francisco (the park's centre; Union / Filbert / Powell / Stockton St).
const LAT := 37.8008
const LON := -122.4103
const ICON := "res://assets/p0/icons/travel.svg"
## Player-visible copy (C-45, finalised on C-115#22 and C-115#34).
const SHORT := "Washington Square"
const TITLE := "Washington Square Travel Post"
const SUBTITLE := "Market · Carpenter"
const NO_HOME := "Claim a home first."
const GO := "Go"
## C-232: the Aquatic Park Municipal Pier's foot (Van Ness Ave and Beach St), north-west of the North Beach starter area.
## Copy as PM finalised it on C-232#28 (C-45): the title only, no subtitle.
const PIER := {"lat": 37.8066, "lon": -122.4242, "icon": "res://assets/p0/icons/pond_coast.svg", "short": "Aquatic Park",
	"title": "Aquatic Park Pier", "subtitle": "", "node": "AquaticPark"}
## The pin's name is shown whole (C-145; C-115#62): "Washington Square" is wider than a map pin's usual 96 px short name.
## Only the width changes, not the copy or its style.
const NAME_MAX_W := 160.0
## CityMapView's selection: the pin grows to FOCUS_SCALE with a back ease, and back.
const FOCUS_SCALE := 1.6
const FOCUS_IN_S := 0.28
const FOCUS_OUT_S := 0.14

## This entry's place and copy (Washington Square's unless made by pier()).
var lat := LAT
var lon := LON
var icon_path := ICON
var short_name := SHORT
var title := TITLE
var subtitle := SUBTITLE
var node_name := "WashingtonSquare"
var camera: Control
## The player's home centre [lon, lat] for the Distance fact ([] without a home; no home, no Go).
var home_center: Array = []
var pin: UiMapDestination
var card: Control
var _focus_tween: Tween
var _safe_bottom := 0.0
## C-188's trip (map_travel.gd): the pin floats up this much while the avatar walks to it (T-07).
var travel_lift := 0.0
var _travel_pop := 1.0

## C-232: the pier's entry (same pin, card and Go; its own place and copy).
static func pier() -> Control:
	var e: Control = load("res://scenes/dynamic_farm/town_entry.gd").new()
	e.lat = float(PIER.lat)
	e.lon = float(PIER.lon)
	e.icon_path = str(PIER.icon)
	e.short_name = str(PIER.short)
	e.title = str(PIER.title)
	e.subtitle = str(PIER.subtitle)
	e.node_name = str(PIER.node)
	return e

func _ready() -> void:
	name = "TownEntry" if node_name == "WashingtonSquare" else "PierEntry"
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin = UiMapDestination.new(load(icon_path) if ResourceLoader.exists(icon_path) else null, short_name)
	pin.name = node_name
	pin.short_max_w = NAME_MAX_W
	add_child(pin)
	pin.visible = false

func _process(_dt: float) -> void:
	place()

## The pin over its spot on the current camera; hidden off screen and past a tilted horizon.
func place() -> void:
	if pin == null: return
	var at := screen_point()
	pin.visible = visible and at != Vector2.INF and Rect2(Vector2.ZERO, size).grow(UiMapDestination.DISC).has_point(at)
	if pin.visible: pin.position = at - pin.anchor_offset() - Vector2(0, travel_lift)

func screen_point() -> Vector2:
	if camera == null or not camera.has_method("geo_screen"): return Vector2.INF
	return camera.geo_screen(lon, lat)

## Whether a screen point (this control's coordinates) is on the pin: its disc and name, grown to the 44 px touch size.
func hit(point: Vector2) -> bool:
	if pin == null or not pin.visible: return false
	var box := pin.footprint()
	box.position += screen_point()
	var gx := maxf(0.0, (UiTokens.SIZE_TOUCH - box.size.x) * 0.5)
	var gy := maxf(0.0, (UiTokens.SIZE_TOUCH - box.size.y) * 0.5)
	return box.grow_individual(gx, gy, gx, gy).has_point(point)

func is_open() -> bool: return is_instance_valid(card)

## The place card (Figma TUT-3-04, P0PlaceSheet.open's layout): title, category, the Distance fact from home, then Go;
## without a home the line says so and there is no Go.
func open_card(safe_bottom := 0.0) -> void:
	if is_open(): return
	_safe_bottom = safe_bottom
	card = Control.new()
	card.name = "PlaceCard"
	card.z_index = 2   # over the pin's name, which draws over the map's pins (UiMapDestination.NAME_Z)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outside := Control.new()   # a tap outside the sheet closes it (and lets the pin go)
	outside.name = "Outside"
	outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outside.mouse_filter = Control.MOUSE_FILTER_STOP
	outside.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed): close_card.call_deferred())
	card.add_child(outside)
	var panel := PanelContainer.new()
	panel.name = "Sheet"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 18, 16, 16 + _safe_bottom))
	card.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	panel.add_child(col)
	col.add_child(UiObjectHeader.new({"title": title, "state": subtitle}))
	if home_center.size() == 2:
		col.add_child(UiFactRow.new("Distance", distance_text(km_between(Vector2(float(home_center[1]), float(home_center[0])), Vector2(lat, lon)))))
		var go := UiCommandButton.new(GO)
		go.name = "Primary"
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.activated.connect(func(): go_requested.emit())
		col.add_child(go)
	else:
		var line := UiKit.label(NO_HOME, UiTokens.STYLE_C14_B, UiTokens.COLOR_SECONDARY)
		line.name = "Line"
		col.add_child(line)
	var close := UiCloseButton.new()   # floats 6 above the sheet's top-right corner
	close.name = "Close"
	close.pressed.connect(close_card)
	card.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	add_child(card)
	_animate_focus(FOCUS_SCALE, FOCUS_IN_S)
	card_changed.emit(true)

func close_card() -> void:
	if not is_open(): return
	card.queue_free()
	card = null
	_animate_focus(1.0, FOCUS_OUT_S)
	card_changed.emit(false)

## C-188: the trip's pose for the pin: `lift` px up (the destination's float) and `pop` × its size (the arrival's pop).
func set_travel_pose(lift: float, pop: float) -> void:
	travel_lift = lift
	if pop != 1.0 or _travel_pop != 1.0:
		_travel_pop = pop
		if _focus_tween: _focus_tween.kill()
		pin.focus = pop
	place()

func _animate_focus(to: float, seconds: float) -> void:
	if _focus_tween: _focus_tween.kill()
	if not is_inside_tree():
		pin.focus = to
		return
	_focus_tween = create_tween()
	if to > 1.0: _focus_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(pin, "focus", to, seconds)

## As P0PlaceSheet.distance_text (q(132)): under 10 km one decimal, never under 0.1 km; from 10 km whole km with commas.
static func distance_text(km: float) -> String:
	var tenths := roundf(maxf(0.1, km) * 10.0) / 10.0
	if tenths < 10.0: return "%.1f km" % maxf(0.1, tenths)
	var whole := str(roundi(km))
	var out := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0: out += ","
		out += whole[i]
	return out + " km"

## Great-circle distance in km between two (lat, lng) points (P0PlaceSheet.km_between).
static func km_between(a: Vector2, b: Vector2) -> float:
	var la1 := deg_to_rad(a.x)
	var la2 := deg_to_rad(b.x)
	var h := sin((la2 - la1) * 0.5) ** 2 + cos(la1) * cos(la2) * sin(deg_to_rad(b.y - a.y) * 0.5) ** 2
	return 2.0 * 6371.0 * asin(minf(1.0, sqrt(h)))

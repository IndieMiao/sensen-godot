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
## Old Kai's shop: a fixed place a short walk from Reed Pond (the winding pond nearest home).
## Entering opens his greeting card for now; the interior room follows once its design is approved.
const TACKLE_SHOP := {"id": "p0_tackle_shop", "kind": "place", "name": "Old Kai's Tackle",
	"category": "Tackle shop · Rods and bait", "lat": 31.2083, "lng": 121.4371,
	"art_path": "res://assets/p0/art/map/tackle_shop.webp", "action": "Enter shop",
	"action_icon": "store", "filter": "pond"}

var rt: P0Runtime

func _initial_region_id() -> String:
	return P0_REGION

func _ready() -> void:
	rt = P0Runtime.ensure()
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
	AppRouter.open_instance(P0_FARM, {})

func _on_city_pond_requested(entry: Dictionary) -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	var pond := SystemPonds.location(str(entry.get("id", "")))
	if pond.is_empty(): return
	_reset_gesture()
	AppRouter.open_instance(P0_POND, {"pond_id": pond.id})

## Touch screens have no hover; the farm marker's "Select My Farm" tooltip only shows up under the
## emulator's resting pointer.
func _enter_farm_home(r: Dictionary) -> void:
	super._enter_farm_home(r)
	if farm_markers:
		for c in farm_markers.find_children("*", "Control", true, false): (c as Control).tooltip_text = ""

func _install_city_map() -> void:
	super._install_city_map()
	if city_map and not city_map.bundled_ponds:
		city_map.preload_ponds(SystemPonds.data().locations.filter(func(e): return str(e.region_id) == P0_REGION))
		city_map.set_places([TACKLE_SHOP])
		city_map.place_requested.connect(_on_place_requested)

func _on_place_requested(entry: Dictionary) -> void:
	if str(entry.get("id", "")) != TACKLE_SHOP.id: return
	city_map.dismiss_overlays()
	rt.ui.open_kai_greeting()

## The city view's bottom bar: Farm opens the homestead; outfit and city switching are not in P0.
func _city_action(action: String) -> void:
	match action:
		"outfit": rt.ui.toast("Outfits come later")
		"city": rt.ui.toast("P0 is set in Shanghai")
		_: super._city_action(action)

func _switch_city(r: Dictionary) -> void:
	if str(r.get("id", "")) == P0_REGION: super._switch_city(r)

func fly_to_city(id: String) -> void:
	if id == P0_REGION: super.fly_to_city(id)

# ---------------------------------------------------------------- old server / account hooks off
func _on_net_booted(_ok: bool) -> void: pass
func _on_net_booted_guest(_ok: bool) -> void: pass
func _on_account_changed(_signed_in: bool) -> void: pass
func _refresh_nearby() -> void: pass
func _refresh_city_counts() -> void: pass
func _open_account() -> void: pass

# ---------------------------------------------------------------- stacking
func resume() -> void:
	super.resume()
	rt.attach(self)

func p0_surface() -> String: return "map"

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"farm": _open_my_farm()
		"pond": _on_city_pond_requested({"id": step[1]})
		"shop":
			if city_map: city_map.select(TACKLE_SHOP)
		"enter":
			if city_map: city_map._on_info_action()
		"zoom":
			_set_zoom(float(step[1]))
			_camera_dirty = true
		_: return false
	return true

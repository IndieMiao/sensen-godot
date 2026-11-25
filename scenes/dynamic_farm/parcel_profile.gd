extends Control
## Profile, Settings and the dressing room in the dynamic farm (C-128, 0.4.4; the owner in C-82#50: the old pages wired
## back in). The main farm's own pages, opened over the map from its `Profile` entry, as P0Ui opens them from the HUD
## avatar: the full-screen profile (P0ProfilePage) — its gear opens Settings (P0SettingsPage), `Edit look ›` the existing
## dressing room, whose Done saves the outfit (Avatar.save_outfit) that the parcel's player and the profile follow.
## Their look stays as it is (the new design is C-108, 0.4.5); only what applies here shows:
## - the profile without its skills, farm card, collections and voice (no such data in the dynamic farm);
## - Settings with Legal alone — Licenses (and Map data's `Share anonymous map usage`, the map SDK's own switch) and
##   the installed package's version; no Test options, Language, Notifications or account rows (sign-in stays on the map).
## English only (C-82#48): the dynamic farm keeps Journey's 中文 table loaded, so the locale is English while these pages
## are open and comes back when they close.
## ‹ and Android Back (back()) close the page on top, the profile last; `closed` then.
signal closed

const DRESS := "res://scenes/dressing_room/dressing_room.tscn"

## The pages open, the profile first; only the top one shows.
var pages: Array[Control] = []
## The map's centre and zoom (lat, lng, zoom), for Map data's `Improve this map`.
var map_view := Vector3.ZERO
var _locale := ""

static func open(parent: Node, map_view_ := Vector3.ZERO) -> Control:
	var profile: Control = load("res://scenes/dynamic_farm/parcel_profile.gd").new()
	profile.map_view = map_view_
	parent.add_child(profile)
	return profile

func _ready() -> void:
	name = "ParcelProfile"
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	open_profile()

func _exit_tree() -> void:
	if not _locale.is_empty(): TranslationServer.set_locale(_locale)
	_locale = ""

func top() -> Control:
	return pages.back() if not pages.is_empty() else null

func _push(page: Control) -> void:
	if not pages.is_empty(): pages.back().hide()
	pages.append(page)
	add_child(page)

## The page on top goes and the one under it shows again; the profile going closes everything.
func back() -> void:
	if pages.is_empty(): return
	_drop(pages.pop_back())
	if pages.is_empty(): close()
	else: pages.back().show()

## Out of the tree at once, not at the frame's end: a page going no longer hears the map waking under it.
func _drop(page: Control) -> void:
	remove_child(page)
	page.queue_free()

func close() -> void:
	if is_queued_for_deletion(): return
	queue_free()
	closed.emit()

## The profile: the signed-in account's name (`You` without one), `Look saved` back from the dressing room's Done.
func open_profile(look_saved := false) -> P0ProfilePage:
	var page := P0ProfilePage.new(profile_view(), _safe_top(), look_saved, {}, [])
	page.back_pressed.connect(back)
	page.settings_pressed.connect(open_settings)
	page.edit_look_pressed.connect(edit_look)
	_push(page)
	return page

func profile_view() -> Dictionary:
	var net := get_node_or_null("/root/Net")
	var name := ""
	if net != null and net.account.signed_in(): name = net.account.display_name
	return {"profile": {"name": name}}

func open_settings() -> P0SettingsPage:
	var page := P0SettingsPage.settings(version_line(), _safe_top(), _safe_bottom(), {}, "", P0SettingsPage.BLOCKED_NONE,
		false, "", "", "", "", "", false)
	page.back_pressed.connect(back)
	page.open_pressed.connect(func(what: String): if what == "licenses": open_licenses())
	_push(page)
	return page

func open_licenses() -> P0SettingsPage:
	var page := P0SettingsPage.licenses(P0Legal.groups(), _safe_top(), _safe_bottom())
	page.back_pressed.connect(back)
	page.open_pressed.connect(func(id: String):
		if str(P0Legal.row(id).get("page", "")) == "map_data": open_map_data()
		else: open_license_text(id))
	_push(page)
	return page

func open_license_text(id: String) -> P0SettingsPage:
	var r := P0Legal.row(id)
	var link: Dictionary = r.get("link", {}) if r.get("link") is Dictionary else {}
	var page := P0SettingsPage.text(str(r.get("title", "")), P0Legal.full_text(r), _safe_top(), _safe_bottom(), link)
	page.back_pressed.connect(back)
	page.open_pressed.connect(func(what: String): if what == "link" and str(link.get("url", "")) != "": ExternalLink.open(str(link.url)))
	_push(page)
	return page

## Map data: the credits and Improve this map in the browser; the switch is the map SDK's telemetry, on at once.
func open_map_data() -> P0SettingsPage:
	var page := P0SettingsPage.map_data(MapUsage.enabled(), _safe_top(), _safe_bottom())
	page.back_pressed.connect(back)
	page.toggled.connect(func(what: String, on: bool): if what == "telemetry": MapUsage.set_enabled(on))
	page.open_pressed.connect(_open_map_data_row)
	_push(page)
	return page

func _open_map_data_row(what: String) -> void:
	match what:
		"mapbox_site": ExternalLink.open(MapUsage.MAPBOX_CREDIT)
		"osm_site": ExternalLink.open(MapUsage.OSM_CREDIT)
		"improve": ExternalLink.open(MapUsage.feedback_url(map_view))

## The existing dressing room over the map, as P0Ui.edit_look: these pages hide while it is on top, and the profile
## comes back when it closes — with `Look saved` after Done, as it was after Back.
func edit_look() -> Node:
	var router := get_node_or_null("/root/AppRouter")
	var avatar := get_node_or_null("/root/Avatar")
	var room: Node = router.push_instance(DRESS) if router != null and avatar != null else null
	if room == null: return null
	hide()
	var saved := [false]
	var on_saved := func(_config): saved[0] = true
	avatar.outfit_saved.connect(on_saved)
	room.tree_exited.connect(func():
		avatar.outfit_saved.disconnect(on_saved)
		if not is_inside_tree() or is_queued_for_deletion(): return
		show()
		while pages.size() > 0:
			_drop(pages.pop_back())
		open_profile(saved[0]), CONNECT_ONE_SHOT)
	return room

## Settings › Version: the installed package's `0.4.4 (2026112501)`, as P0Legal words it; "" (no row) where it cannot
## be read. Android only: the package's own record, through Godot's AndroidRuntime.
static func version_line() -> String:
	if not Engine.has_singleton("AndroidRuntime"): return ""
	var context = Engine.get_singleton("AndroidRuntime").getApplicationContext()
	if context == null: return ""
	var info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0)
	if info == null: return ""
	# versionName is a field, which a JavaObject does not expose, and Field.get is hidden behind Godot's own Object.get:
	# read it through a public getter handle instead (it comes back as a Java String object).
	var field = info.getClass().getField("versionName")
	var getter = JavaClassWrapper.wrap("java.lang.invoke.MethodHandles").publicLookup().unreflectGetter(field) if field != null else null
	var value = getter.invokeWithArguments(JavaClassWrapper.wrap("java.util.Collections").singletonList(info)) if getter != null else null
	var name := str(value.toString()) if value is Object else ""
	var code = info.getLongVersionCode()
	if code == null or name.is_empty() or name.begins_with("<"): return ""
	return P0Legal.version_line({"version": int(code), "name": name})

## System insets (status bar, gesture bar) in UI units; 0 on desktop, as P0Ui's.
func _safe_top() -> float:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).y

func _safe_bottom() -> float:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).w

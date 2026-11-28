extends Control
## Profile, Settings and the dressing room in the dynamic farm. C-128 (0.4.4) wired the main farm's pages back in;
## C-108 (0.4.5) gives the profile and the dressing room the owner-approved v3 design (C-85 pages ① and ②, Q-124).
## Opened over the map from its profile key, or over the parcel from the top bar's HUD avatar (C-H1; ①'s new entry):
## the full-screen profile (ParcelProfilePage) — its gear opens Settings (P0SettingsPage, as before), `Edit look ›` the
## dressing room, whose Done saves the outfit (Avatar.save_outfit) that the parcel's player and the profile follow.
## Only what applies here shows:
## - the profile: the name, and `My farm` with the home's card when there is a home (`home`: its name, status line and
##   what a tap does); no skills, collections or voice (no such data in the dynamic farm; ①-D ⑦);
## - Settings with Legal — Licenses (and Map data's `Share anonymous map usage`, the map SDK's own switch) and the
##   installed package's version; no Test options, Language or Notifications. Signed in, the Danger row `Delete account ›`
##   (no line under it) at the foot (C-243; Google Play asks for deletion in the app): it opens the account panel's delete step (the v3 look,
##   in English; the password for an account that has one), whose `Keep my account` / ✕ go back to Settings and delete
##   nothing. Deleted, the pages close and `account_deleted` comes: the host shows the sign-in panel, as after Sign out.
##   Sign in and Sign out stay on the map's account chip.
## English only (C-82#48): the dynamic farm keeps Journey's 中文 table loaded, so the locale is English while these pages
## are open and comes back when they close.
## ‹ and Android Back (back()) close the page on top, the profile last; `closed` then.
## C-211 (C-185 MS-21): opened with `fade` (over the parcel, from the HUD avatar) the pages fade in over the farm
## (`motion/duration/quick`, 160, standard) and fade out again on close (160, exit; `closed` comes at once, the pages go
## when faded). The same with 减少动效: MS-21 is a fade already.
signal closed
## The account was deleted from Settings › Delete account (C-243); the pages have closed (`closed` came first).
signal account_deleted

const DRESS := "res://scenes/dressing_room/dressing_room.tscn"
## Loaded at run time: the panel uses the Net autoload.
const ACCOUNT_PANEL := "res://scenes/account/account_panel.gd"

## The pages open, the profile first; only the top one shows.
var pages: Array[Control] = []
## The map's centre and zoom (lat, lng, zoom), for Map data's `Improve this map`.
var map_view := Vector3.ZERO
## The player's home for `My farm`: {name, status?, ready?, pressed: Callable}; {} hides the block (no home yet).
var home := {}
## MS-21: fade in when opened, fade out when closed.
var fade := false
var _locale := ""
var _closing := false
## The account panel's delete step over Settings, while it is open.
var _delete_panel: CanvasLayer

static func open(parent: Node, map_view_ := Vector3.ZERO, home_ := {}, fade_ := false) -> Control:
	var profile: Control = load("res://scenes/dynamic_farm/parcel_profile.gd").new()
	profile.map_view = map_view_
	profile.home = home_
	profile.fade = fade_
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
	if fade:
		modulate.a = 0.0
		UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD).tween_property(self, "modulate:a", 1.0,
			UiMotion.secs(UiTokens.MOTION_DURATION_QUICK_MS))

func _exit_tree() -> void:
	if not _locale.is_empty(): TranslationServer.set_locale(_locale)
	_locale = ""

func top() -> Control:
	return pages.back() if not pages.is_empty() else null

func _push(page: Control) -> void:
	if not pages.is_empty(): pages.back().hide()
	pages.append(page)
	add_child(page)

## The page on top goes and the one under it shows again; the profile going closes everything. The delete step over
## Settings goes first (as its ✕: nothing is deleted), unless a delete is in flight.
func back() -> void:
	if is_instance_valid(_delete_panel):
		_delete_panel.dismiss()
		return
	if pages.is_empty(): return
	_drop(pages.pop_back())
	if pages.is_empty(): close()
	else: pages.back().show()

## Out of the tree at once, not at the frame's end: a page going no longer hears the map waking under it.
func _drop(page: Control) -> void:
	remove_child(page)
	page.queue_free()

func close() -> void:
	if is_queued_for_deletion() or _closing: return
	_closing = true
	if not fade or not is_inside_tree():
		queue_free()
		closed.emit()
		return
	# MS-21: whatever is under it takes touches again at once; the pages fade away on top.
	propagate_call(&"set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
	closed.emit()
	var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_EXIT)
	tw.tween_property(self, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_QUICK_MS))
	tw.tween_callback(queue_free)

## Closed (or closing): `closed` has come, the pages may still be fading out.
func is_closing() -> bool: return _closing or is_queued_for_deletion()

## The profile: the signed-in account's name (`You` without one), the home's card, `Look saved` back from the dressing
## room's Done. The farm card goes home: the caller's `pressed` once these pages have closed.
func open_profile(look_saved := false) -> ParcelProfilePage:
	var page := ParcelProfilePage.new(profile_view(), _safe_top())
	page.back_pressed.connect(back)
	page.settings_pressed.connect(open_settings)
	page.edit_look_pressed.connect(edit_look)
	page.farm_pressed.connect(_go_home)
	_push(page)
	if look_saved: page.show_look_saved()
	_time_figure(page)
	return page

func _go_home() -> void:
	var go: Callable = home.get("pressed", Callable())
	close()
	if go.is_valid(): go.call()

## How long the figure took to show after the profile opened, for the QA log (C-133): `PARCEL_PROFILE_FIGURE {"ms":…}`.
func _time_figure(page: ParcelProfilePage) -> void:
	var rig: AvatarRig = page.preview.rig if page.preview != null else null
	if rig == null: return
	var start := Time.get_ticks_msec()
	var report := func(_config = null): print("PARCEL_PROFILE_FIGURE ", JSON.stringify({"ms": Time.get_ticks_msec() - start}))
	if rig.is_busy(): rig.config_applied.connect(report, CONNECT_ONE_SHOT)
	else: report.call()

func profile_view() -> Dictionary:
	var net := get_node_or_null("/root/Net")
	var name := ""
	if net != null and net.account.signed_in(): name = net.account.display_name
	var shown := {"profile": {"name": name}}
	if not home.is_empty():
		shown["home"] = {"name": str(home.get("name", "")), "status": str(home.get("status", "")), "ready": bool(home.get("ready", false))}
	return shown

func open_settings() -> P0SettingsPage:
	var page := P0SettingsPage.settings(version_line(), _safe_top(), _safe_bottom(), {}, "", P0SettingsPage.BLOCKED_NONE,
		false, "", "", "", "", "", false)
	if signed_in(): page.add_delete_account(null, "") # `Delete account ›` alone, no line under it (C-243#9)
	page.back_pressed.connect(back)
	page.open_pressed.connect(func(what: String):
		if what == "licenses": open_licenses()
		elif what == "delete_account": open_delete_account())
	_push(page)
	return page

func signed_in() -> bool:
	var net := get_node_or_null("/root/Net")
	return net != null and net.account.signed_in()

## Settings › Delete account (C-243): the account panel's delete step over the pages. Deleted (signed out when it
## closes), the pages close and `account_deleted` comes; kept, Settings stays as it was.
func open_delete_account() -> CanvasLayer:
	if is_instance_valid(_delete_panel) or not signed_in(): return null
	_delete_panel = load(ACCOUNT_PANEL).open(self, "delete", "", true, true) # the v3 look (C-85 ④), in English (C-144)
	_delete_panel.guest_login = false # the dynamic farm has no guest (C-146)
	var panel := _delete_panel
	panel.closed.connect(func(still_signed_in: bool):
		if _delete_panel == panel: _delete_panel = null
		if still_signed_in or is_closing(): return
		close()
		account_deleted.emit(), CONNECT_ONE_SHOT)
	return panel

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

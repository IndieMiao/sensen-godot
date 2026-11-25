extends SceneTree
## C-128: the map's Profile entry opens the main farm's profile, Settings and dressing room over the real map scene
## (no native map: the map stops after building its panels), with the real AppRouter and Avatar. Headless; the outfit is
## saved under a test user directory and the telemetry choice is put back as it was.
## Loaded at run time: these use autoloads (Avatar, Localization), which a preload here would compile before.
var ProfilePage: GDScript
var SettingsPage: GDScript
var MapUsage: GDScript
var Kind := {}
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func():
		print("FAIL timed out")
		print("PARCEL PROFILE ", checks - failures, "/", checks + 1)
		quit(1))
	_run.call_deferred()

func verify(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func row(page: Node, row_name: String) -> Node:
	return page.find_child(row_name, true, false)

func idle(rig: Node) -> void:
	for i in 900:
		if not rig.is_busy(): return
		await process_frame

func _run() -> void:
	ProfilePage = load("res://scenes/p0/panels/p0_profile_page.gd")
	SettingsPage = load("res://scenes/p0/panels/p0_settings_page.gd")
	MapUsage = load("res://scenes/map_poc/map_usage.gd")
	Kind = SettingsPage.get_script_constant_map()["Kind"]
	var router: Node = root.get_node("AppRouter")
	var avatar: Node = root.get_node("Avatar")
	var saved_store: String = avatar.store.base_dir
	var saved_user: String = avatar.user_id
	avatar.store.base_dir = "user://test_parcel_profile"
	avatar.user_id = "c128"
	var telemetry: bool = MapUsage.saved()
	var telemetry_file := FileAccess.file_exists(str(MapUsage.PREFS))
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var map: Control = load("res://scenes/dynamic_farm/dynamic_farm_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	# C-133: the map has no player of its own; the saved outfit's parts start loading as it opens.
	var outfit: Array[String] = []
	for id in avatar.load_outfit().slots.values():
		if not str(id).is_empty(): outfit.append(str(id))
	verify(not outfit.is_empty() and outfit.all(func(id): return avatar.loader.loading(id) or avatar.cache.get_part(id) != null),
		"the map starts loading the saved outfit as it opens")
	await process_frame
	var entry: Button = map.find_child("MapProfile", true, false)
	var locate: Button = map.find_child("MapLocate", true, false)
	verify(entry != null and entry.is_visible_in_tree() and not entry.disabled, "the map has a profile key")
	verify(entry.theme_type_variation == locate.theme_type_variation and entry.size == locate.size, "the same round key as locate")
	verify(is_equal_approx(entry.position.y, locate.position.y) and entry.position.x < locate.position.x, "at the left, level with locate")
	# A tap while the outfit still loads (a cold start's first seconds): the key holds, the profile opens with its figure.
	avatar.cache.clear()
	verify(not avatar.warm_saved_outfit().is_empty() and avatar.warming(), "cold again: the outfit is loading")
	entry.pressed.emit()
	verify(map._profile == null and entry.disabled, "a tap while it loads holds the key; no profile without its figure yet")
	entry.pressed.emit()
	for i in 900:
		if map._profile != null: break
		await process_frame
	verify(not avatar.warming() and outfit.all(func(id): return avatar.cache.get_part(id) != null), "once it has loaded")
	var host: Control = map._profile
	verify(host != null and host.get_parent() == map and host.pages.size() == 1, "Profile opens the profile over the map, once")
	var figure: Node = host.top().preview.rig
	await process_frame
	verify(figure != null and figure.visible and not figure.is_busy(), "the figure shows on the profile's first frame")
	verify(not map._hud.visible, "the map's panels hide under the profile")
	verify(TranslationServer.get_locale() == "en", "the pages show in English while open")
	var profile: Control = host.top()
	verify(profile.get_script() == ProfilePage and profile.is_visible_in_tree(), "the main farm's full-screen profile")
	verify(profile.name_row.name_label.text == "You", "no account: the name reads You")
	verify(profile.find_children("*", "UiSkillCard", true, false).is_empty(), "no skill cards (no skills here)")
	verify(profile.find_children("*", "UiFarmCard", true, false).is_empty(), "no farm card")
	verify(profile.find_children("*", "UiNeedTile", true, false).is_empty(), "no collections")
	verify(profile.preview != null, "the outfit preview and Edit look stay")
	var p0_profile: Control = ProfilePage.new()
	verify(p0_profile.blocks == ProfilePage.BLOCKS, "P0's profile keeps all its blocks by default")
	p0_profile.free()
	profile.top_bar.settings_pressed.emit()
	await process_frame
	var settings: Control = host.top()
	verify(settings.get_script() == SettingsPage and settings.kind == Kind.SETTINGS and not profile.visible, "the gear opens Settings")
	verify(row(settings, "Licenses") != null, "Settings lists Licenses")
	for gone in ["TestOptions", "Language", "Notifications", "SignedInWith", "SignOut", "DeleteAccount", "HomeCity", "Version"]:
		verify(row(settings, gone) == null, "no %s row in the dynamic farm's Settings" % gone)
	var p0_settings: Control = SettingsPage.settings("0.2.1 (1)")
	verify(row(p0_settings, "TestOptions") != null and row(p0_settings, "Version") != null, "P0's Settings keeps Test options and Version")
	p0_settings.free()
	settings.open_pressed.emit("licenses")
	await process_frame
	var licenses: Control = host.top()
	verify(licenses.kind == Kind.LICENSES and row(licenses, "mapbox_data") != null, "Licenses lists the credits")
	licenses.open_pressed.emit("mapbox_data")
	await process_frame
	var map_data: Control = host.top()
	verify(map_data.kind == Kind.MAP_DATA, "Mapbox opens Map data")
	map_data.toggled.emit("telemetry", not telemetry)
	verify(MapUsage.saved() == not telemetry, "Share anonymous map usage takes effect at once")
	map_data.toggled.emit("telemetry", telemetry)
	verify(MapUsage.saved() == telemetry, "and back")
	host.back(); await process_frame
	licenses.open_pressed.emit("osm")
	await process_frame
	verify(host.top().kind == Kind.TEXT and host.top().header != null, "a credit opens its text")
	verify(map.is_back_navigation_locked(), "Android Back is the profile's while it is open")
	await process_frame
	verify(host.top() == licenses and licenses.visible, "Back closes the page on top only")
	map.is_back_navigation_locked(); await process_frame
	verify(host.top() == settings and settings.visible, "Back again: Settings")
	settings.back_pressed.emit(); await process_frame
	verify(host.top() == profile and profile.visible, "‹ goes back to the profile")
	# The dressing room over the map: Done saves the outfit, the profile comes back with Look saved.
	var room: Node = host.edit_look()
	verify(room != null and router.top_instance() == room, "Edit look opens the existing dressing room")
	verify(not host.visible and map._suspended, "the profile hides and the map is suspended under it")
	await idle(room.rig)
	var before: String = room.rig.current_config().slots[&"cloth"]
	var target := ""
	for meta in avatar.catalog.parts_for_slot(&"cloth"):
		if meta.id != before: target = meta.id; break
	room.rig.equip(&"cloth", target)
	await idle(room.rig)
	room._on_done()
	for i in 120:
		if router.top_instance() == null: break
		await process_frame
	await process_frame
	verify(router.top_instance() == null and host.visible and not map._suspended, "Done goes back to the map's profile")
	verify(str(avatar.load_outfit().slots[&"cloth"]) == target, "the outfit is saved (it stays after a restart)")
	var again: Control = host.top()
	verify(again != profile and host.pages.size() == 1, "the profile opens again")
	verify(again.find_children("*", "Label", true, false).any(func(l): return l.text == "Look saved"), "with Look saved")
	verify(not map._hud.visible, "the map's panels stay hidden while the profile is up")
	room = host.edit_look()
	await idle(room.rig)
	room._on_back()
	for i in 120:
		if router.top_instance() == null: break
		await process_frame
	await process_frame
	verify(host.top().find_children("*", "Label", true, false).all(func(l): return l.text != "Look saved"), "Back from the room: no Look saved")
	again = host.top()
	again.back_pressed.emit(); await process_frame
	verify(map._profile == null and not is_instance_valid(host), "‹ on the profile closes it")
	verify(map._hud.visible and not entry.disabled, "the map's panels come back")
	verify(TranslationServer.get_locale() == "zh_CN", "the locale is put back")
	map.queue_free(); await process_frame
	current_scene = null
	MapUsage.set_enabled(telemetry)
	if not telemetry_file: DirAccess.remove_absolute(str(MapUsage.PREFS))
	for file in DirAccess.get_files_at("user://test_parcel_profile"): DirAccess.remove_absolute("user://test_parcel_profile/" + file)
	DirAccess.remove_absolute("user://test_parcel_profile")
	avatar.store.base_dir = saved_store
	avatar.user_id = saved_user
	TranslationServer.set_locale(locale)
	print("PARCEL PROFILE ", checks - failures, "/", checks)
	quit(1 if failures else 0)

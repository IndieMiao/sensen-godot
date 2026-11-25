extends SceneTree
## C-128: the map's Profile entry opens the profile, Settings and dressing room over the real map scene; C-108: the
## profile and the dressing room in the v3 design (C-85 pages ① and ②). Over the real map scene
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
	ProfilePage = load("res://scenes/dynamic_farm/parcel_profile_page.gd")
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
	verify(profile.get_script() == ProfilePage and profile.is_visible_in_tree(), "the v3 full-screen profile (C-108)")
	verify(profile.name_label.text == "You", "no account: the name reads You")
	verify(profile.find_children("*", "UiSkillCard", true, false).is_empty(), "no skill cards (no skills here)")
	verify(profile.farm_card == null and profile.find_child("SectionMyfarm", true, false) == null, "no home yet: no My farm")
	verify(profile.find_children("*", "UiNeedTile", true, false).is_empty(), "no collections")
	verify(profile.preview != null and profile.edit_look_button != null, "the outfit preview and Edit look stay")
	# ①-A/D: glass ‹, the Profile tag, a glass gear; the hero 330 high, the paper from 300; Edit look a 32 white pill.
	var bar: HBoxContainer = profile.top_bar
	verify(bar.get_child(0) is UiGlassButton and bar.get_child(1) is UiTagPill and (bar.get_child(1) as UiTagPill).text == "Profile"
		and bar.get_child(bar.get_child_count() - 1) is UiGlassButton, "top bar: glass back, Profile tag, glass gear")
	verify(is_equal_approx(bar.offset_top, 8.0) and bar.get_child(0).get_global_rect().size == Vector2(44, 44), "the bar 8 down, 44 hit areas")
	var hero: Control = profile.find_child("Hero", true, false)
	verify(hero != null and is_equal_approx(hero.size.y, 330.0), "the hero is 330 high")
	await create_timer(0.4).timeout
	var paper: Control = profile.find_child("Paper", true, false)
	verify(is_equal_approx(paper.position.y, 300.0) and is_equal_approx(paper.modulate.a, 1.0), "the paper rose to 300 and faded in")
	verify(profile.preview.get_parent().scale.is_equal_approx(Vector2.ONE), "the figure eased to ×1")
	var pill: Control = profile.edit_look_button.get_node("Pill")
	verify(is_equal_approx(pill.get_global_rect().size.y, 32.0) and is_equal_approx(profile.edit_look_button.get_global_rect().size.y, 44.0)
		and is_equal_approx(pill.get_global_rect().position.y, 252.0), "Edit look: a 32 pill at 252 in a 44 hit area %s %s" % [pill.get_global_rect(), profile.edit_look_button.get_global_rect()])
	verify(is_equal_approx(profile.get_global_rect().end.x - profile.edit_look_button.get_global_rect().end.x, 16.0), "16 from the right")
	profile.settings_pressed.emit()
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
	var saved_toast = again.toast
	verify(saved_toast is UiBarToast and saved_toast.text == "Look saved" and saved_toast.kind == UiBarToast.Kind.SUCCESS, "with Look saved, a toast (①-D)")
	await create_timer(0.3).timeout
	verify(is_equal_approx(saved_toast.position.y, 84.0) and is_equal_approx(saved_toast.modulate.a, 1.0)
		and absf(saved_toast.position.x * 2.0 + saved_toast.size.x - again.size.x) <= 1.0, "centred under the top bar at 84 %s %s %s" % [saved_toast.position, saved_toast.size, again.size])
	await create_timer(2.6).timeout
	verify(not is_instance_valid(saved_toast), "gone after 2.5 s")
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
	verify(again.toast == null, "no toast either")
	again.back_pressed.emit(); await process_frame
	verify(map._profile == null and not is_instance_valid(host), "‹ on the profile closes it")
	# A home: My farm and its card; the card closes the profile and flies the map home.
	var went := [false]
	var home_host: Control = load("res://scenes/dynamic_farm/parcel_profile.gd").open(map, Vector3.ZERO,
		{"name": "Your Home", "status": "Carrots ready to harvest", "ready": true, "pressed": func(): went[0] = true})
	await process_frame
	var with_home: Control = home_host.top()
	verify(with_home.farm_card != null and with_home.find_child("SectionMyfarm", true, false).text == "My farm", "a home: My farm")
	verify(with_home.farm_card.find_child("FarmName", true, false).text == "Your Home"
		and with_home.farm_card.find_child("FarmStatus", true, false).text == "Carrots ready to harvest", "its name and status line")
	verify(with_home.farm_card.find_child("FarmStatus", true, false).get_theme_color(&"font_color") == UiTokens.COLOR_PRIMARY_INK, "ready: deep green")
	with_home.farm_pressed.emit(); await process_frame
	verify(went[0] and not is_instance_valid(home_host), "the card closes the profile and goes home")
	verify(map._hud.visible and not entry.disabled, "the map's panels come back")
	verify(TranslationServer.get_locale() == "zh_CN", "the locale is put back")
	# C-135: a load that never ends (the engine's loading thread stuck) holds the key for profile_wait_seconds at most,
	# then the profile and Settings open all the same.
	verify(not ProjectSettings.has_setting(map.PROFILE_WAIT_SETTING) and map.profile_wait_seconds == 5.0, "the wait is 5 s at most by default")
	for i in 900:
		if avatar.loader._by_path.is_empty(): break
		await process_frame
	var stuck := str(avatar.load_outfit().slots[&"cloth"])
	var stuck_path: String = avatar.catalog.part(stuck).res_path
	avatar.loader.set_process(false)   # never polled again: the part stays loading
	avatar.loader._by_path[stuck_path] = {"waiters": []}
	var stuck_ids: Array[String] = [stuck]
	avatar._warming = stuck_ids
	map.profile_wait_seconds = 0.5
	verify(avatar.warming(), "stuck: the outfit never finishes loading")
	var tapped := Time.get_ticks_msec()
	entry.pressed.emit()
	verify(map._profile == null and entry.disabled, "a tap holds the key while it loads")
	while map._profile == null and Time.get_ticks_msec() - tapped < 5000: await process_frame
	var waited := Time.get_ticks_msec() - tapped
	verify(map._profile != null and avatar.warming(), "the profile opens though the outfit is still loading")
	verify(waited >= 500 and waited < 2000, "after the configured wait (%d ms)" % waited)
	host = map._profile
	host.top().settings_pressed.emit(); await process_frame
	verify(host.top().get_script() == SettingsPage, "and Settings opens from it")
	avatar.loader._by_path.erase(stuck_path)
	var none: Array[String] = []
	avatar._warming = none
	host.top().back_pressed.emit(); await process_frame
	host.top().back_pressed.emit(); await process_frame
	verify(map._profile == null and not entry.disabled, "it closes as before")
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

extends GdUnitTestSuite
## P0 demo build (SGODOT-232 D2): the baked server file and where the first session lands.

func test_demo_config_takes_an_http_url_and_an_optional_key() -> void:
	assert_that(P0Session.demo_config('{"url": "https://example.test/preview/p0/v1/", "key": " k1 "}')).is_equal(
		{"url": "https://example.test/preview/p0/v1", "key": "k1", "version": 0, "name": ""})
	assert_that(P0Session.demo_config('{"url": "ftp://nope"}')).is_equal({"url": "", "key": "", "version": 0, "name": ""})
	# Settings › Version (q(129)): the build's versionName with its code
	assert_str(str(P0Session.demo_config('{"url": "https://a.test/v1", "version": 2026101001, "name": " 0.2.1 "}').name)).is_equal("0.2.1")
	# q(74): the build's versionCode goes out as x-p0-version (SGODOT-233)
	assert_int(int(P0Session.demo_config('{"url": "https://a.test/v1", "version": 2026100901}').version)).is_equal(2026100901)
	assert_that(P0Session.demo_config("not json")).is_equal({})
	assert_that(P0Session.demo_config("")).is_equal({})

func test_the_first_world_is_the_homestead() -> void:
	if OS.get_environment("P0_SCENE") != "" or FileAccess.file_exists("user://p0_scene"): return
	assert_str(load("res://scenes/p0/p0_boot.gd").wanted()).is_equal("farm")

## The demo preset asks for what the build uses: INTERNET (the P0 server) and VIBRATE (QuickBar haptics: dragging to
## remove, pinning; int5 hand test found it missing). The Journey presets are not touched.
func test_the_demo_preset_asks_for_internet_and_vibrate() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var section := ""
	for s in cfg.get_sections():
		if str(cfg.get_value(s, "name", "")) == "Android P0": section = s
	assert_str(section).is_not_empty()
	assert_bool(bool(cfg.get_value(section + ".options", "permissions/internet", false))).is_true()
	assert_bool(bool(cfg.get_value(section + ".options", "permissions/vibrate", false))).is_true()

## Settings › Legal › Licenses (q(129)): licenses.json and every text a row opens are plain files, which the export
## takes only through the preset's include_filter; one left out reads blank on the phone (a QA export from the Journey
## "Android" preset, 10-11). Every preset that builds P0 (custom feature p0: Android P0 today, an iOS one later) must
## ship them; the Journey presets do not build P0 and are not checked. The build script checks the APK too (legal_ok).
func test_every_p0_preset_ships_every_license_text() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var files: Array[String] = [P0Legal.DATA]
	for g in P0Legal.groups():
		for r in g.get("rows", []):
			var t := str(r.get("text", ""))
			if t.begins_with("res://"): files.append(t)
	assert_int(files.size()).is_greater(1)
	var p0_presets := 0
	for s in cfg.get_sections():
		var features := Array(str(cfg.get_value(s, "custom_features", "")).split(",")).map(func(f: String) -> String: return f.strip_edges())
		if s.ends_with(".options") or not ("p0" in features): continue
		p0_presets += 1
		var name := str(cfg.get_value(s, "name", s))
		var filters: Array[String] = []
		for f in str(cfg.get_value(s, "include_filter", "")).split(","):
			if f.strip_edges() != "": filters.append(f.strip_edges())
		for path in files:
			assert_bool(FileAccess.file_exists(path)).override_failure_message("%s is not in the repository" % path).is_true()
			var rel := path.trim_prefix("res://")
			var shipped := filters.any(func(f: String) -> bool: return rel.matchn(f.trim_prefix("res://")) or rel.get_file().matchn(f))
			assert_bool(shipped).override_failure_message("%s is not in the %s include_filter" % [rel, name]).is_true()
	assert_int(p0_presets).is_greater_equal(1)

## Data the P0 mine reads as plain files (355 b1): the monsters' json — the placeholders' and the models' beside their
## glb (contract-efg §10) — and each mine type's palette.json (§10.1). Every P0 preset ships them, the preview one too
## (it once had none: its monsters would have fallen back to slimes on the 11-08 preview build).
func test_every_p0_preset_ships_the_mines_json() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var files: Array[String] = ["modules/mining/monsters/placeholder/mob_slime.json", "assets/monsters/mob_cave_bat/mob_cave_bat.json",
		"assets/mine/types/quarry/palette.json", "assets/mine/types/vein/palette.json"]
	var p0_presets := 0
	for s in cfg.get_sections():
		var features := Array(str(cfg.get_value(s, "custom_features", "")).split(",")).map(func(f: String) -> String: return f.strip_edges())
		if s.ends_with(".options") or not ("p0" in features): continue
		p0_presets += 1
		var filters := Array(str(cfg.get_value(s, "include_filter", "")).split(",")).map(func(f: String) -> String: return f.strip_edges())
		for rel in files:
			assert_bool(FileAccess.file_exists("res://" + rel)).override_failure_message("%s is not in the repository" % rel).is_true()
			assert_bool(filters.any(func(f: String) -> bool: return f != "" and rel.matchn(f))) \
				.override_failure_message("%s is not in the %s include_filter" % [rel, cfg.get_value(s, "name", s)]).is_true()
	assert_int(p0_presets).is_greater_equal(2)

## The Play build (上架, 蒙恬 11-13): preset "Android Play" is the only Android one with the custom feature `store`
## (P0Build.store(): no test accounts; the card room kept since 11-13), package app.gensen.maps, exported as an AAB. The
## OSS presets never carry `store`. The upload key never sits in this file: the path, alias and password come from the
## GODOT_ANDROID_KEYSTORE_RELEASE_* variables at export time (the keystore and its password stay on the build Mac).
func test_only_the_play_preset_is_the_store_build() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var store: Array[String] = []
	for s in cfg.get_sections():
		var features := Array(str(cfg.get_value(s, "custom_features", "")).split(",")).map(func(f: String) -> String: return f.strip_edges())
		if not s.ends_with(".options") and "store" in features: store.append(str(cfg.get_value(s, "name", s)))
		if s.ends_with(".options") and str(cfg.get_value(s, "package/unique_name", "")) == "app.gensen.maps":
			assert_int(int(cfg.get_value(s, "gradle_build/export_format", 0))).is_equal(1)
		for k in cfg.get_section_keys(s):
			if k.begins_with("keystore/"): assert_str(str(cfg.get_value(s, k))).override_failure_message("%s %s is set" % [s, k]).is_empty()
	assert_that(store).is_equal(["Android Play"])
	var section := ""
	for s in cfg.get_sections():
		if str(cfg.get_value(s, "name", "")) == "Android Play": section = s
	assert_str(str(cfg.get_value(section + ".options", "package/unique_name", ""))).is_equal("app.gensen.maps")
	assert_str(str(cfg.get_value(section, "custom_features", ""))).is_equal("p0,store")

## 上架清权限 (蒙恬 11-13, audit G8): the Android overlay manifest removes location, camera and the foreground / screen-capture
## service (LiveKit and the old map PoC declare them; the game uses the microphone only) with tools:node="remove", and
## declares none of them itself. build_demo_apk.sh checks the exported APK's manifest too (permissions_ok).
func test_the_android_manifest_removes_what_the_game_does_not_use() -> void:
	var manifest := FileAccess.get_file_as_string("res://tools/android/overlay/AndroidManifest.xml")
	assert_str(manifest).is_not_empty()
	for p in ["ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "CAMERA", "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_MEDIA_PROJECTION"]:
		var line := RegEx.create_from_string('<uses-permission android:name="android\\.permission\\.%s"[^>]*>' % p).search(manifest)
		assert_object(line).override_failure_message("%s is not in the overlay manifest" % p).is_not_null()
		assert_str(line.get_string()).override_failure_message("%s is declared, not removed" % p).contains('tools:node="remove"')
	var service := RegEx.create_from_string('<service\\s+android:name="io\\.livekit\\.android\\.room\\.track\\.screencapture\\.ScreenCaptureService"[^>]*>').search(manifest)
	assert_object(service).is_not_null()
	assert_str(service.get_string()).contains('tools:node="remove"')

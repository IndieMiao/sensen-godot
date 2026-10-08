extends GdUnitTestSuite
## P0 demo build (SGODOT-232 D2): the baked server file and where the first session lands.

func test_demo_config_takes_an_http_url_and_an_optional_key() -> void:
	assert_that(P0Session.demo_config('{"url": "https://example.test/preview/p0/v1/", "key": " k1 "}')).is_equal(
		{"url": "https://example.test/preview/p0/v1", "key": "k1", "version": 0})
	assert_that(P0Session.demo_config('{"url": "ftp://nope"}')).is_equal({"url": "", "key": "", "version": 0})
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

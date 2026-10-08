extends GdUnitTestSuite
## Journey's Android preset (com.sensen.journeypreview) asks for what the app uses: INTERNET (the servers; until now
## only the WebView plugin's manifest brought it in) and VIBRATE (the fishing panel's Input.vibrate_handheld,
## scenes/fishing/fishing_panel.gd). 0.17.10 / 0.17.11 shipped without VIBRATE, so fishing never vibrated on Android.

func test_the_journey_preset_asks_for_internet_and_vibrate() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var section := ""
	for s in cfg.get_sections():
		if not s.ends_with(".options") and str(cfg.get_value(s, "platform", "")) == "Android" \
				and str(cfg.get_value(s + ".options", "package/unique_name", "")) == "com.sensen.journeypreview":
			section = s
	assert_str(section).override_failure_message("no Android preset for com.sensen.journeypreview").is_not_empty()
	assert_bool(bool(cfg.get_value(section + ".options", "permissions/internet", false))).is_true()
	assert_bool(bool(cfg.get_value(section + ".options", "permissions/vibrate", false))).is_true()

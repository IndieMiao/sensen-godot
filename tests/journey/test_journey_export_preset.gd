extends GdUnitTestSuite
## Journey's Android preset (com.sensen.journeypreview) asks for what the app uses: INTERNET (the servers; until now
## only the WebView plugin's manifest brought it in) and VIBRATE (the fishing panel's Input.vibrate_handheld,
## scenes/fishing/fishing_panel.gd). 0.17.10 / 0.17.11 shipped without VIBRATE, so fishing never vibrated on Android.
## Test builds take their version from this preset: the name stays 0.4.x (q(337)) and the code stays above the
## 0.16.37 test build's 2026092405 so installed phones upgrade in place (tools/android/README.md).

func test_the_journey_preset_asks_for_internet_and_vibrate() -> void:
	var cfg := ConfigFile.new()
	var section := _journey_preset(cfg)
	assert_bool(bool(cfg.get_value(section + ".options", "permissions/internet", false))).is_true()
	assert_bool(bool(cfg.get_value(section + ".options", "permissions/vibrate", false))).is_true()


func test_the_journey_preset_version_stays_04x_and_upgrades_over_0_16_37() -> void:
	var cfg := ConfigFile.new()
	var section := _journey_preset(cfg)
	var version_name := str(cfg.get_value(section + ".options", "version/name", ""))
	assert_bool(RegEx.create_from_string("^0\\.4\\.[1-9][0-9]*$").search(version_name) != null) \
		.override_failure_message("version/name %s is not 0.4.x" % version_name).is_true()
	assert_int(int(cfg.get_value(section + ".options", "version/code", 0))).is_greater(2026092405)


func _journey_preset(cfg: ConfigFile) -> String:
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var section := ""
	for s in cfg.get_sections():
		if not s.ends_with(".options") and str(cfg.get_value(s, "platform", "")) == "Android" \
				and str(cfg.get_value(s + ".options", "package/unique_name", "")) == "com.sensen.journeypreview":
			section = s
	assert_str(section).override_failure_message("no Android preset for com.sensen.journeypreview").is_not_empty()
	return section

extends GdUnitTestSuite
## No test opens the desktop's browser (the user's Edge grew a voice-match tab per run, 11-01): every page the app hands
## to the system browser goes through ExternalLink.open, which only records it in a test run or a headless one.

const STORE := "user://test_p0_external_link.json"
const TIPS := "user://test_p0_external_link_tips.json"

var _asked_before := 0

func before_test() -> void:
	_asked_before = ExternalLink.asked.size()

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	assert_int(ExternalLink.shell_opens).override_failure_message("a test opened the system browser").is_equal(0)

func _new_asked() -> Array:
	return ExternalLink.asked.slice(_asked_before)

func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	return ui

## The project's own code has no other door: a direct OS.shell_open anywhere but ExternalLink fails here.
func test_only_external_link_calls_shell_open() -> void:
	var found: Array = []
	for root in ["res://modules", "res://scenes", "res://tools"]:
		_scan(root, found)
	assert_array(found).is_empty()

func _scan(dir: String, found: Array) -> void:
	for d in DirAccess.get_directories_at(dir): _scan(dir.path_join(d), found)
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if not f.ends_with(".gd") or path == "res://modules/ui/external_link.gd": continue
		if FileAccess.get_file_as_string(path).contains("OS.shell_open("): found.append(path)

func test_a_test_run_is_quiet() -> void:
	assert_bool(ExternalLink.quiet()).is_true()   # gdUnit's runner is the main loop
	ExternalLink.open("https://example.com/x")
	assert_array(_new_asked()).is_equal(["https://example.com/x"])

## Voice Profile on desktop / iOS (no WebView plugin): the voice-match H5's address, asked once; nothing counts as open.
func test_voice_match_without_the_plugin_asks_for_its_page() -> void:
	var link := VoiceMatchLink.new()
	add_child(auto_free(link))
	link.open("solo")
	assert_array(_new_asked()).is_equal([VoiceMatchLink.url_for("solo", VoiceMatchLink._base_url())])
	assert_bool(link.is_open()).is_false()

## Settings › Map data: the two credits and Mapbox's feedback page; Licenses: a row's own link (q(205) ⑥).
func test_map_data_rows_and_a_licences_link() -> void:
	var ui := await _ui()
	ui._open_map_data_row("mapbox_site")
	ui._open_map_data_row("osm_site")
	assert_array(_new_asked()).is_equal([MapUsage.MAPBOX_CREDIT, MapUsage.OSM_CREDIT])
	ui._open_map_data_row("improve")
	assert_int(_new_asked().size()).is_equal(3)
	assert_str(str(_new_asked()[2])).starts_with("https://")
	ui.open_license_text("dbip")
	await await_idle_frame()
	var page := ui.find_children("*", "", true, false).filter(func(n): return n is P0SettingsPage)
	assert_int(page.size()).is_equal(1)
	(page[0] as P0SettingsPage).open_pressed.emit("link")
	assert_str(str(_new_asked()[3])).is_equal("https://db-ip.com")

## The Update screen's button: the store page the server named.
func test_the_update_screens_button() -> void:
	var rt := P0Runtime.ensure()
	await await_idle_frame()
	var was := str(rt.get("_block_url"))
	rt.set("_block_url", "https://example.com/update")
	rt.call("_on_screen_action", P0SysScreen.Kind.UPDATE)
	rt.set("_block_url", was)
	assert_array(_new_asked()).is_equal(["https://example.com/update"])

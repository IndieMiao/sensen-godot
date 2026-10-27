extends GdUnitTestSuite
## SGODOT-349 (不知火舞 2ca37b44): the profile's `Voice Profile ›` — a NavigationRow on a farm-card surface 16 under
## Collections — opens the voice-match H5 (VoiceMatchLink "solo"), and while that page is up, and for the Back press
## that closed it, Back is the page's: the profile stays open, a world under it (the mine too) does not go.

const STORE := "user://test_p0_voice_match_entry.json"
const TIPS := "user://test_p0_voice_match_entry_tips.json"

var ui: P0Ui

func _view() -> Dictionary:
	return {
		"coins": 40, "energy": {"value": 150, "max": 200},
		"skills": {"fishing": {"level": 2, "xp": 100}, "farming": {"level": 1, "xp": 0}, "cooking": {"level": 1, "xp": 0}},
		"fishing": {"dex": []},
		"bag": {"capacity": 25, "slots": []},
		"profile": {"name": "Mia"},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TIPS))
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TIPS))

func _page() -> P0ProfilePage:
	ui.open_profile()
	await await_idle_frame()
	await await_idle_frame()
	return ui._profile

func test_the_row_sits_16_under_collections_as_a_farm_card_navigation_row() -> void:
	var page := await _page()
	var row := page.find_child("VoiceProfileRow", true, false) as UiNavButton
	assert_object(row).is_not_null()
	assert_str(row.label).is_equal("Voice Profile")
	assert_bool(row.compact).is_false()   # the full-width NavigationRow: label left, › right, 49 high
	# The kit's NavigationRow as drawn everywhere (View homestead, Details): 49 in Figma, its ButtonB15 line a hair taller
	# in Godot, so 51 on the desktop for every such row; this one is no different.
	assert_float(row.size.y).is_greater_equal(UiTokens.SIZE_NAVIGATION_ROW)
	assert_float(row.size.y).is_less_equal(UiTokens.SIZE_NAVIGATION_ROW + 2.0)
	var card := row.get_parent() as PanelContainer
	var box := card.get_theme_stylebox(&"panel") as UiStyleBox   # the farm card's look: raised surface, radius 12, no stroke
	assert_object(box.bg_color).is_equal(UiTokens.COLOR_SURFACE_RAISED)
	assert_float(box.corner_radius.x).is_equal(12.0)
	assert_float(box.border_width).is_equal(0.0)
	assert_float(row.get_global_rect().position.x - card.get_global_rect().position.x).is_equal_approx(16.0, 0.5)   # its text and › in 16
	assert_float(card.get_global_rect().end.x - row.get_global_rect().end.x).is_equal_approx(16.0, 0.5)
	var wrap := card.get_parent() as Control
	var tiles := wrap.get_parent().get_child(wrap.get_index() - 1) as Control   # the Collections tiles, just above it
	assert_float(card.get_global_rect().position.y - tiles.get_global_rect().end.y).is_equal_approx(16.0, 0.5)
	assert_float(card.size.x).is_equal_approx(tiles.get_parent().size.x, 0.5)   # full width of the content column
	assert_int(wrap.get_index()).is_equal(wrap.get_parent().get_child_count() - 1)   # the last block

func test_tapping_it_asks_the_page_to_open() -> void:
	var page := await _page()
	var hits := []
	page.voice_pressed.connect(func(): hits.append(true))
	(page.find_child("VoiceProfileRow", true, false) as UiNavButton).pressed.emit()
	assert_int(hits.size()).is_equal(1)

func test_back_is_the_pages_while_it_is_up_and_for_the_press_that_closed_it() -> void:
	await _page()
	assert_bool(ui.voice_blocks_back()).is_false()
	ui.voice_match._open = true   # the WebView is up (no plugin here: set as VoiceMatchLink.open would)
	assert_bool(ui.close_top_layer()).is_true()
	assert_bool(ui.has_modal()).is_true()   # the profile stays
	assert_str(ui.modal_kind).is_equal("profile")
	ui.voice_match._open = false
	ui.voice_match._swallow_back_until = Time.get_ticks_msec() + 600   # closed by Back (VoiceMatchLink._on_closed)
	assert_bool(ui.close_top_layer()).is_true()
	assert_str(ui.modal_kind).is_equal("profile")
	ui.voice_match._swallow_back_until = 0
	assert_bool(ui.close_top_layer()).is_true()   # a Back after that closes the profile as ever
	assert_bool(ui.has_modal()).is_false()

func test_the_mine_keeps_its_back_for_the_page() -> void:
	var mine = load("res://scenes/p0/p0_mine.gd").new()
	mine.rt = P0Runtime.ensure()
	for i in 3: await await_idle_frame()   # in the tree: its ui is built
	var real_ui = mine.rt.ui
	assert_bool(mine.is_back_navigation_locked()).is_false()   # Back leaves the mine as before
	real_ui.voice_match._open = true
	assert_bool(mine.is_back_navigation_locked()).is_true()
	real_ui.voice_match._open = false
	mine.free()

func after() -> void:
	P0Runtime.free_instance_for_tests()

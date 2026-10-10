extends GdUnitTestSuite
## q(133) v3 (Q133-V3-MAP 2416:128683 / Q133-V3-CARD 2416:128729): the map's Mapbox credit is one quiet line at the
## bottom-left — `© Mapbox © OpenStreetMap`, 9 pt Regular #2F3A33 at 55 %, no outline or plate, 16 pt in and 6 pt over the
## safe area's bottom — riding 6 pt above a card open over the map, not drawn under a page, nor without a Mapbox map.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

class _Mapbox extends MapBridge:   # a platform with a Mapbox map (the desktop has none)
	func has_mapbox() -> bool: return true
	func get_pixel_ratio() -> float: return 2.0

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func test_one_quiet_line_bottom_left_above_a_card_and_none_under_a_page() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var credits: Label = city.get_node("MapCredits")
	var saved_bridge := city._attached_bridge
	city._update_credits()
	assert_bool(credits.visible).is_false()   # the desktop: no Mapbox map, no line
	city._attached_bridge = _Mapbox.new()
	city._update_credits()
	assert_bool(credits.visible).is_true()
	assert_str(credits.text).is_equal("© Mapbox © OpenStreetMap")
	assert_int(credits.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
	assert_that(credits.get_theme_color(&"font_color")).is_equal(Color(UiTokens.COLOR_TEXT, 0.55))
	assert_int(credits.get_theme_constant(&"outline_size")).is_equal(0)
	assert_object(credits.get_theme_stylebox(&"normal")).is_not_instanceof(StyleBoxFlat)   # no plate
	var k: float = city._px_per_pt()
	assert_int(credits.get_theme_font_size(&"font_size")).is_equal(roundi(9.0 * k))
	assert_float(credits.position.x).is_equal_approx(16.0 * k, 0.01)
	assert_float(credits.position.y + credits.size.y).is_equal_approx(city.size.y - 6.0 * k, 0.01)
	# a card open over the map: the line rides 6 pt above its top
	var floor_hook: Callable = city.credits_floor
	city.credits_floor = func() -> float: return 500.0
	city._update_credits()
	assert_bool(credits.visible).is_true()
	assert_float(credits.position.y + credits.size.y).is_equal_approx(500.0 - city.global_position.y - 6.0 * k, 0.01)
	# a page over the map: none
	city.credits_floor = func() -> float: return 0.0
	city._update_credits()
	assert_bool(credits.visible).is_false()
	# P0's own hook: nothing open is no card
	city.credits_floor = floor_hook
	m.rt.ui.close_modal()
	assert_float(float(floor_hook.call())).is_equal(INF)
	city._update_credits()
	assert_bool(credits.visible).is_true()
	city._attached_bridge = saved_bridge

## The card's own top, not its × above it (emulator, 10-11): the line rides 6 pt above the panel, as in Q133-V3-CARD.
func test_the_floor_is_the_cards_panel_not_its_close_key() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var ui: P0Ui = m.rt.ui
	P0PlaceSheet.open(ui, {"title": "Fern Pond", "subtitle": "Beginner", "facts": [["Distance", "0.8 km"]], "primary": "Go"},
		func(): pass)
	await get_tree().process_frame
	var holder: Control = ui._modal.get_child(ui._modal.get_child_count() - 1)
	var panel: Control = holder.get_children().filter(func(c): return c is PanelContainer)[0]
	assert_float(ui.modal_top()).is_equal_approx(panel.get_global_rect().position.y, 0.5)
	for b in holder.find_children("*", "Button", false, false):   # the × sits over the card: not the floor
		if (b as Control).size.x < 60.0: assert_float((b as Control).get_global_rect().position.y).is_less(ui.modal_top())
	ui.close_modal()

## 周瑜 on #309: only what stands on the screen's bottom edge is a floor — a moment or banner shown mid-screen as the
## modal is none (the line stays down), a page over the whole screen hides it.
func test_only_a_card_on_the_bottom_edge_is_a_floor() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var ui: P0Ui = m.rt.ui
	var mid := Control.new()   # a reward moment over the middle of the screen
	mid.mouse_filter = Control.MOUSE_FILTER_STOP
	mid.position = Vector2(40, 300)
	mid.size = Vector2(280, 160)
	ui._open_modal(mid)
	await get_tree().process_frame
	assert_float(ui.modal_top()).is_equal(INF)
	var page := Control.new()   # a page over the whole screen
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui._open_modal(page)
	await get_tree().process_frame
	assert_float(ui.modal_top()).is_equal(0.0)
	ui.close_modal()

## iOS: the switch's TELEM line follows the saved choice (MapBridgeIOS sends it again once the map is up).
func test_the_telem_line_follows_the_saved_choice() -> void:
	var was := MapUsage.saved()
	MapUsage.set_enabled(false)
	assert_str(MapUsage.telem_packet()).is_equal("TELEM|0")
	MapUsage.set_enabled(true)
	assert_str(MapUsage.telem_packet()).is_equal("TELEM|1")
	MapUsage.set_enabled(was)

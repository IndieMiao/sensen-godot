extends GdUnitTestSuite
## HUD：360×800 下不与顶栏/摇杆重叠、可点、文案全英文；倒计时用服务端时间。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

var _saved_navigation_pending: bool

func before_test() -> void:
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	AppRouter._navigation_pending = _saved_navigation_pending

func _farm_at_phone_size() -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX)})
	add_child(auto_free(scene))
	var safe := scene.get_node("HUD/SafeArea") as SafeAreaMargin
	safe.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	safe.size = Vector2(360, 800)
	safe.apply_margins(Rect2i(), Vector2i(360, 800), Vector2(360, 800))
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func _rects(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
	return out

func test_hud_never_collides_with_topbar_or_joystick() -> void:
	# 顶栏在 360 宽里已经没有余量；HUD 全部新元素都必须在底部与右侧。
	var f := await _farm_at_phone_size()
	var top: Rect2 = (f.get_node("HUD/SafeArea/Root/TopBar") as Control).get_global_rect()
	var stick: Rect2 = (f.joystick as Control).get_global_rect()
	for name in ["TopRight", "BottomBar"]:
		var group := f.hud.get_node(name) as Control
		for b in _rects(group.get_node("SeedBar") if name == "BottomBar" else group):
			pass
		assert_bool(group.get_global_rect().intersects(top)).override_failure_message(
			"%s 与顶栏重叠" % name).is_false()
	var bottom: Rect2 = (f.hud.get_node("BottomBar") as Control).get_global_rect()
	assert_bool(bottom.intersects(stick)).override_failure_message("底栏压住了摇杆").is_false()

func test_every_button_meets_the_touch_target_and_stays_on_screen() -> void:
	var f := await _farm_at_phone_size()
	var screen := Rect2(Vector2.ZERO, Vector2(360, 800))
	var bar := f.hud.get_node("BottomBar") as Control
	var buttons: Array = _rects(bar.get_node("SeedBar")) + _rects(bar.get_node("ToolBar"))
	buttons.append(f.hud._row_button)
	assert_int(buttons.size()).is_equal(4 + 5 + 1)   # 4 作物 + 5 工具 + 右上 Row
	for b in buttons:
		var r: Rect2 = (b as Control).get_global_rect()
		assert_bool(r.size.y >= 44.0).override_failure_message(
			"%s 高度 %.1f 低于 44 触摸目标" % [b.text, r.size.y]).is_true()
		assert_bool(screen.grow(0.5).encloses(r)).override_failure_message(
			"%s 被挤出屏幕: %s" % [b.text, r]).is_true()
		# 标签被省略号吃掉说明横向预算不够，和挤出屏幕是同一个病
		assert_bool(r.size.x >= b.get_theme_font(&"font").get_string_size(b.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, DesignTokens.FONT_CAPTION).x + 8.0
			).override_failure_message("%s 宽 %.1f 装不下自己的标签" % [b.text, r.size.x]).is_true()

func test_all_hud_text_is_english() -> void:
	# 用户可见文案不出现中文（2026-09-04 约定）。
	var f := await _farm_at_phone_size()
	var stack: Array = [f.hud]
	var seen := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		if text.is_empty():
			continue
		seen += 1
		for ch in text:
			assert_bool(ch.unicode_at(0) < 0x2E80).override_failure_message(
				"HUD 文案含非英文字符: %s" % text).is_true()
	assert_bool(seen >= 10).is_true()

func test_tool_button_toggles_back_to_move_mode() -> void:
	# 再点一次已选工具就退回移动模式，不给「取消」单独占按钮位。
	var f := await _farm_at_phone_size()
	f.hud._on_tool("clear")
	assert_str(f.tool).is_equal("clear")
	f.hud._on_tool("clear")
	assert_str(f.tool).is_equal("")

func test_crop_and_row_selection_reach_the_scene() -> void:
	var f := await _farm_at_phone_size()
	f.hud._on_crop("C")
	assert_str(f.sow_crop).is_equal("C")
	f.hud._on_row()
	assert_bool(f.row_tool).is_true()

func test_offline_disables_tools_and_shows_the_banner() -> void:
	var f := await _farm_at_phone_size()
	assert_bool((f.hud.get_node("OfflineBanner") as Control).visible).is_false()
	f.hud.set_offline(true)
	assert_bool((f.hud.get_node("OfflineBanner") as Control).visible).is_true()
	for b in _rects((f.hud.get_node("BottomBar") as Control).get_node("ToolBar")):
		assert_bool((b as Button).disabled).is_true()
	assert_bool(f.hud._row_button.disabled).is_true()

func test_countdown_picks_the_soonest_unripe_cell() -> void:
	var cells := {
		"1,1": {"ready_at": 5_000}, "2,1": {"ready_at": 3_000},
		"3,1": {"ready_at": null}, "1,2": {},
	}
	assert_int(FarmHud.next_ripe_ms(cells, 1_000)).is_equal(2_000)
	assert_int(FarmHud.next_ripe_ms(cells, 3_000)).is_equal(0)      # 已经熟了
	assert_int(FarmHud.next_ripe_ms({"1,1": {"ready_at": null}}, 0)).is_equal(-1)

func test_countdown_formatting() -> void:
	assert_str(FarmHud.format_countdown(-1)).is_equal("--:--")
	assert_str(FarmHud.format_countdown(0)).is_equal("ready")
	assert_str(FarmHud.format_countdown(90_000)).is_equal("01:30")
	assert_str(FarmHud.format_countdown(3 * 3600_000 + 25 * 60_000)).is_equal("3h25m")

func test_condition_chip_names_the_required_care() -> void:
	var f := await _farm_at_phone_size()
	f.hud.set_condition("rain")
	assert_str(f.hud._condition.text).is_equal("Rain · Drain")
	f.hud.set_condition("wind")
	assert_str(f.hud._condition.text).is_equal("Wind · Shelter")

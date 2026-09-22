extends GdUnitTestSuite

func _hud() -> FarmHud:
	var host := auto_free(Control.new()) as Control
	host.size = Vector2(328, 748)
	host.theme = GameUi.theme()
	add_child(host)
	var hud := FarmHud.new()
	host.add_child(hud)
	hud.set_process(false)
	return hud

func _settle() -> void:
	for frame in 5: await get_tree().process_frame

func _assert_natural_height(hud: FarmHud) -> void:
	var padding := hud._toast.get_theme_stylebox("panel").get_minimum_size()
	assert_float(hud._toast.size.y).is_equal_approx(hud._toast_label.get_combined_minimum_size().y + padding.y, 1.0)
	assert_float(hud._toast_label.size.x).is_equal_approx(hud._toast.size.x - padding.x, 1.0)

func test_short_and_rescue_toasts_shrink_after_wrapping_without_covering_the_modal() -> void:
	var hud := _hud()
	hud.show_toast("生命已恢复")
	await _settle()
	_assert_natural_height(hud)
	assert_float(hud._toast.size.y).is_less_equal(60.0)
	assert_bool(hud._toast.visible).is_true()
	assert_int(hud._toast.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(hud._toast_label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	hud.show_modal(hud._quick_actions)
	hud.show_toast("已获救，返回农场休整。随身物品全部保留。")
	await _settle()
	_assert_natural_height(hud)
	assert_float(hud._toast.size.y).is_less_equal(90.0)
	assert_bool(hud.modal_open()).is_true()
	assert_bool(hud._scrim.visible).is_true()
	assert_float(hud._toast_left).is_equal(FarmHud.TOAST_S)
	hud._process(1.0)
	assert_bool(hud._toast.visible).is_true()
	assert_float(hud._toast_left).is_equal(FarmHud.TOAST_S - 1.0)
	hud._process(FarmHud.TOAST_S)
	assert_bool(hud._toast.visible).is_false()
	assert_bool(hud.modal_open()).is_true()

func test_long_toast_reflows_on_width_changes_and_short_replacement_resets_height() -> void:
	var hud := _hud()
	hud.show_toast("农场信息尚未同步，请重新连接后再试。连接恢复后会保留当前作物、装备和随身物品，不会重复提交上一次操作。", true)
	await _settle()
	_assert_natural_height(hud)
	var wide_height := hud._toast.size.y
	hud.get_parent().size.x = 240
	await _settle()
	_assert_natural_height(hud)
	assert_float(hud._toast.size.y).is_greater(wide_height)
	hud.get_parent().size.x = 390
	hud.show_toast("生命已恢复")
	await _settle()
	_assert_natural_height(hud)
	assert_float(hud._toast.size.y).is_less_equal(60.0)
	assert_bool(hud.modal_open()).is_false()
	assert_float(hud._toast_left).is_equal(FarmHud.TOAST_S)

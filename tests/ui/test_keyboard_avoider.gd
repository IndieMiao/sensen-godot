extends GdUnitTestSuite
## 软键盘避让（vivo 真机 2026-09-28 发现键盘挡住搜索结果与账号面板）。

var _kb := 0.0

func _page() -> Array:
	var root := Control.new()
	root.size = Vector2(360, 800)
	add_child(auto_free(root))
	var field := LineEdit.new()
	field.position = Vector2(20, 520)
	field.size = Vector2(300, 44)
	root.add_child(field)
	var avoider := KeyboardAvoider.attach(root, 100.0)
	avoider.keyboard_height = func(): return _kb
	return [root, field, avoider]

## Until the avoider has reached its target offset (it eases by frame time, so a frame count depends on the frame
## rate: an undrawn window runs far above 60 fps), at most 3 s.
func _settle(avoider: KeyboardAvoider) -> void:
	var start := Time.get_ticks_msec()
	for i in 2: await get_tree().process_frame
	while avoider._offset != avoider.desired_offset() and Time.get_ticks_msec() - start < 3000:
		await get_tree().process_frame

func test_focused_field_and_content_below_move_above_the_keyboard() -> void:
	var parts := _page()
	var root: Control = parts[0]
	var field: LineEdit = parts[1]
	var avoider: KeyboardAvoider = parts[2]
	field.grab_focus()
	_kb = 320.0
	var view := get_viewport().get_visible_rect().size.y
	await _settle(avoider)
	# Field bottom + 100 px of results must clear the keyboard top (minus the gap).
	assert_float(field.get_global_rect().end.y + 100.0).is_less_equal(view - 320.0 - avoider.gap + 1.0)
	assert_float(root.position.y).is_less(0.0)
	_kb = 0.0
	await _settle(avoider)
	assert_float(root.position.y).is_equal_approx(0.0, 0.01)

func test_no_shift_without_focus_inside_the_target() -> void:
	var parts := _page()
	var root: Control = parts[0]
	var other := LineEdit.new()
	add_child(auto_free(other))
	other.grab_focus()
	_kb = 320.0
	await _settle(parts[2])
	assert_float(root.position.y).is_equal(0.0)

func test_field_is_never_pushed_off_the_top() -> void:
	var parts := _page()
	var root: Control = parts[0]
	var field: LineEdit = parts[1]
	field.position.y = 60
	parts[2].extra_below = 2000.0
	field.grab_focus()
	_kb = 400.0
	await _settle(parts[2])
	assert_float(field.get_global_rect().position.y).is_greater_equal(7.5)
	assert_bool(root.position.y <= 0.0).is_true()

func test_search_query_ignores_ime_apostrophes() -> void:
	var script := load("res://scenes/city_select/city_select.gd")
	assert_str(script.search_query(" to'k ")).is_equal("tok")
	assert_str(script.search_query("Xi’an")).is_equal("Xian")


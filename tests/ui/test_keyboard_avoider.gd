extends GdUnitTestSuite
## KeyboardAvoider：高度换算、平移量纯函数、只对页内焦点输入框生效、键盘收起归零、逐帧跟随。

class Probe extends RefCounted:
	var kb_px := 0
	var window := Vector2i(1080, 2400)
	var focus: Control = null
	func keyboard() -> int: return kb_px
	func win() -> Vector2i: return window
	func focused() -> Control: return focus

var probe: Probe

func before_test() -> void:
	probe = Probe.new()

func test_pure_functions() -> void:
	assert_float(KeyboardAvoider.keyboard_height_in_viewport(900, 2400, 800.0)).is_equal_approx(300.0, 0.01)
	assert_float(KeyboardAvoider.keyboard_height_in_viewport(0, 2400, 800.0)).is_equal_approx(0.0, 0.01)
	assert_float(KeyboardAvoider.keyboard_height_in_viewport(900, 0, 800.0)).is_equal_approx(0.0, 0.01)
	# 视口 800 高，键盘占 300 → 键盘顶边 500；控件底边 640 + 12 边距 → 上移 152
	assert_float(KeyboardAvoider.shift_for(640.0, 800.0, 300.0, 12.0)).is_equal_approx(152.0, 0.01)
	assert_float(KeyboardAvoider.shift_for(400.0, 800.0, 300.0, 12.0)).is_equal_approx(0.0, 0.01)
	assert_float(KeyboardAvoider.shift_for(640.0, 800.0, 0.0, 12.0)).is_equal_approx(0.0, 0.01)

func _rig() -> Array:
	var root := Control.new()
	root.size = Vector2(360, 800)
	add_child(auto_free(root))
	var column := Control.new()
	column.size = Vector2(360, 800)
	root.add_child(column)
	var field := LineEdit.new()
	field.position = Vector2(20, 600)
	field.size = Vector2(320, 44)
	column.add_child(field)
	var outsider := LineEdit.new()
	outsider.position = Vector2(20, 700)
	outsider.size = Vector2(320, 44)
	root.add_child(outsider)
	var av := KeyboardAvoider.new()
	av.target = column
	av.keyboard_height_provider = probe.keyboard
	av.window_size_provider = probe.win
	av.focus_provider = probe.focused
	root.add_child(av)
	return [av, column, field, outsider]

func test_shifts_target_up_for_focused_input_and_resets_when_keyboard_hides() -> void:
	var r := _rig()
	var av: KeyboardAvoider = r[0]
	var column: Control = r[1]
	var field: LineEdit = r[2]
	probe.focus = field
	probe.kb_px = 0
	av.poll()
	assert_float(column.position.y).is_equal_approx(0.0, 0.01)
	probe.kb_px = 900 # 物理 900 / 窗口 2400 → 视口 300（视口高 = 测试根视口高度，这里只验方向与归零）
	av.poll()
	assert_bool(column.position.y < 0.0).is_true()
	var first := column.position.y
	av.poll()
	assert_float(column.position.y).is_equal_approx(first, 0.01) # 稳定：不会每帧累加
	probe.kb_px = 0
	av.poll()
	assert_float(column.position.y).is_equal_approx(0.0, 0.01)
	assert_float(av.current_shift).is_equal_approx(0.0, 0.01)

func test_ignores_focus_outside_target_and_non_text_controls() -> void:
	var r := _rig()
	var av: KeyboardAvoider = r[0]
	var column: Control = r[1]
	var outsider: LineEdit = r[3]
	probe.kb_px = 900
	probe.focus = outsider
	av.poll()
	assert_float(column.position.y).is_equal_approx(0.0, 0.01)
	var b := Button.new()
	column.add_child(b)
	probe.focus = b
	av.poll()
	assert_float(column.position.y).is_equal_approx(0.0, 0.01)
	probe.focus = null
	av.poll()
	assert_float(column.position.y).is_equal_approx(0.0, 0.01)

func test_follows_keyboard_animation_frame_by_frame() -> void:
	var r := _rig()
	var av: KeyboardAvoider = r[0]
	var column: Control = r[1]
	probe.focus = r[2]
	var last := 0.0
	for px in [200, 500, 900]:
		probe.kb_px = px
		av.poll()
		assert_bool(column.position.y <= last).is_true()
		last = column.position.y
	assert_bool(last < 0.0).is_true()

func test_app_pages_carry_an_avoider_targeting_the_content_column() -> void:
	var login := (load(AppRoutes.LOGIN) as PackedScene).instantiate() as AppPage
	add_child(auto_free(login))
	assert_object(login.keyboard_avoider).is_not_null()
	assert_bool(login.keyboard_avoider.target.is_ancestor_of(login.email)).is_true()

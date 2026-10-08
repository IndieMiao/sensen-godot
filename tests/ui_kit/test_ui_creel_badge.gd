extends GdUnitTestSuite
## CreelBadge 1126:79349 (FISH-1 / FISH-4; 不知火舞 on 235 B1, q(83)): `Creel N · M free` in three states, the alert dot
## only when full, a tap for the host.

const FISH := preload("res://assets/p0/icons/fish.svg")

func _badge(state := UiCreelBadge.State.NORMAL) -> UiCreelBadge:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 200)
	add_child(auto_free(host))
	var b := UiCreelBadge.new(FISH)
	b.text = "Creel 7 · 6 free"
	b.state = state
	host.add_child(b)
	return b

func test_the_state_follows_the_free_slots() -> void:
	assert_int(UiCreelBadge.state_for(6)).is_equal(UiCreelBadge.State.NORMAL)
	assert_int(UiCreelBadge.state_for(1)).is_equal(UiCreelBadge.State.LOW)
	assert_int(UiCreelBadge.state_for(0)).is_equal(UiCreelBadge.State.FULL)
	assert_int(UiCreelBadge.state_for(-1)).is_equal(UiCreelBadge.State.FULL)

func test_each_state_has_the_mains_colours_and_only_full_has_the_dot() -> void:
	var want := {
		UiCreelBadge.State.NORMAL: [UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER, UiTokens.COLOR_TEXT, false],
		UiCreelBadge.State.LOW: [UiTokens.COLOR_SURFACE, UiTokens.COLOR_AMBER, UiTokens.COLOR_WARNING, false],
		UiCreelBadge.State.FULL: [UiTokens.COLOR_WARNING_TINT, UiTokens.COLOR_AMBER, UiTokens.COLOR_WARNING, true]}
	for s in want:
		var b := _badge(s)
		await await_idle_frame()
		var box := b._pill.get_theme_stylebox(&"panel") as UiStyleBox
		assert_that([box.bg_color, box.border_color, b._label.get_theme_color(&"font_color"), b._dot.visible]).is_equal(want[s])

func test_the_pill_is_26_high_and_the_dot_hangs_over_its_top_right() -> void:
	var b := _badge(UiCreelBadge.State.FULL)
	await await_idle_frame()
	var r := b.pill_rect()
	assert_float(r.size.y).is_equal(26.0)   # 16 icon / caption line + 4 + 4 padding + 1 + 1 border
	assert_str(b._label.text).is_equal("Creel 7 · 6 free")
	assert_vector(b._dot.position).is_equal(Vector2(r.size.x - 6.0, -2.0))
	assert_vector(b._dot.size).is_equal(Vector2(8, 8))
	assert_vector(b.size).is_equal(r.size)

func _mouse(pos: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = pos
	e.pressed = down
	return e

## A real tap only (亚瑟 on #106): released where it went down; a press alone or a drag off it is no tap.
func test_a_tap_is_the_hosts_a_drag_is_not() -> void:
	var b := _badge()
	await await_idle_frame()
	var taps := [0]
	b.pressed.connect(func(): taps[0] += 1)
	b._gui_input(_mouse(Vector2(20, 10), true))
	assert_int(taps[0]).is_equal(0)   # not on the press
	b._gui_input(_mouse(Vector2(22, 11), false))
	assert_int(taps[0]).is_equal(1)
	b._gui_input(_mouse(Vector2(20, 10), true))
	b._gui_input(_mouse(Vector2(20 + GestureArbiter.TAP_SLOP + 10, 10), false))
	assert_int(taps[0]).is_equal(1)   # dragged past the slop

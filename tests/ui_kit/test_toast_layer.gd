extends GdUnitTestSuite
## ToastLayer: one at a time, a new toast replaces the old, the same sentence within 2 s only stays up longer
## (q(49) ⑤, SGODOT-233), the duration rule (WP7-B F-08 §3), the R1 tone look and action; placement above the
## quick bar / a drawer's fixed decision area (WP2 D-01, SGODOT-202).

var toasts: ToastLayer

func before_test() -> void:
	toasts = ToastLayer.new()
	add_child(auto_free(toasts))
	toasts.position = Vector2.ZERO
	toasts.size = Vector2(360, 800)   # after _ready: it anchors itself full-rect
	toasts.set_process(false)   # tests drive time with advance()

func test_duration_grows_with_length_and_is_capped() -> void:
	assert_float(ToastLayer.duration_ms("Bag full")).is_equal_approx(float(UiTokens.MOTION_TOAST_BASE_MS), 0.01)
	assert_float(ToastLayer.duration_ms("x".repeat(45))).is_equal_approx(float(UiTokens.MOTION_TOAST_BASE_MS + 2 * UiTokens.MOTION_TOAST_PER20_CHARS_MS), 0.01)
	assert_float(ToastLayer.duration_ms("x".repeat(400))).is_equal_approx(float(UiTokens.MOTION_TOAST_MAX_MS), 0.01)

func test_a_new_toast_replaces_the_one_showing() -> void:
	toasts.show_toast("Sold 3 Radish")
	toasts.show_toast("Bag full · free a slot first")
	assert_str(toasts.current_text()).is_equal("Bag full · free a slot first")   # no queue (q(49) ⑤)
	toasts.advance(UiTokens.MOTION_TOAST_BASE_MS / 1000.0 + 0.01)
	assert_str(toasts.current_text()).is_equal("Bag full · free a slot first")   # 28 chars stay 0.5 s longer
	toasts.advance(UiTokens.MOTION_TOAST_PER20_CHARS_MS / 1000.0)
	assert_str(toasts.current_text()).is_empty()

func test_the_same_sentence_within_two_seconds_only_stays_up_longer() -> void:
	var pops := [0]
	toasts.shown.connect(func(_t, _s): pops[0] += 1)
	toasts.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
	toasts.advance(1.5)
	toasts.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
	assert_str(toasts.current_text()).is_equal("Not ready yet")   # no ×2
	assert_int(pops[0]).is_equal(1)   # it did not pop again
	toasts.advance(1.5)
	assert_str(toasts.current_text()).is_equal("Not ready yet")   # 1.5 s after the repeat it is still up
	toasts.advance(1.0)
	assert_str(toasts.current_text()).is_empty()
	toasts.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
	assert_int(pops[0]).is_equal(2)   # gone, so the next one pops

func test_tones_follow_toast_r1() -> void:
	for sev in [ToastLayer.Severity.SUCCESS, ToastLayer.Severity.INFO, ToastLayer.Severity.ERROR]:
		toasts.show_toast("Sold out · restocks in 9h 12m %d" % sev, sev)
		var box := toasts._panel.get_theme_stylebox(&"panel") as UiStyleBox
		var want: Array = {ToastLayer.Severity.SUCCESS: [UiTokens.COLOR_PRIMARY_TINT, UiTokens.COLOR_PRIMARY],
			ToastLayer.Severity.INFO: [UiTokens.COLOR_SURFACE, UiTokens.COLOR_BORDER],
			ToastLayer.Severity.ERROR: [UiTokens.COLOR_DANGER_TINT, UiTokens.COLOR_DANGER]}[sev]
		assert_str(box.bg_color.to_html()).is_equal((want[0] as Color).to_html())
		assert_str(box.border_color.to_html()).is_equal((want[1] as Color).to_html())
		assert_object(toasts._glyph.texture).is_same(ToastLayer.glyph(sev))
	assert_int(toasts.current_severity()).is_equal(ToastLayer.Severity.ERROR)

func test_the_action_line_emits_and_closes() -> void:
	var got := []
	toasts.action_pressed.connect(func(a): got.append(a))
	toasts.show_toast("Creel full · 0 free slots · Sell or cook first", ToastLayer.Severity.ERROR, "Open bag")
	assert_str(toasts._action.text).is_equal("Open bag ›")
	assert_bool(toasts._action.is_visible_in_tree()).is_true()
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	toasts._action.gui_input.emit(tap)
	assert_array(got).is_equal(["Open bag"])
	assert_str(toasts.current_text()).is_empty()
	toasts.show_toast("Sold 3 Radish")
	assert_bool(toasts._action.is_visible_in_tree()).is_false()

func test_layer_never_blocks_input_and_tapping_the_toast_dismisses_it() -> void:
	assert_int(toasts.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	toasts.show_toast("Rest used today")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	toasts._panel.gui_input.emit(tap)
	assert_str(toasts.current_text()).is_empty()

func _bottom() -> float: return toasts._panel.position.y + toasts._panel.size.y

func test_toast_sits_above_the_quick_bar_left_of_the_action_key() -> void:
	toasts.show_toast("Rest used today")
	var bar_top := 800.0 - UiTokens.SIZE_QUICK_BAR_BOTTOM - UiTokens.SIZE_QUICK_BAR_H   # 708, Figma demo 1182:82261
	assert_float(_bottom()).is_equal_approx(bar_top - UiTokens.SPACE_OVERLAY_BODY, 0.5)
	assert_float(toasts._panel.position.x).is_equal(float(UiTokens.SPACE_PAGE))
	assert_float(toasts._panel.size.x).is_equal(float(ToastLayer.WIDTH))
	# The main action key starts at x 249 in the same demo; the toast must end before it.
	assert_float(toasts._panel.position.x + toasts._panel.size.x).is_less(249.0)

func test_drawer_anchor_puts_the_toast_above_its_fixed_area_and_null_restores_the_bar() -> void:
	var fixed := Control.new()
	toasts.add_child(fixed)
	fixed.position = Vector2(16, 724)   # "Fixed decision area" in Figma demo 1182:82389
	fixed.size = Vector2(328, 60)
	toasts.anchor_above(fixed)
	toasts.show_toast("Need 2 more Copper Ore")
	assert_float(_bottom()).is_equal_approx(724.0 - UiTokens.SPACE_OVERLAY_BODY, 0.5)
	fixed.visible = false   # a hidden anchor falls back to the quick bar
	toasts.anchor_above(fixed)
	assert_float(_bottom()).is_equal_approx(700.0, 0.5)
	fixed.visible = true
	toasts.anchor_above(fixed)
	toasts.anchor_above(null)
	assert_float(_bottom()).is_equal_approx(700.0, 0.5)

func test_long_text_grows_upward_from_the_same_edge() -> void:
	toasts.show_toast("Bag full · Radish Seeds ×12 sent to Inbox · 24h to claim")
	await await_idle_frame()
	await await_idle_frame()
	assert_float(toasts._panel.size.y).is_greater(float(UiTokens.SIZE_TOAST_MIN_H))
	assert_float(_bottom()).is_equal_approx(700.0, 0.5)

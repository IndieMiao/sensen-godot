extends GdUnitTestSuite
## ToastLayer: non-modal queue, duration rule, merging and priority (SGODOT-211, WP7-B F-08 §3);
## placement above the quick bar / a drawer's fixed decision area (WP2 D-01, SGODOT-202).

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

func test_one_toast_at_a_time_then_the_next() -> void:
	toasts.show_toast("Sold 3 Radish")
	toasts.show_toast("Bag full · free a slot first")
	assert_str(toasts.current_text()).is_equal("Sold 3 Radish")
	toasts.advance(UiTokens.MOTION_TOAST_BASE_MS / 1000.0 + 0.01)
	assert_str(toasts.current_text()).is_equal("Bag full · free a slot first")
	toasts.advance(UiTokens.MOTION_TOAST_BASE_MS / 1000.0 + 0.01)
	assert_str(toasts.current_text()).is_equal("Bag full · free a slot first")   # 28 chars stay 0.5 s longer
	toasts.advance(UiTokens.MOTION_TOAST_PER20_CHARS_MS / 1000.0)
	assert_str(toasts.current_text()).is_empty()

func test_repeats_within_a_second_merge() -> void:
	toasts.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
	toasts.advance(0.5)
	toasts.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
	assert_str(toasts.current_text()).is_equal("Not ready yet ×2")
	assert_array(toasts.queued()).is_empty()

func test_refusals_jump_ahead_of_successes() -> void:
	toasts.show_toast("Sold 3 Radish", ToastLayer.Severity.SUCCESS)
	toasts.show_toast("+10 coins", ToastLayer.Severity.SUCCESS)
	toasts.show_toast("Limit reached", ToastLayer.Severity.REFUSED)
	assert_str(String(toasts.queued()[0].text)).is_equal("Limit reached")

func test_queue_keeps_three_and_drops_the_oldest_least_important() -> void:
	toasts.show_toast("showing")
	for i in 3:
		toasts.advance(0.01)
		toasts.show_toast("ok %d" % i, ToastLayer.Severity.SUCCESS)
	toasts.advance(0.01)
	toasts.show_toast("Can't reach the farm server", ToastLayer.Severity.ERROR)
	var texts := toasts.queued().map(func(e): return e.text)
	assert_array(texts).contains_exactly(["Can't reach the farm server", "ok 1", "ok 2"])

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
	assert_float(toasts._panel.size.x).is_equal(ToastLayer.WIDTH)
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

extends GdUnitTestSuite
## SysBanner 1187:82581 (WP6; SGODOT-233): ink Offline with Retry, primary Back online, danger-tint CmdFail; 328 × 40.

func _banner(kind: UiSysBanner.Kind) -> UiSysBanner:
	var b: UiSysBanner = auto_free(UiSysBanner.new())
	b.theme = UiKit.theme()
	b.kind = kind
	add_child(b)
	return b

func test_offline_is_ink_with_retry_and_retry_emits() -> void:
	var b := _banner(UiSysBanner.Kind.OFFLINE)
	await get_tree().process_frame
	assert_that([(b.get_theme_stylebox(&"panel") as UiStyleBox).bg_color, b.retry_button().visible]).is_equal([UiTokens.COLOR_TEXT, true])
	assert_float(b.size.y).is_equal(UiSysBanner.HEIGHT)
	var hit := [0]
	b.retry_pressed.connect(func(): hit[0] += 1)
	b.retry_button().pressed.emit()
	assert_int(hit[0]).is_equal(1)

func test_back_online_and_cmd_fail_have_no_retry() -> void:
	var on := _banner(UiSysBanner.Kind.BACK_ONLINE)
	var fail := _banner(UiSysBanner.Kind.CMD_FAIL)
	await get_tree().process_frame
	assert_that([(on.get_theme_stylebox(&"panel") as UiStyleBox).bg_color, on.retry_button().visible]).is_equal([UiTokens.COLOR_PRIMARY, false])
	var box := fail.get_theme_stylebox(&"panel") as UiStyleBox
	assert_that([box.bg_color, box.border_color, fail.retry_button().visible]).is_equal([UiTokens.COLOR_DANGER_TINT, UiTokens.COLOR_DANGER, false])

extends GdUnitTestSuite
## MomentBanner 1226:104630 (SGODOT-233): LevelUp has the gold accent and level disc, Complete the primary accent and a
## check; every empty part hides; the action emits.

func _banner() -> UiMomentBanner:
	var b: UiMomentBanner = auto_free(UiMomentBanner.new())
	b.theme = UiKit.theme()
	add_child(b)
	return b

func test_level_up_shows_its_parts_and_hides_the_empty_ones() -> void:
	var b := _banner()
	b.level = "2"
	b.title = "Fishing Lv 2"
	b.subtitle = "Fine fish now stay on the hook"
	b.rewards = [UiFloatText.pill("+50 Energy", UiFloatText.Tone.ENERGY_GAIN)]
	await get_tree().process_frame
	assert_that([b._accent.color, b._level.text, b._level.visible, b._check.visible]).is_equal(
		[UiTokens.COLOR_QUALITY_GOLD, "2", true, false])
	assert_bool(b._rewards_box.visible).is_true()
	assert_that([b._detail.visible, b._tip.visible, b._action_box.visible]).is_equal([false, false, false])
	assert_float(b.size.x).is_equal(UiMomentBanner.WIDTH)

func test_complete_has_the_primary_accent_and_a_check() -> void:
	var b := _banner()
	b.kind = UiMomentBanner.Kind.COMPLETE
	b.title = "Gather Gloves"
	await get_tree().process_frame
	assert_that([b._accent.color, b._level.visible, b._check.visible]).is_equal([UiTokens.COLOR_PRIMARY, false, true])

func test_the_action_emits() -> void:
	var b := _banner()
	b.action = "Use bait"
	var hit := [0]
	b.action_pressed.connect(func(): hit[0] += 1)
	b._action.activated.emit()
	assert_int(hit[0]).is_equal(1)
	assert_bool(b._action_box.visible).is_true()

extends GdUnitTestSuite
## SystemCard 1237:87229, Wordmark (placeholder) 1187:82582 and Spinner 1237:87185 (WP6; SGODOT-233).

func _card(kind := UiSystemCard.Kind.BLOCKING) -> UiSystemCard:
	var c := UiSystemCard.new(kind)
	add_child(auto_free(c))
	return c

func test_a_blocking_card_has_the_disc_title_body_and_one_primary() -> void:
	var c := _card()
	c.show_card({icon = UiWordmark.SPROUT, title = "Update to keep playing", body = "This version is out of date.", primary = "Update"})
	await get_tree().process_frame
	assert_float(c.size.x).is_equal(UiSystemCard.WIDTH)
	assert_that([c.title.text, c.body.text, c.primary.text, c.primary.visible, c.secondary.visible]).is_equal(
		["Update to keep playing", "This version is out of date.", "Update", true, false])
	assert_that((c.icon_rect.get_parent() as Panel).get_theme_stylebox(&"panel").bg_color).is_equal(UiTokens.COLOR_PRIMARY_TINT)
	var hit := [0]
	c.primary_pressed.connect(func(): hit[0] += 1)
	c.primary.pressed.emit()
	assert_int(hit[0]).is_equal(1)

func test_an_error_card_greys_its_disc_and_hides_what_it_does_not_have() -> void:
	var c := _card(UiSystemCard.Kind.ERROR)
	c.show_card({title = "Couldn't open this place", primary = "Go back"})
	await get_tree().process_frame
	assert_that([c.icon_rect.get_parent().visible, c.body.visible, c.primary.visible]).is_equal([false, false, true])
	assert_that((c.icon_rect.get_parent() as Panel).get_theme_stylebox(&"panel").bg_color).is_equal(UiTokens.COLOR_DISABLED)
	c.show_card({title = "Down for maintenance", body = "We'll be back soon."})   # no button at all
	assert_bool(c.primary.visible).is_false()

func test_the_wordmark_is_the_sprout_and_gensen_in_primary() -> void:
	var w := UiWordmark.new()
	add_child(auto_free(w))
	await get_tree().process_frame
	var name_label := w.get_child(1) as Label
	assert_that([name_label.text, name_label.get_theme_color(&"font_color")]).is_equal(["Gensen", UiTokens.COLOR_PRIMARY_INK])
	assert_float(w.size.x).is_between(130.0, 170.0)   # 148 in the main; the font's width decides the last pixels

func test_a_spinner_held_still_keeps_its_angle_and_a_running_one_turns() -> void:
	var held := UiSpinner.new()
	held.spinning = false
	var running := UiSpinner.new()
	for s in [held, running]: add_child(auto_free(s))
	var start := running.angle
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(held.angle).is_equal(-PI * 0.5)
	assert_float(running.angle).is_not_equal(start)
	assert_that(held.custom_minimum_size).is_equal(Vector2(UiSpinner.SIDE, UiSpinner.SIDE))

## SYS-LOADING-SCENE-FAIL 1780:103778 (不知火舞 on #88): Go back is a CommandButton Kind=secondary, as wide and tall as Retry.
func test_the_secondary_is_a_secondary_command_as_wide_as_the_primary() -> void:
	var c := _card()
	c.show_card({icon = UiWordmark.SPROUT, title = "Couldn't get there", body = "Check your connection and try again.",
		primary = "Retry", secondary = "Go back"})
	await get_tree().process_frame
	assert_object(c.secondary).is_instanceof(UiCommandButton)
	assert_int(c.secondary.kind).is_equal(UiCommandButton.Kind.SECONDARY)
	assert_that([c.secondary.text, c.secondary.size]).is_equal(["Go back", c.primary.size])
	var hit := [0]
	c.secondary_pressed.connect(func(): hit[0] += 1)
	c.secondary.pressed.emit()
	assert_int(hit[0]).is_equal(1)

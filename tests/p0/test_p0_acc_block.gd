extends GdUnitTestSuite
## ACC-AGE-BLOCK (SGODOT-491, spec §1.3, 634:197069): the card at 220, no key and no way back, the Privacy Policy link.

func test_no_key_no_way_back_only_the_policy() -> void:
	var p: P0AccBlock = auto_free(P0AccBlock.new())
	add_child(p)
	p.size = Vector2(360, 800)
	await await_idle_frame()
	assert_float(p.card.position.y).is_equal(220.0)
	assert_array(p.find_children("*", "UiCommandButton", true, false)).is_empty()
	var texts := p.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(texts).contains(["Sorry, you can't play Gensen.", "Thanks for your interest in Gensen."])
	for t in texts: assert_str(str(t)).not_contains("13")
	var said: Array[String] = []
	p.link_pressed.connect(func(w: String): said.append(w))
	var link := p.find_child("Link", true, false) as UiDismissButton
	assert_str(link.text).is_equal("Privacy Policy ›")
	assert_float(link.get_combined_minimum_size().y).is_greater_equal(UiTokens.SIZE_TOUCH)
	link.pressed.emit()
	assert_array(said).is_equal(["privacy"])

extends GdUnitTestSuite
## UiKeeperBar (SGODOT-224; KeeperBar 1143:102525 Layout=Titled, LOCK-16).

func _host(c: Control) -> Control:
	var top := CanvasLayer.new()
	top.layer = 128
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 640)
	top.add_child(host)
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 3: await get_tree().process_frame

func _bar(role := UiKeeperBar.Role.TACKLE) -> UiKeeperBar:
	var b := UiKeeperBar.new(role)
	b.title = "Finn's Tackle"
	b.place = "Xuhui Tackle Shop"
	b.keeper = "Tackle Keeper · Finn"
	b.line = "Worms are 2 coins."
	return _host(b) as UiKeeperBar

func test_titled_layout_matches_the_main() -> void:
	var b := _bar()
	await _settle()
	assert_vector(b.size).is_equal(Vector2(336, 67))   # 1 + 44 header + 18 bubble + 4
	assert_float(b._ring.get_global_rect().position.x - b.get_global_rect().position.x).is_equal(6.0)
	assert_float(b._title.get_global_rect().position.x - b.get_global_rect().position.x).is_equal(54.0)
	assert_float(b._bubble.get_global_rect().position.y - b.get_global_rect().position.y).is_equal(45.0)
	assert_str(b._place.text).is_equal("· Xuhui Tackle Shop")

func test_role_colours_tint_the_bar_ring_and_keeper_line() -> void:
	var b := _bar(UiKeeperBar.Role.TEA)
	assert_str((b.get_theme_stylebox(&"panel") as UiStyleBox).bg_color.to_html()).is_equal(UiTokens.COLOR_ROLE_TEA_TINT.to_html())
	assert_str((b._ring.get_theme_stylebox(&"panel") as UiStyleBox).bg_color.to_html()).is_equal(UiTokens.COLOR_ROLE_TEA.to_html())
	assert_str(b._keeper.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_ROLE_TEA.to_html())
	assert_int(UiKeeperBar.role_of("post")).is_equal(UiKeeperBar.Role.POST)

func test_note_and_empty_line_fold_away_and_close_reports() -> void:
	var b := _bar()
	assert_bool(b._note.visible).is_false()
	b.note = "Shares the 3 cups a day with tea"
	assert_bool(b._note.visible).is_true()
	b.line = ""
	assert_bool(b._bubble.visible).is_false()
	var closed := [0]
	b.close_pressed.connect(func(): closed[0] += 1)
	(b.find_children("*", "UiCloseButton", true, false)[0] as UiCloseButton).pressed.emit()
	assert_int(closed[0]).is_equal(1)

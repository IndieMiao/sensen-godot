extends GdUnitTestSuite
## InboxRow 1309:89969 (C2-01, LOCK-14; SGODOT-234) and the SegmentedTabs marks of the Inbox switch.

func before_test() -> void:
	UiCommandButton.offline = false   # a runtime left by an earlier suite may have gone offline (no server in tests)

func test_an_item_row_claims_and_greys_with_the_bag_full() -> void:
	var row := UiInboxRow.new(UiInboxRow.Kind.ITEM)
	add_child(auto_free(row))
	row.show_row({key = "p1", title = "Perch ×7", sub = "Request reward · Stall Board", left = "23h 40m left", can_claim = true})
	await get_tree().process_frame
	assert_float(row.size.x).is_equal(UiInboxRow.WIDTH)
	assert_that([row.title.text, row.sub.text, row.left_label.text, row.claim.text, row.claim.sends]).is_equal(
		["Perch ×7", "Request reward · Stall Board", "23h 40m left", "Claim", true])
	var got: Array = []
	row.claim_pressed.connect(func(k): got.append(k))
	row.claim.pressed.emit()
	assert_that(got).is_equal(["p1"])
	row.show_row({key = "p1", title = "Perch ×7", can_claim = false})
	assert_that([row.claim.text, row.claim.is_unavailable(), row.sub.visible]).is_equal(["Claim", true, false])

func test_a_system_row_has_its_time_and_unread_dot_and_no_button() -> void:
	var row := UiInboxRow.new(UiInboxRow.Kind.SYSTEM)
	add_child(auto_free(row))
	row.show_row({key = "u1", title = "Parcel expired · +18 coins", sub = "Perch ×7 · turned into coins at 80%", time = "Just now", unread = true})
	await get_tree().process_frame
	assert_that([row.time_label.text, row.unread(), row.claim == null]).is_equal(["Just now", true, true])
	row.show_row({key = "u1", title = "Parcel expired · +18 coins", time = "2h ago", unread = false})
	assert_bool(row.unread()).is_false()

func test_rows_let_a_drag_through_to_the_list() -> void:
	var row := UiInboxRow.new(UiInboxRow.Kind.SYSTEM)
	assert_int(row.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	row.free()

func test_tab_marks_show_a_count_or_a_dot_and_change_in_place() -> void:
	var tabs := UiSegmentTab.new([{label = "To do"}, {label = "Parcels", badge = 3}, {label = "Updates", dot = true}], 1)
	add_child(auto_free(tabs))
	await get_tree().process_frame
	var mark := func(i: int, name: String) -> Control: return tabs.tabs()[i].get_child(0).get_node(name) as Control
	assert_that([mark.call(0, "Badge").visible, mark.call(1, "Badge").visible, mark.call(2, "Dot").visible]).is_equal([false, true, true])
	assert_str((mark.call(1, "Badge").get_node("Number") as Label).text).is_equal("3")
	tabs.set_marks(1, 0, false)
	tabs.set_marks(2, 0, false)
	assert_that([mark.call(1, "Badge").visible, mark.call(2, "Dot").visible]).is_equal([false, false])
	tabs.selected = 2   # recolouring the labels leaves the marks alone
	assert_that((mark.call(1, "Badge") as PanelContainer).get_theme_stylebox(&"panel").bg_color).is_equal(UiTokens.COLOR_UNREAD_BADGE)

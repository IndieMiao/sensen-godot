extends GdUnitTestSuite
## UiBoardCard (SGODOT-224; Compact/Information row on BOARD-READY 1498:96193 / SHORT 1498:96574 / DONE 1498:96382).

const FISH := preload("res://assets/p0/icons/fish_crucian.svg")

func _host(c: Control) -> Control:
	var top := CanvasLayer.new()
	add_child(auto_free(top))
	var root := Control.new()
	root.theme = UiKit.theme()
	root.size = Vector2(312, 800)
	top.add_child(root)
	root.add_child(c)
	return c

func _row(extra := {}) -> Dictionary:
	return {id = "m1", title = "Dusk Haul", info = true, status = "Tracked", facts = ["4 Fine fish · any kind"],
		reward = "36 coins", needs = [{id = "fish_crucian", name = "Fine fish", have = 3, need = 4, icon = FISH}],
		command = "Deliver", reason = "Need 1 more Fine fish"}.merged(extra, true)

func test_a_row_reads_title_status_facts_reward_needs_and_one_command() -> void:
	var c := _host(UiBoardCard.new()) as UiBoardCard
	c.show_request(_row())
	await await_idle_frame()
	assert_str(c._title.text).is_equal("Dusk Haul")
	assert_bool(c._chevron.visible).is_true()
	assert_str(c._status.text).is_equal("Tracked")
	assert_array(c._facts.get_children().map(func(l): return (l as Label).text)).is_equal(["4 Fine fish · any kind"])
	assert_str(c._reward.text).is_equal("36 coins")
	assert_int(c.need_tiles().size()).is_equal(1)
	assert_int((c.need_tiles()[0] as UiNeedTile).size_class).is_equal(UiNeedTile.Size.S)
	var b := c.command_button()
	assert_bool(b.compact).is_true()
	assert_float(b.custom_minimum_size.x).is_equal(152.0)
	assert_bool(b.is_unavailable()).is_true()   # the gap on the button (LOCK-10)
	assert_str(b.reason).is_equal("Need 1 more Fine fish")
	assert_str(c.get_class()).is_equal("VBoxContainer")   # no card surface or edge: a column on the sheet

func test_done_keeps_the_reward_and_drops_needs_and_button() -> void:
	var c := _host(UiBoardCard.new()) as UiBoardCard
	c.show_request(_row({status = "Done", done = true}))
	assert_str(c._status.text).is_equal("Done")
	assert_bool(c._reward_row.visible).is_true()
	assert_bool(c._needs.visible).is_false()
	assert_bool(c.command_button().visible).is_false()

func test_the_title_line_opens_the_request_only_with_info() -> void:
	var c := _host(UiBoardCard.new()) as UiBoardCard
	var opened := []
	c.info_pressed.connect(func(): opened.append(true))
	c.show_request(_row({info = false}))
	assert_bool(c._chevron.visible).is_false()
	assert_int(c._title_line.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	c.show_request(_row())
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	c._title_line.gui_input.emit(up)
	assert_array(opened).is_equal([true])

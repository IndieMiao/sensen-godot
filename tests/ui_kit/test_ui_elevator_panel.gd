extends GdUnitTestSuite
## UiElevatorPanel (ElevatorPanel 1230:107860 / ElevatorRow 1230:107859, LOCK-21; SGODOT-235 B3).

const S := UiElevatorPanel.State

func _host(c: Control) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 640)
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _panel() -> UiElevatorPanel:
	return _host(UiElevatorPanel.new("Elevator · stops this run", [
		{"floor": "Entrance", "value": "Free", "state": S.FREE},
		{"floor": "Floor 1", "value": "Here", "state": S.HERE},
		{"floor": "Floor 2", "value": "Clear Floor 1 first", "state": S.LOCKED},
		{"floor": "Floor 2", "value": "Need 2 Energy", "state": S.SHORT}])) as UiElevatorPanel

func _texts(b: Button) -> Array:
	return b.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)

func test_lays_out_title_and_one_row_per_stop() -> void:
	var p := _panel()
	assert_str(p._title.text).is_equal("Elevator · stops this run")
	assert_that(_texts(p.row(0))).is_equal(["Entrance", "Free"])
	assert_that(_texts(p.row(2))).is_equal(["Floor 2", "Clear Floor 1 first"])
	assert_float(p.custom_minimum_size.x).is_equal(UiElevatorPanel.WIDTH)
	assert_float(p.row(0).custom_minimum_size.y).is_equal(44.0)

func test_state_colours_follow_the_row_states() -> void:
	var p := _panel()
	var value := func(i: int) -> Color: return (p.row(i).find_children("*", "Label", true, false)[1] as Label).get_theme_color(&"font_color")
	assert_that(value.call(0)).is_equal(UiTokens.COLOR_PRIMARY_INK) # Free
	assert_that(value.call(1)).is_equal(UiTokens.COLOR_SECONDARY)   # Here
	assert_that(value.call(2)).is_equal(UiTokens.COLOR_SECONDARY)   # Locked
	assert_that(value.call(3)).is_equal(UiTokens.COLOR_WARNING)     # Short

func test_rows_travel_locked_rows_say_why_and_here_is_not_a_button() -> void:
	var p := _panel()
	var went: Array = []
	var why: Array = []
	p.row_pressed.connect(func(i): went.append(i))
	p.unavailable_pressed.connect(func(i): why.append(i))
	p.row(0).pressed.emit()
	p.row(2).pressed.emit()
	p.row(3).pressed.emit()
	assert_that(went).is_equal([0, 3])
	assert_that(why).is_equal([2])
	assert_int(p.row(1).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

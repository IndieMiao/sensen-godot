extends GdUnitTestSuite
## UiInfoSheet.layered (不知火舞 on 224, §4.8.7): a card over another panel sits on a color/scrimModal veil; a tap
## on the veil closes it and removes the layer. Docked cards (bag, counter) have no veil.

func _host() -> Control:
	var top := CanvasLayer.new()
	add_child(auto_free(top))
	var root := Control.new()
	root.theme = UiKit.theme()
	root.size = Vector2(360, 800)
	top.add_child(root)
	return root

func test_a_layered_card_dims_the_panel_below_and_a_tap_on_the_veil_closes_it() -> void:
	var host := _host()
	var sheet := UiInfoSheet.layered(host)
	sheet.rules = func(id: String, _c: StringName, _o: Dictionary) -> Dictionary: return {id = id, title = "Pond Crucian"}
	sheet.open("fish_crucian", &"bag")
	await await_idle_frame()
	var veil := sheet.scrim()
	assert_object(veil).is_not_null()
	assert_object(veil.color).is_equal(UiTokens.COLOR_SCRIM_MODAL)
	assert_float(sheet.get_global_rect().end.y).is_equal_approx(800.0 - 16.0, 1.0)   # at the bottom, inside the inset
	var layer: Control = veil.get_parent()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	layer.gui_input.emit(up)
	assert_bool(sheet.is_open()).is_false()
	await await_idle_frame()
	assert_bool(is_instance_valid(layer)).is_false()

func test_a_docked_card_has_no_veil() -> void:
	var host := _host()
	var sheet := UiInfoSheet.new()
	host.add_child(sheet)
	assert_object(sheet.scrim()).is_null()

extends GdUnitTestSuite
## ModalStack: one drawer + one card, back closes the top layer only (SGODOT-211, WP7-B F-04 §5).

var stack: ModalStack

func before_test() -> void:
	stack = ModalStack.new()
	stack.size = Vector2(360, 800)
	add_child(auto_free(stack))

func _panel(n: String) -> Control:
	var c := PanelContainer.new()
	c.name = n
	return c

func _release() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	return e

func test_back_closes_card_first_then_drawer_then_reports_nothing() -> void:
	var bag := _panel("Bag")
	stack.open_drawer(bag)
	stack.open_card(_panel("Detail"))
	assert_bool(stack.back()).is_true()
	assert_bool(stack.has_card()).is_false()
	assert_object(stack.drawer()).is_same(bag)   # the drawer keeps its selection and scroll
	assert_bool(stack.back()).is_true()
	assert_bool(stack.is_empty()).is_true()
	assert_bool(stack.back()).is_false()

func test_new_drawer_replaces_drawer_and_closes_card() -> void:
	stack.open_drawer(_panel("Bag"))
	stack.open_card(_panel("Detail"))
	var counter := _panel("Counter")
	stack.open_drawer(counter)
	assert_object(stack.drawer()).is_same(counter)
	assert_bool(stack.has_card()).is_false()

func test_new_card_replaces_only_the_card() -> void:
	var bag := _panel("Bag")
	stack.open_drawer(bag)
	stack.open_card(_panel("Detail"))
	var energy := _panel("Energy")
	stack.open_card(energy)
	assert_object(stack.card()).is_same(energy)
	assert_object(stack.drawer()).is_same(bag)

func test_scrim_tap_closes_the_top_layer_only() -> void:
	stack.open_drawer(_panel("Bag"))
	stack.open_card(_panel("Detail"))
	stack.get_node("ScrimCard").gui_input.emit(_release())
	assert_bool(stack.has_card()).is_false()
	assert_bool(stack.has_drawer()).is_true()
	stack.get_node("ScrimDrawer").gui_input.emit(_release())
	assert_bool(stack.is_empty()).is_true()

func test_scrim_can_be_made_inert() -> void:
	stack.open_card(_panel("Greeting"), {scrim_closes = false})
	stack.get_node("ScrimCard").gui_input.emit(_release())
	assert_bool(stack.has_card()).is_true()

func test_scrim_uses_the_scrim_tokens() -> void:
	stack.open_drawer(_panel("Bag"))
	stack.open_card(_panel("Detail"))
	assert_float((stack.get_node("ScrimDrawer") as ColorRect).color.a).is_equal_approx(UiTokens.OPACITY_SCRIM_DRAWER, 0.01)
	assert_float((stack.get_node("ScrimCard") as ColorRect).color.a).is_equal_approx(UiTokens.OPACITY_SCRIM_MODAL, 0.01)

func test_android_back_request_closes_the_top_layer() -> void:
	stack.open_drawer(_panel("Bag"))
	stack.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_bool(stack.is_empty()).is_true()

func test_close_callbacks_and_signals_fire_once_per_layer() -> void:
	var calls := []
	var signals := []
	stack.closed.connect(func(layer, _c): signals.append(layer))
	stack.open_drawer(_panel("Bag"), {on_close = func(): calls.append("bag")})
	stack.open_card(_panel("Detail"), {on_close = func(): calls.append("detail")})
	stack.close_all()
	assert_array(calls).contains_exactly(["detail", "bag"])
	assert_array(signals).contains_exactly([ModalStack.Layer.CARD, ModalStack.Layer.DRAWER])

func test_empty_stack_lets_input_through() -> void:
	assert_int(stack.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

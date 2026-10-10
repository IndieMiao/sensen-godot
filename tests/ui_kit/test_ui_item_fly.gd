extends GdUnitTestSuite
## ItemFly (Figma 1226:104639, Count ×N on SGODOT-289): a flight from a point to a control, ×N on its pill, never taking
## input; none when the target is gone or hidden (the Bag under a drawer, q(49)); the landing calls back and bumps.

func _host() -> Control:
	var host := Control.new()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	return host

func test_a_flight_lands_on_its_target_and_calls_back() -> void:
	var host := _host()
	var target := Control.new()
	target.position = Vector2(20, 100)
	target.size = Vector2(120, 28)
	host.add_child(target)
	var landed := [0]
	var f := UiItemFly.launch(host, Vector2(200, 400), target, P0Logic.icon("fish_carp"), 2, 0.0, func(): landed[0] += 1)
	assert_object(f).is_not_null()
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_str(f.count_text()).is_equal("×2")
	assert_str((f.find_child("Text", true, false) as Label).text).is_equal("×2")
	await get_tree().create_timer(UiItemFly.FLIGHT_S + 0.2).timeout   # past FLIGHT_S
	await get_tree().process_frame
	assert_int(landed[0]).is_equal(1)
	assert_bool(is_instance_valid(f)).is_false()   # gone once landed

func test_no_flight_to_a_hidden_or_missing_target() -> void:
	var host := _host()
	var target := Control.new()
	host.add_child(target)
	target.hide()
	assert_object(UiItemFly.launch(host, Vector2.ZERO, target, null)).is_null()
	assert_object(UiItemFly.launch(host, Vector2.ZERO, null, null)).is_null()

func test_a_delayed_flight_waits_unseen_and_the_bump_returns_to_size() -> void:
	var host := _host()
	var target := Control.new()
	target.size = Vector2(100, 28)
	host.add_child(target)
	var f := UiItemFly.launch(host, Vector2(200, 400), target, null, 1, UiItemFly.DELAY_STEP_S * 2)
	assert_bool(f.visible).is_false()
	assert_str(f.count_text()).is_equal("×1")   # shown for ×1 too
	UiItemFly.bump(target)
	assert_vector(target.pivot_offset).is_equal(Vector2(50, 14))
	await get_tree().create_timer(UiItemFly.BUMP_S + 0.1).timeout
	assert_vector(target.scale).is_equal_approx(Vector2.ONE, Vector2.ONE * 0.001)

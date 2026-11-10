extends GdUnitTestSuite
## SGODOT-480 (不知火舞's spec v1, 480 f104605d; the user: 「上钩的时候把hook按钮的效果做的更明显一些，加一些动效」): the
## fishing key stands out while a fish is on — solid primary with white words, a pop, a breath and a ring — and is the
## plain key again the moment the bite ends. Its place, size and tap area never change; q(219)'s sure bite pops again.

const FishingAction := preload("res://scenes/fishing/fishing_action.gd")

func _key() -> Button:
	var host := Control.new()
	host.theme = GameUi.theme()
	add_child(auto_free(host))
	var key: Button = FishingAction.new()
	key.theme_type_variation = &"AccentButton"
	key.text = "Hook"
	host.add_child(key)
	key.size = Vector2(84, 84)
	key.position = Vector2(138, 600)
	key.set_process(false)   # the tests drive it (step)
	return key

func test_a_fish_on_paints_the_key_solid_primary_with_white_words() -> void:
	var key := _key()
	var plain := (key.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color
	key.hook(true)
	assert_bool(key.hooking).is_true()
	assert_object((key.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color).is_equal(UiTokens.COLOR_PRIMARY)
	assert_object(key.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SURFACE)
	assert_object(key.get_theme_color(&"icon_normal_color")).is_equal(UiTokens.COLOR_SURFACE)
	key.hook(false)
	assert_object((key.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color).is_equal(plain)
	assert_object(key.get_theme_color(&"font_color")).is_equal(GameUi.INK)

func test_it_pops_then_breathes_and_rings() -> void:
	var key := _key()
	key.hook(true)
	key.step(0.08)
	assert_float(key.scale.x).is_greater(1.12)   # going up to the pop's 1.18
	assert_float(absf((key.icon as FishingAction.SwingIcon).angle)).is_greater(0.0)   # the fish swings
	for i in 3: key.step(0.08)
	assert_float(key.scale.x).is_less_equal(FishingAction.BREATH_SCALE + 0.001)   # the pop over: the breath alone
	assert_float((key.icon as FishingAction.SwingIcon).angle).is_equal(0.0)
	var ring: Control = key.get_node("HookRing")
	assert_bool(ring.show_behind_parent).is_true()
	assert_int(ring.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)   # it takes no taps
	key.step(0.1)   # past the first breath's top (0.3 s)
	assert_bool(ring.visible).is_true()
	assert_float(FishingAction.breath_scale(0.3)).is_equal_approx(FishingAction.BREATH_SCALE, 0.0001)
	assert_vector(FishingAction.ring_at(0.3)).is_equal_approx(Vector2(0, FishingAction.RING_ALPHA), Vector2.ONE * 0.0001)
	assert_float(FishingAction.ring_at(0.6).x).is_equal_approx(FishingAction.RING_PX * 0.5, 0.0001)
	assert_float(FishingAction.pop_scale(0.35)).is_equal_approx(FishingAction.POP_SCALE, 0.0001)

func test_the_tap_area_is_the_key_as_laid_out() -> void:
	var key := _key()
	key.hook(true)
	key.pivot_offset = key.size * 0.5
	key.scale = Vector2.ONE * FishingAction.POP_SCALE
	# local points: a point drawn just past the key's edge at 1.18× is outside the laid-out key, one inside is inside
	assert_bool(key._has_point(key.pivot_offset + Vector2(43, 0) / key.scale.x)).is_false()
	assert_bool(key._has_point(key.pivot_offset + Vector2(41, 0) / key.scale.x)).is_true()

func test_hooked_or_gone_it_is_the_plain_key_at_once() -> void:
	var key := _key()
	key.hook(true)
	for i in 5: key.step(0.1)
	key.hook(false)
	assert_object(key.scale).is_equal(Vector2.ONE)
	assert_bool(key.get_node("HookRing").visible).is_false()
	assert_float((key.icon as FishingAction.SwingIcon).angle).is_equal(0.0)
	assert_bool(key.is_processing()).is_false()

func test_a_sure_bite_pops_again_every_two_and_a_half_seconds() -> void:
	var key := _key()
	key.hook(true, true)
	key.step(2.4)
	assert_float(key._pop_t).is_less(0.0)   # the first pop long over
	key.step(0.11)
	assert_float(key._pop_t).is_greater_equal(0.0)   # 2.5 s: again
	var plain := _key()
	plain.hook(true, false)
	plain.step(2.4)
	plain.step(0.11)
	assert_float(plain._pop_t).is_less(0.0)   # an ordinary bite: once (its window is 2.2 s anyway)

func test_the_panel_sets_it_by_its_phase() -> void:
	var panel := P0FishingPanel.new()
	add_child(auto_free(panel))
	panel.set_process(false)
	panel.show()
	var key: Button = panel._primary
	panel.phase = "waiting"
	panel._refresh_button()
	assert_bool(key.hooking).is_false()
	panel.phase = "hook"
	panel._sure = true
	panel._refresh_button()
	assert_bool(key.hooking).is_true()
	assert_bool(key.repop).is_true()
	panel.phase = "playing"   # hooked: Reel
	panel._refresh_button()
	assert_bool(key.hooking).is_false()
	panel.phase = "hook"
	panel._sure = false
	panel._refresh_button()
	assert_bool(key.repop).is_false()
	panel.phase = "settling"   # got away
	panel._refresh_button()
	assert_bool(key.hooking).is_false()

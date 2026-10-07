extends GdUnitTestSuite
## UiSceneAction, UiActionKey and UiActionRadial (SGODOT-221, LOCK-02 / 03; WP7-B F-04 / F-08).

const HOE := preload("res://assets/p0/icons/hoe.svg")
const ROD := preload("res://assets/p0/icons/rod.svg")
const S := UiSceneAction.State

func _host(c: Control) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 640)
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 2: await get_tree().process_frame

func _mouse(pos: Vector2, down: bool) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = pos
	m.global_position = pos
	m.pressed = down
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	return m

# ---------------------------------------------------------------- main key

func test_key_is_88_and_hides_an_empty_price() -> void:
	var k := _host(UiSceneAction.new()) as UiSceneAction
	k.verb = "Till"
	k.cost = ""   # LOCK-02: zero-Energy actions carry no price
	assert_vector(k.size).is_equal(Vector2(UiTokens.SIZE_SCENE_ACTION, UiTokens.SIZE_SCENE_ACTION))
	assert_bool(k._cost.visible).is_false()
	k.cost = "2 Energy"
	assert_bool(k._cost.visible).is_true()

func test_fires_on_touch_down_and_releases_on_lift() -> void:
	var k := _host(UiSceneAction.new()) as UiSceneAction
	var log := []
	k.pressed_down.connect(func(): log.append("down"))
	k.released.connect(func(): log.append("up"))
	k._gui_input(_mouse(Vector2(44, 44), true))
	assert_bool(k.is_held()).is_true()
	assert_int(k.drawn_state()).is_equal(S.PRESSED)
	k._gui_input(_mouse(Vector2(44, 44), true))   # a second contact while held is ignored
	k._gui_input(_mouse(Vector2(44, 44), false))
	assert_array(log).contains_exactly(["down", "up"])
	assert_int(k.drawn_state()).is_equal(S.DEFAULT)

func test_hiding_the_key_mid_hold_releases_it() -> void:
	var k := _host(UiSceneAction.new()) as UiSceneAction
	var ups := [0]
	k.released.connect(func(): ups[0] += 1)
	k._gui_input(_mouse(Vector2(44, 44), true))
	k.visible = false
	assert_bool(k.is_held()).is_false()
	assert_int(ups[0]).is_equal(1)

func test_states_and_their_ink() -> void:
	var k := _host(UiSceneAction.new()) as UiSceneAction
	k.verb = "Sow ×1"
	k.cost = "Need 2 Energy"
	k.state = S.INSUFFICIENT
	assert_object(k._cost.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_TEXT)
	k.state = S.UNAVAILABLE
	assert_object(k._verb.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	k.state = S.PENDING
	assert_float(k.modulate.a).is_equal_approx(UiTokens.OPACITY_SCENE_ACTION_PENDING, 0.001)
	assert_bool(k.is_processing()).is_true()   # the spinner turns
	k.state = S.HOLDING
	k.hold_progress = 1.7
	assert_float(k.hold_progress).is_equal(1.0)
	assert_float(k.modulate.a).is_equal(1.0)
	assert_bool(k.is_processing()).is_false()

# ---------------------------------------------------------------- group

func test_group_matches_the_actionkey_main() -> void:
	var g := _host(UiActionKey.new()) as UiActionKey
	g.tool_icon = HOE
	assert_vector(g.size).is_equal(Vector2(95, 148))
	assert_vector(g.switch_button().position).is_equal(Vector2(27, 0))
	assert_vector(g.switch_button().size).is_equal(Vector2(UiTokens.SIZE_SWITCH_KEY, UiTokens.SIZE_SWITCH_KEY))
	assert_vector(g.key().position).is_equal(Vector2(7, 60))
	assert_vector(g.tool_badge().position).is_equal(Vector2(0, 54))
	assert_int(g.tool_badge().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	g.tool_icon = null
	assert_bool(g.tool_badge().visible).is_false()

func test_switch_key_opens_the_radial_and_the_tool_badge_never_steals_the_key() -> void:
	var g := _host(UiActionKey.new()) as UiActionKey
	g.tool_icon = ROD
	g.position = Vector2(20, 20)
	await _settle()
	var log := []
	g.switch_pressed.connect(func(): log.append("switch"))
	g.key().pressed_down.connect(func(): log.append("key"))
	g.switch_button().pressed.emit()
	# Real routing: a press on the tool badge's area lands on the main key (A-08: the badge used to cover it).
	var at := g.tool_badge().get_global_rect().get_center() + Vector2(6, 6)
	get_viewport().push_input(_mouse(at, true), true)
	get_viewport().push_input(_mouse(at, false), true)
	await _settle()
	assert_array(log).contains_exactly(["switch", "key"])

# ---------------------------------------------------------------- radial

func _options() -> Array:
	return [
		{id = "farming", name = "Farming", icon = HOE, available = true},
		{id = "fishing", name = "Fishing", icon = ROD, available = false, reason = "No water nearby"},
		{id = "mining", name = "Mining", icon = HOE, available = false, reason = "Not in a mine"},
		{id = "combat", name = "Combat", icon = HOE, available = false, reason = "No enemies here"},
	]

func _radial() -> UiActionRadial:
	var r := UiActionRadial.new()
	_host(r)
	r.size = Vector2(360, 640)
	r.options = _options()
	r.selected = "farming"
	return r

func test_fan_follows_bar_2_and_mirrors_on_the_right() -> void:
	var r := _radial()
	r.open_at(Vector2(82.5, 425))
	await _settle()
	assert_bool(r.is_mirrored()).is_false()
	# BAR-2 482:23 petal centres: Farming (123, 334), Fishing (175, 388), Mining (175, 462), Combat (123, 516).
	var expected := [Vector2(123, 334), Vector2(175, 388), Vector2(175, 462), Vector2(123, 516)]
	for i in 4: assert_vector(r.petal_center(i)).is_equal_approx(expected[i], Vector2(1.5, 1.5))
	assert_float(r._labels[0].position.x).is_greater(r.petal_center(0).x)
	r.open_at(Vector2(300, 425))
	await _settle()
	assert_bool(r.is_mirrored()).is_true()
	assert_float(r._labels[0].position.x + r._labels[0].size.x).is_less(r.petal_center(0).x)

func test_available_petal_picks_and_closes_unavailable_does_nothing() -> void:
	var r := _radial()
	r.open_at(Vector2(82.5, 425))
	var log := []
	r.picked.connect(func(id): log.append(id))
	r.closed.connect(func(): log.append("closed"))
	r.petals()[1].pressed.emit()   # Fishing · No water nearby
	assert_bool(r.visible).is_true()
	r.petals()[0].pressed.emit()
	assert_array(log).contains_exactly(["farming", "closed"])
	assert_bool(r.visible).is_false()

func test_tapping_the_scrim_closes_without_picking() -> void:
	var r := _radial()
	r.open_at(Vector2(82.5, 425))
	var log := []
	r.picked.connect(func(id): log.append(id))
	r.closed.connect(func(): log.append("closed"))
	r._on_scrim_input(_mouse(Vector2(300, 100), false))
	assert_array(log).contains_exactly(["closed"])

func test_unavailable_petal_shows_lock_and_reason() -> void:
	var r := _radial()
	r.open_at(Vector2(82.5, 425))
	await _settle()
	assert_int(r.petals()[1].get_child_count()).is_equal(2)   # icon + lock badge
	assert_int(r.petals()[0].get_child_count()).is_equal(1)
	var texts := []
	for l in r._labels[1].get_child(0).get_children(): texts.append((l as Label).text)
	assert_array(texts).contains_exactly(["Fishing", "No water nearby"])

func test_labels_match_the_petal_main_once_themed() -> void:
	# RadialPetal 1122:79385: label 77 × 31 (name only) and 116 × 47 (name + reason).
	var r := UiActionRadial.new()
	r.options = _options()   # built before entering the tree: labels must re-measure with the theme
	r.selected = "farming"
	r.open_at(Vector2(82.5, 425))
	_host(r)
	r.size = Vector2(360, 640)
	await _settle()
	assert_vector(r._labels[0].size).is_equal_approx(Vector2(77, 31), Vector2(4, 3))
	assert_vector(r._labels[1].size).is_equal_approx(Vector2(116, 47), Vector2(6, 3))
	assert_float(r._labels[0].position.x).is_equal_approx(r.petal_center(0).x + 26 + 6, 0.5)

func test_caption_counts_in_the_group_height() -> void:
	var g := _host(UiActionKey.new()) as UiActionKey
	assert_float(g.get_combined_minimum_size().y).is_equal(148.0)
	g.caption = "uses your Energy"
	assert_float(g.get_combined_minimum_size().y).is_equal(168.0)

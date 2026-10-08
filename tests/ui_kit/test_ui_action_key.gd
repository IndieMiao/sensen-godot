extends GdUnitTestSuite
## UiSceneAction, UiActionKey and UiActionRadial (SGODOT-221, LOCK-02 / 03; WP7-B F-04 / F-08).

const HOE := preload("res://assets/p0/icons/hoe.svg")
const ROD := preload("res://assets/p0/icons/rod.svg")
const S := UiSceneAction.State

func _host(c: Control) -> Control:
	# On the top canvas layer: tests/scenes leaks a MapPoc whose HUD would take pushed presses in a full run.
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

func test_long_copy_steps_its_font_down_instead_of_clipping() -> void:
	var k := _host(UiSceneAction.new()) as UiSceneAction
	await _settle()
	var room := UiTokens.SIZE_SCENE_ACTION - 8.0
	for text in ["Need 2 Energy", "Ready in 3h 59m", "Walk to a plot"]:
		k.cost = text
		var font := k._cost.get_theme_font(&"font")
		var fs := k._cost.get_theme_font_size(&"font_size")
		assert_float(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x).is_less_equal(room)
		assert_int(fs).is_greater_equal(UiSceneAction._MIN_FONT)
		assert_str(k._cost.text).is_equal(text)   # the whole copy, no ellipsis
	k.cost = "2 Energy"
	assert_int(k._cost.get_theme_font_size(&"font_size")).is_equal(12)   # short copy keeps the style size

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
		{id = "mining", name = "Mining", icon = HOE, available = false, reason = "Enter the mine"},
		{id = "combat", name = "Combat", icon = HOE, available = false, reason = "Mine floors 3–5"},
	]

func _radial() -> UiActionRadial:
	var r := UiActionRadial.new()
	_host(r)
	r.size = Vector2(360, 800)
	r.haptics = false
	r.options = _options()
	r.selected = "farming"
	return r

func _open(r: UiActionRadial) -> void:
	r.open()
	r.advance(1000.0)   # past the whole opening

func test_four_petals_ring_the_screen_centre_icon_only() -> void:
	# 247 / LOCK-03 v2 (P1 1651:100657): centre (180, 400), radius 88, -135 / -45 / 45 / 135°; no labels, no connector.
	var r := _radial()
	_open(r)
	assert_vector(r.ring_center()).is_equal(Vector2(180, 400))
	var expected := [Vector2(117.78, 337.78), Vector2(242.22, 337.78), Vector2(242.22, 462.22), Vector2(117.78, 462.22)]
	for i in 4:
		assert_vector(r.petal_center(i)).is_equal_approx(expected[i], Vector2(0.05, 0.05))
		assert_vector(r.petals()[i].get_rect().get_center()).is_equal_approx(expected[i], Vector2(0.05, 0.05))
		assert_vector(r.petals()[i].size).is_equal_approx(Vector2(72, 72), Vector2(0.01, 0.01))   # every petal takes a 72 px tap
	for b in r.petals():
		for c in b.get_children(): assert_bool(c is Label).is_false()
	# Current: solid primary 72 with a white icon 38; others 64 with a 34 icon; unavailable ones carry the lock.
	var cur: UiStyleBox = r.petals()[0].get_theme_stylebox(&"normal")
	assert_object(cur.bg_color).is_equal(UiTokens.COLOR_PRIMARY)
	assert_float(cur.border_width).is_equal(float(UiTokens.STROKE_RADIAL_SELECTED))
	assert_vector(r.petals()[0].get_node("Icon").size).is_equal(Vector2(38, 38))
	assert_object(r.petals()[0].get_node("Icon").material).is_not_null()
	var other: UiStyleBox = r.petals()[1].get_theme_stylebox(&"normal")
	assert_object(other.bg_color).is_equal(UiTokens.COLOR_SURFACE)
	assert_float(other.inset.x).is_equal(4.0)   # 64 drawn inside the 72 hit
	assert_vector(r.petals()[1].get_node("Icon").size).is_equal(Vector2(34, 34))
	assert_object(r.petals()[1].get_node_or_null("Lock")).is_not_null()
	assert_object(r.petals()[0].get_node_or_null("Lock")).is_null()

func test_petals_fly_out_clockwise_40_ms_apart() -> void:
	# P3 1651:100816: at 80 ms Farming 44 %, Fishing 22 %, the others not out yet, the scrim 67 %.
	var r := _radial()
	r.pose_opening(80.0)
	assert_float(r.progress(0)).is_equal_approx(0.444, 0.005)
	assert_float(r.progress(1)).is_equal_approx(0.222, 0.005)
	assert_float(r.progress(2)).is_equal(0.0)
	assert_float(r.progress(3)).is_equal(0.0)
	assert_float(r.scrim_alpha()).is_equal_approx(0.667, 0.005)
	assert_float(r.petals()[2].modulate.a).is_equal(0.0)
	assert_vector(r.petals()[2].get_rect().get_center()).is_equal_approx(r.ring_center(), Vector2(0.01, 0.01))
	assert_float(r.petals()[0].scale.x).is_greater(0.3)
	r.advance(220.0)   # 300 ms: every petal is out
	for i in 4: assert_float(r.progress(i)).is_equal(1.0)

func test_an_available_petal_picks_pops_and_closes() -> void:
	var r := _radial()
	_open(r)
	var log := []
	r.picked.connect(func(id): log.append(id))
	r.closed.connect(func(): log.append("closed"))
	r.petals()[0].pressed.emit()   # Farming, the current action: same feedback, it just closes
	assert_array(log).is_equal(["farming"])
	assert_bool(r.is_open()).is_false()
	r.advance(75.0)
	assert_float(r.petals()[0].scale.x).is_greater(1.1)   # mid-pop
	assert_float(r.petals()[1].scale.x).is_less(1.0)      # the others shrink back
	r.advance(100.0)
	assert_array(log).is_equal(["farming", "closed"])
	assert_bool(r.visible).is_false()

func test_an_unavailable_petal_shakes_and_says_why_at_the_centre() -> void:
	# P2 1651:100787: ±6 px twice, RadialReason at the ring centre for 1.5 s, tail towards that petal; stays open.
	var r := _radial()
	_open(r)
	var log := []
	r.picked.connect(func(id): log.append(id))
	r.petals()[3].pressed.emit()   # Combat · Mine floors 3–5
	assert_array(log).is_empty()
	assert_bool(r.is_open()).is_true()
	assert_bool(r.reason_visible()).is_true()
	assert_str(r.reason_text()).is_equal("Mine floors 3–5")
	assert_int(r.reason_tail()).is_equal(UiActionRadial.Tail.DOWN_LEFT)
	await await_idle_frame()
	assert_vector(r._reason.get_rect().get_center()).is_equal_approx(r.ring_center(), Vector2(1, 1))
	# RadialReason 1655:101164: 109 × 28 for "Mine floors 3–5" (Caption 12, padding 11 / 6), clear of the petals.
	assert_vector(r._reason.size).is_equal_approx(Vector2(109, 28), Vector2(6, 2))
	var lower := r.petals()[3].get_rect().get_center().y - UiTokens.SIZE_RADIAL_PETAL * 0.5
	assert_float(r._reason.get_rect().end.y + 7.0).is_less(lower)   # bubble plus its tail stay above the lower petals
	r.advance(25.0)
	assert_float(absf(r.petals()[3].get_rect().get_center().x - r.petal_center(3).x)).is_greater(3.0)   # shaking
	r.advance(200.0)
	assert_vector(r.petals()[3].get_rect().get_center()).is_equal_approx(r.petal_center(3), Vector2(0.01, 0.01))
	r.petals()[1].pressed.emit()   # Fishing: the bubble moves on, its tail now up-right
	assert_int(r.reason_tail()).is_equal(UiActionRadial.Tail.UP_RIGHT)
	r.advance(UiTokens.MOTION_RADIAL_REASON_MS + 250.0)
	assert_bool(r.reason_visible()).is_false()
	assert_bool(r.is_open()).is_true()

func test_tapping_the_scrim_closes_without_picking() -> void:
	var r := _radial()
	_open(r)
	var log := []
	r.picked.connect(func(id): log.append(id))
	r.closed.connect(func(): log.append("closed"))
	r._on_scrim_input(_mouse(Vector2(300, 100), false))
	assert_bool(r.is_open()).is_false()
	assert_int(r._scrim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)   # the scene is live again at once
	r.advance(UiTokens.MOTION_RADIAL_RETRACT_MS + 1.0)
	assert_array(log).is_equal(["closed"])
	for i in 4: assert_vector(r.petals()[i].get_rect().get_center()).is_equal_approx(r.ring_center(), Vector2(0.01, 0.01))

func test_caption_counts_in_the_group_height() -> void:
	var g := _host(UiActionKey.new()) as UiActionKey
	assert_float(g.get_combined_minimum_size().y).is_equal(148.0)
	g.caption = "uses your Energy"
	assert_float(g.get_combined_minimum_size().y).is_equal(168.0)

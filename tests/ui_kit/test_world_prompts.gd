extends GdUnitTestSuite
## World prompts (SGODOT-250, LOCK-07 v2 / LOCK-16 v2): UiWorldIconButton 1674:101157, UiWorldNameBar 1674:101190,
## UiNpcNameTag 1674:101195.

const HOME := preload("res://assets/p0/icons/home.svg")

func _host(c: Control) -> Control:
	var top := CanvasLayer.new()
	top.layer = 128
	add_child(auto_free(top))
	var root := Control.new()
	root.theme = UiKit.theme()
	root.size = Vector2(360, 800)
	top.add_child(root)
	root.add_child(c)
	return c

func test_icon_button_is_28_inside_a_44_touch_area() -> void:
	var b := _host(UiWorldIconButton.new()) as UiWorldIconButton
	b.icon = HOME
	b.place_at(Vector2(100, 200))
	await await_idle_frame()
	assert_vector(b.size).is_equal(Vector2(44, 44))
	assert_vector(b.hit_rect().get_center()).is_equal_approx(Vector2(100, 200), Vector2(0.01, 0.01))
	assert_vector(b._disc.size).is_equal(Vector2(28, 28))
	assert_vector(b._disc.get_global_rect().get_center()).is_equal_approx(Vector2(100, 200), Vector2(0.01, 0.01))
	assert_vector(b._glyph.size).is_equal(Vector2(22, 22))
	var box: UiStyleBox = b._disc.get_theme_stylebox(&"panel")
	assert_object(box.border_color).is_equal(UiTokens.COLOR_BORDER)
	assert_float(box.border_width).is_equal(float(UiTokens.STROKE_DEFAULT))
	assert_int(b.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)   # the facility takes the tap

func test_near_grows_with_a_primary_edge_and_a_state_takes_the_whole_button() -> void:
	var b := _host(UiWorldIconButton.new()) as UiWorldIconButton
	b.icon = HOME
	b.near = true
	var box: UiStyleBox = b._disc.get_theme_stylebox(&"panel")
	assert_object(box.border_color).is_equal(UiTokens.COLOR_PRIMARY)
	assert_float(box.border_width).is_equal(float(UiTokens.STROKE_SELECTED))
	assert_vector(b.scale).is_equal(Vector2(1.1, 1.1))
	b.near = false
	b.status = UiStatusBadge.State.READY
	assert_bool(b._disc.visible).is_false()
	assert_bool(b._badge.visible).is_true()
	assert_int(b._badge.state).is_equal(UiStatusBadge.State.READY)
	b.status = -1
	assert_bool(b._disc.visible).is_true()
	assert_bool(b._badge.visible).is_false()

func test_name_bar_reads_icon_name_fact_and_keeps_the_icon_on_its_anchor() -> void:
	var bar := _host(UiWorldNameBar.new()) as UiWorldNameBar
	bar.icon = HOME
	bar.text = "Stove 1/1"
	bar.fact = "Empty"
	bar.anchor_at(Vector2(120, 300))
	bar.set_openness(1.0)
	await await_idle_frame()
	assert_float(bar.size.y).is_equal(32.0)
	var shown := bar._row.get_children().filter(func(c): return (c as Control).visible)
	assert_array(shown.map(func(c): return c.name if not (c is Label) else (c as Label).text)).is_equal([bar._glyph.name, "Stove 1/1", "·", "Empty"])
	# Side Right: the icon sits 5 + 11 from the left edge, on the anchor; the text goes right.
	assert_float(bar._glyph.get_global_rect().get_center().x).is_equal_approx(120.0, 0.5)
	assert_float(bar.get_global_rect().position.x).is_equal_approx(120.0 - 16.0, 0.5)
	bar.side = UiWorldNameBar.Dir.LEFT
	await await_idle_frame()
	var shown_left := bar._row.get_children().filter(func(c): return (c as Control).visible)
	assert_object(shown_left[shown_left.size() - 1]).is_same(bar._glyph)   # icon last, text to its left
	assert_array(shown_left.slice(0, 3).map(func(c): return (c as Label).text)).is_equal(["Stove 1/1", "·", "Empty"])   # still reads name · fact
	assert_float(bar._glyph.get_global_rect().get_center().x).is_equal_approx(120.0, 0.5)
	assert_float(bar.get_global_rect().end.x).is_equal_approx(120.0 + 16.0, 0.5)

func test_name_bar_opens_from_the_icon_and_dims_when_used() -> void:
	var bar := _host(UiWorldNameBar.new()) as UiWorldNameBar
	bar.icon = HOME
	bar.text = "Rest bench"
	bar.fact = "+60 Energy"
	bar.anchor_at(Vector2(120, 300))
	bar.set_openness(0.0)
	await await_idle_frame()
	assert_float(bar.size.x).is_equal(bar.folded_width())   # just the icon
	bar.expand()
	await get_tree().create_timer(0.25).timeout
	assert_bool(bar.is_expanded()).is_true()
	assert_float(bar.size.x).is_equal_approx(bar.full_width(), 0.5)
	assert_float(bar._glyph.get_global_rect().get_center().x).is_equal_approx(120.0, 0.5)   # held still
	bar.dimmed = true
	assert_float(bar._glyph.modulate.a).is_equal_approx(0.45, 0.001)
	assert_object(bar._name.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
	bar.collapse()
	await get_tree().create_timer(0.25).timeout
	assert_float(bar.openness()).is_equal(0.0)

func test_name_bar_status_takes_the_icons_place_at_22() -> void:
	var bar := _host(UiWorldNameBar.new()) as UiWorldNameBar
	bar.icon = HOME
	bar.text = "Homestead Stall"
	bar.status = UiStatusBadge.State.REQUEST
	assert_object(bar._row.get_child(0)).is_same(bar._glyph)
	assert_bool(bar._glyph.visible).is_false()
	assert_bool(bar._badge_holder.visible).is_true()
	assert_vector(bar._badge_holder.custom_minimum_size).is_equal(Vector2(22, 22))
	assert_float(bar._badge.scale.x).is_equal_approx(22.0 / 28.0, 0.001)

func test_npc_tag_is_the_name_only_and_highlights() -> void:
	var t := _host(UiNpcNameTag.new("Ama")) as UiNpcNameTag
	await await_idle_frame()
	t.place_over(Vector2(180, 300))
	var s := t.get_combined_minimum_size()
	assert_float(s.y).is_equal_approx(26.0, 1.0)   # 49 × 26 in Figma (Godot's Caption line box is 18, padding gives 1 back)
	assert_vector(Vector2(t.position.x + s.x * 0.5, t.position.y + s.y)).is_equal_approx(Vector2(180, 300), Vector2(0.5, 0.5))
	t.highlight = true
	var box: UiStyleBox = t.get_theme_stylebox(&"panel")
	assert_object(box.border_color).is_equal(UiTokens.COLOR_PRIMARY)
	assert_vector(t.scale).is_equal(Vector2(1.1, 1.1))
	assert_str(t._label.text).is_equal("Ama")

## 刘邦 on #55: hosts set every property every frame, so an unchanged value must not build a new style or re-sort.
func test_an_unchanged_value_rebuilds_nothing() -> void:
	var b := _host(UiWorldIconButton.new()) as UiWorldIconButton
	b.icon = HOME
	var box: StyleBox = b._disc.get_theme_stylebox(&"panel")
	b.icon = HOME
	b.near = false
	b.status = -1
	assert_object(b._disc.get_theme_stylebox(&"panel")).is_same(box)
	var bar := _host(UiWorldNameBar.new()) as UiWorldNameBar
	bar.text = "Farmhouse"
	var bg: StyleBox = bar._bg.get_theme_stylebox(&"panel")
	bar.text = "Farmhouse"
	bar.fact = ""
	bar.side = UiWorldNameBar.Dir.RIGHT
	bar.dimmed = false
	bar.status = -1
	assert_object(bar._bg.get_theme_stylebox(&"panel")).is_same(bg)
	var t := _host(UiNpcNameTag.new("Ama")) as UiNpcNameTag
	var tb: StyleBox = t.get_theme_stylebox(&"panel")
	t.highlight = false
	t.text = "Ama"
	assert_object(t.get_theme_stylebox(&"panel")).is_same(tb)

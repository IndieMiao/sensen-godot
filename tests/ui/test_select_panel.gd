extends GdUnitTestSuite

func _panel(parent: Control = null) -> SelectPanel:
	var p: SelectPanel = auto_free(SelectPanel.new())
	if parent:
		parent.add_child(p)
	else:
		add_child(p)
	p.set_candidates([
		{"id": "a", "name": "Hengshan Road", "preview": null},
		{"id": "b", "name": "Old Town", "preview": null},
		{"id": "c", "name": "Yuyuan Road", "preview": null}])
	return p

func test_three_cards_same_capacity_text() -> void:
	var p := _panel()
	assert_int(p.card_count()).is_equal(3)
	var texts: Array = []
	for card in p.cards():
		# 容量文案已经搬进卡片内的子 Label，Button.text 不再承载它（D1 修复：
		# 长文案留在 Button.text 上会把卡片最小宽度撑到内容的自然宽度）。
		assert_bool((card as Button).text.is_empty()).is_true()
		var label := p.capacity_label(card)
		assert_object(label).is_not_null()
		texts.append(label.text)
	assert_that(texts).is_equal([SelectPanel.CAPACITY_TEXT, SelectPanel.CAPACITY_TEXT, SelectPanel.CAPACITY_TEXT])
	assert_bool(p.confirm_button.disabled).is_true()

func test_focus_and_confirm_emit() -> void:
	var p := _panel()
	var focused: Array = []
	var confirmed: Array = []
	p.candidate_focused.connect(func(id): focused.append(id))
	p.confirmed.connect(func(id): confirmed.append(id))
	(p.cards()[1] as Button).emit_signal("pressed")
	assert_that(focused).is_equal(["b"])
	assert_str(p.focused_id).is_equal("b")
	assert_bool(p.confirm_button.disabled).is_false()
	p.confirm_button.emit_signal("pressed")
	assert_that(confirmed).is_equal(["b"])

func test_focus_api_marks_card_pressed() -> void:
	var p := _panel()
	p.focus("c")
	assert_bool((p.cards()[2] as Button).button_pressed).is_true()
	assert_str(p.focused_id).is_equal("c")

## C2（2026-09-04 终审）：_init() 里 set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
## 曾经在任何子节点存在之前就被调用，PRESET_MODE_MINSIZE 按调用时刻的
## get_combined_minimum_size()（当时是 0）算 offset_top，面板因此整个长在父容器
## 底边以下、完全不可见——三张候选卡与「Create Farm」是确认候选的唯一入口，这条回归
## 直接决定这个 gate 能不能用。用一个有具体尺寸的父 Control 复现真实布局环境。
func test_panel_stays_within_parent_bounds_after_candidates() -> void:
	var parent := Control.new()
	add_child(auto_free(parent))
	parent.size = Vector2(1080, 1920)
	var p := _panel(parent)
	assert_float(p.position.y).is_greater_equal(0.0)
	assert_float(p.position.y + p.size.y).is_less_equal(parent.size.y)

func test_set_candidates_twice_does_not_accumulate() -> void:
	var p: SelectPanel = auto_free(SelectPanel.new())
	add_child(p)
	p.set_candidates([
		{"id": "a", "name": "Hengshan Road", "preview": null},
		{"id": "b", "name": "Old Town", "preview": null},
		{"id": "c", "name": "Yuyuan Road", "preview": null}])
	# 同一帧内再次调用 set_candidates，验证旧卡片被正确移除而非积累
	p.set_candidates([
		{"id": "d", "name": "Historic Core", "preview": null},
		{"id": "e", "name": "Venice Canals", "preview": null}])
	# _row 的子元素数应为 2，验证旧卡片已从场景树解除
	assert_int(p._row.get_child_count()).is_equal(2)
	assert_int(p.card_count()).is_equal(2)
	await get_tree().process_frame

## D1（2026-09-04 真机实测，vivo V2509A，360×800 逻辑视口）：候选卡片行横向溢出，
## 2/3 号卡片跑出屏幕右边——因为容量文案曾经直接塞进 Button.text，Button 文字默认
## 不折行，卡片最小宽度撑到最长一行的自然宽度，三张卡加两条 8px 间隙远超 360px。
## 用真实的 360×800 逻辑视口尺寸复现，而不是旧测试用的 1080×1920（那个尺寸下
## 即使按钮撑到 656px 宽也还在父容器内，测不出这个 bug）。
func test_row_and_cards_stay_within_the_360_viewport() -> void:
	var parent := Control.new()
	add_child(auto_free(parent))
	parent.size = Vector2(360, 800)
	var p := _panel(parent)
	await get_tree().process_frame
	var bounds := parent.get_global_rect()
	var panel_rect := p.get_global_rect()
	assert_float(panel_rect.position.x).is_greater_equal(bounds.position.x - 0.01)
	assert_float(panel_rect.position.x + panel_rect.size.x).is_less_equal(
		bounds.position.x + bounds.size.x + 0.01)
	assert_int(p.cards().size()).is_equal(3)
	for card in p.cards():
		var r: Rect2 = (card as Control).get_global_rect()
		assert_float(r.position.x).is_greater_equal(bounds.position.x - 0.01)
		assert_float(r.position.x + r.size.x).is_less_equal(bounds.position.x + bounds.size.x + 0.01)
		# 合法可读下限（与 CARD_MIN.x 独立取值，避免测试只是把实现常量抄一遍）：
		# 再窄就装不下预览图 + 两行文字，宁可回归测出来也不要静默变窄。
		assert_float(r.size.x).is_greater_equal(90.0)

## D1 加固：上一条测试用的是今天的真实文案（英文缩短版），文案短本身就可能让
## 卡片"恰好"没超出视口——这样测不出折行到底有没有真的生效，下一次改文案
## （比如又变长）照样会静默复发（controller 2026-09-04 的原话）。这里故意塞
## 一个远超正常长度的名字压测，并直接断言 autowrap_mode 打开，两条一起钉住：
## 折行是靠机制生效，不是靠今天的字符串恰好短。
func test_cards_stay_within_viewport_even_with_much_longer_copy() -> void:
	var parent := Control.new()
	add_child(auto_free(parent))
	parent.size = Vector2(360, 800)
	var p: SelectPanel = auto_free(SelectPanel.new())
	parent.add_child(p)
	p.set_candidates([
		{"id": "a", "name": "A Very Long Neighbourhood Name That Keeps Going On", "preview": null},
		{"id": "b", "name": "Another Rather Long Neighbourhood Name For Testing", "preview": null},
		{"id": "c", "name": "Yet One More Extremely Long Neighbourhood Name Here", "preview": null}])
	await get_tree().process_frame
	var bounds := parent.get_global_rect()
	for card in p.cards():
		var r: Rect2 = (card as Control).get_global_rect()
		assert_float(r.position.x + r.size.x).is_less_equal(bounds.position.x + bounds.size.x + 0.01)
		assert_int(p.name_label(card).autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
		assert_int(p.capacity_label(card).autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)

## D2（2026-09-04 真机实测）：预览缩略图被主题的 Button icon_normal_color
## （app_theme.tres 里给侧栏白色描边图标调墨色用的一次乘色）连带把候选图片乘成
## 近黑色小方块。断言预览贴在独立的 TextureRect 上而不是 Button.icon——
## 这样如果哪天有人"简化"回 card.icon = item.preview，这条测试会先炸。
func test_preview_lives_on_an_untinted_texture_rect_not_button_icon() -> void:
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(64, 64)
	var p: SelectPanel = auto_free(SelectPanel.new())
	add_child(p)
	p.set_candidates([
		{"id": "a", "name": "Hengshan Road", "preview": tex},
		{"id": "b", "name": "Old Town", "preview": null},
		{"id": "c", "name": "Yuyuan Road", "preview": null}])
	for card in p.cards():
		assert_object((card as Button).icon).is_null()
	var preview := p.preview_node(p.cards()[0])
	assert_object(preview).is_not_null()
	assert_bool(preview is TextureRect).is_true()
	assert_object((preview as TextureRect).texture).is_equal(tex)
	assert_object((preview as TextureRect).texture).is_not_null()

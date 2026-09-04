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
		# 这几条守的是"行装不装得下"（CARD_MIN×3+间距是否超过预算），不是折行本身
		# 有没有生效——Button 不是 Container，子节点内容溢出不会往上顶大卡片的
		# 报告最小尺寸，所以这里测不出"忘了开 autowrap"（见下面加固测试的说明）。
		assert_float(r.position.x + r.size.x).is_less_equal(bounds.position.x + bounds.size.x + 0.01)
		# 合法可读下限（与 CARD_MIN.x 独立取值，避免测试只是把实现常量抄一遍）：
		# 再窄就装不下预览图 + 两行文字，宁可回归测出来也不要静默变窄。
		assert_float(r.size.x).is_greater_equal(85.0)

## D1 加固 round 1：上一条测试用的是今天的真实文案（英文缩短版），文案短本身就
## 可能让卡片"恰好"没超出视口——这样测不出折行到底有没有真的生效，下一次改
## 文案（比如又变长）照样会静默复发（controller 2026-09-04 的原话）。这里故意
## 塞一个远超正常长度的名字压测。
##
## 订正（controller code review）：下面的几何断言实际上*不可能*discriminate——
## Button 不是 Container，_build_card_content() 塞进去的 VBoxContainer 溢出
## 多少都不会反向撑大 card 自己报告的 combined_minimum_size（它仍然钉死在
## CARD_MIN）。反证：把 autowrap_mode 那两行注释掉重跑，6 个 autowrap 断言全炸，
## geometry 断言全过——即使名字长到会把内容挤爆卡片视觉上也不例外。真正守住
## "文案再长也不会复发"的是下面直接检查 autowrap_mode 的两行；几何断言留着
## 只是双重保险（万一以后 card 不再是纯 Button），不要过度信任它。
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
		# 这两行才是真正的判别性断言，见上面的订正说明。
		assert_int(p.name_label(card).autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
		assert_int(p.capacity_label(card).autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)

## D1 加固 round 2（controller code review，2026-09-04）：SelectPanel 不独占
## 360 逻辑视口——它是 $HUD/SafeArea/Root 的子节点，SafeArea（MarginContainer +
## SafeAreaMargin 脚本）每边至少留 min_margin=16px（「任何情况下都不贴边」），
## Root 的真实宽度上限只有 360-16-16=328，不是 360。上面两条测试都把
## SelectPanel 直接挂在裸 Control(360,800) 下——面板自己的最小宽度只要 ≤360
## 就会通过，但生产环境里 Root 给不到 360，这条测不出 round 1 遗留的 ~16px
## 越界（面板自身最小宽度在 CARD_MIN.x=104 时算出来正好是 360，跟裸 360 视口
## 严丝合缝地"通过"，而真实 Root 只有 328）。这里用 SafeAreaMargin 的注入式
## 接口（不依赖真机 DisplayServer）搭出 SafeArea → Root → SelectPanel 三层，
## 断言面板和卡片行的右边缘不超过 Root 的真实矩形。
func test_panel_fits_inside_the_real_safe_area_hierarchy() -> void:
	var safe_area := SafeAreaMargin.new()
	safe_area.min_margin = 16.0
	add_child(auto_free(safe_area))
	safe_area.size = Vector2(360, 800)
	safe_area.apply_margins(Rect2i(), Vector2i(360, 800), Vector2(360, 800))
	var root := Control.new()
	root.name = "Root"
	safe_area.add_child(root)
	var p: SelectPanel = auto_free(SelectPanel.new())
	root.add_child(p)
	p.set_candidates([
		{"id": "a", "name": "Hengshan Road", "preview": null},
		{"id": "b", "name": "Old Town", "preview": null},
		{"id": "c", "name": "Yuyuan Road", "preview": null}])
	await get_tree().process_frame
	var root_rect := root.get_global_rect()
	# 328×768：安全区每边 -16 之后 Root 的真实预算，不是裸 360×800——先钉住
	# 这个前提本身，避免以后 SafeAreaMargin 改了 min_margin 这条测试却没跟着变。
	assert_float(root_rect.size.x).is_equal_approx(328.0, 0.5)
	var panel_rect := p.get_global_rect()
	assert_float(panel_rect.position.x + panel_rect.size.x).is_less_equal(
		root_rect.position.x + root_rect.size.x + 0.01)
	for card in p.cards():
		var r: Rect2 = (card as Control).get_global_rect()
		assert_float(r.position.x + r.size.x).is_less_equal(
			root_rect.position.x + root_rect.size.x + 0.01)
	# 垂直方向在真实层级下依然宽裕（Root 高度 800-32=768，面板自身高度远小于
	# 这个数），不需要收紧 CARD_MIN.y——顺带钉住这条，免得以后有人以为要收紧。
	assert_float(panel_rect.size.y).is_less_equal(root_rect.size.y)

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

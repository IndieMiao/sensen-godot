extends GdUnitTestSuite
const Pulses := preload("res://modules/p0/p0_guide_pulses.gd")
const FarmGuide := preload("res://scenes/p0/p0_farm_guide.gd")

func _guide(step := "t_sow_quick") -> Dictionary:
	return {guide = {step = step, at = 100, recover = null, marks = []}, garden = {plots = 30},
		plots = [{id = 0, state = "tilled"}, {id = 1, state = "tilled"}], residents = {}}

func test_only_the_resolved_target_keeps_a_resident_mark_in_its_actual_place() -> void:
	var v := _guide("t_nadia_1")
	v.residents = {res_nadia = {request_state = "accepted", request = {ready = true}}, res_pip = {request_state = "open"}}
	v.guide.marks = [{place = "actual-market", kind = "request"}, {resident = "res_nadia", kind = "request"}]
	assert_str(P0Guide.resident_badge(v, "res_nadia", "actual-market")).is_equal("deliverable")
	assert_str(P0Guide.resident_badge(v, "res_nadia", "another-city-market")).is_empty()
	assert_str(P0Guide.resident_badge(v, "res_pip", "actual-market")).is_empty()
	v.guide.marks[1].kind = "gift"
	assert_str(P0Guide.resident_badge(v, "res_nadia", "actual-market")).is_equal("gift")
	v.guide.step = null
	assert_str(P0Guide.resident_badge(v, "res_pip", "actual-market")).is_equal("request")

func test_teaching_plot_ids_are_typed_unique_and_within_the_actual_garden() -> void:
	var v := _guide()
	v.guide.marks = [{plot = 0}, {plot = 1.0}, {plot = 1}, {plot = -1}, {plot = 100000}, {plot = "teach"}, null]
	assert_array(P0Guide.teaching_plots(v)).is_equal([0, 1])
	v.guide.step = null
	assert_array(P0Guide.teaching_plots(v)).is_empty()
	assert_dict(P0Guide.pip(v)).is_empty()

func test_unrelated_business_facts_and_mail_stay_visible_during_the_guide() -> void:
	var v := _guide()
	v.homestead = {level = 1, next = {can_upgrade = true}}
	assert_int(P0WorldPrompts.sign(v).status).is_equal(-1)
	assert_str(P0WorldPrompts.sign(v).text).is_equal("Homestead Lv1")
	assert_int(P0WorldPrompts.stall(v, true).status).is_equal(-1)
	assert_str(P0WorldPrompts.workbench().text).is_equal("Workbench")
	v.guide.marks = [{place = "home", object = "farmhouse", kind = "request"}]
	assert_int(P0WorldPrompts.farmhouse(v).status).is_equal(UiStatusBadge.State.REQUEST)
	v.guide.marks = []
	assert_int(P0WorldPrompts.farmhouse(v).status).is_equal(-1)
	v.guide.step = null
	assert_int(P0WorldPrompts.sign(v).status).is_equal(UiStatusBadge.State.READY)

func _button() -> UiCommandButton:
	var b: UiCommandButton = auto_free(UiCommandButton.new("Cook"))
	b.position = Vector2(40, 100)
	b.size = Vector2(100, 48)
	add_child(b)
	return b

func test_pulses_do_not_loop_on_frames_rebuilds_or_recover_changes_and_stop_at_two() -> void:
	var budget = Pulses.new()
	var v := _guide()
	var button := _button()
	var targets := {sow = {node = button}}
	for i in 20: budget.update(v, targets)
	assert_int(budget._counts.sow).is_equal(1)
	var replacement := _button()
	targets.sow.node = replacement
	budget.update(v, targets)
	assert_int(budget._counts.sow).is_equal(1)   # rebuilding the same visible action is not a new visit
	budget.update(v, {})
	v.guide.recover = "r_radish_sow"
	budget.update(v, targets)
	assert_int(budget._counts.sow).is_equal(2)
	for i in 4:
		budget.update(v, {})
		v.guide.recover = null if i % 2 else "r_radish_sow"
		budget.update(v, targets)
	assert_int(budget._counts.sow).is_equal(2)
	v.guide.step = "t_water"
	budget.update(v, targets)
	assert_int(budget._counts.sow).is_equal(1)
	budget.cancel()

func test_pulses_wait_for_visible_available_controls_and_clear_on_guide_end() -> void:
	var budget = Pulses.new()
	var button := _button()
	var v := _guide()
	var targets := {cook = {node = button}}
	button.reason = "Need 1 fish"
	budget.update(v, targets)
	assert_dict(budget._counts).is_empty()
	button.reason = ""
	button.visible = false
	budget.update(v, targets)
	assert_dict(budget._counts).is_empty()
	button.visible = true
	budget.update(v, targets)
	assert_int(budget._counts.cook).is_equal(1)
	var pulse := button.get_children().filter(func(c): return c is UiGuidePulse)[0] as UiGuidePulse
	assert_int(pulse.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(button.disabled).is_false()
	v.guide.step = null
	budget.update(v, targets)
	assert_bool(pulse.is_queued_for_deletion()).is_true()
	assert_dict(budget._counts).is_empty()

func test_npc_badge_keeps_name_and_tap_target_and_uses_existing_npc_size() -> void:
	var tag: UiNpcNameTag = auto_free(UiNpcNameTag.new("Pip"))
	tag.theme = UiKit.theme()
	add_child(tag)
	tag.place_over(Vector2(180, 250))
	await await_idle_frame()
	var name_size := tag.size
	tag.status = UiStatusBadge.State.REQUEST
	await await_idle_frame()
	assert_str(tag.text).is_equal("Pip")
	assert_vector(tag.size).is_equal(name_size)
	assert_float(tag._badge.side()).is_equal(36.0)
	assert_bool(tag.hit_rect().has_point(tag._badge.get_global_rect().get_center())).is_true()
	assert_float(tag._badge.get_global_rect().end.y).is_less_equal(tag.get_global_rect().position.y)
	tag.status = UiStatusBadge.State.GIFT
	assert_int(tag._badge.state).is_equal(UiStatusBadge.State.GIFT)
	tag.status = -1
	assert_bool(tag._badge.visible).is_false()

func test_cook_target_never_selects_a_page_or_exposes_experiment_cook() -> void:
	var drawer: P0KitchenDrawer = auto_free(P0KitchenDrawer.new({}))
	assert_str(drawer.selected_page).is_empty()
	assert_object(drawer.guide_cook_target("dish_fish_soup")).is_null()
	drawer.selected_page = "dish_grilled_crucian"
	assert_object(drawer.guide_cook_target("dish_fish_soup")).is_null()
	assert_str(drawer.selected_page).is_equal("dish_grilled_crucian")

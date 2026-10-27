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
	assert_float(tag._badge.get_global_rect().get_center().x).is_equal_approx(tag.get_global_rect().get_center().x, 0.01)
	assert_float(tag._badge.get_global_rect().position.y).is_greater(100.0)   # inherits the pill's transform
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

func test_explicit_pip_reply_wins_over_the_step_line_without_adding_request() -> void:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = "user://test_c2_reply_bar_%d.json" % OS.get_process_id()
	ui.tips_path = "user://test_c2_reply_tips_%d.json" % OS.get_process_id()
	add_child(ui)
	ui.set_surface("farm")
	var v := _guide()
	v.bag = {capacity = 25, slots = []}
	v.residents = {res_pip = {affinity = 2, stage = "Stranger", stage_from = 0, next_stage = "Acquainted", next_at = 15,
		gift_today = false, meal = "none", request = null, request_state = "none"}}
	v.guide.pip = {here = true, bang = true, line = "Now water them. They grow fast!"}
	ui.set_view(v)
	assert_bool(ui.open_resident("res_pip")).is_true()
	var reply := "Out of radishes? Here, two more quick ones."
	assert_bool(ui.resident_say("res_pip", reply)).is_true()
	var bars := ui._modal.find_children("*", "UiResidentBar", true, false)
	assert_str(bars[0].line).is_equal(reply)
	assert_object(bars[0]._request).is_null()
	for file in [ui.quick_store, ui.tips_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))

func _marked_ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.quick_store = "user://test_typed_marks_bar_%d.json" % OS.get_process_id()
	ui.tips_path = "user://test_typed_marks_tips_%d.json" % OS.get_process_id()
	v.bag = {capacity = 25, slots = []}
	v.energy = {value = 200, max = 200}
	add_child(ui)
	ui.set_process(false)
	ui.set_surface("farm")
	ui.set_view(v)
	await await_idle_frame()
	for file in [ui.quick_store, ui.tips_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return ui

class WaterFarm extends Node3D:
	var rt := {}
	var bp: FarmBlueprint
	var cam: Camera3D

func _water_farm(ui: P0Ui) -> Node3D:
	var farm: WaterFarm = auto_free(WaterFarm.new())
	farm.rt = {ui = ui}
	farm.bp = P0Garden.blueprint()
	add_child(farm)
	farm.cam = Camera3D.new()
	farm.add_child(farm.cam)
	farm.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	farm.cam.size = 8.0
	farm.cam.position = farm.bp.cell_to_world(P0Garden.cell_of(0)) + Vector3(0, 10, 0)
	farm.cam.rotation_degrees.x = -90.0
	var guide := FarmGuide.new().setup(farm)
	farm.add_child(guide)
	return guide

func test_two_sown_teaching_beds_show_water_badges_and_water_pulses_once() -> void:
	var v := _guide("t_water")
	v.guide.marks = [{plot = 0}, {plot = 1}, {button = "water", pulse = true}]
	v.plots = [{id = 0, state = "sown"}, {id = 1, state = "sown"}, {id = 2, state = "sown"}]
	var ui := await _marked_ui(v)
	var guide := _water_farm(ui)
	ui.set_action({verb = "Water", enabled = true, cmd = {type = "water", plot = 0}})
	for i in 20:
		guide._water_marks(v)
		ui._refresh_guide_pulses()
	for id in [0, 1]:
		var badge: UiStatusBadge = ui._badges[FarmGuide.WATER_TAG + str(id)]
		assert_bool(badge.visible).is_true()
		assert_int(badge.state).is_equal(UiStatusBadge.State.AVAILABLE)
		assert_object(badge.icon).is_same(P0Logic.icon("water"))
		assert_int(badge.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(ui._badges.has(FarmGuide.WATER_TAG + "2")).is_false()
	assert_int(ui.guide_pulses._counts.water).is_equal(1)
	# Only the server-confirmed growing bed loses its water badge; the other remains actionable.
	v.plots[0].state = "growing"
	guide._water_marks(v)
	assert_bool(ui._badges[FarmGuide.WATER_TAG + "0"].visible).is_false()
	assert_bool(ui._badges[FarmGuide.WATER_TAG + "1"].visible).is_true()
	v.plots[1].state = "ready"
	guide._water_marks(v)
	assert_bool(ui._badges[FarmGuide.WATER_TAG + "1"].visible).is_false()

func test_water_badges_follow_server_targets_and_hide_under_panels_offscreen_and_on_leave() -> void:
	var v := _guide("t_water")
	v.plots[0].state = "sown"
	var ui := await _marked_ui(v)
	var guide := _water_farm(ui)
	guide._water_marks(v)
	assert_dict(ui._badges).is_empty()   # the step alone does not invent a target
	v.guide.marks = [{plot = 0}]
	guide._water_marks(v)
	var badge: UiStatusBadge = ui._badges[FarmGuide.WATER_TAG + "0"]
	assert_bool(badge.visible).is_true()
	ui._open_modal(Control.new())
	guide._water_marks(v)
	assert_bool(badge.visible).is_false()
	ui.close_modal()
	guide._water_marks(v)
	assert_bool(badge.visible).is_true()
	guide.farm.cam.position.x += 100.0
	guide._water_marks(v)
	assert_bool(badge.visible).is_false()
	guide.farm.cam.position.x -= 100.0
	guide._water_marks(v)
	assert_bool(badge.visible).is_true()
	guide.hide_marks()   # farm placement mode
	assert_bool(badge.visible).is_false()
	guide._water_marks(v)
	guide.leave()        # farm suspension, including entering the farmhouse
	assert_bool(badge.visible).is_false()
	guide._water_marks(v)
	assert_bool(badge.visible).is_true()
	v.guide.marks = []
	guide._water_marks(v)
	assert_bool(badge.visible).is_false()
	v.guide.marks = [{plot = 0}]
	v.guide.step = null
	guide._water_marks(v)
	assert_bool(badge.visible).is_false()   # ordinary accounts / ended guide get no new marks

func test_water_badge_stays_readable_when_pip_name_overlaps_its_plot() -> void:
	var v := _guide("t_water")
	v.guide.marks = [{plot = 0}]
	v.plots[0].state = "sown"
	var ui := await _marked_ui(v)
	var guide := _water_farm(ui)
	guide._water_marks(v)
	var badge: UiStatusBadge = ui._badges[FarmGuide.WATER_TAG + "0"]
	ui.npc_tag(FarmGuide.TAG, "Pip", badge.get_global_rect().end, true)
	var tag: UiNpcNameTag = ui._npc_tags[FarmGuide.TAG]
	tag.position = badge.position   # the opening camera can project the first bed under Pip's name
	var original_name_rect := tag.get_global_rect()
	assert_bool(badge.get_global_rect().intersects(original_name_rect)).is_true()
	guide._water_marks(v)
	assert_bool(badge.visible).is_true()
	assert_bool(badge.get_global_rect().intersects(tag.get_global_rect())).is_false()
	assert_that(tag.get_global_rect()).is_equal(original_name_rect)
	assert_bool(ui._marker_area().encloses(badge.get_global_rect())).is_true()

func test_harvest_and_location_need_server_marks_not_step_fallbacks() -> void:
	var v := _guide("t_harvest_quick")
	var ui := await _marked_ui(v)
	ui.set_action({verb = "Harvest", enabled = true, cmd = {type = "harvest"}})
	ui._refresh_guide_pulses()
	assert_dict(ui.guide_pulses._counts).is_empty()
	v.guide.marks = [{button = "harvest", pulse = true}, {button = "location", pulse = true}]
	ui._refresh_guide_pulses()
	assert_int(ui.guide_pulses._counts.harvest).is_equal(1)
	assert_int(ui.guide_pulses._counts.location).is_equal(1)

func test_cast_only_pulses_at_the_marked_pond() -> void:
	var v := _guide("t_fish")
	v.guide.marks = [{button = "cast", pulse = true}, {place = "pond-target", kind = "request"}]
	var ui := await _marked_ui(v)
	ui.set_surface("pond")
	ui.space = "pond"
	ui.set_action({verb = "Cast", enabled = true, cmd = {type = "cast"}})
	ui.place = "other-pond"
	ui._refresh_guide_pulses()
	assert_dict(ui.guide_pulses._counts).is_empty()
	ui.place = "pond-target"
	ui._refresh_guide_pulses()
	assert_int(ui.guide_pulses._counts.cast).is_equal(1)

func test_stove_mark_pulses_only_the_open_world_name_strip() -> void:
	var v := _guide("t_soup")
	v.guide.marks = [{object = "stove", pulse = true}]
	var ui := await _marked_ui(v)
	ui.space = "home"
	ui._refresh_guide_pulses()
	assert_dict(ui.guide_pulses._counts).is_empty()
	ui.name_bar("room:use_stove_1", P0Logic.icon("pot"), "Stove 1/1", "Empty", Vector2(100, 250), true)
	await get_tree().create_timer(0.25).timeout
	ui._refresh_guide_pulses()
	assert_int(ui.guide_pulses._counts["object:stove"]).is_equal(1)

func test_soup_item_mark_matches_all_qualities_without_selecting_or_inserting() -> void:
	var grid: UiInventoryGrid = auto_free(UiInventoryGrid.new())
	add_child(grid)
	grid.items = [{id = "dish_fish_soup@plain", qty = 1}, {id = "dish_fish_soup@good", qty = 1},
		{id = "dish_fish_soup@perfect", qty = 1}, {id = "dish_grilled_crucian@good", qty = 1}]
	assert_int(P0Ui.guide_gift_cells(grid, "dish_fish_soup").size()).is_equal(3)
	assert_str(grid.selected_id).is_empty()
	grid.items = [{id = "dish_grilled_crucian@good", qty = 1}]
	assert_dict(P0Ui.guide_gift_cells(grid, "dish_fish_soup")).is_empty()
	assert_int(grid.shown_items().size()).is_equal(1)

func test_item_pulse_is_outside_the_grid_clip_and_follows_the_cell() -> void:
	var drawer: Control = auto_free(Control.new())
	drawer.size = Vector2(300, 400)
	add_child(drawer)
	var grid := Control.new()
	grid.clip_contents = true
	grid.position = Vector2(20, 100)
	grid.size = Vector2(200, 100)
	drawer.add_child(grid)
	var cell := UiItemCell.new(UiItemCell.Density.INVENTORY)
	cell.size = Vector2(52, 52)
	grid.add_child(cell)
	var overlay := P0Ui.guide_item_overlay(drawer)
	var budget = Pulses.new()
	budget.update(_guide("t_gift"), {soup = {node = cell, overlay = overlay, shape = UiGuidePulse.Shape.CARD}})
	var ring: UiGuidePulse = budget._rings[0].get_ref()
	assert_bool(grid.is_ancestor_of(ring)).is_false()
	assert_int(overlay.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var before := ring.global_position
	cell.position.x += 12
	budget.follow()
	assert_float(ring.global_position.x - before.x).is_equal_approx(12, 0.01)
	budget.cancel()


func _growing_view() -> Dictionary:
	var v := _guide("t_sow_rest")
	v.quick_seeds = [{id = "crop_quick_radish", seed = "seed_quick_radish", grow_s = 45}]
	v.guide.marks = [{button = "quickbar:seed_lettuce", pulse = true}]
	v.plots = [{id = 0, state = "growing", crop = "crop_quick_radish", ready_in = 45000},
		{id = 1, state = "growing", crop = "crop_quick_radish", ready_in = 45000},
		{id = 2, state = "growing", crop = "crop_lettuce", ready_in = 100000}]
	return v

func test_teaching_crop_countdowns_rebuild_without_plot_marks_tick_and_turn_ready() -> void:
	var v := _growing_view()
	var ui := await _marked_ui(v)
	var guide := _water_farm(ui)
	guide._growth_marks(v)   # cold entry in S4: no earlier water-mark history and no plot marks
	for id in [0, 1]:
		var badge: UiStatusBadge = ui._badges[FarmGuide.GROWTH_TAG + str(id)]
		assert_bool(badge.visible).is_true()
		assert_int(badge.state).is_equal(UiStatusBadge.State.COUNTDOWN)
		assert_str(badge.caption).is_equal("0:45")
		assert_bool(badge._pill.visible).is_true()
		assert_bool(badge._glyph.texture.resource_path.ends_with("status/countdown.svg")).is_true()
		assert_int(badge.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(ui._badges.has(FarmGuide.GROWTH_TAG + "2")).is_false()
	guide._growth_marks(P0Logic.project(v, 1000))
	assert_str(ui._badges[FarmGuide.GROWTH_TAG + "0"].caption).is_equal("0:44")
	assert_int(v.plots[0].ready_in).is_equal(45000)   # no timer mutation / double subtraction
	guide._growth_marks(P0Logic.project(v, 45000))
	for id in [0, 1]:
		var badge: UiStatusBadge = ui._badges[FarmGuide.GROWTH_TAG + str(id)]
		assert_bool(badge.visible).is_true()
		assert_int(badge.state).is_equal(UiStatusBadge.State.READY)
		assert_str(badge.caption).is_empty()
		assert_bool(badge._pill.visible).is_false()
		assert_bool(badge._glyph.texture.resource_path.ends_with("status/ready.svg")).is_true()

func test_growth_badges_need_real_crop_facts_and_clear_after_harvest_or_guide_end() -> void:
	var v := _growing_view()
	var ui := await _marked_ui(v)
	var guide := _water_farm(ui)
	v.plots[0].ready_in = null
	v.plots[1].state = "sown"
	guide._growth_marks(v)
	assert_dict(ui._badges).is_empty()   # missing timer is not an invented 0:45 / Ready
	v = P0Logic.project(_growing_view(), 45000)
	guide._growth_marks(v)
	v.plots[0] = {id = 0, state = "tilled", crop = null}
	guide._growth_marks(v)
	assert_bool(ui._badges[FarmGuide.GROWTH_TAG + "0"].visible).is_false()
	assert_bool(ui._badges[FarmGuide.GROWTH_TAG + "1"].visible).is_true()
	v.guide.step = null
	guide._growth_marks(v)
	assert_bool(ui._badges[FarmGuide.GROWTH_TAG + "1"].visible).is_false()
	v.guide.step = "t_harvest_quick"
	v.quick_seeds = []
	guide._growth_marks(v)
	assert_bool(ui._badges[FarmGuide.GROWTH_TAG + "1"].visible).is_false()

func test_countdown_caption_avoids_pip_and_hides_under_panels_offscreen_and_on_leave() -> void:
	var v := _growing_view()
	var ui := await _marked_ui(v)
	var guide := _water_farm(ui)
	guide._growth_marks(v)
	var badge: UiStatusBadge = ui._badges[FarmGuide.GROWTH_TAG + "0"]
	ui.npc_tag(FarmGuide.TAG, "Pip", badge.get_global_rect().end, true)
	var tag: UiNpcNameTag = ui._npc_tags[FarmGuide.TAG]
	tag.position = badge.position + Vector2(0, badge.side())   # name covers the caption, not the clock
	var name_rect := tag.get_global_rect()
	guide._growth_marks(v)
	assert_bool(badge.visible).is_true()
	assert_bool(badge.get_global_rect().intersects(name_rect)).is_false()
	assert_that(tag.get_global_rect()).is_equal(name_rect)
	assert_bool(ui._marker_area().encloses(badge.get_global_rect())).is_true()
	ui._open_modal(Control.new())
	guide._growth_marks(v)
	assert_bool(badge.visible).is_false()
	ui.close_modal()
	guide._growth_marks(v)
	assert_bool(badge.visible).is_true()
	guide.farm.cam.position.x += 100.0
	guide._growth_marks(v)
	assert_bool(badge.visible).is_false()
	guide.farm.cam.position.x -= 100.0
	guide._growth_marks(v)
	guide.hide_marks()
	assert_bool(badge.visible).is_false()
	guide._growth_marks(v)
	guide.leave()
	assert_bool(badge.visible).is_false()

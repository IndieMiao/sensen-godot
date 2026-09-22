extends GdUnitTestSuite

func test_street_water_and_fishing_spots_keep_all_destinations_reachable() -> void:
	var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/regions.json"))
	for region in regions.regions:
		for candidate in region.candidates:
			var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(str(candidate.layout_patch_id), int(candidate.revision)))
			for opened in [false, true]:
				var layout := JourneyStreets.new(source, opened)
				for destination in layout.entrances.values():
					assert_bool(layout.nav.is_walkable(layout.nav.world_to_cell(destination))).is_true()
				for site in ["street_lake", "street_river"]:
					var target := FishingModel.stand(site)
					assert_bool(layout.nav.is_walkable(layout.nav.world_to_cell(target))).is_true()
					assert_bool(layout.grid.point_path(layout.entrances.farm, target).is_empty()).is_false()
				for j in layout.nav.grid.y:
					for i in layout.nav.grid.x:
						var cell := Vector2i(i, j)
						if FishingModel.water_at("street", layout.nav.cell_to_world(cell)):
							assert_bool(layout.nav.is_walkable(cell)).is_false()

func test_farm_uses_existing_water_mask_and_reachable_shore() -> void:
	var bp := FarmPlot.blueprint_for()
	var target := FishingModel.stand("farm_pond")
	assert_bool(bp.is_walkable(bp.world_to_cell(target))).is_true()
	assert_bool(BlueprintGrid.new(bp).point_path(bp.cell_to_world(bp.anchor("spawn")), target).is_empty()).is_false()
	assert_bool(bp.is_walkable(bp.world_to_cell(Vector3(9, 0, -30.75)))).is_false()

func test_all_tiers_can_be_caught_and_abandoned_input_loses() -> void:
	for tier in FishingModel.data().tiers.values():
		var model := FishingModel.initial(123456789)
		while model.outcome == "playing":
			FishingModel.step(model, float(model.fish) > float(model.bar) + float(model.velocity) * 0.15, tier)
		assert_str(model.outcome).is_equal("caught")
		model = FishingModel.initial(123456789)
		while model.outcome == "playing": FishingModel.step(model, false, tier)
		assert_str(model.outcome).is_equal("escaped")

func test_water_and_mobile_controls_instantiate() -> void:
	for id in FishingModel.data().sites:
		var water: FishingWater = auto_free(FishingWater.build(id))
		assert_object(water.get_node("FishingWaterSurface").mesh).is_not_null()
	var panel: FishingPanel = auto_free(FishingPanel.new())
	add_child(panel)
	var session := FarmSession.new(null)
	session.farm_id = "test-farm"
	session.state.bag = {"version": 2, "equipped": {"fishing_rod": {"item_id": "starter_fishing_rod"}}}
	panel.open(session, "farm_pond")
	await get_tree().process_frame
	assert_bool(panel.visible).is_true()
	assert_bool(panel._primary.disabled).is_false()
	await panel.close()
	assert_bool(panel.visible).is_false()

func test_releasing_a_hold_after_settlement_does_not_start_a_second_cast() -> void:
	var requests: Array = []
	var session := FarmSession.new(ApiClient.new("https://fishing.invalid/v1", func(_method, _path, _headers, body):
		requests.append(body)
		return ApiClient.Response.new(true, 422, {"code": "FISHING_LOCATION"})))
	session.farm_id = "test-farm"
	session.state.bag = {"version": 2, "equipped": {"fishing_rod": {"item_id": "starter_fishing_rod"}}}
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	panel.open(session, "farm_pond")
	panel.set_process(false)
	panel.phase = "playing"
	panel._primary.button_down.emit()
	panel.phase = "result"
	panel._primary.button_up.emit()
	panel._primary.pressed.emit()
	await get_tree().process_frame
	assert_array(requests).is_empty()
	panel._primary.button_down.emit()
	panel._primary.button_up.emit()
	panel._primary.pressed.emit()
	await get_tree().process_frame
	assert_int(requests.size()).is_equal(1)

func test_world_controls_leave_the_scene_visible_and_share_one_action_button() -> void:
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	var session := FarmSession.new(null)
	session.farm_id = "layout-test"
	panel.open(session, "farm_pond")
	panel.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(panel.find_children("*", "ColorRect", true, false)).is_empty()
	assert_int(panel.find_children("*", "Button", true, false).size()).is_equal(2)
	assert_vector(panel._primary.size).is_equal(Vector2(84, 84))
	assert_bool(panel._gauge.visible).is_false()
	panel.model = FishingModel.initial(13)
	panel.phase = "playing"
	panel._refresh_button()
	panel.anchor_gauge(Vector2(180, 300))
	await get_tree().process_frame
	assert_bool(panel._gauge.visible).is_true()
	assert_bool(panel._gauge.get_global_rect().intersects(panel._primary.get_global_rect())).is_false()
	assert_bool(panel._message_card.get_global_rect().intersects(panel._primary.get_global_rect())).is_false()
	assert_float(panel._message_card.position.y).is_less(panel._root.size.y * 0.3)
	assert_float(panel._root.size.y - panel._primary.position.y - panel._primary.size.y).is_greater_equal(48)
	var occupied: float = panel._primary.size.x * panel._primary.size.y + panel._gauge.size.x * panel._gauge.size.y + panel._message_card.size.x * panel._message_card.size.y + 44 * 44
	var screen := get_viewport().get_visible_rect().size
	assert_float(occupied / (screen.x * screen.y)).is_less(0.22)

func test_reeling_drives_hands_pole_float_and_line_then_restores_normal_scene() -> void:
	var root := auto_free(Node3D.new()) as Node3D
	add_child(root)
	var actor := Node3D.new()
	actor.position = FishingModel.stand("farm_pond")
	root.add_child(actor)
	var rig := preload("res://assets/avatar/base/base_rig.tscn").instantiate() as AvatarRig
	actor.add_child(rig)
	rig.play_motion("idle")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = actor.position + Vector3(5, 8, 6)
	camera.look_at(actor.position)
	var original_camera := camera.transform
	var original_rig := rig.transform
	var hud := Control.new()
	root.add_child(hud)
	var hidden_hud := Control.new()
	root.add_child(hidden_hud)
	hidden_hud.hide()
	var panel := FishingPanel.new()
	root.add_child(panel)
	var session := FarmSession.new(null)
	session.farm_id = "motion-test"
	panel.open(session, "farm_pond")
	panel.set_process(false)
	panel.phase = "playing"
	panel.model = FishingModel.initial(123)
	var view := FishingPresentation.new()
	root.add_child(view)
	view.configure(panel, actor, rig, camera, [hud, hidden_hud])
	view.set_process(false)
	panel.cast_started.emit()
	panel.phase = "waiting"
	view.step(0.05)
	assert_float(view._cast_age).is_less(0.1)
	assert_float(view.bobber_position.y).is_greater(0.5)
	view._cast_age = 10
	panel.phase = "playing"
	for i in 10: view.step(0.05)
	var eased_tip := view.rod_tip
	var eased_hand := view.hand_position
	var eased_float := view.bobber_position
	panel.held = true
	for i in 14: view.step(0.05)
	assert_float(view.rod_tip.distance_to(eased_tip)).is_greater(0.35)
	assert_float(view.hand_position.distance_to(eased_hand)).is_greater(0.07)
	assert_float(view.bobber_position.distance_to(eased_float)).is_greater(0.10)
	assert_float(view.line_points[0].distance_to(view.rod_tip)).is_less(0.00001)
	assert_float(view.line_points[-1].distance_to(view.bobber_position)).is_less(0.00001)
	var wrist: int = view._bones["Wrist_R"]
	var hand := rig.skeleton.to_global(view._global_pose(wrist).origin)
	assert_float(hand.distance_to(view.hand_position)).is_less(0.08)
	assert_bool(hud.visible).is_false()
	view.finish()
	assert_bool(hud.visible).is_true()
	assert_bool(hidden_hud.visible).is_false()
	assert_that(camera.transform).is_equal(original_camera)
	assert_that(rig.transform).is_equal(original_rig)
	assert_bool(rig.get_node("AnimationPlayer").is_playing()).is_true()
	await get_tree().process_frame


func test_free_shore_plans_reach_different_banks_and_retain_exact_current_position() -> void:
	var bp := FarmPlot.blueprint_for()
	var grid := BlueprintGrid.new(bp)
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	var origins: Array = []
	for clicked in [Vector3(9, 0, -28.6), Vector3(12.4, 0, -30.75), Vector3(5.6, 0, -30.75), Vector3(9, 0, -32.8)]:
		var plan := FishingModel.plan("farm_pond", spawn, clicked, grid)
		assert_bool(plan.is_empty()).is_false()
		if plan.is_empty(): continue
		assert_bool(FishingModel.valid_cast("farm_pond", plan.origin, plan.target, grid)).is_true()
		assert_bool(grid.point_path(spawn, plan.origin).is_empty()).is_false()
		origins.append(plan.origin)
	assert_float((origins[0] as Vector3).distance_to(origins[-1])).is_greater(3)
	var exact := Vector3(9.123, 0, -27.4)
	assert_vector(FishingModel.plan("farm_pond", exact, Vector3(9, 0, -29), grid).origin).is_equal(exact)
	assert_bool(FishingModel.valid_cast("farm_pond", Vector3(21, 0, -26), Vector3(9, 0, -29), grid)).is_false()

func test_remote_fishing_animates_without_ui_or_camera_changes_and_cleans_up() -> void:
	var root := auto_free(Node3D.new()) as Node3D
	add_child(root)
	var actor := Node3D.new()
	root.add_child(actor)
	actor.position = Vector3(9.123, 0, -27.4)
	var rig := preload("res://assets/avatar/base/base_rig.tscn").instantiate() as AvatarRig
	actor.add_child(rig)
	rig.play_motion("idle")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = actor.position + Vector3(5, 8, 6)
	camera.look_at(actor.position)
	var original := camera.transform
	var view := FishingPresentation.new()
	root.add_child(view)
	view.configure_remote({"site": "farm_pond", "sequence": 1, "target": [9, -29], "phase": "playing", "held": false, "cast_age": 5, "fish": 0.5}, actor, rig, camera)
	view.set_process(false)
	for i in 10: view.step(0.05)
	var tip := view.rod_tip
	view.remote_state.held = true
	for i in 15: view.step(0.05)
	assert_float(view.rod_tip.distance_to(tip)).is_greater(0.35)
	assert_that(camera.transform).is_equal(original)
	assert_object(view.panel).is_null()
	view.remote_state.merge({"phase": "result", "outcome": "caught", "fish_id": "fish_koi", "age": 0}, true)
	view.step(0.05)
	assert_bool(view._catch.visible).is_true()
	view.finish()
	await get_tree().process_frame
	assert_bool(is_instance_valid(view)).is_false()
	assert_bool(rig.get_node("AnimationPlayer").is_playing()).is_true()
	assert_that(camera.transform).is_equal(original)


class FeedbackSession extends FarmSession:
	var fail := false
	func _init() -> void:
		super(null)
		farm_id = "feedback-test"
		state = {"fishing": {"sequence": 1, "active": {"fish_id": "fish_crucian", "hook_until": 1}}}
	func refresh() -> bool:
		offline = false
		return true
	func send(type: String, _payload: Dictionary, _pending_owner: StringName = &"") -> bool:
		await Engine.get_main_loop().create_timer(0.12).timeout
		if fail:
			last_error_code = "NETWORK_ERROR"
			offline = true
			return false
		state.fishing.active = null
		state.fishing.last = {"sequence": 1, "outcome": "escaped" if type == "finish_fishing" else "cancelled"}
		return true

func test_escaped_fish_is_explicit_even_while_settlement_is_pending() -> void:
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	var session := FeedbackSession.new()
	panel.open(session, "farm_pond")
	panel.set_process(false)
	panel.phase = "playing"
	panel.model = FishingModel.initial(1)
	panel.model.merge({"progress": 0.001, "bar": 0.95, "fish": 0.1}, true)
	panel._process(0.05)
	assert_str(panel.phase).is_equal("settling")
	assert_str(panel._notice_heading.text).is_equal(L10n.text("Fish escaped"))
	assert_str(panel._primary.text).is_equal(L10n.text("Reeling in"))
	assert_bool(panel._message_card.visible).is_true()
	await get_tree().create_timer(0.2).timeout
	assert_str(panel.phase).is_equal("result")
	assert_str(panel._notice_heading.text).is_equal(L10n.text("Fish escaped"))
	assert_str(panel._status.text).is_equal(L10n.text("No fish this time. Tap Again to try another cast."))
	assert_bool(panel._primary.disabled).is_false()

func test_failed_cancel_keeps_the_connection_error_instead_of_overwriting_it_as_stopped() -> void:
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	var session := FeedbackSession.new()
	session.fail = true
	panel.open(session, "farm_pond")
	panel.set_process(false)
	await panel._cancel("missed")
	assert_str(panel.phase).is_equal("error")
	assert_str(panel._notice_heading.text).is_equal(L10n.text("Checking your catch"))
	assert_str(panel._primary.text).is_equal(L10n.text("Retry"))
	assert_bool(session.state.fishing.active is Dictionary).is_true()

func test_missed_bite_and_missing_active_cast_each_show_their_reason() -> void:
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	panel.open(FeedbackSession.new(), "farm_pond")
	panel.set_process(false)
	panel.phase = "hook"
	panel._process(0.05)
	assert_str(panel._notice_heading.text).is_equal(L10n.text("Fish escaped"))
	await get_tree().create_timer(0.2).timeout
	assert_str(panel._status.text).is_equal(L10n.text("Missed the bite. Tap Hook when the float dips."))
	panel.phase = "playing"
	panel._process(0.05)
	assert_str(panel.phase).is_equal("error")
	assert_str(panel._notice_heading.text).is_equal(L10n.text("Fishing did not finish"))
	assert_bool(panel._message_card.visible).is_true()


func test_connection_recovery_does_not_present_an_older_catch_as_the_current_result() -> void:
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	var session := FeedbackSession.new()
	session.state.fishing.active = null
	session.state.fishing.last = {"sequence": 1, "outcome": "caught", "fish_id": "fish_crucian"}
	session.offline = true
	panel.open(session, "farm_pond")
	panel.set_process(false)
	await panel._action()
	assert_str(panel.phase).is_equal("ready")
	assert_str(panel._notice_heading.text).is_empty()
	panel._cast_sequence = 2
	session.offline = true
	session.state.fishing.last = {"sequence": 2, "outcome": "escaped"}
	await panel._action()
	assert_str(panel.phase).is_equal("result")
	assert_str(panel._notice_heading.text).is_equal(L10n.text("Fish escaped"))


func test_cast_requires_equipped_rod_without_sending_or_creating_a_cast() -> void:
	var requests: Array = []
	var session := FarmSession.new(ApiClient.new("https://fishing.invalid/v1", func(_method, _path, _headers, body):
		requests.append(body)
		return ApiClient.Response.new(false, 0, {})))
	session.farm_id = "no-rod"
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	panel.open(session, "farm_pond")
	panel.set_process(false)
	await panel._cast()
	assert_array(requests).is_empty()
	assert_str(panel.phase).is_equal("error")
	assert_str(panel._status.text).is_equal(L10n.text("Equip a fishing rod on the character page first."))


func test_ready_notice_shrinks_after_first_wrapped_layout() -> void:
	var panel: FishingPanel = auto_free(FishingPanel.new())
	add_child(panel)
	var session := FarmSession.new(null)
	session.farm_id = "water-notice"
	panel.open(session, "farm_pond")
	for frame in 12: await get_tree().process_frame
	assert_float(panel._message_card.size.y).is_less(100.0)
	assert_float(panel._message_card.size.y).is_greater(20.0)

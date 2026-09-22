extends GdUnitTestSuite
## 访客实例：只读、挥手、印章；零写入；从冻结快照渲染。

const FARM_SCENE := "res://scenes/farm/farm.tscn"

var _saved_navigation_pending: bool

func before_test() -> void:
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	AppRouter._navigation_pending = _saved_navigation_pending
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""

func _snapshot() -> Dictionary:
	# 随包的繁茂样例：9 格 growing，6 格 ripe（萝卜），生菜没熟
	var sample: Dictionary = PresetSnapshots.entries("shanghai").filter(func(entry): return entry.avatar_ref == "preset_a")[0]
	return PresetSnapshots.snapshot(sample.farm_id)

func _visitor(snap: Dictionary = {}) -> Node:
	if snap.is_empty(): snap = _snapshot()
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(str(snap.layout_patch_id), int(snap.blueprint_revision)))
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"visitor": true, "snapshot": snap, "blueprint": bp})
	add_child(auto_free(scene))
	await get_tree().process_frame
	return scene

func test_title_says_visiting_and_names_the_avatar() -> void:
	var f: Node = await _visitor()
	assert_bool(f.visitor).is_true()
	assert_str(f.title.text).starts_with("Visiting · ")
	assert_str(f.title.text).is_equal("Visiting · Sample A")

func test_no_session_no_predictor_no_director() -> void:
	# 访客不挂任何能写的东西。
	var f: Node = await _visitor()
	assert_object(f.session).is_null()
	assert_object(f.predictor).is_null()
	assert_object(f.director).is_null()

func test_owner_tools_hidden_visitor_bar_shown() -> void:
	var f: Node = await _visitor()
	assert_bool((f.hud.get_node("BottomBar") as Control).visible).is_false()
	assert_bool(f.hud._coins.visible).is_false()
	assert_bool(f.hud._stall.visible).is_false()
	assert_bool(f.hud._goals.visible).is_false()
	assert_bool(f.hud._condition.get_parent().visible).is_true()       # 田况来自冻结快照
	var bar := f.hud.get_node("VisitorBar") as Control
	assert_bool(bar.visible).is_true()
	var texts := []
	for b in bar.get_children():
		texts.append((b as Button).text)
		assert_bool((b as Control).custom_minimum_size.y >= 44.0).is_true()
	assert_array(texts).is_equal(["Wave", "Stamp"])

func test_crops_render_from_snapshot_with_ripe_as_top_stage() -> void:
	var f: Node = await _visitor()
	var counts: Dictionary = f.crop_field.cell_counts()
	assert_int(int(counts["R"])).is_equal(6)
	assert_int(int(counts["L"])).is_equal(3)
	# The 4.7 dummy renderer cannot read back MultiMesh transforms; native QA covers scale.
	if DisplayServer.get_name() == "headless":
		assert_int(CropField.stage_from_snapshot({"state": "growing", "ripe": true})).is_equal(3)
		assert_int(CropField.stage_from_snapshot({"state": "growing", "ripe": false})).is_equal(1)
		return
	# 熟的萝卜用成熟阶段的高度；没熟的生菜是阶段 1
	var mm_r: MultiMesh = f.crop_field._mm["R"].multimesh
	var ripe_h: float = CropField.STAGE_SIZE[CropField.STAGES - 1].y * f.bp.cell_m
	assert_float(mm_r.get_instance_transform(0).basis.get_scale().y).is_equal_approx(ripe_h, 0.001)
	var mm_l: MultiMesh = f.crop_field._mm["L"].multimesh
	assert_float(mm_l.get_instance_transform(0).basis.get_scale().y).is_equal_approx(CropField.STAGE_SIZE[1].y * f.bp.cell_m, 0.001)

func test_snapshot_stage_mapping() -> void:
	assert_int(CropField.stage_from_snapshot({"state": "growing", "ripe": true})).is_equal(CropField.STAGES - 1)
	assert_int(CropField.stage_from_snapshot({"state": "growing", "ripe": false})).is_equal(1)
	assert_int(CropField.stage_from_snapshot({"state": "sown", "ripe": false})).is_equal(0)

func _reserved_props(scene: Node) -> Array:
	return scene.props.get_children().filter(func(prop): return prop.has_meta("reserved"))


func _worked_reserved_snapshot() -> Dictionary:
	var snap := _snapshot()
	snap.erase("beds_unlocked")
	var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(str(snap.layout_patch_id), int(snap.blueprint_revision)))
	var reserved: Vector2i = source.reserved_bed().cells[0]
	for cell in snap.cells:
		if str(cell.cell_id) == "%d,%d" % [reserved.x, reserved.y]: cell.state = "tilled"
	return snap


func test_zero_writes_even_if_a_tool_is_forced() -> void:
	# 就算有人把工具塞进来，访客也一格都不入队、一条命令都不发。
	var t := FakeTransport.new([])
	Net.use_transport(t.callable())
	Net.client.token = "tok"
	var f: Node = await _visitor()
	var soil := [Vector2i(10, 10), Vector2i(11, 10)]
	f._set_work_mode(true)
	assert_bool(f.work_mode).is_false()
	f._tap_cell(soil[0])                                       # 访客可以走过田地，但不能劳作
	assert_int(f._queue_plots(soil)).is_equal(0)
	assert_bool(f.runner.is_busy()).is_false()
	f._process(0.016)
	f._wave()
	f._stamp()
	f._process(0.016)
	assert_int(t.requests.size()).is_equal(0)

func test_visitor_snapshot_keeps_cultivated_soil_under_the_crops() -> void:
	var snapshot := _snapshot()
	var cell := FarmPlot.blueprint_for().anchor("spawn")
	snapshot.cells = [{"cell_id": "%d,%d" % [cell.x, cell.y], "state": "growing", "crop": "R", "ripe": true}]
	var farm := await _visitor(snapshot)
	assert_int(farm.plot_surface._image.get_pixelv(cell).g8).is_equal(PlotSurface.STATE_RIPE)
	assert_bool(farm.camera_pan.hold_enabled).is_false()

func test_wave_locks_the_animation_briefly_and_is_registered() -> void:
	var f: Node = await _visitor()
	assert_bool(AnimPlaceholders.is_registered("wave")).is_true()
	f._wave()
	assert_bool(f._action_locked()).is_true()
	f._process(1.3)
	assert_bool(f._action_locked()).is_false()

func test_stamp_is_a_local_label_that_expires() -> void:
	var f: Node = await _visitor()
	f._stamp()
	var stamp: Node = f.player.get_node_or_null("Stamp")
	assert_object(stamp).is_not_null()
	assert_str((stamp as Label3D).text).is_equal("Nice!")
	f._stamp()                                              # 第二枚换词并顶掉第一枚
	assert_str((f.player.get_node("Stamp") as Label3D).text).is_equal("Lovely")
	await get_tree().create_timer(f.STAMP_LIFETIME_S + 0.3).timeout
	await get_tree().process_frame
	assert_object(f.player.get_node_or_null("Stamp")).is_null()

func test_leaving_reports_visit_once_without_blocking() -> void:
	# 只写一条零奖励教学事实；D4 之前服务端回 CHAPTER_LOCKED，静默。
	var t := FakeTransport.new([{"status": 422, "json": {"code": "CHAPTER_LOCKED"}}])
	Net.use_transport(t.callable())
	Net.client.token = "tok"
	Net.session.farm_id = "mine"
	Net.session.version = 0
	var f: Node = await _visitor()
	f._record_visit()
	await get_tree().process_frame
	assert_int(t.requests.size()).is_equal(1)
	assert_str(str(t.requests[0].body.type)).is_equal("record_visit_return")
	assert_str(str(t.requests[0].body.payload.visited_farm_id)).is_equal(str(f.snapshot.farm_id))

func test_visitor_without_own_farm_reports_nothing() -> void:
	var t := FakeTransport.new([])
	Net.use_transport(t.callable())
	Net.client.token = "tok"                                # 登录了但还没建场
	var f: Node = await _visitor()
	f._record_visit()
	assert_int(t.requests.size()).is_equal(0)

func test_hud_text_is_english() -> void:
	var f: Node = await _visitor()
	var stack: Array = [f.hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		for ch in text:
			assert_bool(ch.unicode_at(0) < 0x2E80).override_failure_message("含非英文: %s" % text).is_true()
	for ch in f.title.text:
		assert_bool(ch.unicode_at(0) < 0x2E80).is_true()

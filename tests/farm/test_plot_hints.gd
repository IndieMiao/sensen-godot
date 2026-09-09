extends GdUnitTestSuite

var viewport: SubViewport
var camera: Camera3D
var hints: PlotHints
var draws := 0

func before_test() -> void:
	draws = 0
	viewport = auto_free(SubViewport.new())
	viewport.size = Vector2i(360, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.position = Vector3(3, 9, 6)
	camera.look_at(Vector3(3, 0, -3))
	hints = PlotHints.new()
	hints.cam = camera
	hints.bp = FarmBlueprint.load_file("res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json")
	viewport.add_child(hints)
	hints.world_rect = Rect2(0, 0, 360, 640)
	hints.draw.connect(func(): draws += 1)
	await _frame()

func _frame(delta := 0.016) -> void:
	hints.update_motion(false, [], delta)
	await get_tree().process_frame
	await get_tree().process_frame

func test_stationary_hints_retain_geometry_until_crop_becomes_ready() -> void:
	var cells := {"3,3": {"state": "growing", "crop": "R", "ready_at": 2000}}
	hints.sync(cells, 1000, "sunny")
	await _frame()
	var initial := draws
	for now in [1100, 1200, 1500, 1999]:
		hints.sync(cells, now, "sunny")
		await _frame()
	assert_int(draws).is_equal(initial)
	assert_bool(hints._targets.has("3,3")).is_false()
	hints.sync(cells, 2000, "sunny")
	await _frame()
	assert_int(draws).is_greater(initial)
	assert_bool(hints._targets.has("3,3")).is_true()
	assert_vector(hints.pick(hints._targets["3,3"] + hints.global_position)).is_equal(Vector2i(3, 3))

func test_pan_zoom_and_work_progress_refresh_the_targets() -> void:
	hints.sync({"3,3": {"state": "tilled"}}, 1000, "sunny")
	await _frame()
	var original: Vector2 = hints._targets["3,3"]
	camera.position.x += 1
	await _frame()
	assert_bool(hints._targets["3,3"].is_equal_approx(original)).is_false()
	original = hints._targets["3,3"]
	camera.size = 8
	await _frame()
	assert_bool(hints._targets["3,3"].is_equal_approx(original)).is_false()
	var initial := draws
	hints.active = Vector2i(3, 3)
	hints.progress = 0.5
	await _frame()
	assert_int(draws).is_greater(initial)
	initial = draws
	hints.progress = 0.8
	await _frame()
	assert_int(draws).is_greater(initial)

func test_destination_animates_then_clears_without_continuous_redraw() -> void:
	hints.destination(Vector3(3, 0, -3), true, [])
	await _frame()
	var initial := draws
	await _frame(0.1)
	assert_int(draws).is_greater(initial)
	initial = draws
	await _frame(0.7)
	assert_bool(hints._destination_visible).is_false()
	assert_int(draws).is_greater(initial)
	initial = draws
	await _frame()
	await _frame()
	assert_int(draws).is_equal(initial)

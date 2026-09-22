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

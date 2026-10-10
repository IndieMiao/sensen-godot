extends GdUnitTestSuite
## Placement's top-down view (用户 on 284 058639c7; 不知火舞 284 v2 6a751a9a; 哪吒 on #261): straight down with no yaw,
## 36 px a cell when it opens, two fingers zoom 17–56 px a cell; the real camera at 360 × 800 in a SubViewport.

const P0Farm := preload("res://scenes/p0/p0_farm.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const PHONE := Vector2(360, 800)

func _camera() -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = FarmCamera.close_view_size(PHONE) * FarmCamera.P0_VIEW_K
	vp.add_child(cam)
	cam.make_current()
	return cam

## Two neighbouring cell centres on screen, in pixels.
func _cell_px(cam: Camera3D, bp: FarmBlueprint, at: Vector2i) -> float:
	return cam.unproject_position(bp.cell_to_world(at)).distance_to(cam.unproject_position(bp.cell_to_world(at + Vector2i(1, 0))))

func test_the_view_turns_straight_down_at_36_px_a_cell_and_pinches_to_56() -> void:
	var cam := _camera()
	var bp := P0Garden.blueprint()
	var focus := bp.cell_to_world(Vector2i(9, 7))
	P0Farm.place_top(cam, focus, 1.0, P0Farm.TOP_CELL_PX, bp.cell_m)
	assert_float(cam.global_basis.z.y).is_equal_approx(1.0, 0.001)   # looking straight down
	assert_float(cam.rotation.y).is_equal_approx(0.0, 0.001)         # no yaw: cells square on screen
	assert_float(_cell_px(cam, bp, Vector2i(9, 7))).is_equal_approx(36.0, 0.5)
	# the same row stays level on screen; the next row is straight below it (the farmhouse, back, is at the top)
	var a := cam.unproject_position(bp.cell_to_world(Vector2i(9, 7)))
	var b := cam.unproject_position(bp.cell_to_world(Vector2i(10, 7)))
	assert_float(a.y).is_equal_approx(b.y, 0.5)
	var px := P0Farm.top_cell_after(P0Farm.TOP_CELL_PX, 0.5)   # fingers apart: zoom in, stopped at 56
	assert_float(px).is_equal(56.0)
	P0Farm.place_top(cam, focus, 1.0, px, bp.cell_m)
	assert_float(_cell_px(cam, bp, Vector2i(9, 7))).is_equal_approx(56.0, 0.5)
	assert_float(P0Farm.top_cell_after(20.0, 2.0)).is_equal(17.0)   # fingers together: out, stopped at 17

func test_half_way_the_turn_is_between_the_two_views() -> void:
	var cam := _camera()
	var bp := P0Garden.blueprint()
	P0Farm.place_top(cam, bp.cell_to_world(Vector2i(9, 7)), 0.5, P0Farm.TOP_CELL_PX, bp.cell_m)
	var pitch := rad_to_deg(-cam.rotation.x)
	assert_float(pitch).is_between(FarmCamera.PITCH_DEG + 1.0, 89.0)
	assert_float(rad_to_deg(cam.rotation.y)).is_between(0.5, FarmCamera.YAW_DEG - 0.5)

# ---------------------------------------------------------------- the player while placing (user on 284 14e11a67)
func _farm() -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(auto_free(farm))
	var who := P0Actor.new()
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	who.add_child(body)
	farm.add_child(who)
	farm.actor = who
	return farm

## Out in 0.2 s, its shadow gone half way, not drawn while placing; in again in 0.2 s, whole and opaque again.
func test_the_player_fades_out_and_back_in_with_its_shadow() -> void:
	var farm := _farm()
	var body: MeshInstance3D = farm.actor.get_child(0)
	farm._actor_fade_to = 1.0
	farm._step_actor_fade(0.05)
	assert_float(body.transparency).is_equal_approx(0.25, 0.001)
	assert_int(body.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	farm._step_actor_fade(0.1)
	assert_int(body.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_bool(farm.actor.visible).is_true()
	farm._step_actor_fade(0.1)
	assert_bool(farm.actor.visible).is_false()   # placing: not drawn at all
	farm._actor_fade_to = 0.0
	farm._step_actor_fade(0.05)
	assert_bool(farm.actor.visible).is_true()
	assert_int(body.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	farm._step_actor_fade(0.2)
	assert_float(body.transparency).is_equal(0.0)   # out of the transparent pipeline again
	assert_int(body.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

## Back on the nearest free cell by walking, not in a straight line (不知火舞 on #261): solid cells are walls, the
## placed piece's cells can be crossed but not stood on; where it stood when that is free; there when nothing is in reach.
func test_the_player_comes_back_on_the_nearest_free_cell_by_walking() -> void:
	var g := BlueprintGrid.new(P0Garden.blueprint())
	var c := P0Garden.cell_of(14)
	for d in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, 0), Vector2i(0, -1)]:
		assert_bool(g.astar.is_point_solid(c + d)).is_false()
	assert_that(P0Farm.free_cell_near(g, c, [])).is_equal(c)
	assert_that(P0Farm.free_cell_near(g, c, [c])).is_equal(c + Vector2i(1, 0))   # one step off
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(-1, -1)]: g.set_solid(c + d, true)
	# a 1×2 piece over c and the cell above: out through the piece, two steps up, though c + (1, 1) is nearer in a line
	assert_that(P0Farm.free_cell_near(g, c, [c, c + Vector2i(0, -1)])).is_equal(c + Vector2i(0, -2))
	g.set_solid(c + Vector2i(0, -1), true)
	assert_that(P0Farm.free_cell_near(g, c, [c])).is_equal(c)   # walled in: stays
	# Decorate's pieces are solid in the grid: their own cells are still crossed on the way out (苏烈 on #261)
	g.set_solid(c, true)
	assert_that(P0Farm.free_cell_near(g, c, [c, c + Vector2i(0, -1)])).is_equal(c + Vector2i(0, -2))

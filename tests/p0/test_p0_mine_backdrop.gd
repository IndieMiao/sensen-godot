extends GdUnitTestSuite
## The P0 mine's underground backdrop (SGODOT-257; asset #162, spec 不知火舞): placed as authored at the origin, unlit
## with each floor's darkened wall tint fading into the mine's void colour, no shadow, no GI.

const P0Mine := preload("res://scenes/p0/p0_mine.gd")

func test_each_floor_tints_the_backdrop_with_its_darkened_wall_colour() -> void:
	# floor 1 #B85E43 darkened 45 %, floor 2 #A59A77 darkened 50 % (asset README, 不知火舞)
	for c in [[1, Color("B85E43"), 0.55], [2, Color("A59A77"), 0.5]]:
		var t := MineBackdrop.tint(c[0])
		var wall: Color = c[1]
		for i in 3: assert_float(t[i]).is_equal_approx(wall[i] * float(c[2]), 0.00001)
		assert_float(t.a).is_equal(1.0)
	for n in [1, 2]:
		var root: Node3D = auto_free(MineBackdrop.build(n))
		var meshes := root.find_children("*", "GeometryInstance3D", true, false)
		assert_int(meshes.size()).is_greater(0)
		for g: GeometryInstance3D in meshes:
			var mat := g.material_override as ShaderMaterial
			assert_object(mat).is_not_null()
			assert_that(mat.get_shader_parameter("floor_tint")).is_equal(MineBackdrop.tint(n))
			assert_that(mat.get_shader_parameter("void_tint")).is_equal(MineBackdrop.VOID)
			assert_int(g.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			assert_int(g.gi_mode).is_equal(GeometryInstance3D.GI_MODE_DISABLED)

## Authored for the mine camera at the world origin: no transform anywhere on the way down to the mesh.
func test_the_backdrop_sits_as_authored_at_the_origin() -> void:
	var root: Node3D = auto_free(MineBackdrop.build(1))
	assert_that(root.transform).is_equal(Transform3D.IDENTITY)
	for g: Node3D in root.find_children("*", "Node3D", true, false):
		assert_that(g.transform).is_equal(Transform3D.IDENTITY)

## Its outer edge fades into the mine's background: P0Mine's Environment takes the same colour from MineBackdrop.
func test_the_void_tint_is_the_mines_background() -> void:
	assert_that(MineBackdrop.VOID).is_equal(Color("242125"))
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_mine.gd")
	assert_bool(src.contains("environment.background_color = MineBackdrop.VOID")).is_true()
	# Opaque and unlit: the fade is a colour mix, no ALPHA is written (README).
	var shader := FileAccess.get_file_as_string("res://modules/mining/mine_backdrop.gdshader")
	assert_bool(shader.contains("ALPHA =")).is_false()
	assert_bool(shader.contains("unshaded")).is_true()

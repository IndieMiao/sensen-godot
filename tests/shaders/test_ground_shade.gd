extends GdUnitTestSuite
## SGODOT-457 (盘古; 上官婉儿's spec 11-09): the shade GLES draws for the trees and the farmhouse, where no sun casts a
## shadow. What casts, and where its shade falls, are plain functions of the pieces' boxes and the sun: no renderer is
## needed (the mask itself is drawn only with one, so not headless). A MultiMesh's instances are not here: headless, the
## rendering server keeps no instance transforms (they all read as the origin); the wild's shots cover them (457 55064be3).

const GroundShade = preload("res://modules/render/ground_shade.gd")
const SUN_45_FROM_WEST := Vector3(-0.70710678, 0.70710678, 0.0)   # pointing at the sun: shades fall east, a metre a metre

func _box(size: Vector3, at: Vector3, parent: Node) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = at + Vector3(0, size.y * 0.5, 0)   # standing on the ground at `at`
	parent.add_child(m)
	return m

func _root() -> Node3D:
	var r: Node3D = auto_free(Node3D.new())
	add_child(r)
	return r

func test_a_caster_is_its_box_centre_top_and_half_its_wider_side() -> void:
	var c := GroundShade.caster_of(AABB(Vector3(1, 0, 2), Vector3(2, 3, 1)))
	assert_vector(c).is_equal(Vector4(2, 2.5, 3, 1))

func test_a_crown_is_thrown_from_its_middle_along_the_sun() -> void:
	var c := Vector4(0, 0, 4, 1)   # 4 m tall: the crown from 1.2 m up, its middle at 2.6 m
	var overhead: Array = GroundShade.shade_of(c, Vector3.UP)
	assert_vector(overhead[0]).is_equal(Vector2.ZERO)
	assert_float(overhead[1]).is_equal_approx(GroundShade.r_k, 1e-5)
	var low: Array = GroundShade.shade_of(c, SUN_45_FROM_WEST)
	assert_vector(low[0]).is_equal_approx(Vector2(2.6, 0), Vector2(1e-4, 1e-4))
	assert_float(low[3]).is_equal_approx(0.0, 1e-5)   # east
	assert_float(low[1]).is_greater(float(low[2]))   # longer along the throw

func test_only_tall_visible_shadow_casting_pieces_not_too_wide_cast() -> void:
	var r := _root()
	_box(Vector3(1, 3, 1), Vector3(0, 0, 0), r)                       # a tree: casts
	_box(Vector3(1, 1.5, 1), Vector3(5, 0, 0), r)                     # a bush: under MIN_H
	_box(Vector3(10, 3, 10), Vector3(0, 0, 9), r)                     # wider than MAX_R: ground
	var off := _box(Vector3(1, 3, 1), Vector3(-5, 0, 0), r)
	off.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # casts nothing on Metal either
	var hidden := _box(Vector3(1, 3, 1), Vector3(-9, 0, 0), r)
	hidden.visible = false
	var skipped := Node3D.new()                                       # what moves (the insects), or a building
	r.add_child(skipped)
	_box(Vector3(1, 3, 1), Vector3(9, 0, 0), skipped)
	var cs := GroundShade.casters_under(r, null, [skipped])
	assert_int(cs.size()).is_equal(1)
	assert_vector(cs[0]).is_equal(Vector4(0, 0, 3, 0.5))

func test_a_building_throws_its_whole_footprint_and_roof() -> void:
	var hull := GroundShade.box_shade(AABB(Vector3(0, 0, 0), Vector3(2, 3, 2)), SUN_45_FROM_WEST)
	var reach := 3.0 * GroundShade.ROOF_K   # the roof thrown east, a metre a metre
	var xs: Array[float] = []
	for p in hull: xs.append(p.x)
	assert_float(xs.min()).is_equal_approx(0.0, 1e-4)
	assert_float(xs.max()).is_equal_approx(2.0 + reach, 1e-4)
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(1, 1), hull)).is_true()           # under it
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(2 + reach - 0.1, 1), hull)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(-0.5, 1), hull)).is_false()       # nothing towards the sun

func test_a_building_root_counts_itself_and_its_parts() -> void:
	var r := _root()
	var house := _box(Vector3(2, 2.1, 2), Vector3(0, 0, 0), r)   # the farm's house prop is itself a MeshInstance3D
	_box(Vector3(1, 1, 1), Vector3(3, 0, 0), house)                 # a porch, lower than MIN_H: still a building's
	var gone := _box(Vector3(1, 1, 1), Vector3(-3, 0, 0), house)
	gone.visible = false
	assert_int(GroundShade.boxes_under(house).size()).is_equal(2)
	# and as a building, not a tree as well: casters_under leaves it to boxes_under
	assert_int(GroundShade.casters_under(r, null, [house]).size()).is_equal(0)

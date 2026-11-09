extends GdUnitTestSuite
## The wild ground's bake (SGODOT-422, 盘古; #917 GLES frame rate): headless the full shader stays (a SubViewport never
## draws there, so the scene must not wait on it); the bake's key follows the pond, its plants' feet and the bank's
## trees (they move with the gathering points), so a rebuild bakes anew and the same pond again takes the kept one; one
## bake kept, its textures' size known.

const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
const PondWildGroundBake := preload("res://modules/ponds/pond_wild_ground_bake.gd")
const FULL := preload("res://modules/ponds/pond_wild_ground.gdshader")
const SF := ["pond_san_francisco_01", "pond_san_francisco_02", "pond_san_francisco_03"]

func _painted(scene: Node) -> MeshInstance3D: return scene.find_child("PaintedGround", true, false) as MeshInstance3D

func test_headless_keeps_the_full_shader_and_does_not_wait() -> void:
	PondWildGroundBake.clear_cache()
	var scene: Node3D = auto_free(PondScenery.build(P0Ponds.location(SF[2])))
	add_child(scene)
	for i in 3: await get_tree().process_frame
	var ground := _painted(scene)
	assert_bool(PondWildGroundBake.headless()).is_true()
	assert_object((ground.material_override as ShaderMaterial).shader).is_equal(FULL)
	assert_object(scene.find_child("GroundBake", true, false)).is_not_null()
	assert_int(scene.find_children("*", "SubViewport", true, false).size()).is_equal(0)   # nothing waits on a draw
	assert_int(PondWildGroundBake._CACHE.size()).is_equal(0)

func test_the_key_follows_the_pond_its_plants_and_trees() -> void:
	var a := _painted(auto_free(PondScenery.build(P0Ponds.location(SF[0]))))
	var again := _painted(auto_free(PondScenery.build(P0Ponds.location(SF[0]))))
	var other := _painted(auto_free(PondScenery.build(P0Ponds.location(SF[1]))))
	var ka := PondWildGroundBake.key("s", a.material_override)
	assert_str(PondWildGroundBake.key("s", again.material_override)).is_equal(ka)   # the same pond again: the kept bake
	assert_str(PondWildGroundBake.key("s", other.material_override)).is_not_equal(ka)
	assert_str(PondWildGroundBake.key("t", a.material_override)).is_not_equal(ka)   # another shape
	var m := (a.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	var feet: PackedVector2Array = m.get_shader_parameter("contact_points")
	feet[0] += Vector2(0.5, 0)   # a gathering point came: the plants moved
	m.set_shader_parameter("contact_points", feet)
	assert_str(PondWildGroundBake.key("s", m)).is_not_equal(ka)
	var n := (a.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	var trees: PackedVector2Array = n.get_shader_parameter("under_trees")
	trees[0] = Vector2(1e4, 1e4)   # a bank tree left out
	n.set_shader_parameter("under_trees", trees)
	assert_str(PondWildGroundBake.key("s", n)).is_not_equal(ka)

func test_one_bake_kept_and_its_size() -> void:
	assert_int(PondWildGroundBake.CACHE_MAX).is_equal(1)
	var b := PondWildGroundBake.bytes()
	assert_int(b.x).is_between(12_500_000, 13_000_000)   # 1300 × 1850 RGBA8 with mipmaps
	assert_int(b.y).is_between(1_400_000, 1_500_000)     # 528 × 512
	var a := _painted(auto_free(PondScenery.build(P0Ponds.location(SF[0]))))
	assert_float(PondWildGroundBake.soft_share(a.material_override)).is_between(0.5, 0.75)

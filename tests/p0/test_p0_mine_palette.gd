extends GdUnitTestSuite
## 355 mine colours (contract-efg §10.1; C59, 上官婉儿's assets/mine/types/<type>/palette.json): a mine type's band by
## floor — ground and wall for the chamber, backdrop_tint for the relief, fog for the void and the Environment — band 1
## the colours the mine had; a type's own relief with its veins left in their colour where it is imported.

const Art := preload("res://modules/mining/mine_art.gd")
const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")
const STORE := "user://test_p0_mine_palette.json"
const P0_MINE := "res://scenes/p0/p0_mine.tscn"

var rt: P0Runtime
var mine: Node3D

func after_test() -> void:
	if is_instance_valid(mine): mine.queue_free()
	if rt != null: P0Runtime.free_instance_for_tests()
	rt = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	await get_tree().process_frame

func _bands(type: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/mine/types/%s/palette.json" % type)).bands

func test_a_floor_takes_its_band_and_past_the_last_the_last() -> void:
	for type in ["quarry", "vein"]:
		var bands := _bands(type)
		assert_int(bands.size()).is_greater(1)
		for b in bands:
			for n in [int(b.from), int(b.to)]:
				var p := Art.palette(type, n)
				for key in ["ground", "wall", "backdrop_tint", "fog"]:
					assert_str((p[key] as Color).to_html(false)).is_equal(str(b[key]).trim_prefix("#").to_lower())
		var last: Dictionary = bands[-1]
		assert_str((Art.palette(type, int(last.to) + 7).wall as Color).to_html(false)).is_equal(str(last.wall).trim_prefix("#").to_lower())
	assert_dict(Art.palette("", 3)).is_empty()
	assert_dict(Art.palette("no_such_type", 3)).is_empty()

func test_band_one_is_the_colours_the_mine_had() -> void:
	var first := Art.palette("quarry", 1)
	assert_str((first.ground as Color).to_html(false)).is_equal(Art.FLOOR_COLORS[0].to_html(false))
	assert_str((first.wall as Color).to_html(false)).is_equal(Art.WALL_COLORS[0].to_html(false))
	assert_str((first.backdrop_tint as Color).to_html(false)).is_equal(MineBackdrop.tint(1).to_html(false))
	assert_str((first.fog as Color).to_html(false)).is_equal(MineBackdrop.VOID.to_html(false))

## The chamber's floor slab and wall blocks are vertex coloured: the band's ground is among them, another band's is not.
func _colours(root: Node3D) -> Dictionary:
	var out := {}
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null: continue
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var cols = arrays[Mesh.ARRAY_COLOR]
			if cols == null: continue
			for c: Color in cols: out[c.to_html(false)] = true
	return out

func test_the_chamber_wears_its_bands_ground() -> void:
	var a: Node3D = auto_free(Art.chamber(3, "vein"))
	var b: Node3D = auto_free(Art.chamber(25, "quarry"))
	var ga := (Art.palette("vein", 3).ground as Color).to_html(false)
	var gb := (Art.palette("quarry", 25).ground as Color).to_html(false)
	assert_bool(_colours(a).has(ga)).is_true()
	assert_bool(_colours(a).has(gb)).is_false()
	assert_bool(_colours(b).has(gb)).is_true()
	var old: Node3D = auto_free(Art.chamber(3))   # no type: the variant's own, as before
	assert_bool(_colours(old).has(Art.FLOOR_COLORS[0].to_html(false))).is_true()

func test_the_backdrop_takes_the_bands_tint_and_fog_and_marks_veins_only_on_a_types_own_relief() -> void:
	var colours := Art.palette("vein", 33)
	var root: Node3D = auto_free(MineBackdrop.build(4, "vein", colours))
	var own: Node3D = Art.kit(MineBackdrop.TYPE_SCENE % "vein")
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		var mat := g.material_override as ShaderMaterial
		assert_that(mat.get_shader_parameter("floor_tint")).is_equal(colours.backdrop_tint)
		assert_that(mat.get_shader_parameter("void_tint")).is_equal(colours.fog)
		assert_float(float(mat.get_shader_parameter("vein_mask"))).is_equal(1.0 if own != null else 0.0)
	if own: own.free()
	var old: Node3D = auto_free(MineBackdrop.build(1))
	for g: GeometryInstance3D in old.find_children("*", "GeometryInstance3D", true, false):
		assert_float(float((g.material_override as ShaderMaterial).get_shader_parameter("vein_mask"))).is_equal(0.0)
	var names := MineBackdrop.SHADER.get_shader_uniform_list().map(func(u): return str(u.name))
	assert_bool(names.has("vein_mask")).is_true()

func test_the_mine_scene_paints_the_floor_in_its_types_band() -> void:
	P0Runtime.free_instance_for_tests()
	rt = P0Runtime.ensure()
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	await get_tree().process_frame
	rt.session.view = Fx.view(23, {"type": "quarry", "station": false})
	mine = load(P0_MINE).instantiate()
	mine.setup({"mine": Fx.MINE, "floor": 23})
	add_child(mine)
	await get_tree().process_frame
	await get_tree().process_frame
	var colours := Art.palette("quarry", 23)
	assert_that(mine.environment.background_color).is_equal(colours.fog)
	var mat := (mine.backdrop.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).material_override as ShaderMaterial
	assert_that(mat.get_shader_parameter("floor_tint")).is_equal(colours.backdrop_tint)
	assert_bool(_colours(mine.scenery).has((colours.ground as Color).to_html(false))).is_true()

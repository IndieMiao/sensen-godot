extends GdUnitTestSuite
## SGODOT-458 (周瑜's spec 2c, (c), (d)): on GLES only, a StandardMaterial3D drawing a linear vertex colour is swapped for
## a vcol_matte with its parameters, on the instance's own slots (the shared Mesh keeps its material); one marked KEEP,
## or anything a vcol_matte does not draw, stays. The rendering method is injected: no renderer is needed (headless too).

func after_test() -> void:
	GlesAlbedo.method = ""

static func _vcol(roughness := 0.9, specular := 0.18) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic_specular = specular
	return m

func test_only_a_plain_linear_vertex_colour_material_is_swapped() -> void:
	assert_bool(GlesAlbedo.swaps(_vcol())).is_true()
	var cases := {
		"sRGB vertex colour": func(m): m.vertex_color_is_srgb = true,
		"no vertex colour": func(m): m.vertex_color_use_as_albedo = false,
		"transparent": func(m): m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA,
		"unshaded": func(m): m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED,
		"front faces culled": func(m): m.cull_mode = BaseMaterial3D.CULL_FRONT,
		"a texture": func(m): m.albedo_texture = PlaceholderTexture2D.new(),
		"emission": func(m): m.emission_enabled = true,
		"billboard": func(m): m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED,
		"kept": func(m): m.set_meta(GlesAlbedo.KEEP, true),
	}
	for name in cases:
		var m := _vcol()
		cases[name].call(m)
		assert_bool(GlesAlbedo.swaps(m)).override_failure_message(name).is_false()
	assert_bool(GlesAlbedo.swaps(ShaderMaterial.new())).is_false()
	assert_bool(GlesAlbedo.swaps(null)).is_false()

func test_the_matte_takes_the_parameters_and_is_made_once_for_them() -> void:
	var a := _vcol(0.94, 0.15)
	a.albedo_color = Color(0.9, 0.8, 0.7)
	var m := GlesAlbedo.matte(a)
	assert_object(m.shader).is_same(GlesAlbedo.SHADER)
	assert_object(m.get_shader_parameter("albedo")).is_equal(Color(0.9, 0.8, 0.7))
	assert_float(float(m.get_shader_parameter("roughness"))).is_equal_approx(0.94, 0.0001)
	assert_float(float(m.get_shader_parameter("metallic_specular"))).is_equal_approx(0.15, 0.0001)
	assert_float(float(m.get_shader_parameter("metallic"))).is_equal(0.0)
	var same := _vcol(0.94, 0.15)
	same.albedo_color = Color(0.9, 0.8, 0.7)
	assert_object(GlesAlbedo.matte(same)).is_same(m)   # one per look, shared as the originals are
	assert_object(GlesAlbedo.matte(_vcol(0.5, 0.15))).is_not_same(m)
	# both faces drawn (the pond's bank flowers): swapped too, for vcol_matte drawing both
	var both := _vcol(0.94, 0.15)
	both.albedo_color = Color(0.9, 0.8, 0.7)
	both.cull_mode = BaseMaterial3D.CULL_DISABLED
	assert_bool(GlesAlbedo.swaps(both)).is_true()
	var mb := GlesAlbedo.matte(both)
	assert_object(mb).is_not_same(m)
	assert_str(mb.shader.code).contains("cull_disabled")
	assert_str(mb.shader.code).not_contains("cull_back")

## The instance's slots only: an override replaced; a mesh's own surface material set as that surface's override, the
## Mesh resource untouched (another instance of it, unswapped, keeps it); a MultiMesh's single surface via its override.
func test_a_node_changes_its_own_slots_never_the_mesh() -> void:
	var over := MeshInstance3D.new()
	over.mesh = BoxMesh.new()
	over.material_override = _vcol()
	GlesAlbedo.fix(over)
	assert_object(over.material_override).is_instanceof(ShaderMaterial)
	var mesh := BoxMesh.new()
	var own := _vcol()
	mesh.surface_set_material(0, own)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	GlesAlbedo.fix(inst)
	assert_object(inst.get_surface_override_material(0)).is_instanceof(ShaderMaterial)
	assert_object(mesh.surface_get_material(0)).is_same(own)
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.mesh = mesh
	GlesAlbedo.fix(batch)
	assert_object(batch.material_override).is_instanceof(ShaderMaterial)
	var kept := MeshInstance3D.new()
	kept.mesh = BoxMesh.new()
	kept.material_override = _vcol()
	kept.set_meta(GlesAlbedo.KEEP, true)
	GlesAlbedo.fix(kept)
	assert_object(kept.material_override).is_instanceof(StandardMaterial3D)
	for n in [over, inst, batch, kept]: n.free()

## The hook: on GLES it swaps what comes into the tree, a frame later too (the material set after add_child); on any
## other renderer it never connects.
func test_the_hook_runs_on_gles_only() -> void:
	GlesAlbedo.method = "mobile"
	var off: Node = auto_free(GlesAlbedo.new())
	add_child(off)
	assert_bool(get_tree().node_added.is_connected(off._added)).is_false()
	GlesAlbedo.method = "gl_compatibility"
	var hook: Node = GlesAlbedo.new()
	add_child(hook)
	assert_bool(get_tree().node_added.is_connected(hook._added)).is_true()
	var late := MeshInstance3D.new()
	late.mesh = BoxMesh.new()
	add_child(late)
	late.material_override = _vcol()   # after add_child
	await get_tree().process_frame
	assert_object(late.material_override).is_instanceof(ShaderMaterial)
	get_tree().node_added.disconnect(hook._added)
	hook.free()
	late.free()

func test_on_follows_the_renderer() -> void:
	GlesAlbedo.method = "gl_compatibility"
	assert_bool(GlesAlbedo.on()).is_true()
	GlesAlbedo.method = "mobile"
	assert_bool(GlesAlbedo.on()).is_false()

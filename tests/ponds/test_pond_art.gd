extends GdUnitTestSuite

func test_tall_bank_stones_stay_inside_the_navigation_clearance() -> void:
	# Check actual geometry against the immutable polygon, including concave
	# corners and every location's different seed. An art edit must not create
	# a visible rock in a cell where the server allows the player to stand.
	for entry in SystemPonds.data().locations:
		var spec := SystemPonds.site(entry)
		var shore := auto_free(WaterShore.build(str(entry.id), spec)) as WaterShore
		var polygon := FishingModel._polygon(spec)
		var arrays: Array = shore.get_node("BankStones").mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var max_outside := 0.0
		for vertex in vertices:
			if vertex.y < .18: continue
			var point := Vector2(vertex.x, vertex.z)
			if Geometry2D.is_point_in_polygon(point, polygon): continue
			max_outside = maxf(max_outside, point.distance_to(FishingModel._nearest_polygon(point, polygon)))
		assert_float(max_outside).override_failure_message("Tall stone enters walkable clearance at %s: %f" % [entry.id, max_outside]).is_less(.277)

func test_pond_art_does_not_change_the_farm_water_material_or_site_data() -> void:
	var entry: Dictionary = SystemPonds.data().locations[0]
	var spec := SystemPonds.site(entry)
	var original := spec.duplicate(true)
	var pond := auto_free(FishingWater.build(str(entry.id), spec)) as FishingWater
	var farm := auto_free(FishingWater.build("farm_pond")) as FishingWater
	assert_that(spec).is_equal(original)
	assert_str(farm.water_material.shader.resource_path).is_equal("res://modules/fishing/water.gdshader")
	assert_object(pond.water_material.get_shader_parameter("pond_shore")).is_not_null()
	assert_object(pond.water_material.get_shader_parameter("pebble_bed")).is_not_null()

func test_near_bank_boulders_do_not_hide_the_demo_float() -> void:
	var entry: Dictionary = SystemPonds.data().locations.filter(func(p): return p.template_id == "gourd")[0]
	var spec := SystemPonds.site(entry)
	var plan := FishingModel.plan(str(entry.id), Vector3(9,0,-3.5), Vector3(6.7,0,-6.9), BlueprintGrid.new(SystemPonds.blueprint(entry)), spec)
	assert_bool(plan.is_empty()).is_false()
	var bank := auto_free(WaterShore.build(str(entry.id), spec)) as WaterShore
	var faces: PackedVector3Array = bank.get_node("BankStones").mesh.get_faces()
	var origin: Vector3 = plan.target + Vector3.UP * .14
	var view := Vector3(.16,1.1,1).normalized()
	var blocked := false
	for index in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(origin,view,faces[index],faces[index+1],faces[index+2]) != null:
			blocked = true
			break
	assert_bool(blocked).override_failure_message("A near-bank boulder hides the float from the fishing view").is_false()

func test_english_fishing_action_fits_inside_the_safe_area() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var entry: Dictionary = SystemPonds.data().locations[0]
	var scene: FishingPondScene = auto_free(load(SystemPonds.SCENE).instantiate())
	scene.setup({"pond_id":entry.id,"session":null})
	add_child(scene)
	await await_idle_frame()
	await await_idle_frame()
	var action := scene.ui.get_node("PondFish") as Button
	assert_float(action.get_global_rect().end.x).is_less_equal(scene.ui.get_global_rect().end.x + .1)
	assert_float(action.size.x).is_greater_equal(action.get_combined_minimum_size().x)
	TranslationServer.set_locale(previous)

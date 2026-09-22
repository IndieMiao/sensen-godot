extends GdUnitTestSuite

const FIXTURE := "res://tests/fixtures/generated_shoreline_farm_terrain.json"
const CHECKSUM := "60c376d6bd1207be96537ea361a5975b37c81ef5378c3fabbaa9693a88586513"
const CAPTURES := "res://output/farm-generation-error-2026-09-21/native"

func _terrain() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))

func _state() -> Dictionary:
	return {"cells": {}, "wallet": 187, "clock": {"chapter_index": 0, "field_condition": "sunny"},
		"engineering": {"reserved": {}}, "nursery": {"stage": 0, "appearance": {}},
		"inventory": {"produce": {}, "dishes": {}, "seeds": {"R": {"bound": 6}, "L": {"bound": 3}}},
		"xp": {"total": 0, "first_harvest_crops": []}, "chapters": [],
		"bag": {"version": 2, "slots": [], "overflow": [], "equipped": {"fishing_rod": {"item_id": "starter_fishing_rod"}}},
		"journey": {"version": 1, "facts": [], "unlocks": [], "wood": 0, "completed": [], "materials": {},
			"exploration": {"round": 0, "collected": []}, "opportunities": {}}}

func _body() -> Dictionary:
	var terrain := _terrain()
	return {"farm_id": "recorded-shoreline-test", "region_id": "los_angeles", "layout_patch_id": terrain.layout_id,
		"blueprint_revision": 1, "farm_terrain": terrain, "location": terrain.source.center, "version": 1, "state": _state()}

func after_test() -> void:
	FarmChoice.clear()
	for frame in 3: await get_tree().process_frame

func _primary_water(terrain: Dictionary) -> Array[Vector2i]:
	var water: Array[Vector2i] = []
	for y in 40:
		for x in 40:
			for region in terrain.plot.regions:
				if region.get("kind") != "water" or not str(region.get("id", "")).begins_with("geo_relation_"): continue
				if FarmPlot.precise_region_contains(region, x, y, []):
					water.append(Vector2i(x, y))
					break
	return water

func test_recorded_geography_passes_unmodified_checksum_and_preserves_all_628_reservoir_cells() -> void:
	var terrain := _terrain()
	assert_str(terrain.source.land_cover.provider).is_equal("esa_worldcover")
	var bp := FarmPlot.register_terrain(terrain)
	assert_object(bp).is_not_null()
	if bp == null: return
	assert_str(bp.checksum).is_equal(CHECKSUM)
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()
	assert_vector(bp.grid).is_equal(Vector2i(40, 40))
	assert_float(bp.play_area_m).is_equal(32.0)
	var primary := _primary_water(terrain)
	assert_int(primary.size()).is_equal(628)
	for cell in primary:
		assert_str(FarmPlot.kind_at(bp.layout_patch_id, cell)).is_equal("water")
		assert_bool(bp.is_walkable(cell)).is_false()
	var walks := 0
	var tills := 0
	for y in 40:
		for x in 40:
			walks += int(bp.is_walkable(Vector2i(x, y)))
			tills += int(bp.mask_has("cultivable", Vector2i(x, y)))
	assert_int(walks).is_equal(730)
	assert_int(tills).is_equal(397)
	var grid := BlueprintGrid.new(bp)
	var origin := bp.cell_to_world(bp.anchor("spawn"))
	for key in ["mine_approach", "pond_stand", "pond_shore", "stall", "exit"]:
		assert_array(grid.point_path(origin, bp.cell_to_world(bp.anchor(key)))).is_not_empty()
	var pond := FishingModel.site_for_plot("farm_pond", bp)
	var plan := FishingModel.plan("farm_pond", origin, Vector3.INF, grid, pond)
	assert_bool(plan.is_empty()).is_false()
	if not plan.is_empty(): assert_bool(FishingModel.valid_cast("farm_pond", plan.origin, plan.target, grid, pond)).is_true()

func test_real_source_metadata_roundtrips_but_private_snapshot_does_not_need_it() -> void:
	var body := _body()
	var session := FarmSession.new(ApiClient.new("https://recorded-shoreline.invalid/v1", FakeTransport.new([]).callable()))
	assert_bool(session._adopt(body)).is_true()
	FarmChoice.save_choice(session.farm_choice())
	assert_that(FarmChoice.load().farm_terrain.source.land_cover).is_equal(body.farm_terrain.source.land_cover)
	assert_str(FarmBlueprint.load_choice(FarmChoice.load()).checksum).is_equal(CHECKSUM)
	var private_body := body.duplicate(true)
	private_body.erase("location")
	private_body.farm_terrain.erase("source")
	for index in private_body.farm_terrain.plot.regions.size(): private_body.farm_terrain.plot.regions[index].id = "region_%d" % index
	var private_bp := FarmBlueprint.load_choice(private_body)
	assert_object(private_bp).is_not_null()
	if private_bp == null: return
	assert_str(private_bp.checksum).is_equal(CHECKSUM)
	assert_array(private_bp.overlay.blocks).is_empty()
	assert_that(FishingModel.site_for_plot("farm_pond", private_bp)).is_equal(FishingModel.site_for_plot("farm_pond", FarmPlot.register_terrain(body.farm_terrain)))

func _assert_dry_outer_boundary(scene: Node) -> void:
	var bp: FarmBlueprint = scene.bp
	var outer_rocks := 0
	for layer in ["BoundaryRocks", "BoundaryBushes"]:
		var mesh: MultiMesh = scene.scenery.get_node(layer).multimesh
		for index in mesh.instance_count:
			var p := mesh.get_instance_transform(index).origin
			if p.x >= 0 and p.x <= 32 and p.z <= 0 and p.z >= -32: continue
			if layer == "BoundaryRocks": outer_rocks += 1
			var nearest := bp.world_to_cell(Vector3(clampf(p.x, 0, 31.999), 0, clampf(p.z, -31.999, 0)))
			assert_str(FarmPlot.kind_at(bp.layout_patch_id, nearest)).is_not_equal("water")
	assert_int(outer_rocks).is_greater(0)
	assert_int(outer_rocks).is_less(96)

func _capture(scene: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	scene.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.cam.size = 43
	scene.cam.near = 0.05
	scene.cam.far = 100
	scene.cam.position = Vector3(16, 39, 22)
	scene.cam.look_at(Vector3(16, 0, -16))
	scene.cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES))
	assert_int(get_viewport().get_texture().get_image().save_png(CAPTURES.path_join(name + ".png"))).is_equal(OK)

func test_full_owner_and_visitor_render_recorded_shoreline_with_reachable_pond_and_mine() -> void:
	var session := FarmSession.new(ApiClient.new("https://recorded-shoreline.invalid/v1", FakeTransport.new([]).callable()))
	assert_bool(session._adopt(_body())).is_true()
	var original_site := FishingModel.site("farm_pond").duplicate(true)
	FarmChoice.save("sh_b", 2)
	var old_choice := FarmChoice.load()
	var owner := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	owner.setup({"session": session})
	add_child(auto_free(owner))
	owner.set_process(false)
	for frame in 3: await get_tree().process_frame
	assert_vector(owner.bp.anchor("house")).is_equal(Vector2i(22, 33))
	assert_vector(owner.bp.anchor("mine")).is_equal(Vector2i(19, 31))
	assert_object(owner.plot_surface.get_node_or_null("GeographicWater")).is_not_null()
	_assert_dry_outer_boundary(owner)
	owner._go_fishing()
	assert_bool(owner._fishing_plan.is_empty()).is_false()
	assert_bool(FishingModel.valid_cast("farm_pond", owner._fishing_plan.origin, owner._fishing_plan.target, owner.grid, owner.fishing_site)).is_true()
	assert_array(owner.grid.point_path(owner.mover.position, owner.mine_approach(owner.bp))).is_not_empty()
	await _capture(owner, "recorded-shore-owner")
	owner.suspend()
	var snapshot := _body()
	snapshot.farm_terrain.erase("source")
	snapshot.erase("location")
	snapshot.erase("state")
	snapshot.cells = []
	snapshot.props = []
	var visitor := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	visitor.setup({"visitor": true, "snapshot": snapshot})
	add_child(auto_free(visitor))
	visitor.set_process(false)
	for frame in 3: await get_tree().process_frame
	assert_bool(visitor.visitor).is_true()
	assert_str(visitor.bp.checksum).is_equal(CHECKSUM)
	assert_that(visitor.fishing_site).is_equal(owner.fishing_site)
	assert_object(visitor.farm_activities).is_null()
	_assert_dry_outer_boundary(visitor)
	await _capture(visitor, "recorded-shore-visitor")
	assert_that(FarmChoice.load()).is_equal(old_choice)
	assert_that(FishingModel.site("farm_pond")).is_equal(original_site)
	assert_that(session.state).is_equal(_state())

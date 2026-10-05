extends GdUnitTestSuite
## P0 ponds live at the fixed map locations of the bundled catalog and reuse the old pond worlds.

const POND := preload("res://scenes/p0/p0_pond.gd")

func _sites() -> Dictionary:
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
	return content.fishing.sites

func test_every_bundled_pond_maps_to_a_p0_fishing_site() -> void:
	var sites := _sites()
	for entry in SystemPonds.data().locations:
		var site: String = POND.site_for(str(entry.template_id))
		assert_bool(sites.has(site)).override_failure_message("%s → %s is not a P0 site" % [entry.id, site]).is_true()

func test_the_winding_template_reads_as_a_stream() -> void:
	assert_str(POND.site_for("meander")).is_equal("river")
	assert_str(POND.site_for("crescent")).is_equal("pond")
	assert_str(POND.site_for("gourd")).is_equal("pond")

func test_shanghai_has_both_sites_on_the_map() -> void:
	var seen := {}
	for entry in SystemPonds.data().locations:
		if str(entry.region_id) == "shanghai": seen[POND.site_for(str(entry.template_id))] = true
	assert_that(seen.keys()).contains_exactly_in_any_order(["pond", "river"])

func test_every_shanghai_pond_has_a_reachable_bank() -> void:
	# The main key walks to FishingModel.plan's origin; each pond must have one from its spawn.
	for entry in SystemPonds.data().locations:
		if str(entry.region_id) != "shanghai": continue
		var spec := SystemPonds.site(entry)
		var bp := SystemPonds.blueprint(entry)
		var grid := BlueprintGrid.new(bp)
		var mover := PlayerMover.new(bp, grid)
		var plan := FishingModel.plan(str(entry.id), mover.position, Vector3.INF, grid, spec)
		assert_bool(plan.is_empty()).override_failure_message(str(entry.id)).is_false()

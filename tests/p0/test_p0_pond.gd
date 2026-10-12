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

## Joey 296 #8: a Cast on the move fished on one foot — the presentation keeps the pose it finds as its base and the run
## clip was mid-stride. The pond stands the player still, in the idle pose this very frame, before the presentation.
func test_a_cast_on_the_move_fishes_standing_on_both_feet() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/p0/p0_pond.gd")
	var at := src.find("func _begin_fishing(")
	var begin := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_int(begin.find("actor.stand_still()")).is_between(0, begin.find("view.configure("))
	var bp := P0Garden.blueprint()
	var actor: P0Actor = auto_free(P0Actor.new())
	add_child(actor)
	actor.setup(bp, BlueprintGrid.new(bp), null)
	await get_tree().process_frame
	var anim := actor.rig.get_node("AnimationPlayer") as AnimationPlayer
	var sk: Skeleton3D = actor.rig.skeleton
	var poses := func() -> Array: return range(sk.get_bone_count()).map(func(i): return sk.get_bone_pose_rotation(i))
	anim.stop()   # idle may be playing already (the outfit's config): its first frame, not wherever it got to
	actor.rig.play_motion("idle")
	var idle: Array = poses.call()
	actor._play("run", true)
	anim.advance(0.3)   # mid-stride
	actor.state = "move"
	var run: Array = poses.call()
	var apart := func(a: Array, b: Array) -> float:
		var most := 0.0
		for i in a.size(): most = maxf(most, (a[i] as Quaternion).angle_to(b[i]))
		return most
	assert_float(apart.call(run, idle)).is_greater(0.2)   # the case: a leg out
	actor.stand_still()
	assert_float(apart.call(poses.call(), idle)).is_less(0.001)
	assert_str(anim.current_animation).is_equal("idle")
	assert_str(actor.state).is_equal("idle")
	assert_bool(actor.mover.is_moving()).is_false()

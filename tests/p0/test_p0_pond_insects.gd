extends GdUnitTestSuite
## The wild's insects (SGODOT-454; 上官婉儿's plan and spec): a kind a MultiMesh, small meshes, no shadows; the same
## pond has them in the same places; their anchors off the gathering points and the spawn at the spec's heights, the
## dragonflies over the water off its edge; half as many under gl_compatibility; on the opening screen 3–6 of them, a bee
## or a yellow butterfly among them within 5 m of the player, none of their flights over the keys, the player or a point's name
## bar.

const PondInsects := preload("res://modules/ponds/pond_insects.gd")
const PondWalk := preload("res://modules/ponds/pond_walk.gd")
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const SF := ["pond_san_francisco_01", "pond_san_francisco_02", "pond_san_francisco_03"]
const FERN_CLEAR := [Vector3(4.0, 0, -2.4), Vector3(7.6, 0, -1.4)]   # Fern Pond's C1 and F2

func _spawn(entry: Dictionary) -> Vector3:
	var bp := PondWalk.blueprint(entry)
	return bp.cell_to_world(bp.anchor("spawn"))

func _opening(entry: Dictionary, clear: Array) -> Dictionary:
	var r := FishingModel.water_rect(str(entry.id), SystemPonds.site(entry))
	var piece: Vector3 = clear[0] if not clear.is_empty() else Vector3.INF
	return P0Pond.insects_opening(_spawn(entry), Vector3(r.get_center().x, 0, r.get_center().y), piece, clear)

func _layout(id: String, clear: Array, opening := {}, gles := false) -> Dictionary:
	var entry := P0Ponds.location(id)
	var scenery := auto_free(PondScenery.build(entry, clear)) as Node
	return PondInsects.layout(entry, SystemPonds.site(entry), PondInsects.points(scenery), clear, _spawn(entry), opening, gles)

func test_each_kind_is_one_small_unshadowed_multimesh() -> void:
	var entry := P0Ponds.location(SF[2])
	var scenery := auto_free(PondScenery.build(entry, FERN_CLEAR)) as Node
	var insects := auto_free(PondInsects.build(entry, SystemPonds.site(entry), scenery, FERN_CLEAR, _spawn(entry), _opening(entry, FERN_CLEAR))) as Node3D
	assert_int(insects.get_child_count()).is_equal(3)
	var l := _layout(SF[2], FERN_CLEAR, _opening(entry, FERN_CLEAR))
	var faces := {"bee": 12, "butterfly": 12, "dragonfly": 16}
	for kind in faces:
		var node := insects.get_node(kind.to_pascal_case()) as MultiMeshInstance3D
		assert_object(node).override_failure_message(kind).is_not_null()
		assert_int(node.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_int(node.multimesh.mesh.get_faces().size() / 3).override_failure_message(kind).is_less_equal(faces[kind])
		assert_bool(node.multimesh.use_custom_data).is_true()
		for a in l[kind]:   # the culling box holds every flight
			var reach := Vector3(a.radius, PondInsects.BOB[kind], a.radius)
			assert_bool(node.custom_aabb.has_point(a.at + reach) and node.custom_aabb.has_point(a.at - reach)).override_failure_message(kind).is_true()

func test_the_same_pond_has_them_in_the_same_places() -> void:
	assert_dict(_layout(SF[0], [])).is_equal(_layout(SF[0], []))
	assert_bool(_layout(SF[0], []) == _layout(SF[1], [])).is_false()

func test_counts_and_half_under_gl_compatibility() -> void:
	for id in SF:
		var full := _layout(id, FERN_CLEAR)
		var half := _layout(id, FERN_CLEAR, {}, true)
		for kind in PondInsects.COUNT:
			assert_int(full[kind].size()).override_failure_message("%s %s" % [id, kind]).is_equal(PondInsects.COUNT[kind])
			assert_int(half[kind].size()).override_failure_message("%s %s gles" % [id, kind]).is_equal(floori(PondInsects.COUNT[kind] / 2.0))
			# the same insects as the full draw's first half: a GLES phone and a Vulkan one show some of the same
			assert_array(half[kind]).override_failure_message("%s %s subset" % [id, kind]).is_equal((full[kind] as Array).slice(0, half[kind].size()))

## The water's band is sampled once a pond (周瑜 on #929: 15–19 ms a build, built again as the points come): the
## scenery's rebuild takes it from the cache, and the same points either way.
func test_the_water_band_is_kept_per_pond() -> void:
	var entry := P0Ponds.location(SF[0])
	var spec := SystemPonds.site(entry)
	PondInsects._bands.clear()
	var first := PondInsects._water_band(str(entry.id), spec, int(entry.decoration_seed))
	var again := PondInsects._water_band(str(entry.id), spec, int(entry.decoration_seed))
	assert_array(again).is_same(first)
	assert_int(first.size()).is_greater(20)

func test_anchors_keep_off_the_points_and_the_spawn_at_their_heights() -> void:
	for id in SF:
		var entry := P0Ponds.location(id)
		var spec := SystemPonds.site(entry)
		var spawn := _spawn(entry)
		var l := _layout(id, FERN_CLEAR, _opening(entry, FERN_CLEAR))
		for kind in l:
			for a in l[kind]:
				var at: Vector3 = a.at
				var what := "%s %s %s" % [id, kind, at]
				assert_bool(PondScenery._near(at, FERN_CLEAR)).override_failure_message(what).is_false()
				assert_float(Vector2(at.x - spawn.x, at.z - spawn.z).length()).override_failure_message(what).is_greater_equal(PondInsects.CLEAR_M)
				var ground := PondInsects.WATER_Y if kind == "dragonfly" else 0.0
				var h: Vector2 = PondInsects.HEIGHT[kind]
				assert_float(at.y - ground - PondInsects.BOB[kind]).override_failure_message(what).is_greater_equal(h.x - 0.0001)
				assert_float(at.y - ground + PondInsects.BOB[kind]).override_failure_message(what).is_less_equal(h.y + 0.0001)
				if kind != "dragonfly": continue
				assert_bool(FishingModel.contains(id, at, 0.0, spec)).override_failure_message(what).is_true()
				for k in 8:   # 0.3 m in from the edge every way
					var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * PondInsects.SHORE.x
					assert_bool(FishingModel.contains(id, at + d, 0.0, spec)).override_failure_message(what).is_true()

func test_the_opening_shows_three_to_six_none_over_the_keys_the_player_or_the_points() -> void:
	for id in SF:
		var entry := P0Ponds.location(id)
		var opening := _opening(entry, FERN_CLEAR)
		var l := _layout(id, FERN_CLEAR, opening)
		var spawn := _spawn(entry)
		var near := 0
		var seen := 0
		# under gl_compatibility (the first half) the ones by the player still fly (不知火舞 on #929)
		var gles := _layout(id, FERN_CLEAR, opening, true)
		var gles_near := 0
		for kind in gles:
			for a in gles[kind]:
				var shows := (opening.shown as Rect2).has_point((opening.screen.call(PackedVector3Array([a.at])) as Rect2).position)
				if shows and (kind == "bee" or (kind == "butterfly" and a.variant == 0)) and Vector2(a.at.x - spawn.x, a.at.z - spawn.z).length() <= 5.0:
					gles_near += 1
		assert_int(gles_near).override_failure_message("%s gles" % id).is_greater_equal(1)
		for kind in l:
			for a in l[kind]:
				var box: Rect2 = opening.screen.call(PondInsects._flight_box(kind, a))
				for r in opening.keep_off:
					assert_bool((r as Rect2).intersects(box)).override_failure_message("%s %s %s over %s" % [id, kind, box, r]).is_false()
				if not (opening.shown as Rect2).has_point((opening.screen.call(PackedVector3Array([a.at])) as Rect2).position): continue
				seen += 1
				var bright: bool = kind == "bee" or (kind == "butterfly" and a.variant == 0)
				if bright and Vector2(a.at.x - spawn.x, a.at.z - spawn.z).length() <= 5.0: near += 1
		assert_int(seen).override_failure_message(id).is_between(3, 6)
		# 1–2 bees or yellow butterflies near the player (上官婉儿 on #929: over the grass and flowers 3–5 m off)
		assert_int(near).override_failure_message(id).is_greater_equal(1)

func after_test() -> void:   # a failed marker test must not leave the desktop without insects (周瑜 on #929)
	if FileAccess.file_exists(PondInsects.OFF_FILE): DirAccess.remove_absolute(ProjectSettings.globalize_path(PondInsects.OFF_FILE))

## One build timed with and without them (李元芳 on gs66): a user://p0_no_insects marker leaves them out.
func test_a_marker_file_leaves_them_out() -> void:
	assert_bool(PondInsects.wanted()).is_true()
	FileAccess.open(PondInsects.OFF_FILE, FileAccess.WRITE).close()
	assert_bool(PondInsects.wanted()).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PondInsects.OFF_FILE))
	assert_bool(PondInsects.wanted()).is_true()

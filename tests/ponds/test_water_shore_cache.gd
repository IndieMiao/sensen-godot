extends GdUnitTestSuite
## Pond banks are generated once per pond (optionally on a worker thread) and must be identical
## to a fresh build; the local primitive helpers must match PlaceScenery's geometry.

func _counts(shore: WaterShore) -> Array:
	var out := []
	for n in ["BankStones", "BankReedsAndGrass", "BankFlowers"]:
		out.append((shore.get_node(n) as MeshInstance3D).mesh.surface_get_array_len(0))
	return out

func test_cached_and_prewarmed_banks_match_a_fresh_build() -> void:
	var a := SystemPonds.location("pond_shanghai_03")
	var spec := SystemPonds.site(a)
	var fresh: Array = _counts(auto_free(WaterShore.build(str(a.id), spec)))
	var again: Array = _counts(auto_free(WaterShore.build(str(a.id), spec)))
	assert_that(again).is_equal(fresh)
	var b := SystemPonds.location("pond_shanghai_06")
	var b_spec := SystemPonds.site(b)
	WaterShore.prewarm(str(b.id), b_spec)
	var warmed: Array = _counts(auto_free(WaterShore.build(str(b.id), b_spec)))   # waits for the worker if needed
	var key := WaterShore._cache_key(str(b.id), FishingModel.site(str(b.id), b_spec))
	var direct := WaterShore._generate(str(b.id), FishingModel.site(str(b.id), b_spec))
	assert_int(warmed[0]).is_equal((direct.rocks[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	assert_int(warmed[1]).is_equal((direct.plants[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	assert_bool(WaterShore._cache.has(key)).is_true()

func test_local_primitives_match_place_scenery() -> void:
	WaterShore._prepare_units()
	var basis := Basis(Vector3.UP, 0.7)
	for case in [["oval"], ["cylinder", 4], ["cylinder", 5]]:
		var ours := SurfaceTool.new()
		var theirs := SurfaceTool.new()
		ours.begin(Mesh.PRIMITIVE_TRIANGLES)
		theirs.begin(Mesh.PRIMITIVE_TRIANGLES)
		if case[0] == "oval":
			WaterShore._oval(ours, Vector3(.24, .055, .12), Vector3(1, .2, 3), Color.WHITE, basis)
			PlaceScenery._oval(theirs, Vector3(.24, .055, .12), Vector3(1, .2, 3), Color.WHITE, basis)
		else:
			WaterShore._cylinder(ours, .009, .6, Vector3(1, .3, 3), Color.WHITE, case[1])
			PlaceScenery._cylinder(theirs, .009, .6, Vector3(1, .3, 3), Color.WHITE, Vector3.ONE, case[1])
		var a := ours.commit_to_arrays()
		var b := theirs.commit_to_arrays()
		var va: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var vb: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
		var na: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var nb: PackedVector3Array = b[Mesh.ARRAY_NORMAL]
		assert_int(va.size()).is_equal(vb.size())
		for i in va.size():
			assert_bool(va[i].is_equal_approx(vb[i]) or va[i].distance_to(vb[i]) < 1e-5).override_failure_message("%s vertex %d" % [case, i]).is_true()
			# Primitive normals come back octahedral-compressed (~1.5e-5 noise); a 9 mm × 0.6 m stem's
			# inverse-transpose magnifies that ~67× on its caps, so allow ~0.6° there.
			assert_bool(na[i].distance_to(nb[i]) < 1e-2).override_failure_message("%s normal %d" % [case, i]).is_true()

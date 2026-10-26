extends GdUnitTestSuite
## SGODOT-272: every P0 pond (assets/p0/p0_ponds.json, San Francisco's six on the bundled templates) has its baked
## shore-foam mask, made for its own template and seed (tools/art/bake_pond_foam.py --merge); without one the pond
## shows no foam along its bank and nothing says so.

func test_every_p0_pond_has_its_foam_mask() -> void:
	var ponds: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_ponds.json")).locations
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ponds/art/foam/manifest.json"))
	var made := {}
	for e in manifest.entries: made[str(e.id)] = e
	assert_int(ponds.size()).is_greater(0)
	for p in ponds:
		if not bool(p.get("enabled", true)): continue
		var id := str(p.id)
		assert_bool(ResourceLoader.exists("res://assets/ponds/art/foam/%s.png" % id)).override_failure_message("no foam mask for " + id).is_true()
		assert_bool(made.has(id)).override_failure_message("not in the foam manifest: " + id).is_true()
		assert_str(str(made[id].template_id)).is_equal(str(p.template_id))
		assert_float(float(made[id].decoration_seed)).is_equal(float(p.decoration_seed))

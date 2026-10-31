extends GdUnitTestSuite
## SGODOT-374 (不知火舞's open-water outlines, q(267)): P0's own pond shapes laid over the frozen catalog, for the
## San Francisco ponds and the generated cities' alike; the Cast key lands 2.5 m out, backing off where the water is
## narrower; the catalog file itself does not move.

const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")

func _area(poly: Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p: Array = poly[i]
		var q: Array = poly[(i + 1) % poly.size()]
		a += float(p[0]) * float(q[1]) - float(q[0]) * float(p[1])
	return absf(a) * 0.5

func test_the_catalog_stays_frozen_and_p0_takes_the_open_water_shapes() -> void:
	var frozen: Dictionary = SystemPonds.data().templates
	for t in ["crescent", "gourd", "meander"]:
		var spec := SystemPonds.template(t)
		assert_str(str(spec.id)).is_equal(t)
		assert_int(int(spec.revision)).is_equal(1)   # the server names template + layout_revision 1
		assert_str(str(spec.fish_profile)).is_equal(str(frozen[t].fish_profile))
		assert_str(str(spec.art)).is_equal("res://assets/ponds/p0/")
		assert_float(_area(spec.polygon)).is_greater(70.0)   # 72 / 81 / 82 m², from 29 / 47 / 39
		assert_float(_area(frozen[t].polygon)).is_less(50.0)
		assert_array(spec.extent).is_equal([12.0, 16.0])
		assert_bool(ResourceLoader.exists("res://assets/ponds/p0/%s_shore.png" % t)).is_true()

func test_a_san_francisco_pond_and_a_generated_one_both_open_on_the_new_water() -> void:
	var sf := P0Ponds.location("pond_san_francisco_01")
	var gen := P0CityPlaces.pond_entry("gn-5350159", {"id": "gn-5350159~pond0", "name": "Acorn Creek", "lat": 37.67,
		"lng": -122.08, "template_id": "gourd", "decoration_seed": 7})
	for entry in [sf, gen]:
		var site := SystemPonds.site(entry)
		assert_array(site.polygon).is_equal(SystemPonds.template("gourd").polygon)
		assert_str(str(site.art)).is_equal("res://assets/ponds/p0/")
		var bp := SystemPonds.blueprint(entry)
		assert_array(Array(bp.masks.walkable)).is_equal(SystemPonds.template("gourd").navigation.rows)
		# the spawn stands on a walkable cell, dry, a short step from the near bank
		var spawn := Vector3(6.125, 0, -1.625)
		var cell := bp.world_to_cell(spawn)
		assert_str(bp.masks.walkable[cell.y][cell.x]).is_equal("1")
		assert_bool(FishingModel.contains(str(entry.id), spawn, 1.0, site)).is_false()

func test_the_cast_key_lands_two_and_a_half_metres_out_and_backs_off_where_the_water_is_narrow() -> void:
	var entry := P0Ponds.location("pond_san_francisco_02")   # meander
	var site := SystemPonds.site(entry)
	var id := str(entry.id)
	var origin := Vector3(6.0, 0, -2.4)   # on the near bank, facing the open water
	var edge := FishingModel.nearest_water(id, origin, site)
	var landing := FishingModel.default_target(id, origin, site)
	assert_float(Vector2(landing.x - edge.x, landing.z - edge.z).length()).is_equal_approx(FishingModel.POND_REACH, 0.001)
	assert_bool(FishingModel.contains(id, landing, 0.0, site)).is_true()
	# A sliver of water: the reach backs off until the run from the bank stays wet, never under the old 0.55 m.
	var sliver := {"polygon": [[0.0, 0.0], [10.0, 0.0], [10.0, -1.0], [0.0, -1.0]], "space": "pond"}
	var short := FishingModel.default_target("sliver", Vector3(5, 0, 0.6), sliver)
	assert_float(-short.z).is_less_equal(1.0 - FishingModel.FAR_CLEAR + 0.001)   # the float clear of the far bank
	assert_float(-short.z).is_greater_equal(FishingModel.SHORE_REACH - 0.001)
	assert_bool(FishingModel.contains("sliver", short, 0.0, sliver)).is_true()

extends GdUnitTestSuite
## The P0 wild pond's shore foam (SGODOT-422, the user's 0.3.5 11-09: "新版野外的水花，其实是上一版石头的水花"): made as
## the pond is entered from its bank as v7 lays it (PondWildFoam via PondScenery.foam_contact) — its waterline, rock
## groups and cattails — not the mask baked from the old round stones. Those baked masks (SGODOT-272) stay for the old
## pond scene (scenes/pond), which still loads them.

const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
const PondWildFoam := preload("res://modules/ponds/pond_wild_foam.gd")
const SF := ["pond_san_francisco_01", "pond_san_francisco_02", "pond_san_francisco_03"]

func _polygon(entry: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in SystemPonds.site(entry).get("polygon", []): out.append(Vector2(float(q[0]), float(q[1])))
	return out

## The value (metres, the shader's foam distance) at a point of the pond (x, z), filtered as the shader samples it.
func _at(img: Image, p: Vector2) -> float:
	var fx := p.x / PondWildFoam.PX - 0.5
	var fy := -p.y / PondWildFoam.PX - 0.5
	var x := floori(fx)
	var y := floori(fy)
	var texel := func(i: int, j: int) -> float:
		return img.get_pixel(clampi(i, 0, img.get_width() - 1), clampi(j, 0, img.get_height() - 1)).r
	return lerpf(lerpf(texel.call(x, y), texel.call(x + 1, y), fx - x), lerpf(texel.call(x, y + 1), texel.call(x + 1, y + 1), fx - x), fy - y)

func _shore(p: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for k in polygon.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, polygon[k], polygon[(k + 1) % polygon.size()])))
	return best

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

## 8 bits, one channel: filterable on every phone (a 32-bit float one is not on iOS and many GLES3 phones — the 0.3.4
## sand edges' squares), over the template's extent at PX a texel, so the shader's pond_uv lands on it.
func test_the_wild_foam_is_an_8_bit_texture_over_the_pond() -> void:
	for id in SF:
		var e: Dictionary = P0Ponds.location(id)
		var scene := auto_free(PondScenery.build(e)) as PondScenery
		var tex := scene.foam_contact()
		assert_object(tex).override_failure_message(id).is_not_null()
		var img := tex.get_image()
		assert_int(img.get_format()).is_equal(Image.FORMAT_R8)
		var extent: Array = SystemPonds.site(e).extent
		assert_vector(Vector2(img.get_size())).is_equal(Vector2(float(extent[0]), float(extent[1])) / PondWildFoam.PX)
		assert_object(scene.foam_contact()).is_same(tex)   # made once a scenery

## Every rock group's rock and every cattail has foam at its foot; the open water, away from the bank and from them,
## none at all (no white island where the old stones were).
func test_the_rocks_and_reeds_have_foam_and_the_open_water_none() -> void:
	for id in SF:
		var e: Dictionary = P0Ponds.location(id)
		var scene := auto_free(PondScenery.build(e)) as PondScenery
		var img := scene.foam_contact().get_image()
		var polygon := _polygon(e)
		var rocks: Array = scene._foam.rocks
		var reeds: Array = scene._foam.reeds
		assert_int(rocks.size()).override_failure_message(id).is_greater_equal(9)
		assert_int(reeds.size()).override_failure_message(id).is_greater(0)
		for r in rocks + reeds:
			var at := Vector2(r.x, r.y)
			assert_float(_at(img, at)).override_failure_message("%s: no foam at %s" % [id, at]).is_less(0.02)
			# just past its edge, toward the water: still the contact froth
			var into := Vector2.ZERO
			for k in 16:
				var dir := Vector2.from_angle(k * TAU / 16.0)
				if Geometry2D.is_point_in_polygon(at + dir * (float(r.z) + 0.1), polygon): into += dir
			if into != Vector2.ZERO:
				assert_float(_at(img, at + into.normalized() * (float(r.z) + 0.06))).is_less(PondWildFoam.FOAM_W)
		var open := 0
		for y in img.get_height():
			for x in img.get_width():
				var p := Vector2((x + 0.5) * PondWildFoam.PX, -(y + 0.5) * PondWildFoam.PX)
				if not Geometry2D.is_point_in_polygon(p, polygon): continue
				var near := false
				for r in rocks + reeds:
					if p.distance_to(Vector2(r.x, r.y)) < (float(r.z) * PondWildFoam.SPREAD.y + 0.6) * (1.0 + PondWildFoam.TAIL): near = true
				if near: continue
				var v := img.get_pixel(x, y).r
				if v < 0.999:   # any foam at all here: the bank's own, so near the bank
					assert_float(_shore(p, polygon)).override_failure_message("%s: foam %.3f in the open water at %s" % [id, v, p]).is_less(PondWildFoam.DEEP_M)
				elif _shore(p, polygon) > 2.0: open += 1
		assert_int(open).override_failure_message(id).is_greater(1000)   # the middle stays clear

## The whole waterline has foam, not the same all round: a weak, narrow stretch (WEAK_SHARE, give or take the bays)
## and wide ones; at the waterline every stretch has some.
func test_the_base_runs_round_the_whole_bank_and_varies() -> void:
	for id in SF:
		var e: Dictionary = P0Ponds.location(id)
		var scene := auto_free(PondScenery.build(e)) as PondScenery
		var img := scene.foam_contact().get_image()
		var polygon := _polygon(e)
		var samples := 0
		var narrow := 0
		var wide := 0
		for k in polygon.size():
			var a := polygon[k]
			var b := polygon[(k + 1) % polygon.size()]
			var steps := maxi(1, int(a.distance_to(b) / 0.25))
			for s in steps:
				var p := a.lerp(b, float(s) / steps)
				var inward := (b - a).normalized().orthogonal()
				if not Geometry2D.is_point_in_polygon(p + inward * 0.2, polygon): inward = -inward
				if not Geometry2D.is_point_in_polygon(p + inward * 0.2, polygon): continue
				samples += 1
				assert_float(_at(img, p + inward * 0.04)).override_failure_message("%s: bare waterline at %s" % [id, p]).is_less(PondWildFoam.FOAM_W)
				var at := _at(img, p + inward * 0.3)
				if at > PondWildFoam.FOAM_W: narrow += 1
				if _at(img, p + inward * 0.45) < PondWildFoam.FOAM_W * 0.8: wide += 1
		assert_int(samples).is_greater(100)
		var share := float(narrow) / samples
		assert_float(share).override_failure_message("%s: narrow share %.2f" % [id, share]).is_between(0.2, 0.6)
		assert_float(float(wide) / samples).override_failure_message(id).is_greater(0.15)

## The rocks keep off the gathering points, so a point arriving moves them: the foam is made again from where they are.
func test_the_foam_follows_the_rocks_when_the_bank_is_built_again() -> void:
	var e: Dictionary = P0Ponds.location(SF[0])
	var before := auto_free(PondScenery.build(e)) as PondScenery
	var first: Vector3 = before._foam.rocks[0]
	var after := auto_free(PondScenery.build(e, [Vector3(first.x, 0, first.y)])) as PondScenery
	assert_bool(after._foam.rocks == before._foam.rocks).is_false()
	var img := after.foam_contact().get_image()
	for r in after._foam.rocks: assert_float(_at(img, Vector2(r.x, r.y))).is_less(0.02)
	assert_bool(img.get_data() == before.foam_contact().get_image().get_data()).is_false()

## The P0 pond's water does not load the baked mask (the old stones'); the old pond scene's still does.
func test_the_p0_water_skips_the_baked_mask() -> void:
	var e: Dictionary = P0Ponds.location(SF[1])
	var spec := SystemPonds.site(e)
	var old := auto_free(FishingWater.build(str(e.id), spec)) as FishingWater
	assert_bool(old.water_material.get_shader_parameter("has_foam_contact") == true).is_true()
	spec["foam"] = "runtime"
	var water := auto_free(FishingWater.build(str(e.id), spec)) as FishingWater
	assert_bool(water.water_material.get_shader_parameter("has_foam_contact") == true).is_false()
	assert_object(water.water_material.get_shader_parameter("foam_contact")).is_null()

## Whatever SPREAD is, a rock's or a cattail's ring starts at the bank (周瑜 on #942: the rocks reach 0.10 m into the
## water at most, the cattails 0.58 m on the six SF ponds): no centre further than 0.8 m out, so no ring of froth far
## off the bank (no white island).
func test_the_rocks_and_reeds_stand_at_the_bank() -> void:
	for id in SF:
		var e: Dictionary = P0Ponds.location(id)
		var scene := auto_free(PondScenery.build(e)) as PondScenery
		var polygon := _polygon(e)
		for r in scene._foam.rocks + scene._foam.reeds:
			var at := Vector2(r.x, r.y)
			if Geometry2D.is_point_in_polygon(at, polygon):
				assert_float(_shore(at, polygon)).override_failure_message("%s: %s %.2f m out in the water" % [id, at, _shore(at, polygon)]).is_less_equal(0.8)

## A pond with no outline makes no foam texture (it would be froth all over).
func test_no_outline_no_foam() -> void:
	var scene := auto_free(PondScenery.build(P0Ponds.location(SF[0]))) as PondScenery
	scene._foam["outline"] = 0
	scene._foam_texture = null
	assert_object(scene.foam_contact()).is_null()

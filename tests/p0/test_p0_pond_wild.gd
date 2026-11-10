extends GdUnitTestSuite
## The wild round a pond (SGODOT-422; 赵云's pieces, 刘备's ground, 不知火舞's rules, 上官婉儿's notes): the same pond
## dresses the same way; nothing but cattails in the water, and those only in the shallows; every piece off the gathering
## points, no tree or tall piece in front of one or under the main key; the opening screen holds 10 pieces or more; the
## bank's trees are the wild's single trees; the ground's overlay on the pond's shape's channel only.

const PondWildProps := preload("res://modules/ponds/pond_wild_props.gd")
const PondWildGround := preload("res://modules/ponds/pond_wild_ground.gd")
const SF := ["pond_san_francisco_01", "pond_san_francisco_02", "pond_san_francisco_03"]
const TALL := ["wild_tree_pine", "wild_tree_round", "wild_bush_dark", "wild_bush_olive", "wild_log_moss", "wild_fern"]

const P0Ponds := preload("res://modules/p0/p0_ponds.gd")
func _entry(id: String) -> Dictionary: return P0Ponds.location(id)

func _layout(id: String, clear: Array) -> Dictionary:
	var e := _entry(id)
	return PondWildProps.layout(e, SystemPonds.site(e), clear, [Vector3(0.1, 0, -4), Vector3(9.5, 0, -16.4)])

func test_the_same_pond_dresses_the_same_way() -> void:
	assert_dict(_layout(SF[0], [])).is_equal(_layout(SF[0], []))
	assert_bool(_layout(SF[0], []) == _layout(SF[1], [])).is_false()

func test_water_keeps_its_cattails_and_nothing_else() -> void:
	for id in SF:
		var e := _entry(id)
		var spec := SystemPonds.site(e)
		var l := _layout(id, [])
		for asset in l:
			for t in l[asset]:
				var at: Vector3 = (t as Transform3D).origin
				if asset == "wild_cattail_water":
					assert_bool(FishingModel.contains(id, at, 0.0, spec)).override_failure_message("%s cattail %s" % [id, at]).is_true()
				else:
					assert_bool(FishingModel.contains(id, at, 0.3, spec)).override_failure_message("%s %s %s" % [id, asset, at]).is_false()
		assert_bool(l.has("wild_cattail_water")).override_failure_message(id).is_true()

func test_pieces_keep_off_the_points_and_the_main_key() -> void:
	var clear := [Vector3(4.0, 0, -2.4), Vector3(7.6, 0, -1.4)]   # Fern Pond's C1 and F2
	var l := _layout(SF[2], clear)
	for asset in l:
		for t in l[asset]:
			var at: Vector3 = (t as Transform3D).origin
			if asset == "wild_cattail_water": continue
			assert_bool(PondScenery._near(at, clear)).override_failure_message("%s %s" % [asset, at]).is_false()
			if asset in TALL and asset != "wild_log_moss" and asset != "wild_fern":
				assert_bool(PondScenery._in_front(at, clear)).override_failure_message("%s in front %s" % [asset, at]).is_false()
				assert_bool(PondWildProps.KEY_COLUMN.has_point(Vector2(at.x, at.z))).override_failure_message("%s key %s" % [asset, at]).is_false()

func test_the_opening_screen_holds_ten_pieces_or_more() -> void:
	for id in SF:
		var n := 0
		var l := _layout(id, [])
		for asset in l:
			for t in l[asset]:
				var at: Vector3 = (t as Transform3D).origin
				if PondWildProps.OPENING.has_point(Vector2(at.x, at.z)): n += 1
		assert_int(n).override_failure_message(id).is_greater_equal(10)

## 不知火舞 on 422: two more clusters below the player (the quick bar's top up), none in the metre before the feet.
func test_two_clusters_below_the_player() -> void:
	for id in SF:
		var n := 0
		var l := _layout(id, [])
		for asset in l:
			for t in l[asset]:
				var at: Vector3 = (t as Transform3D).origin
				if PondWildProps.LOWER.grow(0.6).has_point(Vector2(at.x, at.z)): n += 1
				var feet := Vector2(PondWildProps.SPAWN.x, PondWildProps.SPAWN.z + 0.5)
				assert_float(Vector2(at.x, at.z).distance_to(feet)).override_failure_message("%s %s at the feet" % [id, asset]).is_greater_equal(PondWildProps.FEET_CLEAR_M)
		assert_int(n).override_failure_message(id).is_greater_equal(5)

func test_the_bank_trees_are_single_wild_trees() -> void:
	var l := _layout(SF[0], [])
	var trees := 0
	for asset in l:
		if str(asset).begins_with("wild_tree"): trees += (l[asset] as Array).size()
	assert_int(trees).is_equal(2)   # one a tree point given
	var scene := PondScenery.build(_entry(SF[0]))
	auto_free(scene)
	assert_object(scene.find_child("WildProps", false, false)).is_not_null()

func test_the_ground_overlay_on_its_shapes_channel() -> void:
	for shape in ["crescent", "gourd", "meander"]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://modules/ponds/pond_ground.gdshader")
		PondScenery._wild_ground(m, shape)
		assert_object(m.get_shader_parameter("dry_channel")).is_equal(PondScenery.DRY_CHANNEL[shape])
		assert_object(m.get_shader_parameter("ground_layout")).is_not_null()
	var other := ShaderMaterial.new()
	other.shader = preload("res://modules/ponds/pond_ground.gdshader")
	PondScenery._wild_ground(other, "lagoon")
	assert_object(other.get_shader_parameter("dry_channel")).is_equal(Vector3.ZERO)   # another shape: the ground as it was

## 盘古 on 422: with the opening camera known, `in_key` says what falls on the action keys — here the ground x 8–11,
## z −5–0 (as the bottom-right keys at the spawn), by any corner of a piece's box. Only LOW pieces have a box there;
## the others moved off or stood in for; trees under them do not stand; the dressing stays rich (10+ on the opening).
func test_on_the_keys_only_low_pieces_by_their_box() -> void:
	var zone := Rect2(8.0, -5.0, 3.0, 5.0)
	var in_key := func(corners: PackedVector3Array) -> bool:
		for c in corners: if zone.has_point(Vector2(c.x, c.z)): return true
		return false
	for id in SF:
		var e := _entry(id)
		var trees := PondScenery.tree_points([], in_key)
		var l := PondWildProps.layout(e, SystemPonds.site(e), [], trees, in_key)
		var n := 0
		for asset in l:
			for t in l[asset]:
				var at: Vector3 = (t as Transform3D).origin
				var s := (t as Transform3D).basis.get_scale().x
				if not asset in PondWildProps.LOW:
					assert_bool(in_key.call(PondWildProps.box_corners(asset, at, s))).override_failure_message("%s %s at %s" % [id, asset, at]).is_false()
				if PondWildProps.OPENING.has_point(Vector2(at.x, at.z)): n += 1
		assert_int(n).override_failure_message(id).is_greater_equal(10)
	assert_bool(PondScenery.tree_points([], in_key).has(Vector3(12.1, 0, -5.5))).is_true()   # its crown short of the zone
	var wide := func(corners: PackedVector3Array) -> bool:
		for c in corners: if Rect2(10.5, -7.0, 3.0, 4.0).has_point(Vector2(c.x, c.z)): return true
		return false
	assert_bool(PondScenery.tree_points([], wide).has(Vector3(12.1, 0, -5.5))).is_false()   # under them: it does not stand
	for id in SF:   # no camera: the old rule, no tall piece standing in KEY_COLUMN
		var l := _layout(id, [])
		for asset in l:
			if not asset in TALL or asset in ["wild_log_moss", "wild_fern"]: continue
			for t in l[asset]:
				var at: Vector3 = (t as Transform3D).origin
				assert_bool(PondWildProps.KEY_COLUMN.has_point(Vector2(at.x, at.z))).override_failure_message("%s %s at %s" % [id, asset, at]).is_false()

## The user's 0.3.4 (2) on an iPhone (bot 589 / 590): a 32-bit float texture is not filterable there (nor on many GLES3
## phones), so the water's distance field fell back to nearest and the sand edges stepped in 0.25 m squares. It stays
## a 16-bit float one, which filters everywhere.
func test_the_water_distance_field_is_a_filterable_half_float() -> void:
	var e: Dictionary = P0Ponds.location(SF[0])
	var polygon := PackedVector2Array()
	for q in SystemPonds.site(e).get("polygon", []): polygon.append(Vector2(float(q[0]), float(q[1])))
	var tex := PondWildGround._water_sdf(polygon)
	assert_int(tex.get_image().get_format()).is_equal(Image.FORMAT_RH)

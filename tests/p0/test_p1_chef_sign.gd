extends GdUnitTestSuite
## The Chef's Sign (Homestead Lv10, §7.7; SGODOT-282, 不知火舞 / 上官婉儿 on 282): a post and hanging board left of the door
## path as one faces the house, on a yard cell that is no bed, no path and nothing else's; up only from Lv10, then solid;
## its strip `Chef's Sign`, and a tap opens the facilities' small card with HOME-1's Lv10 line, no button.

const FarmArt = preload("res://modules/farm/farm_art.gd")

func test_its_cell_is_yard_left_of_the_door_path_off_the_field_and_the_paths() -> void:
	var c := P0Garden.CHEF_SIGN_CELL
	var yard: Dictionary = P0Decor.yard()
	var inside := func(rects: Array) -> bool:
		return rects.any(func(r): return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(c))
	assert_bool(P0Garden.WALK_RECT.has_point(c)).is_true()
	assert_bool(inside.call(yard.get("field", []))).is_false()
	assert_bool(inside.call(yard.get("paths", []))).is_false()
	assert_bool(inside.call(yard.get("objects", []))).is_true()   # its cell is a yard object: no decor on it (the server's too)
	for k in P0Garden.FOOTPRINTS: assert_bool((P0Garden.FOOTPRINTS[k] as Rect2i).has_point(c)).is_false()
	assert_int(c.x).is_less(P0Garden.PLAQUE_CELL.x)   # left of the plaque, so left of the path (x 8–10)
	assert_int(c.x).is_greater(P0Garden.CHEF_SIGN_BOARD_CELL.x)   # its board hangs on the post's left
	assert_int(c.y).is_equal(P0Garden.PLAQUE_CELL.y)
	var bp := P0Garden.blueprint()
	assert_bool(bp.is_walkable(c)).is_true()

## 刘备's models (#356 / #376): timber chef_sign_a, stone chef_sign_b after Lv10's look (上官婉儿 on 282), timber by
## default; 1.74 m, the 0.50 m board 1.06 m up on an arm out to −X, its centre where the strip's tap is; the post right of
## the cell's centre (at most 0.185: B's foot is 5 mm from the cell's edge; 0.08 keeps the board off the bench on screen).
func test_the_sign_is_the_timber_or_stone_model_after_lv10s_look() -> void:
	var farm = load("res://scenes/p0/p0_farm.gd")
	var a: MeshInstance3D = auto_free(farm.chef_sign_mesh("a"))
	var b: MeshInstance3D = auto_free(farm.chef_sign_mesh("b"))
	var plain: MeshInstance3D = auto_free(farm.chef_sign_mesh(""))
	assert_object(a.mesh).is_same(FarmArt.mesh_for("chef_sign_a"))
	assert_object(b.mesh).is_same(FarmArt.mesh_for("chef_sign_b"))
	assert_object(plain.mesh).is_same(a.mesh)
	for m in [a, b]:
		var box := (m as MeshInstance3D).mesh.get_aabb()
		assert_float(box.end.y).is_equal_approx(1.74, 0.01)
		assert_float(box.position.x).is_equal_approx(-0.582, 0.01)   # the board's outer edge, out to −X
		assert_bool(box.has_point(farm.CHEF_SIGN_HIT)).is_true()
	assert_vector(farm.CHEF_SIGN_HIT).is_equal(Vector3(-0.332, 1.285, 0))   # board_center
	assert_float(farm.CHEF_SIGN_SHIFT.x).is_between(0.0, 0.185)

## B (不知火舞 282 33835f54; 上官婉儿 56fa9620): its board hangs over (4,14) at shoulder height, so with the sign up that
## cell is not walked; the door, the spawn and the bench still reach the yard's west corner (where the mine mouth stood
## until 355 b1), never through it. No decor stands under the board either: the cell is a yard object.
## The farm's grid as it stands: the yard fence's front, the Homestead sign, the mailbox, then the sign's cells.
func test_with_the_sign_up_the_way_west_goes_round_its_board() -> void:
	var bp := P0Garden.blueprint()
	P0Garden.block_points(bp, P0Garden.fence_block_points(bp))
	P0Garden.block_points(bp, [P0Garden.sign_point(bp), P0Garden.mailbox_point(bp)])
	var grid := BlueprintGrid.new(bp)
	for c in [P0Garden.CHEF_SIGN_CELL, P0Garden.CHEF_SIGN_BOARD_CELL]: grid.set_solid(c, true)
	var board := P0Garden.CHEF_SIGN_BOARD_CELL
	assert_bool(P0Decor.yard().get("objects", []).any(func(r): return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(board))).is_true()   # a yard object to decor
	assert_str(P0Decor.reason({"decor": {"placed": [], "cap": 20, "stored": {}}}, "deco_planter", board)).is_equal("Space taken")
	for from in [Vector2i(9, 14), P0Garden.ANCHORS.spawn, Vector2i(6, 15)]:   # the door's walkway, the spawn, before the bench
		for to in [Vector2i(3, 13), Vector2i(3, 14)]:   # the yard's west corner
			var path := grid.point_path(bp.cell_to_world(from), bp.cell_to_world(to))
			assert_array(path).override_failure_message("%s → %s" % [from, to]).is_not_empty()
			for i in range(1, path.size()):   # every 5 cm along it
				var a: Vector3 = path[i - 1]
				for k in 20:
					var c := bp.world_to_cell(a.lerp(path[i], k / 20.0))
					assert_bool(c == board).override_failure_message("%s → %s crosses %s" % [from, to, board]).is_false()

func test_its_card_reads_its_title_level_and_homes_line_without_a_button() -> void:
	var card: Dictionary = load("res://scenes/p0/p0_farm.gd").chef_sign_card()
	assert_that([card.title, card.lead, card.facts, card.button]).is_equal(["Chef's Sign", "Homestead Lv10",
		["Every dish's gold zone +5"], ""])
	assert_str(str(P0WorldPrompts.chef_sign({}).text)).is_equal("Chef's Sign")
	var ui := P0Ui.new()
	ui.quick_store = "user://test_p1_chef_sign_quick.json"
	add_child(auto_free(ui))
	await get_tree().process_frame
	var sheet := ui.open_facility_card(card, func(): pass)
	await get_tree().process_frame
	assert_int(sheet.find_children("*", "UiCommandButton", true, false).filter(func(b): return b.visible).size()).is_equal(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p1_chef_sign_quick.json"))

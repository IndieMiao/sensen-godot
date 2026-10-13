extends GdUnitTestSuite
## The Chef's Sign (Homestead Lv10, §7.7; SGODOT-282, 不知火舞 / 上官婉儿 on 282): a post and hanging board left of the door
## path as one faces the house, on a yard cell that is no bed, no path and nothing else's; up only from Lv10, then solid;
## its strip `Chef's Sign`, and a tap opens the facilities' small card with HOME-1's Lv10 line, no button.

func test_its_cell_is_free_yard_left_of_the_door_path() -> void:
	var c := P0Garden.CHEF_SIGN_CELL
	var yard: Dictionary = P0Decor.yard()
	var inside := func(rects: Array) -> bool:
		return rects.any(func(r): return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(c))
	assert_bool(P0Garden.WALK_RECT.has_point(c)).is_true()
	assert_bool(inside.call(yard.get("field", []))).is_false()
	assert_bool(inside.call(yard.get("paths", []))).is_false()
	assert_bool(inside.call(yard.get("objects", []))).is_false()
	for k in P0Garden.FOOTPRINTS: assert_bool((P0Garden.FOOTPRINTS[k] as Rect2i).has_point(c)).is_false()
	assert_int(c.x).is_less(P0Garden.PLAQUE_CELL.x)   # left of the plaque, so left of the path (x 8–10)
	assert_int(c.y).is_equal(P0Garden.PLAQUE_CELL.y)
	var bp := P0Garden.blueprint()
	assert_bool(bp.is_walkable(c)).is_true()

func test_the_placeholder_is_a_post_and_a_board_up_off_the_ground() -> void:
	var s: Node3D = auto_free(load("res://scenes/p0/p0_farm.gd").chef_sign_prop(Vector3.ZERO))
	var board := s.get_node("Board") as MeshInstance3D
	var post := s.get_node("Post") as MeshInstance3D
	assert_float(post.position.y + (post.mesh as BoxMesh).size.y * 0.5).is_equal_approx(1.7, 0.01)   # 1.7 m tall
	assert_float(board.position.y - (board.mesh as BoxMesh).size.y * 0.5).is_greater_equal(1.0)   # its foot ≥ 1.0 m up

func test_its_card_reads_its_title_level_and_homes_line_without_a_button() -> void:
	var card: Dictionary = load("res://scenes/p0/p0_farm.gd").chef_sign_card()
	assert_that([card.title, card.lead, card.facts, card.button]).is_equal(["Chef's Sign", "Master Chef · Homestead Lv10",
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

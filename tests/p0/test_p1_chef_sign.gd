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
	assert_int(c.x).is_greater(4)   # off the mine path (x 3–4)
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

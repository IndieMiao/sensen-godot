extends GdUnitTestSuite
## FarmBlueprint：加载、mask、坐标、canonical/checksum 与 Node 管线逐字一致。

const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"
const CANON := "fix_grid|1|1111111111111111111111111111111111111111111111111111110011111100|0000000011101110000000000000000000000000111000000000000000000000|1110111111101111111011110000000011101111111011111110110011101100|1111111111111111111111111111111111111111111111111111111111111111|spawn:3,3;house:4,5;storage:5,5;well:3,2;exit:3,7;beds:0,1,1,1,2,1/4,1,5,1,6,1/0,5,1,5,2,5"

func test_load_fields() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_object(bp).is_not_null()
	assert_str(bp.layout_patch_id).is_equal("fix_grid")
	assert_int(bp.revision).is_equal(1)
	assert_that(bp.grid).is_equal(Vector2i(8, 8))
	assert_float(bp.cell_m).is_equal(1.0)
	assert_int(bp.blocks.size()).is_equal(4)
	assert_int(bp.paths.size()).is_equal(2)
	assert_that(bp.anchor("spawn")).is_equal(Vector2i(3, 3))
	assert_int(bp.beds().size()).is_equal(3)
	assert_that(bp.beds()[1].cells[2]).is_equal(Vector2i(6, 1))
	assert_that(bp.overlay.center).is_equal(Vector2(31.2, 121.4))

func test_masks_and_bounds() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_bool(bp.is_walkable(Vector2i(3, 3))).is_true()
	assert_bool(bp.is_walkable(Vector2i(7, 7))).is_false() # 水塘
	assert_bool(bp.is_walkable(Vector2i(8, 0))).is_false() # 越界
	assert_bool(bp.mask_has("cultivable", Vector2i(1, 1))).is_true()
	assert_bool(bp.mask_has("buildable", Vector2i(3, 0))).is_false() # 路上不可建

func test_canonical_and_checksum_match_node_pipeline() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	assert_str(bp.canonical()).is_equal(CANON)
	assert_str(bp.compute_checksum()).is_equal("d74f428b8c7fe9131cb8c9191aaf1009c5e1f993a941465f53f0cd9cb1a20ca7")
	assert_bool(bp.verify_checksum()).is_true()
	bp.masks.walkable[7] = "11111110"
	assert_bool(bp.verify_checksum()).is_false()

func test_world_roundtrip() -> void:
	var bp := FarmBlueprint.load_file(FIX)
	var w := bp.cell_to_world(Vector2i(2, 5))
	assert_that(w).is_equal(Vector3(2.5, 0.0, -5.5))
	assert_that(bp.world_to_cell(w)).is_equal(Vector2i(2, 5))
	assert_that(bp.world_to_cell(Vector3(2.99, 0, -5.01))).is_equal(Vector2i(2, 5))
	assert_that(bp.cell_to_world(Vector2i(1, 1), 2.0)).is_equal(Vector3(3.0, 0.0, -3.0))

func test_missing_file_returns_null() -> void:
	assert_object(FarmBlueprint.load_file("res://tests/fixtures/blueprints/nope/r1/farm_blueprint.json")).is_null()
	assert_str(FarmBlueprint.asset_path("sh_a", 1)).is_equal("res://assets/blueprints/sh_a/r1/farm_blueprint.json")

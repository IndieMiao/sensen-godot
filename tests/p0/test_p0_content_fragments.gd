extends GdUnitTestSuite
## SGODOT-275 (亚瑟's cross-city plan §6): content fragments under assets/p0/content/ merge into the main table the way
## the server's mergeContent does. A fragment only adds; a clash is reported, never applied.

func _base() -> Dictionary:
	return {
		crops = [{id = "crop_radish", energy = 2}],
		shops = {market = {buy = ["seed_radish"]}},
		residents = {res_pip = {name = "Pip"}},
		wallet_floor = 40,
	}

func test_a_fragment_adds_ids_keys_and_entries_without_touching_what_is_there() -> void:
	var c := _base()
	var errors := P0Logic.merge_content(c, {
		_note = "skipped",
		crops = [{id = "crop_corn", energy = 3}],
		shops = {tea = {buy = ["drink_hot_tea"]}, market = {sells = ["seed_corn"]}},
		residents = {res_ama = {name = "Ama"}, res_pip = {likes = ["dish_grilled_crucian"]}},
	}, "farm_crops.json")
	assert_array(errors).is_empty()
	assert_array((c.crops as Array).map(func(x): return x.id)).is_equal(["crop_radish", "crop_corn"])
	assert_int(int(c.crops[0].energy)).is_equal(2)
	assert_dict(c.shops).is_equal({market = {buy = ["seed_radish"], sells = ["seed_corn"]}, tea = {buy = ["drink_hot_tea"]}})
	assert_dict(c.residents.res_pip).is_equal({name = "Pip", likes = ["dish_grilled_crucian"]})
	assert_bool(c.has("_note")).is_false()

func test_a_clash_is_reported_with_the_file_and_path_and_not_applied() -> void:
	var c := _base()
	assert_array(P0Logic.merge_content(c, {crops = [{id = "crop_radish", energy = 9}]}, "farm_crops.json")) \
		.is_equal(["p0 content: farm_crops.json: crops already has id crop_radish"])
	assert_int(int(c.crops[0].energy)).is_equal(2)
	assert_str(str(P0Logic.merge_content(c, {residents = {res_pip = {name = "Pippa"}}}, "res_p1.json"))) \
		.contains("res_p1.json: residents.res_pip.name is already set")
	assert_str(str(c.residents.res_pip.name)).is_equal("Pip")
	assert_str(str(P0Logic.merge_content(c, {wallet_floor = 50}, "econ_p1.json"))).contains("wallet_floor is already set")
	assert_str(str(P0Logic.merge_content(c, {shops = {market = {buy = ["seed_corn"]}}}, "farm_crops.json"))) \
		.contains("shops.market.buy is already set")
	assert_array(c.shops.market.buy).is_equal(["seed_radish"])

func test_the_repo_fragments_merge_cleanly_in_name_order() -> void:
	P0Logic._content = {}
	var c := P0Logic.content()
	assert_bool(c.is_empty()).is_false()
	assert_array(P0Logic.content_errors).is_empty()
	assert_bool(c.has("_note")).is_true()   # the main table's own note; a fragment's _note never lands
	assert_str(str(c._note)).not_contains("Content fragments (SGODOT-275")

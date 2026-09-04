extends GdUnitTestSuite

const TEXT := """{"format":1,"regions":[
{"id":"shanghai","name":"上海","timezone":"Asia/Shanghai","center":[31.2304,121.4737],"street_zoom":16.0,"pitch":45.0,
 "candidates":[{"layout_patch_id":"sh_a","revision":1,"name":"A"},{"layout_patch_id":"sh_b","revision":1,"name":"B"}]},
{"id":"los_angeles","name":"LA","timezone":"America/Los_Angeles","center":[34.0522,-118.2437],"street_zoom":16.0,"pitch":45.0,
 "candidates":[{"layout_patch_id":"la_a","revision":1,"name":"LA-A"}]}]}"""

func after_test() -> void:
	FarmRegions.clear_choice()
	FarmChoice.clear()

func test_parse_and_query() -> void:
	var r := FarmRegions.from_text(TEXT)
	assert_object(r).is_not_null()
	assert_that(r.ids()).is_equal(PackedStringArray(["shanghai", "los_angeles"]))
	assert_str(r.region("shanghai").name).is_equal("上海")
	assert_int(r.candidates("shanghai").size()).is_equal(2)
	assert_str(r.candidates("los_angeles")[0].layout_patch_id).is_equal("la_a")
	assert_bool(r.region("mars").is_empty()).is_true()
	assert_object(FarmRegions.from_text("not json")).is_null()

func test_nearest_region() -> void:
	var r := FarmRegions.from_text(TEXT)
	assert_str(FarmRegions.nearest_region_id(r.regions, 34.1, -118.3)).is_equal("los_angeles")
	assert_str(FarmRegions.nearest_region_id(r.regions, 31.0, 121.0)).is_equal("shanghai")
	assert_str(FarmRegions.nearest_region_id([], 0.0, 0.0)).is_equal("")

func test_choice_roundtrip() -> void:
	assert_str(FarmRegions.load_choice()).is_equal("")
	FarmRegions.save_choice("los_angeles")
	assert_str(FarmRegions.load_choice()).is_equal("los_angeles")
	FarmChoice.save("sh_b", 1)
	assert_that(FarmChoice.load()).is_equal({"layout_patch_id": "sh_b", "revision": 1})

func test_default_file_loads() -> void:
	var r := FarmRegions.load_default()
	assert_object(r).is_not_null()
	assert_bool(r.ids().has("shanghai")).is_true()
	assert_bool(r.ids().has("los_angeles")).is_true()

extends GdUnitTestSuite

const SCENE := "res://scenes/city_select/city_select.tscn"

func after_test() -> void:
	FarmRegions.clear_choice()

func test_one_button_per_region() -> void:
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	assert_int(s.region_buttons().size()).is_equal(FarmRegions.load_default().ids().size())
	assert_object(s.get_node("%UseCurrent")).is_not_null()

func test_pick_region_pure() -> void:
	var regions := FarmRegions.load_default().regions
	assert_str(s_pick(regions, 34.0, -118.2, true)).is_equal("los_angeles")
	assert_str(s_pick(regions, 0.0, 0.0, false, "shanghai")).is_equal("shanghai")
	assert_str(s_pick(regions, 0.0, 0.0, false)).is_equal("")

func s_pick(regions: Array, lat: float, lng: float, has_fix: bool, fallback := "") -> String:
	var script := load("res://scenes/city_select/city_select.gd")
	return script.pick_region(regions, lat, lng, has_fix, fallback)

func test_main_scene_is_city_select() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(SCENE)

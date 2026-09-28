extends GdUnitTestSuite
## 选城页（SGODOT-137）：全球任意城市可选，不申请定位权限，默认城市由 IP 预填且需确认。

const SCENE := "res://scenes/city_select/city_select.tscn"
const TOKYO := {"id": "gn-1850147", "name": "Tokyo", "country": "Japan", "country_code": "JP", "timezone": "Asia/Tokyo",
	"center": [35.6895, 139.69171], "radius_km": 45, "curated": false, "farm_count": 3,
	"placement_bounds": [35.2853, 139.1953, 36.0937, 140.1881]}

func after_test() -> void:
	FarmRegions.clear_choice()

func _scene() -> Control:
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	return s

func test_offline_list_shows_the_curated_cities() -> void:
	var s := _scene()
	await get_tree().process_frame
	var ids: Array = s.region_buttons().map(func(b): return str(b.get_meta("city_id")))
	assert_array(ids).contains_exactly(["shanghai", "los_angeles"])

func test_no_location_permission_entry_point() -> void:
	var s := _scene()
	assert_object(s.get_node_or_null("%UseCurrent")).is_null()
	var source := FileAccess.get_file_as_string("res://scenes/city_select/city_select.gd")
	assert_str(source).not_contains("start_location")
	assert_str(source).not_contains("MapBridgeFactory")

func test_suggestion_is_a_card_the_player_confirms() -> void:
	var s := _scene()
	var box: Control = s.find_child("Suggestion", true, false)
	assert_bool(box.visible).is_false()
	s.show_suggestion(TOKYO)
	assert_bool(box.visible).is_true()
	var button: Button = s.find_child("SuggestedCity", true, false)
	assert_str(button.text).is_equal("Tokyo, Japan")
	# Nothing is chosen until the button is pressed.
	assert_str(FarmRegions.load_choice()).is_empty()

func test_search_results_and_popular_list_render_server_cities() -> void:
	var s := _scene()
	s.show_results([TOKYO, {"id": "gn-6058560", "name": "London", "country": "Canada", "admin": "Ontario"}])
	await get_tree().process_frame
	var labels: Array = s.result_buttons().map(func(b): return b.text)
	assert_str(labels[0]).is_equal("Tokyo, Japan · 3 farms")
	assert_str(labels[1]).is_equal("London, Ontario, Canada")
	assert_bool(s.buttons.visible).is_false()
	s.show_results([])
	assert_bool(s.buttons.visible).is_true()
	s._show_popular([TOKYO])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(s.region_buttons().size()).is_equal(1)

func test_city_labels_disambiguate_same_names() -> void:
	var script := load("res://scenes/city_select/city_select.gd")
	assert_str(script.city_label({"name": "London", "country": "United Kingdom", "admin": "England"})).is_equal("London, United Kingdom")
	assert_str(script.city_label({"name": "London", "country": "Canada", "admin": "Ontario"})).is_equal("London, Ontario, Canada")
	assert_str(script.city_label({"name": "Shanghai", "curated": true})).is_equal("Shanghai")

func test_main_scene_is_city_select() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(SCENE)

func test_owned_farm_region_skips_picker_only_with_usable_farm() -> void:
	var script := load("res://scenes/city_select/city_select.gd")
	var regions := FarmRegions.load_default()
	assert_str(script.owned_farm_region(regions, {})).is_equal("")
	assert_str(script.owned_farm_region(regions, {"layout_patch_id": "missing", "revision": 1})).is_equal("")
	var bp := FarmBlueprint.load_choice({"layout_patch_id": "sh_a", "revision": 2})
	assert_object(bp).is_not_null()
	assert_str(script.owned_farm_region(regions, {"layout_patch_id": "sh_a", "revision": 2})).is_equal(bp.region_id)

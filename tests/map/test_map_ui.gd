extends GdUnitTestSuite
## The map HUD stays compact so nearby people and notes remain the primary content.

const MAP_SCENE := "res://scenes/map_poc/map_poc.tscn"
const MAP_SCRIPT := "res://scenes/map_poc/map_poc.gd"


func _instantiate(add_to_tree: bool = false) -> Node:
	var scene := (load(MAP_SCENE) as PackedScene).instantiate()
	if add_to_tree:
		add_child(auto_free(scene))
	else:
		auto_free(scene)
	return scene


func test_header_is_compact_english_and_keeps_avatar_loading_progress() -> void:
	var scene := _instantiate()
	var top := scene.get_node("HUD/SafeArea/Root/TopPanel") as PanelContainer
	assert_bool(top.custom_minimum_size.x <= 220.0).is_true()
	assert_bool(top.custom_minimum_size.y <= 64.0).is_true()
	assert_float(top.anchor_right).is_equal(0.0)
	assert_str((top.get_node("VBox/TitleRow/RegionTitle") as Label).text).is_equal("Nearby")
	assert_str((top.get_node("VBox/StatusRow/LocationStatus") as Label).text).is_equal(
		"Loading map...")
	assert_str((top.get_node("VBox/TitleRow/NearbyCount") as Label).text).contains("people")
	var load_bar := top.get_node("VBox/LoadSlot/LoadBar") as ProgressBar
	assert_bool(load_bar.visible).is_true()
	assert_float(load_bar.max_value).is_equal(float(scene.INITIAL_ROLE_COUNT + 1))
	assert_bool(load_bar.show_percentage).is_false()


func test_engineering_controls_and_old_wide_layout_are_absent() -> void:
	var root := _instantiate().get_node("HUD/SafeArea/Root")
	for path in ["Stack", "Chip/VBox/Debug", "Chip/VBox/Sub", "ViewMode",
			"BottomActions", "SideToolbar/VBox/Mode2D", "SideToolbar/VBox/Mode3D"]:
		assert_object(root.get_node_or_null(path)).is_null()
	var source := FileAccess.get_file_as_string(MAP_SCRIPT)
	for old_copy in ["z%.1f", "飞洛杉矶", "回我的位置", "去换装"]:
		assert_bool(source.contains(old_copy)).is_false()


func test_travel_uses_the_side_rail_and_avatar_edit_stays_small() -> void:
	var scene := _instantiate(true)
	var root := scene.get_node("HUD/SafeArea/Root")
	var rail := root.get_node("SideToolbar") as PanelContainer
	var travel := rail.get_node("VBox/TravelGroup/Travel") as Button
	var edit := rail.get_node("VBox/EditGroup/EditAvatar") as Button
	assert_bool(rail.custom_minimum_size.x <= 72.0).is_true()
	assert_bool(rail.get_theme_stylebox(&"panel") is StyleBoxEmpty).is_true()
	assert_str((rail.get_node("VBox/TravelGroup/TravelLabel") as Label).text).is_equal("LA")
	assert_str(travel.tooltip_text).is_equal("Explore Los Angeles")
	assert_str((rail.get_node("VBox/EditGroup/EditLabel") as Label).text).is_equal("Edit")
	assert_str(edit.tooltip_text).is_equal("Edit Avatar")
	assert_bool(FileAccess.get_file_as_string(MAP_SCRIPT).contains(
		"AppRouter.go_to_dressing()" )).is_true()


func test_rotate_control_is_gone_and_bearing_has_no_mutator() -> void:
	## 侧栏 Rotate 已移除。bearing 仍是相机协议的一部分（要喂给 Mapbox），但不再有
	## 任何入口改它——若哪天又冒出个 setter 而侧栏没有对应控件，就是有人加了回来
	## 却没接 UI，这里直接拦下。
	var rail := _instantiate().get_node("HUD/SafeArea/Root/SideToolbar")
	assert_object(rail.get_node_or_null("VBox/Rotate")).is_null()
	assert_object(rail.get_node_or_null("VBox/RotateGroup")).is_null()
	var source := FileAccess.get_file_as_string(MAP_SCRIPT)
	assert_bool(source.contains("func _set_bearing")).is_false()
	assert_bool(source.contains("rotate_btn")).is_false()


func test_side_rail_is_uniform_tiles_with_captions_outside_the_button() -> void:
	## 侧栏曾是 CheckButton(带拨杆) + 胶囊 + 圆角矩形 + 正圆四种控件、三种宽度。
	## 现在每项都是"同尺寸纯图标方块 + 方块外的文案"，文字不再撑按钮的形状。
	## Edit 必须在最上面（进换装房是这屏最主要的去处）。
	## 必须挂进场景树：theme_type_variation 要有 theme owner 才解析得出来，
	## 游离节点上 get_theme_constant 只会拿到引擎默认值（描边恒为 0）。
	var rail := _instantiate(true).get_node("HUD/SafeArea/Root/SideToolbar")
	var groups := (rail.get_node("VBox") as Control).get_children()
	assert_int(groups.size()).is_equal(3)
	assert_str(groups[0].name).is_equal("EditGroup")
	var first_button := groups[0].get_child(0) as Button
	for group in groups:
		var tile := group.get_child(0) as Button
		var caption := group.get_child(1) as Label
		assert_object(tile).is_not_null()
		assert_object(caption).is_not_null()
		assert_str(str(tile.theme_type_variation)).is_equal("RailButton")
		assert_vector(tile.custom_minimum_size).is_equal(first_button.custom_minimum_size)
		# 48dp 触摸下限，同时不撑破 rail 的 <=72 宽度预算
		assert_bool(tile.custom_minimum_size.x >= 48.0).is_true()
		assert_bool(tile.custom_minimum_size.y >= 48.0).is_true()
		assert_bool(tile.custom_minimum_size.x <= 72.0).is_true()
		# 纯图标：文案已经搬到按钮外，按钮里再有 text 就会把方块撑成不同宽度
		assert_object(tile.icon).is_not_null()
		assert_bool(tile.text.is_empty()).is_true()
		# 图标必须显式居中。Button.icon_alignment 默认是 LEFT——有 text 时看不出来，
		# 去掉文案后图标会整个贴到左内边距上（真机上三个图标一起偏左，很明显）。
		assert_int(tile.icon_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
		assert_int(tile.vertical_icon_alignment).is_equal(VERTICAL_ALIGNMENT_CENTER)
		# 文案直接压在地图上，必须有描边兜底可读性
		assert_str(str(caption.theme_type_variation)).is_equal("RailCaption")
		assert_bool(caption.text.is_empty()).is_false()
		assert_int(caption.get_theme_constant(&"outline_size")).is_greater(0)


func test_2d_3d_is_one_switch_with_a_clear_current_value() -> void:
	var scene := _instantiate(true)
	var root := scene.get_node("HUD/SafeArea/Root")
	var mode := root.get_node("SideToolbar/VBox/ViewGroup/ViewModeSwitch") as Button
	var mode_label := root.get_node("SideToolbar/VBox/ViewGroup/ViewLabel") as Label
	assert_bool(mode.custom_minimum_size.x >= 48.0).is_true()
	assert_bool(mode.custom_minimum_size.y >= 48.0).is_true()
	assert_object(root.get_node_or_null("ViewMode/Mode2D")).is_null()
	assert_object(root.get_node_or_null("ViewMode/Mode3D")).is_null()
	# 必须是 toggle Button 而不是 CheckButton：CheckButton 自带拨杆，在一排图标
	# 方块里是唯一带活动部件的控件，正是"侧栏样式不统一"的最大来源。
	assert_bool(mode is CheckButton).is_false()
	assert_bool(mode.toggle_mode).is_true()
	scene._set_pitch(0.0)
	assert_bool(mode.button_pressed).is_false()
	assert_str(mode_label.text).is_equal("2D")
	assert_str(mode.tooltip_text).is_equal("Switch to 3D")
	var flat_icon := mode.icon
	scene._set_pitch(45.0)
	assert_bool(mode.button_pressed).is_true()
	assert_str(mode_label.text).is_equal("3D")
	assert_str(mode.tooltip_text).is_equal("Switch to 2D")
	# 图标随状态换：只换文案的话 2D/3D 两字在小字号下几乎看不出差别
	assert_bool(mode.icon == flat_icon).is_false()


func test_fallback_location_is_never_presented_as_the_users_position() -> void:
	var scene = auto_free(load(MAP_SCRIPT).new())
	scene._home_resolved = true
	scene._home_from_fallback = true
	var status: String = scene._location_status_text()
	assert_str(status).is_equal("Demo location")
	assert_bool(status.contains("My location")).is_false()
	assert_str(scene._region_title_text()).is_equal("Demo Area")


func test_region_title_stays_truthful_for_real_unknown_locations() -> void:
	var scene = auto_free(load(MAP_SCRIPT).new())
	assert_str(scene._region_title_text()).is_equal("Nearby")
	scene._home_resolved = true
	scene._home_from_fallback = false
	assert_str(scene._region_title_text()).is_equal("Near You")
	scene._in_la = true
	assert_str(scene._region_title_text()).is_equal("Los Angeles")


func test_la_round_trip_copy_stays_compact() -> void:
	var scene := _instantiate(true)
	var group := scene.get_node("HUD/SafeArea/Root/SideToolbar/VBox/TravelGroup")
	var travel := group.get_node("Travel") as Button
	var caption := group.get_node("TravelLabel") as Label
	assert_float(scene.LA_SPREAD_M).is_less_equal(scene.NEAR_SPREAD_M)
	scene._header_locked = false
	var away_icon := travel.icon
	scene._on_fly_pressed()
	assert_str(caption.text).is_equal("Nearby")
	assert_str(travel.tooltip_text).is_equal("Back Nearby")
	assert_bool(travel.icon == away_icon).is_false()
	assert_str(scene.region_title.text).is_equal("Los Angeles")
	assert_str(scene.location_status.text).is_equal("Exploring")
	scene._on_fly_pressed()
	assert_str(caption.text).is_equal("LA")
	assert_str(travel.tooltip_text).is_equal("Explore Los Angeles")
	assert_bool(travel.icon == away_icon).is_true()
	assert_str(scene.region_title.text).is_equal("Nearby")


func test_nearby_count_excludes_the_users_own_avatar() -> void:
	var scene = auto_free(load(MAP_SCRIPT).new())
	var self_node := Node3D.new()
	var nearby_node := Node3D.new()
	scene.add_child(self_node)
	scene.add_child(nearby_node)
	scene._pawns.append({"cohort": "self", "ready": true, "node": self_node})
	scene._pawns.append({"cohort": "near", "ready": true, "node": nearby_node})
	assert_int(scene._visible_role_count()).is_equal(1)
	assert_str(scene._people_count_text(0)).is_equal("0 people")
	assert_str(scene._people_count_text(1)).is_equal("1 person")
	assert_str(scene._people_count_text(2)).is_equal("2 people")


func test_progress_waits_for_map_and_all_initial_roles() -> void:
	var scene := _instantiate(true)
	var load_bar := scene.load_bar as ProgressBar
	assert_bool(scene.LOAD_BAR_MIN_VISIBLE_MS >= 1500).is_true()
	assert_bool(scene.LOAD_BAR_MIN_VISIBLE_MS <= 2000).is_true()
	assert_bool(load_bar.visible).is_true()
	scene._spawn_queue.clear()
	scene._pawns.clear()
	for i in scene.INITIAL_ROLE_COUNT:
		var holder := Node3D.new()
		scene.rigs.add_child(holder)
		scene._pawns.append({"ready": true, "cohort": "la", "node": holder})
	scene._map_is_ready = false
	scene._header_locked = false
	scene._load_bar_started_ms = Time.get_ticks_msec()
	scene._update_load_bar()
	assert_float(load_bar.value).is_equal(float(scene.INITIAL_ROLE_COUNT))
	assert_bool(load_bar.visible).is_true()
	scene._home_resolved = true
	scene._home_from_fallback = false
	assert_str(scene._location_status_text()).is_equal("Loading map...")
	scene._map_is_ready = true
	scene._load_bar_started_ms = Time.get_ticks_msec() - scene.LOAD_BAR_MIN_VISIBLE_MS
	scene._update_load_bar()
	assert_float(load_bar.value).is_equal(float(scene.INITIAL_ROLE_COUNT + 1))
	assert_bool(load_bar.visible).is_false()
	assert_str(scene.location_status.text).is_equal("Location ready")


func test_markers_render_below_controls_and_reserve_every_control_edge() -> void:
	var scene := _instantiate(true)
	await get_tree().process_frame
	var layer := scene.marker_layer as MarkerLayer
	var top := scene.get_node("HUD/SafeArea/Root/TopPanel") as Control
	var rail := scene.get_node("HUD/SafeArea/Root/SideToolbar") as Control
	var system_top: int = scene.safe_area.get_theme_constant(&"margin_top")
	var system_right: int = scene.safe_area.get_theme_constant(&"margin_right")
	var system_bottom: int = scene.safe_area.get_theme_constant(&"margin_bottom")
	assert_bool(layer.z_index < top.z_index).is_true()
	assert_bool(layer._safe_margins.y >= system_top + top.size.y).is_true()
	assert_bool(layer._safe_margins.z >= system_right + rail.size.x).is_true()
	assert_bool(layer._safe_margins.w > system_bottom).is_true()

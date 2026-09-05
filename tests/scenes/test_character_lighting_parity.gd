extends GdUnitTestSuite
## 角色打光必须在两个场景里一致。
##
## 2026-09-01 真机反馈："地图里角色整个是暗的，换装场景又过曝"。根因是两处不对称：
##   1. 地图场景**根本没有 WorldEnvironment**，project.godot 也没配默认环境
##      → 环境光 = 0 → 角色只被一盏平行光照着，背光面纯黑。
##   2. 换装房的环境光来自**背景色**（Godot 的 ambient_light_source 默认 = BG），
##      背景 0.9 白 × energy 0.6，叠上平行光 1.2 就过曝。
##      顺带这个默认还有个结构问题：改背景颜色会连带改角色打光，两件事不该耦合。
##
## 所以两个场景现在都用**显式的 ambient 颜色**（source = 2 / COLOR），与背景解耦，
## 且数值必须相同——同一个角色在哪个场景看起来都该一样。

const MAP := "res://scenes/map_poc/map_poc.tscn"
const ROOM := "res://scenes/dressing_room/dressing_room.tscn"

## 从 .tscn 文本里取某个 key 的值（首个匹配）。
func _val(path: String, key: String) -> String:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var s := line.strip_edges()
		if s.begins_with(key + " ="):
			return s.split("=", true, 1)[1].strip_edges()
	return ""

func test_both_scenes_declare_an_environment() -> void:
	## 地图曾经完全没有 WorldEnvironment，这条就是防它再被删掉
	for p in [MAP, ROOM]:
		var src := FileAccess.get_file_as_string(p)
		assert_bool(src.contains('type="WorldEnvironment"')).is_true()
		assert_bool(src.contains('type="Environment"')).is_true()

func test_ambient_is_explicit_colour_not_background_derived() -> void:
	## source = 2 是 AMBIENT_SOURCE_COLOR。默认的 0（BG）会让背景色决定角色打光。
	for p in [MAP, ROOM]:
		assert_str(_val(p, "ambient_light_source")).is_equal("2")

func test_ambient_matches_across_scenes() -> void:
	assert_str(_val(MAP, "ambient_light_color")).is_equal(_val(ROOM, "ambient_light_color"))
	assert_str(_val(MAP, "ambient_light_energy")).is_equal(_val(ROOM, "ambient_light_energy"))
	assert_str(_val(MAP, "ambient_light_energy")).is_not_empty()

func test_ambient_energy_is_a_fill_not_a_wash() -> void:
	## 太低 → 背光面纯黑（地图当时的样子）；太高 → 过曝、失去明暗（换装房当时的样子）
	var e := float(_val(MAP, "ambient_light_energy"))
	assert_bool(e >= 0.2 and e <= 0.6).is_true()

func test_directional_light_energy_matches_across_scenes() -> void:
	assert_str(_val(MAP, "light_energy")).is_equal(_val(ROOM, "light_energy"))

func test_both_scenes_cast_shadows() -> void:
	## 自阴影是形体感的另一半；两个场景的平行光默认都是不投影的
	for p in [MAP, ROOM]:
		assert_str(_val(p, "shadow_enabled")).is_equal("true")

func test_map_background_mode_keeps_transparency() -> void:
	## 地图靠 viewport.transparent_bg 让 Mapbox 从底下透上来。
	## Environment 的 background_mode 必须是 0（CLEAR_COLOR），
	## 用 1（COLOR）会画一层实色盖掉底图，G1/G3 那套透明合成就废了。
	assert_str(_val(MAP, "background_mode")).is_equal("0")

## The translucent Android window needs opaque pixels across the whole viewport.
## The room canvas provides them independently of the live avatar camera and lighting.
func test_dressing_room_has_opaque_backdrop() -> void:
	var room := (load(ROOM) as PackedScene).instantiate()
	auto_free(room)
	var environment := (room.get_node("WorldEnvironment") as WorldEnvironment).environment
	var background := room.get_node("RoomBackground") as CanvasLayer
	var paper := background.get_node("Paper") as ColorRect
	var scenery := background.get_node("Scenery") as TextureRect
	assert_int(environment.background_mode).is_equal(Environment.BG_CANVAS)
	assert_int(background.layer).is_less(0)
	assert_int(background.layer).is_less_equal(environment.background_canvas_max_layer)
	assert_bool(background.follow_viewport_enabled).is_false()
	assert_object(background.get_parent()).is_same(room)
	assert_object(room.get_node("RigAnchor").get_parent()).is_same(room)
	assert_float(paper.color.a).is_equal(1.0)
	assert_float(paper.modulate.a).is_equal(1.0)
	assert_float(paper.self_modulate.a).is_equal(1.0)
	assert_float(paper.anchor_left).is_equal(0.0)
	assert_float(paper.anchor_top).is_equal(0.0)
	assert_float(paper.anchor_right).is_equal(1.0)
	assert_float(paper.anchor_bottom).is_equal(1.0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_float(paper.get_offset(side)).is_equal(0.0)
	assert_object(background.get_child(0)).is_same(paper)
	assert_int(paper.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(scenery.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_object(scenery.texture).is_not_null()
	assert_int(scenery.texture.get_image().detect_alpha()).is_equal(Image.ALPHA_NONE)

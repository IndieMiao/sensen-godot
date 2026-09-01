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

## 换装房必须有实体背板，不能靠清屏色当背景。
## 2026-09-01：真机上从地图进换装房时整屏透到桌面。已排除的两个原因——
## transparent_bg 在地图 _exit_tree 里确实还原了（真机日志 [DR] enter transparent_bg=false），
## DisplayServer.WINDOW_FLAG_TRANSPARENT 关掉也无效（背景像素逐字节不变）。
## 根因在 Activity 级窗口透明（Godot 因 per_pixel_transparency/allowed=true 套的
## translucent 主题），GDScript 管不到。与其跟引擎较劲，不如给场景一个真的背板——
## 这本来也是对的：参考版的换装间是个真实房间，不是一块清屏色。
func test_dressing_room_has_opaque_backdrop() -> void:
	var src := FileAccess.get_file_as_string(ROOM)
	assert_bool(src.contains('name="Backdrop"')).is_true()
	assert_bool(src.contains('type="MeshInstance3D"')).is_true()
	## 无光照（shading_mode = 0）：背板要的是确定的底色，不该跟着平行光变
	assert_bool(src.contains("shading_mode = 0")).is_true()

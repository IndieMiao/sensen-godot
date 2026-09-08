@tool
extends EditorExportPlugin
## Android 导出：把 native/map/android/bin 里的 AAR 交给 Gradle（Godot 插件 v2 靠 AAR 的
## AndroidManifest meta-data 自注册）。AAR 是构建产物不进仓库：先跑 ./gradlew copyAars。
##
## 这份东西原来是「覆盖到 Godot 安卓构建模板」用的（tools/android/overlay），模板一重装就没了，
## 社交包也没人去铺——所以安卓一直没有地图垫底。改成 AAR 后与另外三个插件同一形状。

const AAR_DEBUG := "res://native/map/android/bin/sensen_map-debug.aar"
const AAR_RELEASE := "res://native/map/android/bin/sensen_map-release.aar"

func _get_name() -> String:
	return "SensenMap"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	var aar := AAR_DEBUG if debug else AAR_RELEASE
	if not FileAccess.file_exists(aar):
		push_warning("SensenMap: %s 不存在，Android 包里没有地图垫底（先跑 native/map/android/gradlew copyAars）" % aar)
		return PackedStringArray()
	return PackedStringArray([aar])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	return PackedStringArray(["com.mapbox.maps:android-ndk27:11.30.0"])

## Mapbox 在自家 maven 上，Maven Central 没有。
func _get_android_dependencies_maven_repos(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	return PackedStringArray(["https://api.mapbox.com/downloads/v2/releases/maven"])

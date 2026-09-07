@tool
extends EditorExportPlugin
## Android 导出：把 native/photo_picker/android/bin 里的 AAR 交给 Gradle（Godot 插件 v2 靠 AAR 的
## AndroidManifest meta-data 自注册，不用改模板）。AAR 是构建产物不进仓库：先跑 ./gradlew copyAars。

const AAR_DEBUG := "res://native/photo_picker/android/bin/sensen_photo_picker-debug.aar"
const AAR_RELEASE := "res://native/photo_picker/android/bin/sensen_photo_picker-release.aar"

func _get_name() -> String:
	return "SensenPhotoPicker"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	var aar := AAR_DEBUG if debug else AAR_RELEASE
	if not FileAccess.file_exists(aar):
		push_warning("SensenPhotoPicker: %s 不存在，Android 包里不会有系统选图器（先跑 native/photo_picker/android/gradlew copyAars）" % aar)
		return PackedStringArray()
	return PackedStringArray([aar])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	return PackedStringArray(["androidx.exifinterface:exifinterface:1.3.7"])

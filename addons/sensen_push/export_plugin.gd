@tool
extends EditorExportPlugin
## Android 导出：把 native/push/android/bin 里的 AAR 交给 Gradle（Godot 插件 v2 靠 AAR 的
## AndroidManifest meta-data 自注册）。AAR 是构建产物不进仓库：先跑 ./gradlew copyAars。
##
## 还差应用侧两件事才真能收到推送：模板 app/ 目录里的 google-services.json，
## 与模板 build.gradle 上的 com.google.gms.google-services 插件（SSLAUNCH D1 给到服务账号那批）。

const AAR_DEBUG := "res://native/push/android/bin/sensen_push-debug.aar"
const AAR_RELEASE := "res://native/push/android/bin/sensen_push-release.aar"

func _get_name() -> String:
	return "SensenPush"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	var aar := AAR_DEBUG if debug else AAR_RELEASE
	if not FileAccess.file_exists(aar):
		push_warning("SensenPush: %s 不存在，Android 包里不会有推送（先跑 native/push/android/gradlew copyAars）" % aar)
		return PackedStringArray()
	return PackedStringArray([aar])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	return PackedStringArray(["com.google.firebase:firebase-messaging:24.1.0"])

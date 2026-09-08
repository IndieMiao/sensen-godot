@tool
extends EditorExportPlugin
## Android 导出：把 native/voice/android/bin 里的 AAR 交给 Gradle（Godot 插件 v2 靠 AAR 的
## AndroidManifest meta-data 自注册）。AAR 是构建产物不进仓库：先跑 ./gradlew copyAars。

const AAR_DEBUG := "res://native/voice/android/bin/sensen_voice-debug.aar"
const AAR_RELEASE := "res://native/voice/android/bin/sensen_voice-release.aar"

func _get_name() -> String:
	return "SensenVoice"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	var aar := AAR_DEBUG if debug else AAR_RELEASE
	if not FileAccess.file_exists(aar):
		push_warning("SensenVoice: %s 不存在，Android 包里语音房是只读的（先跑 native/voice/android/gradlew copyAars）" % aar)
		return PackedStringArray()
	return PackedStringArray([aar])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	return PackedStringArray(["io.livekit:livekit-android:2.11.0"])

## LiveKit 依赖 com.github.davidliu:audioswitch，只在 JitPack 上有，Maven Central 没有。
## 不加这一条，APK 的 Gradle 构建会在解析依赖时失败（本地编 AAR 时同理，见 settings.gradle.kts）。
func _get_android_dependencies_maven_repos(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _supports_platform(platform):
		return PackedStringArray()
	return PackedStringArray(["https://jitpack.io"])

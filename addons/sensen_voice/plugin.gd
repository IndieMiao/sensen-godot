@tool
extends EditorPlugin
## 只在导出 Android 时起作用：注册一个 EditorExportPlugin 把推送插件的 AAR 加进 Gradle 构建。

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = preload("res://addons/sensen_voice/export_plugin.gd").new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	if exporter != null:
		remove_export_plugin(exporter)
		exporter = null

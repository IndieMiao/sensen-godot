@tool
extends EditorPlugin
## 只在导出 Android 时起作用：注册一个 EditorExportPlugin 把 Photo Picker 的 AAR 加进 Gradle 构建。

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = preload("res://addons/sensen_photo_picker/export_plugin.gd").new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	if exporter != null:
		remove_export_plugin(exporter)
		exporter = null

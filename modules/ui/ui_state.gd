class_name UiState
extends RefCounted
## 轻量 UI 状态持久化（PRD §3.3：返回时恢复角色选择与列表位置）。
## 地图节点不销毁，同一次运行内选中与滚动天然保留；这里只管冷启动。
## 方法名不叫 load/save：类内不带前缀的 load() 会解析到全局 load()，静默拿错。

const PATH := "user://ui_state.json"

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}

static func write(patch: Dictionary) -> void:
	var cur := read()
	cur.merge(patch, true)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cur))

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

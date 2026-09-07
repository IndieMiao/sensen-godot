extends AppPage
## A6 生命周期探针（调试构建，设置页入口）：记录 Godot 在 iOS / Android 上实际派发的应用级通知，
## 验证 godot #115936（iOS 生命周期通知回归）是否影响 4.7.2——WsClient 的后台断开 / 回前台补拉
## 全靠 APPLICATION_PAUSED / RESUMED。切后台再回来若计数不涨，就要在 iOS 插件层桥 UIApplication 通知。
## 日志同时落盘 user://lifecycle_probe.json，便于用 devicectl 从设备拷回。

const LOG_PATH := "user://lifecycle_probe.json"
const WATCHED := {
	Node.NOTIFICATION_APPLICATION_PAUSED: "APPLICATION_PAUSED",
	Node.NOTIFICATION_APPLICATION_RESUMED: "APPLICATION_RESUMED",
	Node.NOTIFICATION_APPLICATION_FOCUS_IN: "APPLICATION_FOCUS_IN",
	Node.NOTIFICATION_APPLICATION_FOCUS_OUT: "APPLICATION_FOCUS_OUT",
	Node.NOTIFICATION_WM_WINDOW_FOCUS_IN: "WM_WINDOW_FOCUS_IN",
	Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT: "WM_WINDOW_FOCUS_OUT",
	Node.NOTIFICATION_WM_GO_BACK_REQUEST: "WM_GO_BACK_REQUEST",
}

var counts := {}
var entries: Array = []
## 见过的最大软键盘高度（px）。镜像操作时 iOS 不弹软键盘，人手点一次后拉文件即可判定，不用盯屏幕。
var keyboard_max_px := 0
## () -> int；测试注入，默认 DisplayServer.virtual_keyboard_get_height()。
var keyboard_height_provider: Callable
var summary: Label
var log_label: Label
var keyboard_label: Label
var pick_label: Label

func _init() -> void:
	page_title = "Lifecycle probe"
	stacked = true

func _build_body() -> void:
	placeholder(tr("Switch to another app and come back several times. Each PAUSED/RESUMED pair must increase by one."))
	summary = GameUi.label("", 14)
	summary.name = "Summary"
	body.add_child(summary)
	keyboard_label = GameUi.label("", 12, GameUi.MUTED)
	keyboard_label.name = "Keyboard"
	body.add_child(keyboard_label)
	var field := LineEdit.new()
	field.name = "KeyboardField"
	field.placeholder_text = tr("Tap here to test keyboard avoidance")
	field.custom_minimum_size.y = 44
	body.add_child(field)
	log_label = GameUi.label("", 11, GameUi.MUTED)
	log_label.name = "Log"
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(log_label)
	# C3 选图桥的真机验证入口：弹系统选图器，把回来的张数 / 尺寸 / 字节数打在下面。
	pick_label = GameUi.label("", 12, GameUi.MUTED)
	pick_label.name = "PickResult"
	pick_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pick := GameUi.button("", tr("Pick photos"), "PhotoPicker.pick(3)")
	pick.name = "PickPhotos"
	pick.pressed.connect(func(): pick_photos())
	body.add_child(pick)
	body.add_child(pick_label)
	# 进页就把后端打出来：真机截图一眼看出 GDExtension 有没有装进包里。
	pick_label.text = "picker: %s" % ("native" if PhotoPicker.native_available() else ("dialog" if PhotoPicker.dialog_available() else "none"))
	var clear := GameUi.button("x", tr("Clear log"), "reset counters")
	clear.name = "Clear"
	clear.pressed.connect(_clear)
	body.add_child(clear)
	_load()
	_refresh()

func keyboard_height() -> int:
	if keyboard_height_provider.is_valid():
		return int(keyboard_height_provider.call())
	return DisplayServer.virtual_keyboard_get_height()

func _process(_delta: float) -> void:
	var h := keyboard_height()
	if h > keyboard_max_px:
		keyboard_max_px = h
		_save()
	keyboard_label.text = "virtual_keyboard_get_height() = %d px (max %d) | ws: %s" % [
		h, keyboard_max_px,
		str(Net.ws.state) if Net.ws != null else "-"]

func _notification(what: int) -> void:
	if not WATCHED.has(what):
		return
	record(str(WATCHED[what]))

## 记一条（测试直接调用；真机由 _notification 触发）。
func record(name: String) -> void:
	counts[name] = int(counts.get(name, 0)) + 1
	entries.append({"t": Time.get_datetime_string_from_system(false, true), "ticks_ms": Time.get_ticks_msec(), "event": name})
	if entries.size() > 60:
		entries = entries.slice(entries.size() - 60)
	_save()
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	var parts: Array = []
	for n in ["APPLICATION_PAUSED", "APPLICATION_RESUMED", "APPLICATION_FOCUS_OUT", "APPLICATION_FOCUS_IN", "WM_WINDOW_FOCUS_OUT", "WM_WINDOW_FOCUS_IN"]:
		parts.append("%s: %d" % [n.replace("APPLICATION_", "APP_").replace("WM_WINDOW_", "WIN_"), int(counts.get(n, 0))])
	summary.text = "\n".join(parts)
	var lines: Array = []
	for e in entries.slice(maxi(0, entries.size() - 12)):
		lines.append("%s  %s" % [str(e.t).substr(11), e.event])
	log_label.text = "\n".join(lines)

func _save() -> void:
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"counts": counts, "entries": entries, "keyboard_max_px": keyboard_max_px, "os": OS.get_name(), "godot": Engine.get_version_info().string}))

func _load() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LOG_PATH))
	if parsed is Dictionary:
		counts = parsed.get("counts", {})
		entries = parsed.get("entries", [])
		keyboard_max_px = int(parsed.get("keyboard_max_px", 0))

func _clear() -> void:
	counts = {}
	entries = []
	keyboard_max_px = 0
	_save()
	_refresh()


func pick_photos() -> Dictionary:
	pick_label.text = tr("Picking…") if PhotoPicker.available() else tr("No picker on this platform.")
	var r: Dictionary = await PhotoPicker.new().pick(3)
	if not bool(r.get("ok", false)):
		pick_label.text = "pick failed: %s" % str(r.get("code", ""))
		return r
	var lines: Array = []
	for it in r.get("items", []):
		lines.append("%dx%d %d KB %s" % [int(it.width), int(it.height), int((it.bytes as PackedByteArray).size() / 1024), str(it.path).get_file()])
	pick_label.text = tr("%d picked") % lines.size() + ("\n" + "\n".join(lines) if not lines.is_empty() else "")
	return r

extends Node
## 无真机的 UI 预览宿主：把目标场景挂进来并强制注入手机安全区后渲帧。
##
## 为什么需要它：SafeAreaMargin 走 DisplayServer.get_display_safe_area()，桌面上
## 拿到的是**宿主显示器**的可用区（MacBook 的摄像头缺口），再按窗口/视口比例换算，
## 得到的边距既不对称也远大于真机——本地截图因此和真机对不上，右侧还会被切掉。
## 这里用 SafeAreaMargin 已有的注入式入口 apply_margins() 覆盖成确定值。
##
## 用法：
##   godot --path . --write-movie /tmp/shot.png tools/dev/ui_preview.tscn \
##         --quit-after 120 -- <场景> [notch|flat] [槽位]
## 看最后一帧 /tmp/shot00000119.png。--quit-after 别设太短，异步装配没落地会
## 拍到半成品（换装房挑槽位时要 >=200 帧，见下）。
##
## 参数 2 选安全区形态：
##   notch（默认）= 有刘海/手势条的真机，上 44 下 28 左右 16
##   flat         = 无缺口机型，四边 16（可用宽度最坏情况，用于查抽屉是否撑破）
##
## 参数 3 仅对换装房有效：预览指定槽位的选项列表（hairHat/cloth/shoes/
## messengerBag/glass），用来看部件多的槽位会不会截断文案或撑破格子。
## 等 1.5 秒再切是因为首次装配要等 config_applied 落地。
##
##   godot --path . --write-movie /tmp/s.png tools/dev/ui_preview.tscn \
##         --quit-after 200 -- res://scenes/dressing_room/dressing_room.tscn flat shoes
##
## 参数 4 再指定该槽位的具体部件并穿上，用来核对取景：换最高的发型
## （当前是 hairhat20，1.952m）时角色大小应当**完全不变**，头发向上溢出到顶栏
## 那条带子里但不出画。
##
##   ... -- res://scenes/dressing_room/dressing_room.tscn notch hairHat hairhat20

const DEFAULT_SCENE := "res://scenes/dressing_room/dressing_room.tscn"

## 视口单位下的模拟系统内缩。
const NOTCH_INSETS := Vector4(16.0, 44.0, 16.0, 28.0)
const FLAT_INSETS := Vector4(16.0, 16.0, 16.0, 16.0)

## 换装房首次装配落地所需的等待；movie 模式下时钟是固定 60fps，因此可复现。
const SLOT_SETTLE_S := 1.5
const PARTS_PANEL_PATH := "UI/SafeArea/VBox/Drawer/VBox"

var _insets := NOTCH_INSETS


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var target := args[0] if args.size() > 0 else DEFAULT_SCENE
	if args.size() > 1 and args[1] == "flat":
		_insets = FLAT_INSETS

	var packed := load(target) as PackedScene
	if packed == null:
		push_error("ui_preview: 无法加载场景 %s" % target)
		return
	var inst := packed.instantiate()
	add_child(inst)
	print("ui_preview: %s insets=%s" % [target, _insets])
	if args.size() > 2:
		await _preview_slot(inst, StringName(args[2]), args[3] if args.size() > 3 else "")


## 切到指定槽位，可选再穿上指定部件；目标场景没有部件面板（例如地图）时安静跳过。
func _preview_slot(scene: Node, slot: StringName, part_id: String) -> void:
	await get_tree().create_timer(SLOT_SETTLE_S).timeout
	if not is_instance_valid(scene):
		return
	var panel := scene.get_node_or_null(PARTS_PANEL_PATH)
	if panel == null or not panel.has_method("_show_slot"):
		push_warning("ui_preview: %s 没有部件面板，忽略槽位参数" % scene.name)
		return
	# 第二个参数 = user_initiated：带上它才会触发分区推近，和真机点标签一致。
	panel.call("_show_slot", slot, true)
	if part_id.is_empty():
		await get_tree().create_timer(SLOT_SETTLE_S).timeout
		return
	var rig = scene.get("rig")
	if rig == null:
		return
	rig.equip(slot, part_id)
	await get_tree().create_timer(SLOT_SETTLE_S).timeout


func _process(_delta: float) -> void:
	# 场景内的 SafeAreaMargin 会在 _ready 和 root.size_changed 时自行 refresh()，
	# 每帧覆盖才能保证注入值不被它自己的真实读数盖回去。
	for node in _safe_areas(self):
		node.apply_margins(_synthetic_area(), DisplayServer.window_get_size(),
			get_viewport().get_visible_rect().size)


## 反解 UIMetrics.safe_margins：给定期望的视口单位内缩，构造等价的物理像素安全区。
func _synthetic_area() -> Rect2i:
	var window := DisplayServer.window_get_size()
	var viewport := get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return Rect2i(Vector2i.ZERO, window)
	# s = viewport / window，safe_margins 用 area 的物理像素乘 s 得到视口单位。
	var inv := Vector2(window) / viewport
	var left := roundi(_insets.x * inv.x)
	var top := roundi(_insets.y * inv.y)
	var right := roundi(_insets.z * inv.x)
	var bottom := roundi(_insets.w * inv.y)
	return Rect2i(left, top, maxi(window.x - left - right, 1), maxi(window.y - top - bottom, 1))


func _safe_areas(from: Node) -> Array[SafeAreaMargin]:
	var found: Array[SafeAreaMargin] = []
	for child in from.get_children():
		if child is SafeAreaMargin:
			found.append(child)
		found.append_array(_safe_areas(child))
	return found

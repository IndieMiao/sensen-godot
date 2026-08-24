class_name DressingCamera
extends Camera3D
## 换装房间相机：窄视角平透视 + 按角色包围盒自适应取景，
## 保证全身（含高帽、宽挂件）完整落在抽屉之上的可用区内。

const FOV_DEG := 35.0    # 现状 75° 默认值透视过强（头大脚小）
const PADDING := 1.12    # 包围盒四周留白系数

var drawer_height: float = 312.0
var safe_margin_top: float = 16.0
var safe_margin_bottom: float = 16.0

func _ready() -> void:
	fov = FOV_DEG
	rotation = Vector3.ZERO

## 合并 root 子树内所有可见 GeometryInstance3D（真实渲染几何：网格/粒子/文字等）的
## 全局包围盒。用 GeometryInstance3D 而非 VisualInstance3D 是为了排除
## VisibleOnScreenNotifier3D / VisibleOnScreenEnabler3D 这类只继承 VisualInstance3D、
## 但不产生任何渲染像素的节点——RigActivity 会挂一个硬编码剔除框的 Notifier3D 到 rig 下
## （modules/avatar/assembly/rig_activity.gd），若不过滤会把取景撑大到它的 AABB。
## 子树为空或全不可见时返回 size 为 0 的退化 AABB，调用方据此跳过取景。
static func merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for node in _visuals(root):
		var box := node.get_global_transform() * node.get_aabb()
		if found:
			out = out.merge(box)
		else:
			out = box
			found = true
	return out

static func _visuals(node: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var vi := node as GeometryInstance3D
	if vi and vi.is_visible_in_tree():
		result.append(vi)
	for c in node.get_children():
		result.append_array(_visuals(c))
	return result

## 重新取景。viewport_size 由调用方传入而非内部取，便于 headless 测试。
func reframe(subject_root: Node3D, viewport_size: Vector2) -> void:
	var subject := merged_aabb(subject_root)
	if subject.size.y <= 0.0:
		return
	var ratios := UIMetrics.free_ratios(
		viewport_size.y, safe_margin_top, safe_margin_bottom, drawer_height)
	if ratios.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var dist := UIMetrics.frame_distance(
		subject, viewport_size.x / viewport_size.y, ratios.x, FOV_DEG, PADDING)
	if dist <= 0.0:
		return
	var center := subject.position + subject.size * 0.5
	fov = FOV_DEG
	rotation = Vector3.ZERO
	position = Vector3(center.x, center.y, center.z + dist)
	v_offset = UIMetrics.frame_v_offset(subject, ratios.x, ratios.y, PADDING)

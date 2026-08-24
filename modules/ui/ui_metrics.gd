class_name UIMetrics
extends RefCounted
## 移动端 UI 布局纯计算：安全区换算与相机取景数学。
## 不触碰节点与 DisplayServer，全部逻辑可 headless 单测。

## 系统安全区（物理像素）换算为视口单位的四边内缩 (left, top, right, bottom)。
## min_margin 是兜底：无刘海机型或桌面上系统上报整屏，此时仍需舒适边距。
static func safe_margins(
		safe_area: Rect2i,
		window_size: Vector2i,
		viewport_size: Vector2,
		min_margin: float) -> Vector4:
	if window_size.x <= 0 or window_size.y <= 0:
		return Vector4(min_margin, min_margin, min_margin, min_margin)
	var area := safe_area
	if area.size.x <= 0 or area.size.y <= 0:
		area = Rect2i(Vector2i.ZERO, window_size)  # 未上报 → 视作无内缩
	var s := viewport_size / Vector2(window_size)
	return Vector4(
		maxf(float(area.position.x) * s.x, min_margin),
		maxf(float(area.position.y) * s.y, min_margin),
		maxf(float(window_size.x - area.end.x) * s.x, min_margin),
		maxf(float(window_size.y - area.end.y) * s.y, min_margin))

## 角色可用区（安全区上边 → 抽屉顶边）在视口高中的占比与中心位置占比。
## 返回 (ratio, center_ratio)；无可用区返回 Vector2.ZERO，调用方据此跳过取景。
static func free_ratios(
		viewport_h: float,
		margin_top: float,
		margin_bottom: float,
		drawer_h: float) -> Vector2:
	if viewport_h <= 0.0:
		return Vector2.ZERO
	var free_top := margin_top
	var free_h := viewport_h - margin_bottom - drawer_h - free_top
	if free_h <= 0.0:
		return Vector2.ZERO
	return Vector2(free_h / viewport_h, (free_top + free_h * 0.5) / viewport_h)

## 让 subject 完整落入占比 ratio 的可用区所需的相机距离。
## fov_deg 为竖直视角（Godot 默认 keep_aspect=KEEP_HEIGHT）；aspect 为视口 宽/高。
## 取高度约束与宽度约束的较大值，宽挂件才不会被左右裁切。
static func frame_distance(
		subject: AABB,
		aspect: float,
		ratio: float,
		fov_deg: float,
		padding: float) -> float:
	if ratio <= 0.0 or aspect <= 0.0 or subject.size.y <= 0.0:
		return 0.0
	var half_tan := tan(deg_to_rad(fov_deg) * 0.5)
	if half_tan <= 0.0:
		return 0.0
	var dist_h := (subject.size.y * padding / ratio) * 0.5 / half_tan
	var dist_w := subject.size.x * padding * 0.5 / (half_tan * aspect)
	return maxf(dist_h, dist_w)

## 把 subject 中心从画面 50% 移到 center_ratio 所需的 Camera3D.v_offset。
## 注意 Godot 的 v_offset 是沿相机局部 Y 平移相机本身（见 Camera3D.get_camera_transform），
## 不是平移视锥；因此负值使被摄体在画面中上移，且不产生俯仰造成的梯形畸变。
static func frame_v_offset(
		subject: AABB,
		ratio: float,
		center_ratio: float,
		padding: float) -> float:
	if ratio <= 0.0 or subject.size.y <= 0.0:
		return 0.0
	return -(subject.size.y * padding / ratio) * (0.5 - center_ratio)

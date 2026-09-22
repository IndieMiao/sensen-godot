class_name LabourBrush
extends RefCounted
## 网格刷子：把一条屏幕拖拽轨迹变成**有序、去重**的格列表。
##
## 纯函数（投影方式由调用方以 Callable 注入），因为真正难对的是几何而不是输入管线：
## 单测能直接喂一串屏幕点，不必造相机、场景树和触摸事件。

## 相邻两个采样点之间最多补多少格。手指抬起再落下、或者投影掠过地平线时，
## 前后两点可能相隔半张地图——那不是一笔划过，不该凭空刷出一长条。
const MAX_BRIDGE := 32

## 轨迹点 → 格列表。`project.call(Vector2) -> Variant`：返回 Vector2i 命中格，
## 或 null 表示这一点没打到地面（射线与地平面平行/朝天）。
##
## 去重规则是「压掉**连续**重复」而不是「整条去重」：来回描同一格应当只算一次，
## 但 A→B→A 这种画回头路，第二次经过 A 仍是玩家的真实意图。
##
## 相邻采样点之间要**补格**：输入事件是离散的，手指划快一点前后两点就能差出好几格，
## 只记录命中点会在刷过的带子上留下窟窿（真机实测 0.5m 格下一划三格里漏一格）。
## 屏幕上的直线段反投影到地平面仍是直线，所以按格坐标线性插值就是手指真实走过的格。
static func trace(points: PackedVector2Array, project: Callable) -> Array:
	var out: Array = []
	for p in points:
		var hit = project.call(p)
		if hit == null:
			continue
		var cell: Vector2i = hit
		if out.is_empty():
			out.append(cell)
			continue
		if out[-1] == cell:
			continue
		for mid in _bridge(out[-1], cell):
			if out[-1] != mid:
				out.append(mid)
		out.append(cell)
	return out

## from 与 to 之间的中间格（不含两端）。相邻或同格时没有空档，返回空。
static func _bridge(from: Vector2i, to: Vector2i) -> Array:
	var delta := to - from
	var steps := maxi(absi(delta.x), absi(delta.y))
	if steps <= 1 or steps > MAX_BRIDGE:
		return []
	var out: Array = []
	for i in range(1, steps):
		var t := float(i) / float(steps)
		out.append(Vector2i(roundi(from.x + delta.x * t), roundi(from.y + delta.y * t)))
	return out

## 只保留地面属性允许开垦的格；顺序不变、去重。
static func filter_actionable(cells: Array, bp: FarmBlueprint) -> Array:
	var out: Array = []
	var seen := {}
	for c in cells:
		var cell: Vector2i = c
		if seen.has(cell) or not bp.mask_has("cultivable", cell):
			continue
		seen[cell] = true
		out.append(cell)
	return out

## 行级工具：把选中的格沿四邻加粗一圈。过去是「扩到整条田畦」，自由格子下没有畦了，
## 加粗笔刷是同一个意图的自然表达——少划几下，不改产量也不缩短时长。
static func thicken(cells: Array, bp: FarmBlueprint) -> Array:
	var out: Array = []
	var seen := {}
	for c in cells:
		for delta in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = (c as Vector2i) + delta
			if seen.has(cell) or not bp.mask_has("cultivable", cell):
				continue
			seen[cell] = true
			out.append(cell)
	return out

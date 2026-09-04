class_name LabourBrush
extends RefCounted
## 网格刷子：把一条屏幕拖拽轨迹变成**有序、去重**的格列表。
##
## 纯函数（投影方式由调用方以 Callable 注入），因为真正难对的是几何而不是输入管线：
## 单测能直接喂一串屏幕点，不必造相机、场景树和触摸事件。

## 轨迹点 → 格列表。`project.call(Vector2) -> Variant`：返回 Vector2i 命中格，
## 或 null 表示这一点没打到地面（射线与地平面平行/朝天）。
##
## 去重规则是「压掉**连续**重复」而不是「整条去重」：来回描同一格应当只算一次，
## 但 A→B→A 这种画回头路，第二次经过 A 仍是玩家的真实意图。
static func trace(points: PackedVector2Array, project: Callable) -> Array:
	var out: Array = []
	for p in points:
		var hit = project.call(p)
		if hit == null:
			continue
		var cell: Vector2i = hit
		if out.is_empty() or out[-1] != cell:
			out.append(cell)
	return out

## 只保留可耕作、且当前解锁的格；顺序不变。
static func filter_actionable(cells: Array, bp: FarmBlueprint, beds_unlocked: int) -> Array:
	var reserved := {}
	for c in bp.reserved_bed().get("cells", []):
		reserved[c] = true
	var out: Array = []
	var seen := {}
	for c in cells:
		var cell: Vector2i = c
		if seen.has(cell) or not bp.mask_has("cultivable", cell):
			continue
		if reserved.has(cell) and beds_unlocked != 4:
			continue
		seen[cell] = true
		out.append(cell)
	return out

## 行级工具：把命中格扩到它所在的整畦。**仍逐格播放**，不改产量也不缩短时长
## （PRD §6.3 L408）——row_tool 只是一次手势少划两下，不是效率道具。
static func expand_rows(cells: Array, bp: FarmBlueprint) -> Array:
	var beds: Array = bp.beds().duplicate()
	var rb := bp.reserved_bed()
	if not rb.is_empty():
		beds.append(rb)
	var out: Array = []
	var seen := {}
	for c in cells:
		var cell: Vector2i = c
		var row: Array = [cell]
		for bed in beds:
			if (bed.get("cells", []) as Array).has(cell):
				row = bed.cells
				break
		for r in row:
			if not seen.has(r):
				seen[r] = true
				out.append(r)
	return out

## 屏幕点 → 地面格的投影器，交给 trace() 用。
static func ground_projector(cam: Camera3D, bp: FarmBlueprint, world_scale := 1.0) -> Callable:
	return func(p: Vector2):
		var hit = Plane(Vector3.UP, 0.0).intersects_ray(
			cam.project_ray_origin(p), cam.project_ray_normal(p))
		if hit == null:
			return null
		return bp.world_to_cell(hit as Vector3, world_scale)

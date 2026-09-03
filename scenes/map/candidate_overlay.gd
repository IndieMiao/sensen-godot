class_name CandidateOverlay
extends Node3D
## 三个候选街区的高亮：蓝图 overlay_wgs84 → 浮动原点本地米制 → 贴地 mesh。
## 每个候选一个子 Node3D（position = 候选中心的本地坐标），mesh 顶点相对候选中心，
## 重锚只需改子节点 position。

const Y_LIFT := 0.3 # 贴地抬高，避开与 y=0 地面/角色底面的 z-fighting
const ALPHA_IDLE := 0.16
const ALPHA_SELECTED := 0.42
const PATH_WIDTH_M := 4.0

var selected_id := ""
var _items: Dictionary = {} # id -> {node, mats: Array[StandardMaterial3D], center: Vector2(lat,lng)}
var _anchor_lat := 0.0
var _anchor_lng := 0.0

## 命名为 geo_to_local 而非 to_local：Node3D 已内置实例方法 to_local(Vector3)->Vector3，
## 同名 static 会与父类签名冲突（GDScript 硬编译错误，非可抑制的警告）。
static func geo_to_local(lat: float, lng: float, anchor_lat: float, anchor_lng: float) -> Vector2:
	var w := MapGeoMath.geo_to_world(lat, lng, anchor_lat, anchor_lng)
	return Vector2(w.x, w.z)

static func _material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(DesignTokens.ACCENT, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func block_mesh(pts: PackedVector2Array) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(pts[i].x, Y_LIFT, pts[i].y))
	return st.commit()

static func path_mesh(pts: PackedVector2Array, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := (b - a).orthogonal().normalized() * (width * 0.5)
		var quad := [a + n, b + n, b - n, a + n, b - n, a - n]
		for q in quad:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, Y_LIFT, q.y))
	return st.commit()

func set_candidates(bps: Array, anchor_lat: float, anchor_lng: float) -> void:
	for c in get_children():
		c.queue_free()
	_items.clear()
	selected_id = ""
	_anchor_lat = anchor_lat
	_anchor_lng = anchor_lng
	for bp in bps:
		var center: Vector2 = bp.overlay.center
		var node := Node3D.new()
		node.name = bp.layout_patch_id
		add_child(node)
		var mats: Array[StandardMaterial3D] = []
		for pg in bp.overlay.blocks:
			var local := PackedVector2Array()
			for ll in pg:
				local.append(geo_to_local(ll.x, ll.y, center.x, center.y))
			if local.size() > 1 and local[0].is_equal_approx(local[local.size() - 1]):
				local.remove_at(local.size() - 1)
			mats.append(_add_mesh(node, block_mesh(local), ALPHA_IDLE))
		for pl in bp.overlay.paths:
			var local := PackedVector2Array()
			for ll in pl:
				local.append(geo_to_local(ll.x, ll.y, center.x, center.y))
			mats.append(_add_mesh(node, path_mesh(local, PATH_WIDTH_M), ALPHA_IDLE))
		_items[bp.layout_patch_id] = {"node": node, "mats": mats, "center": center}
	reanchor(anchor_lat, anchor_lng)

func _add_mesh(parent: Node3D, mesh: ArrayMesh, alpha: float) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(alpha)
	parent.add_child(mi)
	return mi.material_override

func select(id: String) -> void:
	selected_id = id
	for key in _items:
		var alpha := ALPHA_SELECTED if key == id else ALPHA_IDLE
		for m in _items[key].mats:
			m.albedo_color = Color(DesignTokens.ACCENT, alpha)

func reanchor(anchor_lat: float, anchor_lng: float) -> void:
	_anchor_lat = anchor_lat
	_anchor_lng = anchor_lng
	for key in _items:
		var c: Vector2 = _items[key].center
		var l := geo_to_local(c.x, c.y, anchor_lat, anchor_lng)
		(_items[key].node as Node3D).position = Vector3(l.x, 0.0, l.y)

func candidate_ids() -> PackedStringArray:
	return PackedStringArray(_items.keys())

func candidate_center(id: String) -> Vector2:
	return _items.get(id, {}).get("center", Vector2.ZERO)

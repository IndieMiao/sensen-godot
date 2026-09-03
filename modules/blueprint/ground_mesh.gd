class_name BlueprintGroundMesh
extends RefCounted
## masks → 平地 ArrayMesh，每格两个三角形，顶点色区分路/区块/田畦/水。灰盒口径，G4 换正式地表。

const COLOR_GROUND := Color(0.87, 0.89, 0.84)
const COLOR_PATH := Color(0.91, 0.84, 0.67)
const COLOR_BLOCK := Color(0.63, 0.80, 0.63)
const COLOR_BED := Color(0.59, 0.41, 0.27)
const COLOR_WATER := Color(0.55, 0.72, 0.86)

static func cell_color(bp: FarmBlueprint, c: Vector2i) -> Color:
	if bp.mask_has("cultivable", c):
		return COLOR_BED
	if not bp.is_walkable(c):
		return COLOR_WATER
	if bp.mask_has("buildable", c):
		return COLOR_BLOCK
	return COLOR_PATH

static func build(bp: FarmBlueprint, scale := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := bp.cell_m * scale
	for j in bp.grid.y:
		for i in bp.grid.x:
			var col := cell_color(bp, Vector2i(i, j))
			var x0 := i * s
			var x1 := (i + 1) * s
			var z0 := -j * s
			var z1 := -(j + 1) * s
			var quad := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1),
				Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
			for v in quad:
				st.set_normal(Vector3.UP)
				st.set_color(col)
				st.add_vertex(v)
	return st.commit()

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	return m

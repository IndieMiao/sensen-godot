extends SceneTree
const Fringe = preload("res://modules/dynamic_farm/core_grass_edge.gd")
const Ground = preload("res://modules/dynamic_farm/farm_mesh.gd")
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

# Cover the point even when triangulation puts it exactly on a shared edge.
func contains_center(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var p := Vector3(0.5, 0, -0.5)
	return maxf((b-a).cross(p-a).y, maxf((c-b).cross(p-b).y, (a-c).cross(p-c).y)) <= 0.000001

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Include corner, one-cell-wide strip, and isolated core-cell cases. The
	# two opaque materials must exactly tile the square without cropping it.
	var noise := Fringe.noise_for("c0011234")
	var corners := [Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT + Vector3.FORWARD, Vector3.FORWARD]
	for sides in range(1, 16):
		for sample in 12:
			var soil := SurfaceTool.new()
			var grass := SurfaceTool.new()
			soil.begin(Mesh.PRIMITIVE_TRIANGLES)
			grass.begin(Mesh.PRIMITIVE_TRIANGLES)
			Fringe.emit(soil, grass, corners, Vector2i(31 + sample, 9), sides, 1.0, noise)
			var total := 0.0
			var soil_contains_center := false
			for tool: SurfaceTool in [soil, grass]:
				var vv: PackedVector3Array = tool.commit_to_arrays()[Mesh.ARRAY_VERTEX]
				for j in range(0, vv.size(), 3):
					var v := vv[j]
					total -= (vv[j+1] - v).cross(vv[j+2] - v).y * 0.5
					if tool == soil and contains_center(v, vv[j+1], vv[j+2]):
						soil_contains_center = true
			check(absf(total - 1.0) < 0.00001, "seam mesh lost or doubled projected area (mask %d)" % sides)
			check(soil_contains_center, "soil centre lost (mask %d)" % sides)
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/dynamic_farm/499-art-recipe.json"))
	for path: String in OS.get_cmdline_user_args():
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var data := Data.decode(raw)
		check(data.ok, "schema4 decode " + path)
		if not data.ok: continue
		var before := data.duplicate(true)
		var walk := Walk.new(data)
		var ground := Ground.build(data, walk, recipe)
		var repeat := Ground.build(data, walk, recipe)
		var same := ground.get_child_count() == repeat.get_child_count()
		for batch in ground.get_children():
			var other := repeat.get_node_or_null(NodePath(str(batch.name))) as MeshInstance3D
			if not other or batch.mesh.surface_get_arrays(0) != other.mesh.surface_get_arrays(0): same = false
		var source_core := 0
		for run in raw.zones.core.runs: source_core += int(run[2])
		var plantable := 0
		var edges := 0
		var picks := 0
		for cell: Vector2i in data.by_cell:
			if Data.permits(data, cell, "plant"): plantable += 1
			if data.by_cell[cell].zone != "core": continue
			var is_edge := false
			for dir: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if data.by_cell.get(cell+dir, {}).get("kind") != "grass": continue
				is_edge = true
				# Pick just *inside* the old, full cell, in its grass-painted fringe.
				var p := walk.point(cell) + Vector3(dir.x, 0, -dir.y) * (0.49 * walk.cell_m)
				var hit := walk.cell_at(p)
				check(hit == cell and Data.permits(data, hit, "plant"), "painted region lost its cell")
				picks += 1
			if is_edge: edges += 1
		check(plantable == source_core and edges > 0 and data == before, "source counts/permissions changed or empty edge case")
		check(same, "repeat build changed mesh arrays")
		print("CORE_FRINGE parcel=%s source=%d plantable=%d edge_cells=%d edge_picks=%d repeat_mesh=%s" % [data.block_id, source_core, plantable, edges, picks, same])
		ground.free()
		repeat.free()
	print("DYNAMIC_CORE_GRASS_EDGE failures=", failures)
	quit(1 if failures else 0)

extends SceneTree
const Spill = preload("res://modules/dynamic_farm/core_grass_edge.gd")
const Ground = preload("res://modules/dynamic_farm/farm_mesh.gd")
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Edges = preload("res://modules/dynamic_farm/farm_edges.gd")
const UNIT := [Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT + Vector3.FORWARD, Vector3.FORWARD]
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

# Unit-square coordinates of a committed triangle list (corners at grid 0..1).
func triangles(tool: SurfaceTool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var arrays := tool.commit_to_arrays()
	# A failed triangulation leaves the tool empty; report it as zero area.
	if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null: return out
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]: out.append(Vector2(v.x, -v.z))
	return out

func area(tris: PackedVector2Array) -> float:
	var total := 0.0
	for j in range(0, tris.size(), 3):
		# Front faces are clockwise from above, i.e. negative in (x, -z).
		total -= (tris[j+1] - tris[j]).cross(tris[j+2] - tris[j]) * 0.5
	return total

func covers(tris: PackedVector2Array, p: Vector2) -> bool:
	for j in range(0, tris.size(), 3):
		var a := tris[j]
		var b := tris[j+1]
		var c := tris[j+2]
		if maxf((b-a).cross(p-a), maxf((c-b).cross(p-b), (a-c).cross(p-c))) <= 0.000001: return true
	return false

# Emit one spill cell on a unit square; returns its soil area.
func tile(at: Vector2i, masks: Dictionary, noise: FastNoiseLite) -> float:
	var sides: int = masks[at]
	var soil := SurfaceTool.new()
	var grass := SurfaceTool.new()
	soil.begin(Mesh.PRIMITIVE_TRIANGLES)
	grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	Spill.emit(soil, grass, UNIT, at, masks, noise)
	var dirt := triangles(soil)
	var lawn := triangles(grass)
	check(absf(area(dirt) + area(lawn) - 1.0) < 0.00001, "seam mesh lost or doubled projected area (mask %d)" % sides)
	check(area(dirt) > 0.0 and area(lawn) > 0.0, "a material vanished (mask %d)" % sides)
	check(covers(lawn, Vector2(0.5, 0.5)) and not covers(dirt, Vector2(0.5, 0.5)), "grass centre lost (mask %d)" % sides)
	for p in dirt:
		var reach := INF
		for side in 4:
			if sides & (1 << side):
				reach = minf(reach, [p.y, 1.0 - p.x, 1.0 - p.y, p.x][side])
		check(reach <= Spill.MAX_SPILL + 0.000001, "soil spilled too far (mask %d)" % sides)
	return area(dirt)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Every side combination, isolated or continuing along its run: the two
	# opaque materials tile the square exactly, the grass keeps the centre, and
	# soil stays within MAX_SPILL of a core side.
	var noise := Spill.noise_for("c0011234")
	var spilled := 0.0
	for sides in range(1, 16):
		for sample in 12:
			var at := Vector2i(31 + sample, 9 + sample % 3)
			var masks := {at: sides}
			if sample % 2:
				for side in 4:
					if not sides & (1 << side): continue
					var axis := Vector2i(1, 0) if side % 2 == 0 else Vector2i(0, 1)
					for step: Vector2i in [axis, -axis]:
						# The run can only continue where that neighbour is not core.
						if sides & (1 << Edges.NEIGHBORS.find(step)): continue
						masks[at + step] = int(masks.get(at + step, 0)) | (1 << side)
			spilled += tile(at, masks, noise)
	check(spilled / 180.0 > 0.08, "spill too thin to read")
	# A straight run: neighbours agree on the shared depth; a closed end meets
	# the corner, so no lump is cut straight at the end of a run.
	var row := {}
	for x in range(10, 16): row[Vector2i(x, 4)] = 1
	for x in range(10, 15):
		var left := Spill.spill(Vector2i(x, 4), 0, 1.0, row, noise)
		var right := Spill.spill(Vector2i(x + 1, 4), 0, 0.0, row, noise)
		check(left == right and left > 0.0, "run depth not continuous at x=%d" % (x + 1))
	check(Spill.spill(Vector2i(10, 4), 0, 0.0, row, noise) == 0.0 and Spill.spill(Vector2i(15, 4), 0, 1.0, row, noise) == 0.0, "closed run end left a cut")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/dynamic_farm/499-art-recipe.json"))
	var parcels := 0
	for path: String in OS.get_cmdline_user_args():
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var data := Data.decode(raw)
		check(data.ok, "schema4 decode " + path)
		if not data.ok: continue
		parcels += 1
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
		var lumps := 0
		var masks := {}
		var parcel_noise := Spill.noise_for(data.seed_hex)
		for cell: Vector2i in data.by_cell:
			if Data.permits(data, cell, "plant"): plantable += 1
			var sides := Spill.mask(data.by_cell, cell)
			if sides: masks[cell] = sides
		for cell: Vector2i in masks:
			tile(cell, masks, parcel_noise)
			for side in 4:
				if not masks[cell] & (1 << side): continue
				edges += 1
				var core: Vector2i = cell + Edges.NEIGHBORS[side]
				var deepest := 0.0
				for j in 9: deepest = maxf(deepest, Spill.spill(cell, side, j / 8.0, masks, parcel_noise))
				if deepest >= 0.25: lumps += 1
				# Just inside the core edge stays the plantable core cell; just
				# outside, where the lumps are painted, stays the extension cell.
				var out := -Edges.normal(side)
				var inside_hit := walk.cell_at(walk.point(core) + out * (0.49 * walk.cell_m))
				var outside_hit := walk.cell_at(walk.point(core) + out * (0.51 * walk.cell_m))
				check(inside_hit == core and Data.permits(data, core, "plant"), "core edge cell lost")
				check(outside_hit == cell and not Data.permits(data, cell, "plant"), "painted lump became plantable")
				picks += 2
		check(plantable == source_core and edges > 0 and data == before, "source counts/permissions changed or empty edge case")
		check(lumps * 3 > edges, "too few rounded lumps")
		check(same, "repeat build changed mesh arrays")
		print("CORE_SOIL_SPILL parcel=%s source=%d plantable=%d edge_sides=%d lump_sides=%d picks=%d repeat_mesh=%s" % [data.block_id, source_core, plantable, edges, lumps, picks, same])
		ground.free()
		repeat.free()
	if parcels == 0: print("CORE_SOIL_SPILL SKIP real parcels: none passed after --")
	print("DYNAMIC_CORE_GRASS_EDGE parcels=%d failures=%d" % [parcels, failures])
	quit(1 if failures else 0)

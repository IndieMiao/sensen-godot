extends RefCounted
## One opaque painted surface per species; all transforms (including trunk contacts),
## gather IDs and fitted walk profiles still come from the original parcel plan.
const LIBRARY = preload("res://assets/dynamic_farm/fieldkit/parcel_botanicals.glb")
const Art = preload("res://modules/farm/farm_art.gd")
const TYPES := {"wild_pz_tree_20": "Linden", "wild_pz_tree_20_g": "OrchardElm",
	"wild_pz_pine_01": "Spruce", "wild_pz_pine_03": "Fir", "wild_pz_rock_08": "Ledge",
	"wild_pz_rock_13": "Cobble", "wild_pz_softrock_10": "Flint"}
static var _meshes := {}

static func mesh(key: String) -> Mesh:
	if _meshes.is_empty():
		var root := LIBRARY.instantiate()
		for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			_meshes[str(node.name)] = node.mesh
		root.free()
	return _meshes.get(key)

## Small ambient tufts and three flowers grow in little drifts, not evenly spaced
## dots. Noninteractive, no proxies, no per-frame work. Max 240 instances per island.
static func meadow(data: Dictionary, walk: RefCounted) -> Node3D:
	var root := Node3D.new()
	root.name = "MeadowDrifts"
	var batches := {"Tuft": [], "Chamomile": [], "Buttercup": [], "Lilac": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed_hex.left(8).hex_to_int() ^ 184
	var pool: Array[Vector2i] = []
	for cell: Dictionary in data.cells:
		if cell.zone == "extension" and cell.surface_id == 1: pool.append(Vector2i(cell.x,cell.y))
	for i in mini(60, ceili(pool.size()/16.0)):
		var anchor := pool[rng.randi_range(0, pool.size()-1)]
		var center: Vector3 = walk.point(anchor)
		var kind: String = ["Chamomile", "Buttercup", "Lilac"][rng.randi_range(0, 2)]
		for j in 4:
			var p := center + Vector3(rng.randf_range(-0.7,0.7), 0.012, rng.randf_range(-0.55,0.55))
			var at: Vector2i = walk.cell_at(p)
			var cell: Dictionary = data.by_cell.get(at,{})
			if cell.get("zone") != "extension" or cell.get("surface_id") != 1 or data.protected.has(at): continue
			var scale_factor := rng.randf_range(0.72,1.32)
			batches["Tuft" if j < 3 else kind].append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_factor),p))
	for key: String in batches:
		if batches[key].is_empty(): continue
		var node := MultiMeshInstance3D.new()
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = mesh(key)
		node.multimesh.instance_count = batches[key].size()
		for j in batches[key].size(): node.multimesh.set_instance_transform(j,batches[key][j])
		node.material_override = Art.material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
	return root

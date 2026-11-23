extends RefCounted
## Warm recolouring of the 13 existing models (C-21). Only vertex colours change, at
## runtime, from the recipe's `prop_palette`; geometry, pivots, collision profiles,
## layouts and the shared FarmArt material stay as they are. No asset is authored.
const Art = preload("res://modules/farm/farm_art.gd")
const MATCH := 0.02 # per-channel sRGB tolerance for a vertex colour to hit a palette key
static var _meshes := {}

## Variant of one placed instance, hashed from its asset and position: the same layout
## gets the same colours on every opening and the placement streams are not consumed.
static func pick(palette: Dictionary, asset: String, origin: Vector3) -> int:
	var variants: Array = palette.get("assets", {}).get(asset, [])
	if variants.size() < 2: return variants.size() - 1
	var key := "%s|%d|%d" % [asset, roundi(origin.x * 100.0), roundi(origin.z * 100.0)]
	var total := 0.0
	for variant: Dictionary in variants: total += float(variant.weight)
	var at := float(key.sha256_text().substr(0, 8).hex_to_int()) / 4294967296.0 * total
	for i in variants.size():
		at -= float(variants[i].weight)
		if at < 0.0: return i
	return variants.size() - 1

## The model with variant `index`'s colours; -1 keeps the original mesh.
static func mesh(palette: Dictionary, asset: String, index: int) -> Mesh:
	var source := Art.mesh_for(asset)
	if index < 0 or source == null: return source
	var key := "%s|%s|%d" % [palette.version, asset, index]
	if _meshes.has(key): return _meshes[key]
	var pairs: Array = []
	var colours_by_key: Dictionary = palette.assets[asset][index].map
	for from: String in colours_by_key:
		pairs.append([Color(from), Color(colours_by_key[from]).srgb_to_linear()])
	var arrays := source.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colours.size():
		var seen := colours[i].linear_to_srgb()
		for pair: Array in pairs:
			var from: Color = pair[0]
			if absf(seen.r - from.r) <= MATCH and absf(seen.g - from.g) <= MATCH and absf(seen.b - from.b) <= MATCH:
				var to: Color = pair[1]
				colours[i] = Color(to.r, to.g, to.b, colours[i].a)
				break
	arrays[Mesh.ARRAY_COLOR] = colours
	var recoloured := ArrayMesh.new()
	# Keep the import's attribute compression, so positions and normals round-trip exactly.
	recoloured.add_surface_from_arrays(source.surface_get_primitive_type(0), arrays, [], {},
		source.surface_get_format(0) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	_meshes[key] = recoloured
	return recoloured

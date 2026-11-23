extends SceneTree
## Decodes a generated dataset with the client's own code: client-manifest.json through
## map/geo_map_config.gd, every index feature and every parcel-tile feature through
## map/parcel_metadata.gd and every farm through farm_data.gd.
## Run through check_client_decode.sh, which builds a throwaway project around the script and
## decodes the tiles first (cli check-tiles --properties), since GDScript has no MVT decoder.
## Arguments after `--`: <dataset dir> <label> [<tile properties json>]. Exit code 0 only if
## every farm and every parcel decodes.

## ParcelPayload.publicProperties (tools/android/overlay/ParcelPayload.kt): the only feature
## properties the native map hands to GDScript after a tap.
const PUBLIC_KEYS := ["block_id", "parcel_id", "selection_unit", "name", "address", "address_count", "center", "center_lon", "center_lat", "bbox", "cell_count", "core_cell_count", "extension_cell_count", "total_cell_count", "farm_path", "source_area_m2", "inset_area_m2", "building_count"]

static func public_properties(raw: Dictionary) -> Dictionary:
	var out := {}
	for key in PUBLIC_KEYS:
		if raw.has(key): out[key] = raw[key]
	if not out.has("center") and raw.get("center_lon") is float and raw.get("center_lat") is float:
		out["center"] = [raw.center_lon, raw.center_lat]
	return out

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var label: String = args[1]
	var FarmData = load("res://modules/dynamic_farm/farm_data.gd")
	var ParcelMetadata = load("res://modules/dynamic_farm/map/parcel_metadata.gd")
	var MapConfig = load("res://modules/dynamic_farm/map/geo_map_config.gd")
	var index = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("index.geojson")))
	var failures := 0
	var errors := {}
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("client-manifest.json")))
	var map_config: Dictionary = MapConfig.build(manifest, "https://dataset.invalid/r5")
	if map_config.is_empty():
		failures += 1
		errors["client manifest rejected"] = 1
	var tiles := "not checked"
	if args.size() > 2:
		# Parcel tiles: the vector source the map config points at, and every tile feature's
		# properties through the same path a tapped parcel takes.
		if map_config.get("source_type") != "vector" or map_config.get("parcel_source_layer") != "parcels" or not str(map_config.get("parcel_url", "")).ends_with("/tilejson.json"):
			failures += 1
			errors["map config is not the parcel tile source"] = 1
		var decoded_tiles = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
		var ids := {}
		for raw in decoded_tiles:
			var meta: Dictionary = ParcelMetadata.decode(public_properties(raw))
			if meta.is_empty():
				failures += 1
				errors["tile parcel metadata rejected"] = int(errors.get("tile parcel metadata rejected", 0)) + 1
				continue
			ids[meta.block_id] = true
			if FarmData.decode(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(meta.farm_path)))).get("ok") != true:
				failures += 1
				errors["tile farm_path does not decode"] = int(errors.get("tile farm_path does not decode", 0)) + 1
		for feature in index.features:
			if not ids.has(feature.properties.block_id):
				failures += 1
				errors["parcel missing from tiles"] = int(errors.get("parcel missing from tiles", 0)) + 1
		tiles = "%d parcels" % decoded_tiles.size()
	for feature in index.features:
		if ParcelMetadata.decode(feature.properties).is_empty():
			failures += 1
			errors["parcel metadata rejected"] = int(errors.get("parcel metadata rejected", 0)) + 1
		var path: String = dir.path_join(feature.properties.farm_path)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		var decoded: Dictionary = FarmData.decode(data)
		if not decoded.ok:
			failures += 1
			errors[decoded.error] = int(errors.get(decoded.error, 0)) + 1
		elif decoded.counts.core != int(feature.properties.core_cell_count) or decoded.cells.size() != int(feature.properties.total_cell_count):
			failures += 1
			errors["count mismatch"] = int(errors.get("count mismatch", 0)) + 1
	print("CLIENT_DECODE %s farms=%d tiles=%s failures=%d errors=%s map=%s" % [label, index.features.size(), tiles, failures, JSON.stringify(errors), JSON.stringify(map_config)])
	quit(0 if failures == 0 else 1)

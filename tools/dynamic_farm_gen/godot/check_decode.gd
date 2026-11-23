extends SceneTree
## Decodes a generated dataset with the client's own code: client-manifest.json through
## map/geo_map_config.gd, every index feature through map/parcel_metadata.gd and every farm
## through farm_data.gd.
## Run through check_client_decode.sh, which builds a throwaway project around the script.
## Arguments after `--`: <dataset dir> <label>. Exit code 0 only if every farm decodes.

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
	print("CLIENT_DECODE %s farms=%d failures=%d errors=%s map=%s" % [label, index.features.size(), failures, JSON.stringify(errors), JSON.stringify(map_config)])
	quit(0 if failures == 0 else 1)

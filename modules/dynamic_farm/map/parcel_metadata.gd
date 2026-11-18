extends RefCounted
const Contract:=preload("res://modules/dynamic_farm/map/geo_contract.gd")
const Geo:=preload("res://modules/dynamic_farm/map/geo_math.gd")
static func decode(raw:Variant) -> Dictionary:
	if not raw is Dictionary or not Contract.parcel_identity(raw) or not raw.get("name") is String:return {}
	raw=raw.duplicate(true)
	# Native queried-feature properties may serialize array-valued GeoJSON properties as JSON strings.
	for key in ["center","bbox"]:
		if raw.get(key) is String:
			var parser:=JSON.new()
			if parser.parse(raw[key])!=OK:return {}
			raw[key]=parser.data
	if raw.get("selection_unit",Contract.UNIT)!=Contract.UNIT:return {}
	if raw.get("farm_path")!=Contract.farm_path(raw.block_id).trim_prefix("/"):return {}
	if not raw.has("center") and (raw.get("center_lon") is int or raw.get("center_lon") is float) and (raw.get("center_lat") is int or raw.get("center_lat") is float):
		raw["center"]=[float(raw.center_lon),float(raw.center_lat)]
	if not Geo.valid_point(raw.get("center")):return {}
	if raw.has("bbox") and not Geo.valid_bbox(raw.bbox):return {}
	for key in ["core_cell_count","extension_cell_count","total_cell_count"]:
		if not (raw.get(key) is int or raw.get(key) is float) or not is_finite(float(raw[key])) or float(raw[key])!=floorf(float(raw[key])) or raw[key]<0:return {}
	if raw.core_cell_count<760 or raw.core_cell_count>840 or raw.extension_cell_count<=0 or raw.total_cell_count!=raw.core_cell_count+raw.extension_cell_count or raw.total_cell_count>8192:return {}
	if raw.has("cell_count") and raw.cell_count!=raw.core_cell_count:return {}
	raw["cell_count"]=raw.core_cell_count
	for key in ["source_area_m2","inset_area_m2"]:
		if raw.has(key) and (not (raw[key] is int or raw[key] is float) or not is_finite(float(raw[key])) or float(raw[key])<=0):return {}
	var result:Dictionary={}
	for key in ["block_id","parcel_id","name","address","address_count","center","bbox","cell_count","core_cell_count","extension_cell_count","total_cell_count","farm_path","source_area_m2","inset_area_m2","building_count"]:
		if raw.has(key):result[key]=raw[key]
	return result


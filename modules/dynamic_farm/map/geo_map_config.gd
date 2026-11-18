extends RefCounted
const Api:=preload("res://modules/dynamic_farm/map/geo_api.gd")
const Contract:=preload("res://modules/dynamic_farm/map/geo_contract.gd")
const Geo:=preload("res://modules/dynamic_farm/map/geo_math.gd")
static func _url(base:String,path:Variant) -> String:
	if not path is String or path.is_empty():return ""
	if path.begins_with("https://"):return path if Api.valid_base(path) else ""
	if ".." in path.uri_decode() or "?" in path or "#" in path or "@" in path:return ""
	return base.trim_suffix("/")+"/"+path.trim_prefix("/")
static func build(manifest:Dictionary,base:String,options:Dictionary={}) -> Dictionary:
	if not Api.valid_base(base) or not manifest.get("native_map") is Dictionary:return {}
	var n:Dictionary=manifest.native_map
	var source_type:=str(n.get("type",""))
	if source_type=="mvt":source_type="vector"
	if source_type not in ["vector","geojson"] or n.get("promote_id")!="block_id":return {}
	if manifest.get("dataset_version")==Contract.DATASET and source_type!="vector":return {}
	if not Geo.valid_point(n.get("center")):return {}
	var provider:=str(options.get("building_source",n.get("building_source","mapbox")))
	if provider not in ["mapbox","datasf"]:return {}
	var result:={"source_type":source_type,"promote_id":"block_id","min_zoom":float(n.get("minzoom",16)),"address_min_zoom":float(n.get("address_minzoom",18)),"building_source":provider}
	if not is_finite(result.min_zoom) or not is_finite(result.address_min_zoom) or result.min_zoom<0 or result.address_min_zoom<result.min_zoom or result.address_min_zoom>22:return {}
	var parcel_url:=_url(base,n.get("parcel_url_path","tilejson.json" if source_type=="vector" else "index.geojson"))
	if parcel_url.is_empty():return {}
	result["parcel_url"]=parcel_url
	if source_type=="vector":
		result["parcel_source_layer"]=str(n.get("parcel_source_layer","parcels"))
		result["source_minzoom"]=int(n.get("source_minzoom",15));result["source_maxzoom"]=int(n.get("source_maxzoom",18))
		if result.parcel_source_layer!="parcels" or result.source_minzoom<0 or result.source_maxzoom<result.source_minzoom or result.source_maxzoom>22:return {}
	if provider=="datasf":
		var buildings_url:=_url(base,options.get("buildings_url",n.get("buildings_url_path","")))
		if buildings_url.is_empty():return {}
		result["buildings_url"]=buildings_url
	else:
		result["buildings_url"]=""
		var layers=options.get("mapbox_building_layers",n.get("mapbox_building_layers",["building"]))
		if not layers is Array or layers.is_empty():return {}
		for layer in layers:
			if not layer is String or layer.is_empty():return {}
		result["mapbox_building_layers"]=layers
	return result

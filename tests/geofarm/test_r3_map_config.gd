extends SceneTree
const C:=preload("res://demo/geofarm/geo_contract.gd")
const Config:=preload("res://demo/geofarm/geo_map_config.gd")
const Fixture:=preload("res://tests/geofarm/parcel_fixtures.gd")
var checked:=0
var failed:=0
func verify(ok:bool,label:String) -> void:
	checked+=1
	if not ok:failed+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:
	var full:=Fixture.manifest()
	var native:=Config.build(full,"https://r3.invalid")
	verify(native.get("source_type")=="vector" and native.get("parcel_url")=="https://r3.invalid/tilejson.json","full city uses native vector TileJSON")
	verify(native.get("source_minzoom")==15 and native.get("source_maxzoom")==18 and native.get("min_zoom")==16,"source zoom bounds are distinct from display threshold")
	verify(native.get("building_source")=="mapbox" and native.get("buildings_url")=="","Mapbox mode does not require DataSF building URL")
	var data_sf:=Config.build(full,"https://r3.invalid",{"building_source":"datasf","buildings_url":"own-buildings.geojson"})
	verify(data_sf.get("building_source")=="datasf" and data_sf.get("buildings_url")=="https://r3.invalid/own-buildings.geojson","DataSF selection is config-switchable")
	verify(Config.build(full,"https://r3.invalid",{"building_source":"datasf"}).is_empty(),"missing DataSF source never silently switches to Mapbox")
	verify(Config.build(full,"https://r3.invalid",{"building_source":"other"}).is_empty(),"unknown building source rejected")
	var small:=full.duplicate(true);small.dataset_version=C.SMALL_DATASET;small.native_map.type="geojson";small.native_map.parcel_url_path="index.geojson"
	var fallback:=Config.build(small,"https://small-r3.invalid")
	verify(fallback.get("source_type")=="geojson" and fallback.get("parcel_url")=="https://small-r3.invalid/index.geojson","fallback is a separately configured dataset and source")
	verify(C.envelope(small,C.SMALL_DATASET) and not C.envelope(small,C.DATASET),"small dataset cannot masquerade as full city")
	full.native_map.type="geojson"
	verify(Config.build(full,"https://r3.invalid").is_empty(),"full-city config refuses a whole-city GeoJSON source")
	verify(C.identity_path(C.DATASET)!=C.identity_path(C.SMALL_DATASET),"full and fallback own/pending files are isolated")
	var farm:=Fixture.farm()
	verify(C.farm_matches(farm,"p-A",C.DATASET) and farm.schema==2,"r3 manifest3 retains farm2 compatibility")
	farm.dataset_version="sf-parcel-20261117-v2"
	verify(not C.farm_matches(farm,"p-A",C.DATASET),"r2 farm response cannot enter r3")
	print("R3 CONFIG ",checked-failed,"/",checked)
	quit(1 if failed else 0)

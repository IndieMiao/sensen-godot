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
	var native:=Config.build(full,"https://r4.invalid")
	verify(C.envelope(full) and full.schema==4,"r4 manifest is explicitly schema4")
	verify(native.get("source_type")=="vector" and native.get("parcel_url")=="https://r4.invalid/tilejson.json","dynamic farms retain native viewport tiles")
	verify(native.get("source_minzoom")==15 and native.get("source_maxzoom")==18 and native.get("min_zoom")==16,"tile and display zooms remain distinct")
	verify(native.get("building_source")=="mapbox" and native.get("buildings_url")=="","building selection stays independent of farm surface generation")
	var data_sf:=Config.build(full,"https://r4.invalid",{"building_source":"datasf","buildings_url":"own-buildings.geojson"})
	verify(data_sf.get("building_source")=="datasf","alternative building provider remains configurable")
	verify(Config.build(full,"https://r4.invalid",{"building_source":"datasf"}).is_empty(),"missing own building source never silently switches provider")
	for old in ["sf-parcel-20261117-v2","sf-parcel-20261117-v3","sf-parcel-small-20261117-v3"]:
		var previous:=full.duplicate(true);previous.dataset_version=old
		verify(not C.envelope(previous) and not C.valid_dataset(old),"old dataset is excluded from r4 state")
	var farm:=Fixture.farm()
	verify(C.farm_matches(farm,"p-A") and farm.schema==4,"RLE farm schema4 accepted for active dataset")
	farm.schema=2
	verify(not C.farm_matches(farm,"p-A"),"old triple-cell farm format is rejected")
	verify(C.identity_path(C.DATASET)=="user://geo_farm_identity_sf-dynamic-farm-20261118-r4.json","r4 uses its own identity file")
	print("DYNAMIC MAP CONFIG ",checked-failed,"/",checked)
	quit(1 if failed else 0)

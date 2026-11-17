extends RefCounted
const C:=preload("res://demo/geofarm/geo_contract.gd")
static func metadata(id:="p-A") -> Dictionary:
	return {"block_id":id,"parcel_id":id.trim_prefix("p-"),"selection_unit":"parcel","name":"328 TEST WAY" if id=="p-A" else "424 TEST AVE","address":"328 TEST WAY" if id=="p-A" else "424 TEST AVE","address_count":1,"center":[-122.452182,37.7295073],"bbox":[-122.45235,37.729465,-122.452013,37.72955],"cell_count":4,"source_area_m2":271.16,"inset_area_m2":271.16,"farm_path":"farms/"+id+".json","building_count":1}
static func manifest() -> Dictionary:
	return {"schema":2,"dataset_version":C.DATASET,"selection_unit":"parcel","parcel_count":1322,"native_map":{"type":"geojson","promote_id":"block_id","parcel_url_path":"index.geojson","buildings_url_path":"buildings.geojson","minzoom":17,"address_minzoom":18,"center":[-122.45190271843384,37.729419227],"initial_zoom":17.5}}
static func claim(id:="p-A",nickname:="Tester A") -> Dictionary:
	return {"block_id":id,"nickname":nickname,"claimed_at":"2026-11-17T10:00:00.000Z","center":[-122.452182,37.7295073]}
static func farm(id:="p-A") -> Dictionary:
	var result:=metadata(id)
	result.merge({"schema":2,"dataset_version":C.DATASET,"inset_m":0,"grid":{"width":3,"height":2,"cells":[[0,0,8],[1,0,1],[2,0,6],[0,1,5]]},"materials":[{"id":8,"color":"#986d51"},{"id":1,"color":"#a5c67c"},{"id":6,"color":"#9e927a"},{"id":5,"color":"#66b8d4"}]})
	return result

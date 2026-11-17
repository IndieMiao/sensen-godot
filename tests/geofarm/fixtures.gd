extends RefCounted
const VERSION := "sf-20261117-v1"
static func feature(id:String,lon:float,lat:float) -> Dictionary:
	var west:=lon-.0008;var east:=lon+.0008;var south:=lat-.0008;var north:=lat+.0008
	return {"type":"Feature","properties":{"block_id":id,"name":"SF Block "+id,"bbox":[west,south,east,north],"center":[lon,lat],"farm_path":"farms/"+id+".json","cell_count":800,"inset_area_m2":15000,"source_area_m2":17000,"inset_m":8},"geometry":{"type":"Polygon","coordinates":[[[west,south],[east,south],[east,north],[west,north],[west,south]]]}}
static func index_data() -> Dictionary:
	return {"schema":1,"dataset_version":VERSION,"type":"FeatureCollection","features":[feature("A",-122.4194,37.7749),feature("B",-122.4169,37.7749),feature("FAR",-122.49,37.72)]}
static func claim(id:String,nickname:String) -> Dictionary:
	return {"block_id":id,"nickname":nickname,"claimed_at":"2026-11-17T07:00:00.000Z"}
static func farm(id:String) -> Dictionary:
	return {"schema":1,"dataset_version":VERSION,"block_id":id,"name":"SF Block "+id,"source_area_m2":17000,"inset_area_m2":15000,"grid":{"width":3,"height":2,"cells":[[0,0,1],[1,0,1],[2,0,6],[0,1,5]]},"materials":[{"id":1,"name":"Residential","color":"#8aaa64"},{"id":5,"name":"Water","color":"#629eac"},{"id":6,"name":"Path","color":"#d5bb86"}]}

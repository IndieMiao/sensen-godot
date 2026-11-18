extends RefCounted
const C:=preload("res://demo/geofarm/geo_contract.gd")
static func metadata(id:="p-A") -> Dictionary:
	return {"block_id":id,"parcel_id":id.trim_prefix("p-"),"selection_unit":"parcel","name":"328 TEST WAY" if id=="p-A" else "424 TEST AVE","address":"328 TEST WAY" if id=="p-A" else "424 TEST AVE","address_count":1,"center":[-122.452182,37.7295073],"bbox":[-122.45235,37.729465,-122.452013,37.72955],"cell_count":800,"core_cell_count":800,"extension_cell_count":544,"total_cell_count":1344,"source_area_m2":271.16,"farm_path":"farms/"+id+".json"}
static func manifest() -> Dictionary:
	return {"schema":4,"dataset_version":C.DATASET,"selection_unit":"parcel","parcel_count":7,"generator_version":"dynamic-core-ext-1","native_map":{"type":"vector","promote_id":"block_id","parcel_url_path":"tilejson.json","parcel_source_layer":"parcels","source_minzoom":15,"source_maxzoom":18,"minzoom":16,"address_minzoom":18,"center":[-122.45190271843384,37.729419227],"initial_zoom":17.5,"building_source":"mapbox"}}
static func claim(id:="p-A",nickname:="Tester A") -> Dictionary:
	return {"block_id":id,"nickname":nickname,"claimed_at":"2026-11-18T13:00:00.000Z","center":[-122.452182,37.7295073]}
static func farm(id:="p-A") -> Dictionary:
	var core:Array=[];var extension:Array=[];var reserved:Array=[]
	for y in 28:
		reserved.append([y,0,48])
		if y>=4 and y<24:
			core.append([y,4,40,0]);extension.append([y,0,4,1]);extension.append([y,44,4,1])
		else:extension.append([y,0,48,1])
	return {"schema":4,"dataset_version":C.DATASET,"selection_unit":"parcel","block_id":id,"parcel_id":id.trim_prefix("p-"),"parcel_aliases":[id.trim_prefix("p-")],"name":metadata(id).name,"address":metadata(id).address,
		"generator_version":"dynamic-core-ext-1","seed_hex":"c".repeat(64),"game_cell_m":0.8,"source_area_m2":271.16,"source_cell_m":0.582194,
		"source_transform":{"crs":"EPSG:32610","rotation_deg":0},"grid":{"width":48,"height":28,"origin_cell":[-24,-14]},
		"zones":{"core":{"runs":core},"extension":{"runs":extension}},
		"capabilities":{"core":{"walk":true,"till":true,"plant":true,"arrange":true,"place":true},"extension":{"walk":true,"till":false,"plant":false,"arrange":false,"place":false}},
		"counts":{"core_cell_count":800,"extension_cell_count":544,"total_cell_count":1344},
		"surface_palette":[{"id":0,"name":"Soil","color":"#D8BF8D"},{"id":1,"name":"Grass","color":"#8FAD69"},{"id":2,"name":"Path","color":"#BBA882"}],
		"boundaries":{"core":[{"outer":[[4,4],[44,4],[44,24],[4,24],[4,4]],"holes":[]}],"outer":[{"outer":[[0,0],[48,0],[48,28],[0,28],[0,0]],"holes":[]}]},
		"walk_reserve":{"no_solid_decor_runs":reserved,"spawn_cell":[24,14],"entry_cell":[24,1]},
		"geo_hints":{"water_fraction":0.0,"landuse":"residential","source_building_count":2},"stats":{"core_iou":1.0,"width_min_cells":4,"width_max_cells":4,"core_components":1,"walk_components":1,"recovery_flags":[]},"attribution":"Synthetic test fixture only"}

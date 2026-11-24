extends RefCounted
const C:=preload("res://modules/dynamic_farm/map/geo_contract.gd")
static func metadata(id:="p-A") -> Dictionary:
	return {"block_id":id,"parcel_id":id.trim_prefix("p-"),"selection_unit":"parcel","name":"328 TEST WAY" if id=="p-A" else "424 TEST AVE","address":"328 TEST WAY" if id=="p-A" else "424 TEST AVE","address_count":1,"center":[-122.452182,37.7295073],"bbox":[-122.45235,37.729465,-122.452013,37.72955],"cell_count":800,"core_cell_count":800,"extension_cell_count":544,"total_cell_count":1344,"source_area_m2":271.16,"farm_path":"farms/"+id+".json"}
static func manifest() -> Dictionary:
	return {"schema":4,"dataset_version":C.DATASET,"selection_unit":"parcel","parcel_count":7,"generator_version":"dynamic-core-ext-1","native_map":{"type":"vector","promote_id":"block_id","parcel_url_path":"tilejson.json","parcel_source_layer":"parcels","source_minzoom":15,"source_maxzoom":18,"minzoom":16,"address_minzoom":18,"center":[-122.45190271843384,37.729419227],"initial_zoom":17.5,"building_source":"mapbox"}}
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
## C-43: a farm whose core is any cell set (non-rectangular, any size). Every other grid cell is walk-only
## extension, row 0 holds the entry, and the whole grid is walking reserve so the core contract always holds.
static func shaped_farm(id:String, core_cells:Dictionary, width:int, height:int, version:=C.DATASET) -> Dictionary:
	var core:Array=[];var extension:Array=[];var reserved:Array=[]
	var spawn:Vector2i=core_cells.keys()[core_cells.size() >> 1]
	for y in height:
		reserved.append([y,0,width])
		var x:=0
		while x<width:
			var inside:=core_cells.has(Vector2i(x,y));var start:=x
			while x<width and core_cells.has(Vector2i(x,y))==inside:x+=1
			(core if inside else extension).append([y,start,x-start,0 if inside else 1])
	var data:=farm(id)
	data.dataset_version=version
	data.grid={"width":width,"height":height,"origin_cell":[-(width >> 1),-(height >> 1)]}
	data.zones={"core":{"runs":core},"extension":{"runs":extension}}
	data.counts={"core_cell_count":core_cells.size(),"extension_cell_count":width*height-core_cells.size(),"total_cell_count":width*height}
	data.boundaries={"core":[{"outer":[[1,1],[width-1,1],[width-1,height-1],[1,height-1],[1,1]],"holes":[]}],"outer":[{"outer":[[0,0],[width,0],[width,height],[0,height],[0,0]],"holes":[]}]}
	data.walk_reserve={"no_solid_decor_runs":reserved,"spawn_cell":[spawn.x,spawn.y],"entry_cell":[0,0]}
	return data
## Cells of axis-aligned rectangles [x, y, w, h], minus optional holes of the same form.
static func cells(rects:Array, holes:Array=[]) -> Dictionary:
	var result:={}
	for r in rects:
		for y in range(r[1],r[1]+r[3]):
			for x in range(r[0],r[0]+r[2]):result[Vector2i(x,y)]=true
	for r in holes:
		for y in range(r[1],r[1]+r[3]):
			for x in range(r[0],r[0]+r[2]):result.erase(Vector2i(x,y))
	return result

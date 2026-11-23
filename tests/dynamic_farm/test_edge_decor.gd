extends SceneTree
const Data=preload("res://modules/dynamic_farm/farm_data.gd")
const Walk=preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery=preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade=preload("res://modules/dynamic_farm/farm_shade.gd")
const Decor=preload("res://modules/dynamic_farm/farm_edge_decor.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
func _run() -> void:
	var config=JSON.parse_string(FileAccess.get_file_as_string(Decor.CONFIG))
	for path:String in OS.get_cmdline_user_args():
		if not path.ends_with(".json"):continue
		var data:Dictionary=Data.decode(JSON.parse_string(FileAccess.get_file_as_string(path)))
		var walk:=Walk.new(data)
		var original:=Scenery.plan(data,walk)
		Shade.enforce_budget(original,data,walk)
		var original_copy:=original.duplicate(true)
		var blocked_copy:Dictionary=walk.reserved.duplicate()
		var data_copy:=data.duplicate(true)
		var added:=Decor.plan(data,walk,original)
		var again:=Decor.plan(data,walk,original)
		_check(added==again,"new layer deterministic")
		_check(original==original_copy and walk.reserved==blocked_copy and data==data_copy,"original plan, blockers and authority masks unchanged")
		var caps:Dictionary=config.sample_caps.get(data.block_id,{})
		if caps.is_empty():
			_check(added.layout.is_empty(),"review layer has no unapproved all-city defaults")
			continue
		_check(added.layout.size()>0,"real comparison includes actual new geometry, not a silent empty B")
		_check(added.layout.size()<=caps.instances and added.clusters.size()<=caps.clusters and added.triangles<=caps.triangles and added.batches<=4,"sample instance/triangle/batch caps")
		_check(added.covered_cells<=added.perimeter_cells*0.2+0.00001,"at least 80 percent bare outer perimeter")
		var footprints_ok:=true
		var scale_ok:=true
		var flags_ok:=true
		for item:Dictionary in added.layout:
			var box:AABB=item.box
			# Independently enumerate the entire AABB footprint from its world corners.
			var low:=Vector2i(floori(box.position.x/data.cell_m+walk.center_grid.x),floori(-box.end.z/data.cell_m+walk.center_grid.y+0.000001))
			var high:=Vector2i(floori(box.end.x/data.cell_m+walk.center_grid.x-0.000001),floori(-box.position.z/data.cell_m+walk.center_grid.y))
			for y in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					var at:=Vector2i(x,y)
					if not data.by_cell.has(at) or data.by_cell[at].zone!="extension" or data.protected.has(at) or blocked_copy.has(at):footprints_ok=false
			var tr:Transform3D=item.transform
			var scale_value:=tr.basis.x.length()
			if scale_value<0.84999 or scale_value>1.00001 or not is_equal_approx(scale_value,tr.basis.y.length()) or not is_equal_approx(scale_value,tr.basis.z.length()):scale_ok=false
			if not is_zero_approx(box.position.y) or item.solid or item.shadow or item.asset not in ["wild_pz_grass_24","wild_pz_foot_leafy"]:flags_ok=false
		_check(footprints_ok,"every transformed footprint square stays in allowed existing extension")
		_check(scale_ok and flags_ok,"original pivot, low scale, no collisions/shadows/new assets")
		var gaps_ok:=true
		var rings:=Decor._segments(data)
		for i in added.clusters.size():
			for j in range(i+1,added.clusters.size()):
				var a:Dictionary=added.clusters[i]
				var b:Dictionary=added.clusters[j]
				if a.ring!=b.ring:continue
				for shift:float in [-rings[a.ring].length,0.0,rings[a.ring].length]:
					if a.interval.x<b.interval.y+shift+6-0.000001 and a.interval.y>b.interval.x+shift-6+0.000001:gaps_ok=false
		_check(gaps_ok,"entire cluster intervals retain six cells of bare arc")
		# The batch budget counts what build() draws: one batch per colour variant and chunk.
		var drawn:=Scenery.build(added,Walk.new(data),original.recipe)
		_check(drawn.ok and drawn.batches==added.batches and drawn.instances==added.layout.size(),"planned batches match built batches (%d vs %d)" % [added.batches,drawn.batches])
		drawn.root.free()
		print("EDGE_DECOR_SAMPLE ",data.block_id," instances=",added.layout.size()," clusters=",added.clusters.size()," triangles=",added.triangles," batches=",added.batches," covered=",added.covered_cells," perimeter=",added.perimeter_cells)
	print("DYNAMIC_EDGE_DECOR_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

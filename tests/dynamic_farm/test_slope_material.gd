extends SceneTree
const Data=preload("res://modules/dynamic_farm/farm_data.gd")
const Walk=preload("res://modules/dynamic_farm/farm_walk.gd")
const Ground=preload("res://modules/dynamic_farm/farm_mesh.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	_run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func _triangles(root:Node3D) -> Array[String]:
	var records:Array[String]=[]
	for child in root.get_children():
		if not child is MeshInstance3D:continue
		var arrays:Array=child.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var key:=""
			for j in 3:key+=str(vertices[indices[i+j]])+":"+str(normals[indices[i+j]])+";"
			records.append(key)
	records.sort()
	return records

func _run() -> void:
	var recipe=JSON.parse_string(FileAccess.get_file_as_string("res://assets/dynamic_farm/499-art-recipe.json"))
	for path:String in OS.get_cmdline_user_args():
		if not path.ends_with(".json"):continue
		var data:Dictionary=Data.decode(JSON.parse_string(FileAccess.get_file_as_string(path)))
		var original:=data.duplicate(true)
		var walk:=Walk.new(data)
		var before:=Ground.build(data,walk,recipe,true,true,1.0)
		var after:=Ground.build(data,walk,recipe,true,true,0.65)
		_check(_triangles(before)==_triangles(after),"every actual triangle position, winding and normal is unchanged")
		_check(before.get_meta("bank_metrics")==after.get_meta("bank_metrics") and data==original,"guard and authority masks unchanged")
		var slope_count:=0
		var changed_only_colour:=true
		var same_chunks:=true
		var old_chunks:Array=before.get_meta("shade_chunks")
		var new_chunks:Array=after.get_meta("shade_chunks")
		for chunk:Dictionary in new_chunks:
			var old:Dictionary={}
			for c:Dictionary in old_chunks:
				if c.key==chunk.key:old=c
			if old.is_empty() or old.rect!=chunk.rect:
				same_chunks=false
				continue
			for mesh:MeshInstance3D in chunk.meshes:
				var material:ShaderMaterial=mesh.material_override
				var is_slope:=str(mesh.name).begins_with("Slope_")
				var source_name:=str(mesh.name).replace("Slope_","Surface_")
				var old_mesh:=before.get_node(source_name) as MeshInstance3D
				var old_material:ShaderMaterial=old_mesh.material_override
				if is_slope:
					slope_count+=1
					_check(material!=old_material and material.shader==old_material.shader,"independent slope instance reuses existing shader")
					var base:Color=old_material.get_shader_parameter("clearing_color")
					var actual:Color=material.get_shader_parameter("clearing_color")
					var expected:=base.srgb_to_linear()
					expected.r*=0.65
					expected.g*=0.65
					expected.b*=0.65
					expected.a=1.0
					_check(actual.is_equal_approx(expected.linear_to_srgb()),"source_color receives linear gain converted back to sRGB exactly once")
				for parameter:Dictionary in material.shader.get_shader_uniform_list():
					var name:String=parameter.name
					if is_slope and name=="clearing_color":continue
					if material.get_shader_parameter(name)!=old_material.get_shader_parameter(name):changed_only_colour=false
		_check(slope_count>0 and slope_count==int(after.get_meta("slope_batches")),"slopes are batched by surface and chunk")
		_check(changed_only_colour,"all other shader parameters and all top materials unchanged")
		_check(same_chunks,"new slope draws belong to same existing shade chunk bounds")
		before.free()
		after.free()
	print("DYNAMIC_SLOPE_MATERIAL_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

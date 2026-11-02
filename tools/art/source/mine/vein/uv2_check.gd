extends SceneTree
# Director's GLTFDocument probe, extended only with mask counts and resource cleanup.
func _init():
	var report={}
	for f in ["orig.glb","backdrop.glb"]:
		var doc=GLTFDocument.new();var state=GLTFState.new()
		var error=doc.append_from_file(f,state)
		assert(error==OK)
		var root=doc.generate_scene(state)
		var mesh:MeshInstance3D=root.find_children("*","MeshInstance3D",true,false)[0]
		var arrays=mesh.mesh.surface_get_arrays(0);var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		var lo=Vector2(9,9);var hi=Vector2(-9,-9);var zero=0;var one=0;var invalid=0;var gray_errors=0
		for i in uv2.size():
			var v=uv2[i];lo=lo.min(v);hi=hi.max(v)
			if absf(v.y)<.0001:
				zero+=1
				var c=arrays[Mesh.ARRAY_COLOR][i]
				if maxf(absf(c.r-c.g),absf(c.g-c.b))>.0001:gray_errors+=1
			elif absf(v.y-1)<.0001:one+=1
			else:invalid+=1
		report[f]={"error":error,"min":[lo.x,lo.y],"max":[hi.x,hi.y],"vertices":uv2.size(),
			"mask_0_vertices":zero,"mask_1_vertices":one,"other_vertices":invalid,"non_gray_mask_0_vertices":gray_errors}
		print(f," err=",error," UV2 min=",lo," max=",hi," n=",uv2.size()," y0=",zero," y1=",one," other=",invalid)
		root.free()
	assert(report["backdrop.glb"].mask_0_vertices>0 and report["backdrop.glb"].mask_1_vertices>0)
	assert(report["backdrop.glb"].other_vertices==0 and report["backdrop.glb"].non_gray_mask_0_vertices==0)
	var file=FileAccess.open("res://uv2-report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	quit()

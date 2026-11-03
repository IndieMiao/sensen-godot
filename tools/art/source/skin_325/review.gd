extends Node
var vp:SubViewport
var world:Node3D
var room:Node3D
var camera:Camera3D
var rig
var room_id:String
var output:String
var report={"checks":[],"captures":[],"rooms":{}}

func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func fingerprint(value):return var_to_bytes(value).hex_encode().sha256_text()
func setup(id):
	room_id=id
	vp=SubViewport.new();vp.size=Vector2i(720,1600);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	world=Node3D.new();vp.add_child(world)
	var n1=id=="poi_hotel_lobby"
	var env=Environment.new();env.background_mode=Environment.BG_COLOR
	env.background_color=Color("B5A18B" if n1 else "D9E1E4")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("FFF1DC" if n1 else "EEF0E9")
	env.ambient_light_energy=.4 if n1 else .55
	env.tonemap_mode=Environment.TONE_MAPPER_ACES if n1 else Environment.TONE_MAPPER_LINEAR
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,4,-1) if n1 else Vector3(-6,7,2);sun.look_at(Vector3.ZERO)
	sun.light_color=Color("FFF2DA" if n1 else "FFF6E8");sun.light_energy=1.2 if n1 else 1.
	sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=30 if n1 else 100
	sun.shadow_bias=.15 if n1 else .05;sun.shadow_normal_bias=.8 if n1 else .25
	if n1:sun.light_angular_distance=.4
	else:sun.shadow_opacity=.55
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=40;camera.current=true;world.add_child(camera)
	room=load("res://scenes/"+id+"/"+id+"_art.tscn").instantiate();world.add_child(room)
	if n1:room.get_node("SharedHearthFire").set_process(false)
	report.rooms[id]={"lighting":{"ambient":env.ambient_light_energy,"sun":sun.light_energy,"tonemap":env.tonemap_mode},"formal_resources":true}
func pose(width,focus):
	camera.size=width;camera.rotation_degrees=Vector3(-43,45,0);camera.position=focus+camera.basis.z*22
func default_camera():
	vp.size=Vector2i(720,1600)
	if room_id=="poi_hotel_lobby":
		var native=JSON.parse_string(FileAccess.get_file_as_string("res://n1-camera.json"))
		check(native.layout_sha256==FileAccess.get_sha256("res://assets/rooms/poi_hotel_lobby/layout.json"),"N1 native opening matches current layout")
		camera.transform=Transform3D(Basis(vec(native.basis[0]),vec(native.basis[1]),vec(native.basis[2])),vec(native.origin))
		camera.size=native.width_m
	else:pose(6.72,Vector3(0,1.1,.35))
func overview_camera():
	vp.size=Vector2i(1440,1320)
	pose(11. if room_id=="poi_hotel_lobby" else 12.,Vector3(0,2.,0) if room_id=="poi_hotel_lobby" else Vector3(0,1.85,.1))
func avatar():
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),room_id+": actual player assembled")
	rig.play_motion("idle");var anim=rig.get_node("AnimationPlayer");anim.seek(.3,true);anim.pause()
	var lo=INF;var hi=-INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for s in mesh.get_surface_count():
			for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*node.global_transform*v;lo=minf(lo,p.y);hi=maxf(hi,p.y)
	rig.scale=Vector3.ONE*1.745/(hi-lo)
	var spawn=room.get_node("spawn").position
	if room_id=="poi_hotel_lobby":spawn=Vector3(2.20,.0837,2.35)
	rig.position=spawn-Vector3.UP*lo*rig.scale.y;rig.rotation_degrees.y=180
	report.rooms[room_id].avatar={"height":1.745,"position":[rig.position.x,rig.position.y,rig.position.z]}
	if room_id=="poi_hotel_lobby":
		var rug=room.get_node("green_rug").find_children("*","MeshInstance3D",true,false)[0]
		var arrays=rug.mesh.surface_get_arrays(0);var vertices=arrays[Mesh.ARRAY_VERTEX];var indices=arrays[Mesh.ARRAY_INDEX];var supported=false
		for i in range(0,indices.size(),3):
			var hit=Geometry3D.segment_intersects_triangle(spawn+Vector3.UP,spawn-Vector3.UP,
				rug.global_transform*vertices[indices[i]],rug.global_transform*vertices[indices[i+1]],rug.global_transform*vertices[indices[i+2]])
			if hit!=null and absf(hit.y-spawn.y)<.001:supported=true
		check(supported,"N1 player feet stand on actual rug triangles")
	else:check(absf(spawn.x-.04)<.35 and absf(spawn.y-.08)<.0001,"N2 player feet stand on central cross strip")
func signature():
	var result={}
	for node in room.find_children("*","MeshInstance3D",true,false):
		var path=str(room.get_path_to(node))
		if path.contains("VariantOption"):continue
		var surfaces=[]
		for s in node.mesh.get_surface_count():
			var a=node.mesh.surface_get_arrays(s)
			surfaces.append({"vertices":fingerprint(a[Mesh.ARRAY_VERTEX]),"normals":fingerprint(a[Mesh.ARRAY_NORMAL]),
				"uv":fingerprint(a[Mesh.ARRAY_TEX_UV]),"indices":fingerprint(a[Mesh.ARRAY_INDEX]),"colors":fingerprint(a[Mesh.ARRAY_COLOR])})
		result[path]={"transform":str(node.global_transform),"surfaces":surfaces}
	return result
func apply_variant(id):
	var prefix="res://assets/rooms/"+room_id+"/"
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(prefix+"variants.json"))
	for option in manifest.options.values():
		for path in option.hide_meshes:room.get_node(path).visible=true
	for node in room.find_children("VariantOption_*","",true,false):node.free()
	var variant=manifest.variants[id]
	var replacement=load(prefix+variant.atlas)
	var count=0
	for node in room.find_children("*","MeshInstance3D",true,false):
		for surface in node.mesh.get_surface_count():
			var mat=node.get_active_material(surface) as StandardMaterial3D
			if mat==null or mat.albedo_texture==null:continue
			if mat.albedo_texture.resource_path not in [prefix+manifest.material_source_atlas,prefix+"room_albedo_ao_b.png"]:continue
			var copy=mat.duplicate();copy.albedo_texture=replacement
			node.set_surface_override_material(surface,copy);count+=1
	check(count>20,room_id+": "+id+" atlas assigned to shell and furniture")
	for key in variant.enabled_options:
		var option=manifest.options[key]
		var node=load(prefix+option.scene).instantiate()
		node.name="VariantOption_"+key
		var parent=room.get_node(option.parent)
		parent.add_child(node)
		for path in option.hide_meshes:
			check(room.get_node(path) is MeshInstance3D,"Switch hides only mesh, keeps collision: "+path)
			room.get_node(path).visible=false
	var expected_size=[.66,.23] if room_id=="poi_service_hall" and id=="B" else manifest.variants.A.sign.size_m
	check(variant.sign.size_m==expected_size,room_id+": approved writing area "+id)
	report.rooms[room_id]["variant_"+id]={"atlas":variant.atlas,"surfaces":count,"enabled_options":variant.enabled_options,"sign":variant.sign}
func structural_signature():
	var result={}
	for node in room.find_children("*","",true,false):
		if str(room.get_path_to(node)).contains("VariantOption"):continue
		if node is Marker3D or node is CollisionShape3D:
			result[str(room.get_path_to(node))]={"transform":str(node.global_transform),"meta":{}}
			for key in node.get_meta_list():result[str(room.get_path_to(node))].meta[key]=node.get_meta(key)
	return result
func capture(name):
	for i in 8:await RenderingServer.frame_post_draw
	check(vp.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"name":name,"pixels":[vp.size.x,vp.size.y],"camera":str(camera.transform),"width":camera.size,"pitch":camera.rotation_degrees.x})
	print("SKIN_CAPTURE ",name)
func run_room(id):
	setup(id);default_camera();await avatar()
	for i in 20:await RenderingServer.frame_post_draw
	for particles in room.find_children("*","GPUParticles3D",true,false):particles.speed_scale=0
	var before=signature();var prefix="N1" if id=="poi_hotel_lobby" else "N2"
	await capture(prefix+"_A_default")
	var structure=structural_signature()
	apply_variant("B")
	var after=signature();check(before.keys()==after.keys(),prefix+": original mesh node inventory unchanged")
	for key in before:
		check(before[key].transform==after[key].transform,prefix+": furniture transform unchanged "+key)
		for i in before[key].surfaces.size():
			for attribute in ["vertices","normals","uv","colors"]:
				check(before[key].surfaces[i][attribute]==after[key].surfaces[i][attribute],prefix+": original "+attribute+" unchanged "+key)
			check(before[key].surfaces[i].indices==after[key].surfaces[i].indices,prefix+": topology unchanged "+key)
	report.rooms[id].baseline=before;report.rooms[id].b=after
	check(structure==structural_signature(),prefix+": seats, markers and collisions unchanged")
	default_camera();await capture(prefix+"_B_default")
	var pair=report.captures.filter(func(c):return c.name in [prefix+"_A_default",prefix+"_B_default"])
	check(pair[0].camera==pair[1].camera and pair[0].width==pair[1].width,prefix+": exact same A/B camera")
	overview_camera();await capture(prefix+"_B_overview")
	apply_variant("A")
	check(room.find_children("VariantOption_*","",true,false).is_empty(),prefix+": no B options remain after A restoration")
	check(before==signature(),prefix+": switching back to A restores all original geometry")
	check(structure==structural_signature(),prefix+": switching back preserves all markers/collision")
	for node in room.find_children("*","MeshInstance3D",true,false):
		check(node.visible,prefix+": A original mesh visible "+str(room.get_path_to(node)))
	vp.queue_free();await get_tree().process_frame;await get_tree().process_frame
func sign_detail():
	setup("poi_service_hall");apply_variant("B")
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/poi_service_hall/variants.json"))
	var spec=manifest.variants.B.sign;var anchor=room.get_node(spec.anchor)
	var label=Label3D.new();label.name="RuntimeSignProof";label.text="Service Hall"
	label.font=ThemeDB.fallback_font;label.font_size=64;label.outline_size=0
	label.modulate=Color("37564A");label.shaded=true
	label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var font_width=label.font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x
	label.pixel_size=minf(spec.size_m[0]*.94/font_width,spec.size_m[1]*.94/label.font.get_height(label.font_size))
	room.add_child(label);label.position=anchor.position+vec(spec.offset_m)
	# The legacy marker points -Z; Label3D's visible face points +Z.
	label.rotation_degrees.y=fposmod(anchor.rotation_degrees.y+180.,360.)
	vp.size=Vector2i(1600,800);camera.size=1.9;camera.rotation_degrees=Vector3(-15,15,0)
	camera.position=anchor.position+Vector3(-.12,0,0)+camera.basis.z*22
	for i in 8:await RenderingServer.frame_post_draw
	var bounds=label.get_aabb();var left=label.position.x+bounds.position.x
	var right=left+bounds.size.x;var cross_right=anchor.position.x-.44+.175
	var patch:MeshInstance3D=room.get_node("VariantOption_sign_b/GreenCrossSign")
	var patch_bounds=patch.get_aabb();var patch_center=room.to_local(patch.global_position)
	check(patch_bounds.size.distance_to(Vector3(.88,.23,0))<.00001,"N2 patch matches plaque inner size .88 x .23m")
	check(absf(patch_center.x-anchor.position.x)<.00001 and absf(patch_center.y-anchor.position.y)<.00001,"N2 patch centered inside original plaque")
	check(left>=patch_center.x-.44 and right<=patch_center.x+.44,"Runtime lettering stays inside inset patch")
	check(is_zero_approx(label.rotation_degrees.y),"Text faces same +Z side as green cross at marker yaw 180")
	check(bounds.size.x>0 and bounds.size.x<=spec.size_m[0] and bounds.size.y<=spec.size_m[1],"Actual runtime text fits .66 x .23m writing area")
	check(left>cross_right+.02,"Runtime Service Hall is physically to the right of the green cross")
	check(left>=anchor.position.x+.1-.33 and right<=anchor.position.x+.1+.33,"Runtime text remains inside the offset B writing area")
	report.sign={"text":label.text,"anchor_yaw":anchor.rotation_degrees.y,"text_yaw":label.rotation_degrees.y,
		"patch_size_m":[patch_bounds.size.x,patch_bounds.size.y],"patch_center_room":[patch_center.x,patch_center.y,patch_center.z],
		"size_m":spec.size_m,"room_space_offset_m":spec.offset_m,"actual_text_size_m":[bounds.size.x,bounds.size.y],
		"text_x_range_m":[left,right],"cross_right_x_m":cross_right,"clear_gap_m":left-cross_right,"baked_text":false}
	await capture("N2_sign_Service_Hall")
	vp.queue_free();await get_tree().process_frame
func run():
	var detail=OS.get_cmdline_user_args().has("--sign-detail")
	output=ProjectSettings.globalize_path("res://../captures-v1.2" if detail else "res://../captures");DirAccess.make_dir_recursive_absolute(output)
	if detail:await sign_detail()
	else:
		for id in ["poi_hotel_lobby","poi_service_hall"]:await run_room(id)
	report.passed=report.checks.all(func(c):return c.passed)
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("SKIN_V1_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)

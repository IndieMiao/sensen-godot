extends Node
var rt: P0Runtime
var farm
var fixture: Dictionary
var checks:=[]
var report:={}
func _ready() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func respond(cmd: Dictionary) -> void:
	rt.session._finish(HTTPRequest.RESULT_SUCCESS,200,JSON.stringify({"ok":true,"state":fixture,"events":[]}).to_utf8_buffer(),cmd)
func run() -> void:
	rt=P0Runtime.ensure();fixture=JSON.parse_string(FileAccess.get_file_as_string("res://view-lv3.json"))
	rt.session.view=fixture;rt.session._received_ms=Time.get_ticks_msec()
	rt.session.transport=func(_method,_path,_body,cmd):respond.call_deferred(cmd)
	for i in 3:await get_tree().process_frame
	farm=load("res://scenes/p0/p0_farm.tscn").instantiate();add_child(farm)
	for i in 150:await get_tree().process_frame
	var plaque: Node3D=farm._plaque_node
	check(plaque.visible,"Upgrade Plaque visible after first upgrade")
	check(plaque.scale.is_equal_approx(Vector3.ONE),"runtime 1.0 scale")
	check(plaque.position.is_equal_approx(P0Garden.plaque_point(farm.bp)),"existing PLAQUE_CELL placement retained")
	check(not farm.actor.rig.is_busy(),"native player fully assembled")
	var marker:=plaque.find_child("PlaqueText",true,false) as Marker3D
	check(marker!=null,"PlaqueText is an imported Marker3D")
	check(marker.transform.origin.is_equal_approx(Vector3(0,.43,.078)),"text centre .002 m outside .076 m face")
	check(marker.transform.basis.is_equal_approx(Basis.IDENTITY),"text mount identity basis / +Z front")
	check(marker.get_meta("size")==Vector2(.38,.24),"clear writable area .38 x .24 m")
	var triangles:=0;var surfaces:=0
	for mesh in plaque.find_children("*","MeshInstance3D",true,false):
		check(str(mesh.mesh.resource_name).ends_with("_mobile"),"runtime mobile mesh name (Godot prefixes its node name)")
		report.mesh_resource_name=str(mesh.mesh.resource_name)
		for surface in mesh.mesh.get_surface_count():
			surfaces+=1;triangles+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3
			var mat:=mesh.get_active_material(surface) as StandardMaterial3D
			check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb,"linear farm vertex colours")
			check(is_equal_approx(mat.roughness,.9) and is_equal_approx(mat.metallic_specular,.18) and mat.metallic==0,"one matte farm material; nails are not metallic")
	check(triangles<=600 and surfaces==1,"runtime <=600 triangles / one surface")
	check(plaque.find_children("*","Skeleton3D",true,false).is_empty() and plaque.find_children("*","AnimationPlayer",true,false).is_empty(),"no skeleton or animations")
	check(plaque.find_children("*","CollisionObject3D",true,false).is_empty(),"no new plaque collision")
	var label:=Label3D.new();label.name="ReviewDateExample"
	label.text="Lv2 · Nov 4\nLv3 · Nov 6";label.font=load("res://assets/ui/fonts/NotoSansSC-Regular.otf")
	label.font_size=46;label.pixel_size=.001;label.outline_size=0;label.modulate=Color("4E3A27")
	label.shaded=true;label.no_depth_test=false;label.billboard=BaseMaterial3D.BILLBOARD_DISABLED
	marker.add_child(label)
	var native_width: float=farm.FarmCamera.close_view_size(get_viewport().get_visible_rect().size)*farm.FarmCamera.P0_VIEW_K/farm._zoom
	check(absf(farm.cam.rotation_degrees.x+43)<.001 and absf(farm.cam.size-native_width)<.001,"original 43 degree opening camera; b1 fits the open beds")
	for i in 12:await get_tree().process_frame
	var text_box:=label.get_aabb()
	check(text_box.size.x<=.38 and text_box.size.y<=.24,"two runtime example lines fit the clear writing area")
	report.example_text_aabb=str(text_box)
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	check(image.save_png("res://../default.png")==OK,"default farm capture saved")
	report.default_camera={"transform":str(farm.cam.transform),"size":farm.cam.size,"native_zoom":farm._zoom,"opening_zoom":farm._opening_zoom,"logical_size":str(get_viewport().get_visible_rect().size),"pixels":str(image.get_size()),"actor":str(farm.actor.position)}
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.world_3d=farm.get_world_3d()
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH
	cam.near=.1;cam.far=40;cam.size=4.0;vp.add_child(cam);cam.make_current()
	cam.global_basis=farm.cam.global_basis
	var center: Vector3=(farm._plaque+farm._sign)*.5+Vector3(0,.75,-.1)
	cam.global_position=center+cam.global_basis.z*11
	for i in 15:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	image=vp.get_texture().get_image();check(image.save_png("res://../two_signs.png")==OK,"paired signs in actual farm close-up saved")
	report.close_camera={"transform":str(cam.transform),"size":cam.size,"pixels":str(image.get_size()),"pitch":cam.rotation_degrees.x}
	report.merge_demo="Two-line runtime Label3D only; no letters exported in GLB"
	report.marker_global=str(marker.global_position);report.triangles=triangles;report.surfaces=surfaces
	report.asset_sha256=FileAccess.get_sha256("res://assets/farm/art/upgrade_plaque.glb")
	report.renderer=RenderingServer.get_current_rendering_method();report.gpu=RenderingServer.get_video_adapter_name()
	report.checks=checks;report.passed=checks.all(func(c):return c.passed)
	FileAccess.open("res://../render-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("PLAQUE_RENDER ",report.passed," ",triangles," triangles / ",surfaces," surface; ",checks.size()," checks")
	vp.queue_free();farm.queue_free();rt.queue_free();await get_tree().process_frame
	get_tree().quit(0 if report.passed else 1)

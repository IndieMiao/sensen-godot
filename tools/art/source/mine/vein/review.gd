extends Node
const MineArt=preload("res://modules/mining/mine_art.gd")
const MineCombat=preload("res://modules/mining/mine_combat.gd")
const CameraRules=preload("res://modules/farm/farm_camera.gd")
var vp:SubViewport
var mine:Probe
var output:String
var band_rect:Rect2
var report={"checks":[],"bands":[],"captures":[]}

class Probe extends "res://scenes/p0/p0_mine.gd":
	func _ready():
		_build_light();set_process(false);set_process_input(false);set_process_unhandled_input(false)
	func _view()->Dictionary:return {}
	func _process(_delta):pass

func _ready():run.call_deferred()
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func xyz(p):return [p.x,p.y,p.z]

func camera_band():
	var reference=SubViewport.new();reference.size=Vector2i(360,800);add_child(reference)
	var ui=P0Ui.new();ui.quick_store="user://vein_review_ui.json";reference.add_child(ui)
	await get_tree().process_frame;await get_tree().process_frame
	ui.set_view({"energy":{"value":200,"max":200,"next_in":null,"regen_ms":240000},
		"bag":{"capacity":25,"free":25,"slots":[{"id":"torch","qty":2}]},"plots":[],"coins":40,"skills":{},
		"rest":{"used":0,"limit":1,"resets_in":1},"inbox":{"parcels":[],"letters":[]}})
	ui.set_mode("mine");ui.set_surface("mine");await get_tree().process_frame;await get_tree().process_frame
	var rect=ui.camera_band();band_rect=Rect2(rect.position*2,rect.size*2)
	reference.queue_free();await get_tree().process_frame

func avatar():
	var rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();mine.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Actual player assembled")
	rig.play_motion("idle");var anim=rig.get_node("AnimationPlayer");anim.seek(.3,true);anim.pause()
	var lo=INF;var hi=-INF
	for node in rig.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var mesh=node.bake_mesh_from_current_skeleton_pose() if node.skin!=null else node.mesh
		if mesh==null:continue
		for i in mesh.get_surface_count():
			for vertex in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var p=rig.global_transform.affine_inverse()*node.global_transform*vertex;lo=minf(lo,p.y);hi=maxf(hi,p.y)
	rig.scale=Vector3.ONE*1.745/(hi-lo);rig.position=Vector3(2.3,-lo*rig.scale.y,-5.7);rig.rotation_degrees.y=180
	return rig

func monster(id,position):
	var root=load("res://assets/monsters/"+id+"/"+id+".glb").instantiate();mine.add_child(root);root.position=position
	var players=root.find_children("*","AnimationPlayer",true,false);check(players.size()==1,id+" animation imported")
	var player:AnimationPlayer=players[0];player.play("idle");player.seek(.125,true);player.pause()
	var spec=JSON.parse_string(FileAccess.get_file_as_string("res://assets/monsters/"+id+"/"+id+".json"))
	BlobShadow.attach(root,spec.radius*1.15)
	return root

func capture(name):
	for i in 6:await RenderingServer.frame_post_draw
	var image=vp.get_texture().get_image();check(image.save_png(output+"/"+name+".png")==OK,"Capture "+name)
	report.captures.append({"id":name,"pixels":[vp.size.x,vp.size.y],"camera_width_m":mine.cam.size,
		"camera_position":xyz(mine.cam.position),"near":mine.cam.near,"far":mine.cam.far})
	print("VEIN_CAPTURE ",name)

func backdrop_checks():
	var meshes=mine.backdrop.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==1,"Backdrop is one mesh")
	var node:MeshInstance3D=meshes[0];var arrays=node.mesh.surface_get_arrays(0)
	check(node.mesh.get_surface_count()==1,"Backdrop one surface")
	check(arrays[Mesh.ARRAY_INDEX].size()/3<=4000,"Backdrop <=4000 triangles after import")
	check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Backdrop disables shadows")
	check(node.material_override.get_shader_parameter("vein_mask")==1.0,"Approved shader uses vein_mask=1")
	check(mine.backdrop.find_children("*","CollisionObject3D",true,false).is_empty(),"Backdrop has no collision")
	var rock=0;var seam=0;var invalid=0
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var mask=arrays[Mesh.ARRAY_TEX_UV2][i];var color=arrays[Mesh.ARRAY_COLOR][i]
		if mask.y>.99:seam+=1
		elif absf(mask.y)<.001:
			rock+=1
			if maxf(absf(color.r-color.g),absf(color.g-color.b))>.0001:invalid+=1
		else:invalid+=1
	check(rock>0 and seam>0 and invalid==0,"Actual imported UV2.y separates grayscale rock and mineral colour")
	check(mine.backdrop.position.distance_to(MineBackdrop.toward_camera())<.0001,"Runtime owns the 1m forward offset")
	report.backdrop={"triangles":arrays[Mesh.ARRAY_INDEX].size()/3,"rock_vertices":rock,"mineral_vertices":seam}

func scene(band,index,guard=false):
	var measured_ores=[]
	ProjectSettings.set_setting("mine_vein/ground",Color(band.ground));ProjectSettings.set_setting("mine_vein/wall",Color(band.wall))
	ProjectSettings.set_setting("mine_vein/backdrop_tint",Color(band.backdrop_tint));MineBackdrop.VOID=Color(band.fog)
	MineArt._floor_cache.clear();mine=Probe.new();vp.add_child(mine);mine._build_floor(3)
	for node in mine.objects.get_children():
		if str(node.name).begins_with("Rock") or node.name=="MineElevator":node.free()
	var station=load("res://assets/mine/props/elevator_station.glb").instantiate();mine.add_child(station);station.position=Vector3(1.25,0,-6.75)
	var player=await avatar()
	var combat=MineCombat.new();var slime=combat._slime({"radius":.85 if guard else .4},false);mine.add_child(slime);combat.free()
	for name in ["HealthFill","HealthTrack","Health"]:slime.get_node(name).visible=false
	if guard:
		var arena=load("res://assets/mine/props/guard_arena.glb").instantiate();mine.add_child(arena);arena.position=Vector3(4.9,0,-3.8)
		slime.position=Vector3(5.2,0,-3.8);player.position.x=3.0;player.position.z=-3.2
		var head=load("res://assets/monsters/slime_king/quartz_cluster.glb").instantiate();slime.add_child(head);head.position.y=1.43*.85;head.scale=Vector3.ONE*.85
		(slime.get_node("Body").material_override as StandardMaterial3D).albedo_color=Color("D7B8CF")
	else:
		slime.position=Vector3(3.7,0,-4.9)
		monster("mob_cave_bat",Vector3(6.0,0,-5.8));monster("mob_shroomling",Vector3(5.3,0,-3.9));monster("mob_rock_beetle",Vector3(7.3,0,-4.2))
		var n=0
		for id in ["iron_ore","quartz","coal","copper_ore"]:
			var root=load("res://assets/mine/rocks/rock_"+id+".glb").instantiate();mine.add_child(root)
			root.position=Vector3(2.2+1.7*n,0,-2.3);BlobShadow.attach(root,.52);n+=1
			if id in ["iron_ore","quartz"]:measured_ores.append(root)
	mine._band=band_rect;mine._focus=Vector3(4.75,0,-.75);mine._zoom=.8;mine._update_camera()
	var name="guard_f40" if guard else "band_"+str(index+1)
	await capture(name)
	mine.backdrop.visible=false;await capture(name+"_without_backdrop");mine.backdrop.visible=true
	if index==0:backdrop_checks()
	if index in [2,3] and not guard:
		# Isolate visible stone-body pixels, then measure ground at those exact pixels.
		for i in measured_ores.size():
			var shader=Shader.new()
			shader.code="shader_type spatial; render_mode unshaded, fog_disabled, cull_disabled; uniform vec3 id_color; void fragment(){ bool stone=COLOR.r<0.3 && COLOR.b>COLOR.r && COLOR.g>COLOR.r; ALBEDO=stone?id_color:vec3(0.0); }"
			var mat=ShaderMaterial.new();mat.shader=shader
			mat.set_shader_parameter("id_color",Vector3(1,0,1) if i==0 else Vector3(0,1,0))
			for mesh in measured_ores[i].find_children("*","MeshInstance3D",true,false):
				if mesh.mesh!=null and mesh.name!="BlobShadow":mesh.material_override=mat
		await capture(name+"_ore_masks")
		for root in measured_ores:root.visible=false
		await capture(name+"_ground_under_ores")
	report.bands.append({"from":band.from,"to":band.to,"guard":guard,"colors":band,"player_height_m":1.745,
		"monsters":["slime","bat","shroomling","rock_beetle"] if not guard else ["quartz_king"],
		"ore_order":["iron_ore","quartz","coal","copper_ore"] if not guard else [],"zoom":.8,"camera_band":[band_rect.position.x,band_rect.position.y,band_rect.size.x,band_rect.size.y]})
	mine.queue_free();await get_tree().process_frame;await get_tree().process_frame

func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	await camera_band()
	vp=SubViewport.new();vp.size=Vector2i(720,1600);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var palette=JSON.parse_string(FileAccess.get_file_as_string("res://assets/mine/types/vein/palette.json"))
	for i in palette.bands.size():await scene(palette.bands[i],i)
	await scene(palette.bands[-1],4,true)
	check(report.bands.size()==5,"All four bands and guard floor captured")
	check(RenderingServer.get_current_rendering_method()=="mobile","Actual Mobile renderer")
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.passed=report.checks.all(func(c):return c.passed)
	var file=FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
	print("VEIN_VALIDATION ",report.passed);vp.queue_free();await get_tree().process_frame
	P0Runtime.free_instance_for_tests();get_tree().quit(0 if report.passed else 1)

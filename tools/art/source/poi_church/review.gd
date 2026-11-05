extends Node
## Locked desktop Mobile review. Independent scene_bench remains unmodified.
const KIT="res://assets/rooms/poi_church/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var room:Node3D
var rig
var ui:Control
var overlay:Node3D
var output:String
var report={"checks":[],"captures":[],"routes":[]}
func _ready():run.call_deferred()
func vec(a):return Vector3(a[0],a[1],a[2])
func xyz(v):return [v.x,v.y,v.z]
func check(ok,label):
	report.checks.append({"check":label,"passed":bool(ok)})
	if not ok:push_error(label)
func setup():
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp);world=Node3D.new();vp.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("DDE8E7")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("FFF0DC");env.ambient_light_energy=.65
	env.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun=DirectionalLight3D.new();world.add_child(sun);sun.position=Vector3(-6,9,3);sun.look_at(Vector3.ZERO)
	sun.light_color=Color("FFF1D8");sun.light_energy=1.0;sun.shadow_enabled=true;sun.shadow_opacity=.5
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;sun.shadow_bias=.05;sun.shadow_normal_bias=.25
	camera=Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;camera.near=.1;camera.far=80;world.add_child(camera)
	room=load("res://scenes/poi_church/poi_church_art.tscn").instantiate();world.add_child(room)
	ui=Control.new();vp.add_child(ui);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay=Node3D.new();world.add_child(overlay);overlay.visible=false
func pose(width,pitch=43.,yaw=45.,focus=Vector3(0,1.4,0)):
	camera.size=width;camera.rotation_degrees=Vector3(-pitch,yaw,0);camera.position=focus+camera.basis.z*24
func points(node):
	var result=PackedVector3Array()
	for child in node.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null:continue
		for s in child.mesh.get_surface_count():
			for v in child.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:result.append(child.global_transform*v)
	return result
func projected(node):
	var vs=points(node);var low=Vector2(INF,INF);var high=-low
	for v in vs:
		var pt=camera.unproject_position(v);low=low.min(pt);high=high.max(pt)
	return Rect2(low,high-low)
func pill(text,at,size):
	var p=Panel.new();p.position=at;p.size=size
	var style=StyleBoxFlat.new();style.bg_color=Color("FFF8E9");style.set_corner_radius_all(12);style.border_color=Color("BCA882");style.set_border_width_all(1);p.add_theme_stylebox_override("panel",style);ui.add_child(p)
	if text!="":
		var label=Label.new();label.text=text;label.position=Vector2(0,0);label.size=size;label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;label.add_theme_color_override("font_color",Color("3C493E"));label.add_theme_font_size_override("font_size",14);p.add_child(label)
	return p
func make_ui():
	for n in ui.get_children():n.free()
	var exit=camera.unproject_position(room.get_node("badge_exit").position)
	var button=pill("",exit-Vector2(18,22),Vector2(36,36))
	# Same door/seat pictograms as the tea room; no words beside seat hooks.
	var icon=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.texture=load("res://review_icons/door.svg");icon.position=Vector2(7,7);icon.size=Vector2(22,22);button.add_child(icon)
	pill("Map",exit+Vector2(-23,16),Vector2(46,24))
	for a in room.layout.anchors:
		if not a.name.begins_with("seat_"):continue
		var at=camera.unproject_position(vec(a.position)+Vector3(0,.25,0))
		var b=pill("",at-Vector2(11,11),Vector2(22,22));var t=TextureRect.new();t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;t.texture=load("res://review_icons/seat.svg");t.position=Vector2(4,4);t.size=Vector2(14,14);b.add_child(t)
	var namepos=camera.unproject_position(rig.position+Vector3.UP*1.98)
	pill("Player",namepos-Vector2(28,0),Vector2(56,22))
	report.exit_ui={"centre":[exit.x,exit.y],"button_and_label_rect":[exit.x-23,exit.y-22,46,62]}
	var allowed=Rect2(0,80,360,650)
	check(allowed.encloses(Rect2(exit-Vector2(23,22),Vector2(46,62))),"Map button/name strip inside safe visible region")
	# Ray from icon anchor to camera is checked separately, as is the front pew silhouette.
	var nearest=room.get_node("pew_left_4");var r=projected(nearest)
	check(not r.intersects(Rect2(exit-Vector2(23,22),Vector2(46,62))),"Nearest left pew does not cover exit button/nameplate")
	var lower_right=Rect2(264,650,96,150);var tall=[]
	for spec in room.layout.assets:
		if spec.review_only or spec.name in ["foundation","outer_steps","grass_surround","entry_landing","labyrinth","stained_light"]:continue
		if projected(room.get_node(spec.name)).intersects(lower_right):tall.append(spec.name)
	for item in room.layout.instances:
		if projected(room.get_node(item.name)).intersects(lower_right):tall.append(item.name)
	check(tall.is_empty(),"Lower-right action zone contains floor only: "+str(tall))
	report.lower_right={"rect":[264,650,96,150],"intersecting_tall_modules":tall}
func geometry():
	var tris=0;var surfaces=0
	for n in room.find_children("*","MeshInstance3D",true,false):
		for s in n.mesh.get_surface_count():tris+=n.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size()/3;surfaces+=1
	var stats=JSON.parse_string(FileAccess.get_file_as_string(KIT+"asset_stats.json"))
	check(tris==stats.scene_triangles and tris<=200000,"Placed triangle budget and manifest match")
	check(surfaces==stats.static_draw_surfaces and surfaces<=60,"Placed surface budget and manifest match")
	check(stats.plant_triangles<=100000,"Plant budget")
	check(room.materials.opaque.albedo_texture.get_size()==Vector2(2048,2048),"One 2048 atlas")
	check(room.materials.light_patch.albedo_color.a<=.35,"Coloured ground light alpha <= .35")
	var seats=room.layout.anchors.filter(func(a):return a.name.begins_with("seat_"))
	check(seats.size()==8,"Eight seats")
	for a in seats:check(abs(a.position[1]-.795)<.00001 and room.has_node(a.module),a.name+" owns actual seat surface")
	for a in room.layout.assets:
		var c=ConfigFile.new();check(c.load(KIT+a.file+".import")==OK,a.name+" import")
		check(str(c.get_value("remap","uid","")).begins_with("uid://"),a.name+" Godot import UID")
		check(c.get_value("params","gltf/texture_map_mode",0)==1,a.name+" texture_map_mode 1")
	report.geometry={"triangles":tris,"surfaces":surfaces,"plant_triangles":stats.plant_triangles}
func query(point,radius):
	var shape=CapsuleShape3D.new();shape.radius=radius;shape.height=1.745
	var q=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.margin=.001;q.transform.origin=point+Vector3.UP*.873;return q
func routes():
	await get_tree().physics_frame
	var space=world.get_world_3d().direct_space_state
	# The shared bench's fallback blocker ray is at torso height; independently
	# measure the low three-step plinth at 0.28 m above the model origin.
	var low_ray=PhysicsRayQueryParameters3D.create(Vector3(-1.84,.28,-1.84),Vector3(-3.1,.28,-3.1))
	var low_hit=space.intersect_ray(low_ray)
	check(not low_hit.is_empty() and str(low_hit.collider.get_path()).contains("sanctuary_steps"),"Actual low sanctuary step blocks at shin height")
	for group in [[room.layout.preflight.routes,.25],[room.layout.preflight.main_routes,.39]]:
		for route in group[0]:
			var bad=[]
			for i in range(route.points_xz.size()-1):
				var a=route.points_xz[i];var b=route.points_xz[i+1];var at=Vector3(a[0],.085,a[1]);var end=Vector3(b[0],.085,b[1]);var q=query(at,group[1]);q.motion=end-at
				if not space.intersect_shape(query(at,group[1]),1).is_empty() or space.cast_motion(q)[0]<.999:bad.append(i)
			check(bad.is_empty(),route.name+" capsule radius "+str(group[1]))
			report.routes.append({"name":route.name,"radius":group[1],"failed_segments":bad})
func avatar():
	rig=Avatar.create_rig()
	for c in rig.get_children():
		if c is RigActivity:c.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Default avatar assembled")
	rig.play_motion("idle");var anim=rig.get_node("AnimationPlayer");anim.seek(.3,true);anim.pause()
	var low=INF;var high=-INF
	for n in rig.find_children("*","MeshInstance3D",true,false):
		if not n.is_visible_in_tree() or n.mesh==null:continue
		var m=n.bake_mesh_from_current_skeleton_pose() if n.skin!=null else n.mesh
		for s in m.get_surface_count():
			for v in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var q=rig.global_transform.affine_inverse()*n.global_transform*v;low=minf(low,q.y);high=maxf(high,q.y)
	rig.scale=Vector3.ONE*1.745/(high-low);rig.position=vec(room.layout.spawn)-Vector3.UP*low*rig.scale.y;rig.rotation_degrees.y=225
	report.avatar={"height_m":1.745,"scale":rig.scale.y}
func capture(name):
	for i in 5:await RenderingServer.frame_post_draw
	var im=vp.get_texture().get_image();check(im.save_png(output+"/"+name+".png")==OK,"capture "+name)
	report.captures.append({"name":name,"width_m":camera.size,"size":[vp.size.x,vp.size.y],"pitch":-camera.rotation_degrees.x})
	print("CHURCH_CAPTURE ",name)
func top_markers():
	for a in room.layout.anchors:
		if a.name.begins_with("seat_") or a.name in ["spawn","exit"]:
			var label=Label3D.new();label.text=a.name;label.font_size=32;label.pixel_size=.004;label.position=vec(a.position)+Vector3.UP*.2;label.rotation_degrees.x=-90;label.no_depth_test=true;overlay.add_child(label)
	for item in [["Central aisle 1.60 m",Vector3(0,.15,0)],["Entry 1.40 m",Vector3(2,.15,5.25)],["Row gap 0.85 m",Vector3(-1.2,.15,1.6)]]:
		var label=Label3D.new();label.text=item[0];label.font_size=32;label.pixel_size=.005;label.position=item[1];label.rotation_degrees.x=-90;label.no_depth_test=true;overlay.add_child(label)
func run():
	output=ProjectSettings.globalize_path("res://../captures");DirAccess.make_dir_recursive_absolute(output)
	setup();geometry();await avatar();await routes();pose(6.72);make_ui()
	await capture("default_360")
	var spawn_pose=rig.position;rig.position.x=4.15*sqrt(.5);rig.position.z=4.15*sqrt(.5);make_ui()
	await capture("labyrinth_readability");rig.position=spawn_pose;make_ui();ui.visible=false
	await capture("default_clean")
	# A magenta background control proves coverage rather than similar colour.
	var we=world.find_children("*","WorldEnvironment",true,false)[0];var previous=we.environment.background_color
	we.environment.background_color=Color(1,0,1);await capture("coverage_magenta");we.environment.background_color=previous
	vp.size=Vector2i(1400,1200);pose(19,43,45,Vector3(0,2.25,0));await capture("overview")
	rig.visible=false;top_markers();overlay.visible=true
	for name in ["west_wall","north_wall","apse","rose_window","chandelier_left","chandelier_right"]:room.get_node(name).visible=false
	vp.size=Vector2i(1400,1400);pose(14.8,90,0,Vector3(0,0,.4));await capture("topdown")
	for name in ["west_wall","north_wall","apse","rose_window","chandelier_left","chandelier_right"]:room.get_node(name).visible=true
	overlay.visible=false;rig.visible=true;room.visible=false
	var tea=load("res://scenes/tea_house/tea_house_art.tscn").instantiate();world.add_child(tea)
	rig.position=Vector3(.30,.08,2.55);rig.rotation_degrees.y=180
	vp.size=Vector2i(360,800);pose(6.72,43,45,Vector3(.10,1.1,.4));await capture("tea_same_scale")
	tea.free();room.visible=true
	report.renderer={"method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()}
	report.passed=report.checks.all(func(c):return c.passed)
	FileAccess.open(output+"/godot-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("CHURCH_VALIDATION ",report.passed);get_tree().quit(0 if report.passed else 1)

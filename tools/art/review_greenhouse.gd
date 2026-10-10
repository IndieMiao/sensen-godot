extends Node
## Offline art-only fixture. No p0_farm_facilities or production data dependency.
const Art=preload("res://modules/farm/farm_art.gd")
const IDS=["greenhouse_base","greenhouse_roof","greenhouse_glass"]
const POST_CENTRE=2.475
const BED_SIZE=.65
const BED_PITCH=1.3
const COVERED_BLOCK=4.55
var vp:SubViewport
var world:Node3D
var cam:Camera3D
var rig:AvatarRig
var base:MeshInstance3D
var roof:MeshInstance3D
var glass:MeshInstance3D
var pane_material:StandardMaterial3D
var crop_stage:Node3D
var soil_stage:Node3D
var grid_stage:Node3D
var report={"checks":[],"assets":[],"captures":[]}
var out:String
var title:Label
var note:Label

func _ready():_run.call_deferred()
func check(ok:bool,message:String):
	report.checks.append({"check":message,"passed":ok})
	if not ok:push_error(message)

func mat(c:Color)->StandardMaterial3D:
	var m=StandardMaterial3D.new();m.albedo_color=c;m.roughness=.9;return m

func solid(parent:Node3D,mesh:Mesh,at:Vector3,material:Material)->MeshInstance3D:
	var node=MeshInstance3D.new();node.mesh=mesh;node.position=at;node.material_override=material
	parent.add_child(node);return node

func _run():
	out=ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(out)
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/art/manifest.json"))
	var total=0
	var entry_clearance=INF
	for id in IDS:
		var scene=load("res://assets/farm/art/"+id+".glb").instantiate()
		var nodes=scene.find_children("*","MeshInstance3D",true,false)
		if scene is MeshInstance3D:nodes.push_front(scene)
		var mesh:Mesh=Art.mesh_for(id)
		var box=mesh.get_aabb()
		var triangles=mesh.get_faces().size()/3
		total+=triangles
		var entry=manifest.assets[id]
		var all_faces=mesh.get_faces()
		for i in range(0,all_faces.size(),3):
			var tri=AABB(all_faces[i],Vector3.ZERO).expand(all_faces[i+1]).expand(all_faces[i+2])
			for axis in 2:
				for side in [-1,1]:
					var zone=AABB(Vector3(-.65,0,side*POST_CENTRE-.10),Vector3(1.3,3,.20)) if axis==0 else AABB(Vector3(side*POST_CENTRE-.10,0,-.65),Vector3(.20,3,1.3))
					if tri.intersects(zone):entry_clearance=minf(entry_clearance,tri.position.y)
		check(nodes.size()==1,id+": one merged mesh")
		check(mesh.get_surface_count()==1,id+": one surface")
		check(triangles==int(entry.triangles) and triangles<=int(entry.triangle_limit),id+": triangle budget and manifest")
		check(scene.transform.is_equal_approx(Transform3D.IDENTITY),id+": shared ground origin, root transform identity")
		check(nodes[0].transform.is_equal_approx(Transform3D.IDENTITY),id+": mesh local transform identity")
		check(box.position.x>=-2.62501 and box.end.x<=2.62501 and box.position.z>=-2.62501 and box.end.z<=2.62501,id+": physical bounds within 5.25 m including 0.30 m feet")
		check(entry.footprint==[4.95,4.95] and is_equal_approx(entry.covered_block_m,COVERED_BLOCK),id+": nominal 4.95 m frame span and 4.55 m covered block")
		var colors:PackedColorArray=mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var opaque=not colors.is_empty()
		for c in colors:opaque=opaque and is_equal_approx(c.a,1)
		check(opaque,id+": opaque vertex colors, runtime controls opacity")
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]==null,id+": no texture coordinates")
		var lo=entry.bounds[0];var hi=entry.bounds[1]
		check(box.position.distance_to(Vector3(lo[0],lo[1],lo[2]))<.00001 and box.end.distance_to(Vector3(hi[0],hi[1],hi[2]))<.00001,id+": bounds match manifest")
		report.assets.append({"id":id,"triangles":triangles,"surfaces":1,"bounds_min":[box.position.x,box.position.y,box.position.z],"bounds_max":[box.end.x,box.end.y,box.end.z]})
		if id=="greenhouse_base":
			var socket=scene.find_child("roof_center",true,false)
			check(socket!=null,"roof_center exists on base")
			check(socket.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,float(entry.ridge_height)-.12,0))),"roof_center position and +Z orientation")
			check(absf(box.position.y)<.00001,"Base sits on y=0")
			check(absf(box.end.y-float(entry.eave_height))<.00001,"Base contains no ridge or rafters above the eave")
			# All low geometry is localized to corners. The central entrances are empty.
			var clear=true
			var faces=mesh.get_faces()
			for i in range(0,faces.size(),3):
				var tri=AABB(faces[i],Vector3.ZERO).expand(faces[i+1]).expand(faces[i+2])
				if tri.position.y>=.8:continue
				if tri.position.x<.65 and tri.end.x>-.65:clear=false
				if tri.position.z<.65 and tri.end.z>-.65:clear=false
			check(clear,"All four central 1.3 m entry strips have no low geometry or ground beams")
			check_bed_clearance(mesh)
			report.eave_underside_m=entry.eave_underside
		if id=="greenhouse_glass":
			check(triangles==6,"Exactly four single-thickness glass panels: 2 quads and 2 triangles")
			var faces=mesh.get_faces();var normal_ok=true
			for i in range(0,faces.size(),3):
				var center=(faces[i]+faces[i+1]+faces[i+2])/3
				var n=(faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized()
				# Godot uses clockwise front winding; normal is outward/upward.
				if absf(n.y)>.1:normal_ok=normal_ok and n.y>0
				else:normal_ok=normal_ok and n.z*center.z>0
			check(normal_ok,"Glass front faces point outward/upward")
		scene.free()
	check(total<=3000,"Combined triangle budget <= 3000")
	check(entry_clearance>=1.7999,"Four central 1.3 m entrances have at least 1.80 m geometric clearance")
	report.minimum_mid_entry_clearance_m=entry_clearance
	report.scale_avatar_height_m=1.745
	report.clearance_margin_m=entry_clearance-1.745
	check(Art.material().vertex_color_use_as_albedo and not Art.material().vertex_color_is_srgb,"FarmArt shared vertex-color material")
	report.total_triangles=total
	vp=SubViewport.new();vp.size=Vector2i(1800,1500);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp);world=Node3D.new();vp.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e7eddf")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.79,.88,.94);env.environment.ambient_light_energy=.42
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-51,-38,0)
	sun.light_color=Color(1,.96,.87);sun.light_energy=1.1;sun.shadow_enabled=true
	sun.shadow_opacity=.58;sun.shadow_bias=.10;sun.shadow_normal_bias=1.0
	sun.light_angular_distance=1;sun.directional_shadow_max_distance=30;world.add_child(sun)
	var floor_mesh=PlaneMesh.new();floor_mesh.size=Vector2(50,50)
	solid(world,floor_mesh,Vector3(0,-.008,0),mat(Color("dbe3ce")))
	base=Art.instance(IDS[0]);roof=Art.instance(IDS[1]);glass=Art.instance(IDS[2])
	world.add_child(base);world.add_child(roof);world.add_child(glass)
	pane_material=Art.material().duplicate();pane_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	pane_material.albedo_color.a=.25;pane_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	glass.material_override=pane_material;glass.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check(base.material_override==Art.material() and roof.material_override==Art.material(),"Base and roof share unmodified FarmArt.material()")
	check(Art.material().transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Glass material duplication does not change shared farm material")
	make_plots()
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.free()
	rig.assembler=AvatarAssemblerMerged.new();world.add_child(rig)
	rig.position=Vector3(-3.70,0,.65);rig.apply_config(Avatar.slot_table.default_config())
	var ticks=0
	while rig.is_busy() and ticks<900:await get_tree().process_frame;ticks+=1
	check(not rig.is_busy(),"Existing scale avatar assembled")
	rig.play_motion("idle");var ap=rig.get_node("AnimationPlayer");ap.seek(.3,true);ap.pause()
	cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.keep_aspect=Camera3D.KEEP_WIDTH
	cam.size=9.2;cam.near=.1;cam.far=70;cam.current=true;world.add_child(cam)
	var canvas=CanvasLayer.new();vp.add_child(canvas)
	title=Label.new();title.position=Vector2(64,48);title.add_theme_font_size_override("font_size",35)
	title.add_theme_color_override("font_color",Color("394532"));canvas.add_child(title)
	note=Label.new();note.position=Vector2(64,1420);note.add_theme_font_size_override("font_size",22)
	note.add_theme_color_override("font_color",Color("4a503f"));canvas.add_child(note)
	cam.rotation_degrees=Vector3(-43,25,0);cam.position=Vector3(-.18,.75,0)+cam.basis.z*20
	title.text="GREENHOUSE / 43 DEG / GLASS 25%"
	note.text="R2 v1.4 | FRAME SPAN 4.95 m / BEDS 4.55 m | 1,862 TRIS | GODOT MOBILE | AVATAR 1.745 m"
	await capture("greenhouse-43deg-normal")
	pane_material.albedo_color.a=.10
	title.text="GREENHOUSE / 43 DEG / GLASS 10%"
	await capture("greenhouse-43deg-glass10")
	roof.visible=false;glass.visible=false;rig.visible=false;crop_stage.visible=false;soil_stage.visible=true;grid_stage.visible=true
	cam.size=7.4;cam.rotation_degrees=Vector3(-90,0,0);cam.position=Vector3(0,20,0)
	title.text="GREENHOUSE / TOP / BASE ONLY"
	note.text="4 x 4 BEDS + PLACEMENT COLOURS | POSTS AT +/-2.475 m | ROOF + GLASS HIDDEN"
	await capture("greenhouse-top-base")
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.failures=report.checks.filter(func(item):return not item.passed)
	FileAccess.open(out+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("GREENHOUSE_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	get_tree().quit(0 if report.failures.is_empty() else 1)

func make_plots():
	soil_stage=Node3D.new();crop_stage=Node3D.new();grid_stage=Node3D.new()
	world.add_child(soil_stage);world.add_child(crop_stage);world.add_child(grid_stage);grid_stage.visible=false
	var soil=mat(Color("997046"));var leaf_mat=mat(Color("70984d"));var young_mat=mat(Color("95b65c"))
	var green=mat(Color("b6cc98"));var red=mat(Color("d3a299"))
	for row in 4:
		for col in 4:
			var p=Vector3((col-1.5)*BED_PITCH,0,(row-1.5)*BED_PITCH)
			var bed=Art.instance("plot",p,BED_SIZE/.94);bed.material_override=soil;soil_stage.add_child(bed)
			var cell=PlaneMesh.new();cell.size=Vector2(.51,.51)
			solid(grid_stage,cell,p+Vector3(0,.110,0),red if row==1 and col==2 else green)
			# Existing crops are outside this asset PR. Simple labeled fixture plants show transparency.
			for i in 3:
				var leaf=SphereMesh.new();leaf.radius=.09;leaf.height=.27;leaf.radial_segments=8;leaf.rings=3
				var node=solid(crop_stage,leaf,p+Vector3(.08*cos(i*TAU/3),.23,.08*sin(i*TAU/3)),leaf_mat if (col+row)%2==0 else young_mat)
				node.rotation=Vector3(.5*cos(i*TAU/3),0,.5*sin(i*TAU/3))

func check_bed_clearance(mesh:Mesh):
	# A disjoint projected triangle AABB guarantees no geometry over that bed.
	# Include eaves, braces, vine and can, not only the posts and their plinths.
	var faces=mesh.get_faces()
	var overlaps=0
	var minimum_gap=INF
	for i in range(0,faces.size(),3):
		var tri=AABB(faces[i],Vector3.ZERO).expand(faces[i+1]).expand(faces[i+2])
		for row in 4:
			for col in 4:
				var centre=Vector2((col-1.5)*BED_PITCH,(row-1.5)*BED_PITCH)
				var lower=centre-Vector2.ONE*BED_SIZE/2
				var upper=centre+Vector2.ONE*BED_SIZE/2
				var dx=maxf(0,maxf(lower.x-tri.end.x,tri.position.x-upper.x))
				var dz=maxf(0,maxf(lower.y-tri.end.z,tri.position.z-upper.y))
				minimum_gap=minf(minimum_gap,Vector2(dx,dz).length())
				if dx==0 and dz==0:overlaps+=1
	check(overlaps==0,"Base triangle projections clear all 16 beds, including eaves, vine and can")
	check(minimum_gap>=.0499,"Every base triangle stays at least 0.05 m from covered beds in plan")
	report.bed_projection_overlap_count=overlaps
	report.minimum_projected_bed_gap_m=minimum_gap
	report.corner_feet=[]
	for sx in [-1,1]:
		for sz in [-1,1]:
			var points:PackedVector3Array=[]
			for p in faces:
				if p.y<.23 and p.x*sx>2.2 and p.z*sz>2.2:points.append(p)
			check(not points.is_empty(),"Corner foot exists: %d,%d"%[sx,sz])
			if points.is_empty():continue
			var bounds=AABB(points[0],Vector3.ZERO)
			for p in points:bounds=bounds.expand(p)
			var centre=bounds.get_center()
			# Retained Godot mesh compression quantizes some vertices by ~0.1 mm.
			check(absf(centre.x-sx*POST_CENTRE)<.0001 and absf(centre.z-sz*POST_CENTRE)<.0001,"Corner foot centre matches +/-2.475 m within 0.1 mm: %d,%d"%[sx,sz])
			check(bounds.size.x<=.30001 and bounds.size.z<=.30001,"Corner post and foot projection <= 0.30 m square: %d,%d"%[sx,sz])
			report.corner_feet.append({"centre_xz":[centre.x,centre.z],"projection_m":[bounds.size.x,bounds.size.z]})
	var box=mesh.get_aabb()
	var adjacent_gap=2.925-maxf(maxf(absf(box.position.x),absf(box.end.x)),maxf(absf(box.position.z),absf(box.end.z)))
	check(adjacent_gap>=.2999,"Base stays at least 0.30 m inside adjacent bed edges at +/-2.925 m")
	report.adjacent_bed_edge_gap_m=adjacent_gap

func capture(id:String):
	for i in 8:await RenderingServer.frame_post_draw
	var im=vp.get_texture().get_image();check(im.save_png(out+"/"+id+".png")==OK,"Capture saved: "+id)
	report.captures.append({"id":id,"size":[im.get_width(),im.get_height()],"pitch_degrees":-cam.rotation_degrees.x,"glass_alpha":pane_material.albedo_color.a,"roof_visible":roof.visible})
	print("GREENHOUSE_CAPTURE ",id)

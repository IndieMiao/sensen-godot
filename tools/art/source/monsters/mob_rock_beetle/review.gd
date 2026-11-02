extends Node
const KIT := "res://assets/monsters/mob_rock_beetle/"
const MODEL := KIT + "mob_rock_beetle.glb"
const OUT := "res://../captures/"
var vp: SubViewport
var world: Node3D
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var mesh: MeshInstance3D
var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var spec: Dictionary
var checks := []
var report := {"animations":{}, "captures":[]}
var elapsed := 0.0

func _ready() -> void: run.call_deferred()
func _process(dt: float) -> void:
	elapsed += dt
	if elapsed > 180: get_tree().quit(2)

func check(ok: bool, label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok: push_error(label)

func aim(target: Vector3, width: float, yaw: float, pitch: float) -> void:
	camera.size = width
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	camera.position = target + Vector3(sin(y)*cos(p), sin(p), cos(y)*cos(p))*18
	camera.look_at(target)

func apply_pose(name_: String, seconds: float) -> void:
	player.play(name_)
	player.seek(seconds,true)
	player.advance(0)
	skeleton.force_update_all_bone_transforms()

func save_view(name_: String) -> void:
	for i in 5:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	var image := vp.get_texture().get_image()
	check(image.save_png(OUT+name_+".png") == OK,name_+" screenshot")
	report.captures.append({"name":name_,"size":[vp.size.x,vp.size.y],"camera":str(camera.transform),"width_m":camera.size})

func poses() -> Array:
	var result := []
	for i in skeleton.get_bone_count(): result.append(skeleton.get_bone_global_pose(i))
	return result

func difference(a: Array, b: Array) -> float:
	var result := 0.0
	for i in a.size():
		result = maxf(result,a[i].origin.distance_to(b[i].origin))
		result = maxf(result,(a[i].basis.x-b[i].basis.x).length())
		result = maxf(result,(a[i].basis.y-b[i].basis.y).length())
	return result

func validate() -> void:
	check(model.find_children("*","Skeleton3D",true,false).size()==1,"one skeleton")
	check(skeleton.get_bone_count()==11,"11 bones")
	check(skeleton.find_bone("root")>=0,"named root")
	check(model.find_children("*","MeshInstance3D",true,false).size()==1,"one skinned mesh")
	check(mesh.mesh.get_surface_count()==1,"one surface")
	check(mesh.skin != null and mesh.skin.get_bind_count()==11,"11 skin binds")
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var count: int = arrays[Mesh.ARRAY_INDEX].size()/3
	report.triangles = count
	check(count<=1500,"triangle budget")
	check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"model casts no real shadow")
	var material := mesh.get_active_material(0) as StandardMaterial3D
	check(material != null and material.vertex_color_use_as_albedo,"imported vertex colors enabled")
	check(not material.resource_path.ends_with(".tres"),"shared import fix enables embedded material")
	report.material = {"vertex_colors":material.vertex_color_use_as_albedo,"roughness":material.roughness,"specular":material.metallic_specular}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	check(uv.size()==vertices.size() and colors.size()==vertices.size(),"vertex colors and UV2 retained")
	var rigid := weights.size()==vertices.size()*4
	for i in vertices.size():
		var ones := 0
		var sum := 0.0
		for j in 4:
			var w := weights[i*4+j]
			sum += w
			if absf(w-1)<.0001: ones += 1
		rigid = rigid and ones==1 and absf(sum-1)<.0001
	check(rigid,"every vertex has exactly one weight of one")
	var mask_zero := 0
	var mask_one := 0
	for value in uv:
		if is_equal_approx(value.x,0): mask_zero+=1
		elif is_equal_approx(value.x,1): mask_one+=1
	check(mask_zero>0 and mask_one>0 and mask_zero+mask_one==vertices.size(),"binary UV2.x tint mask")
	report.tint_vertices = {"protected":mask_zero,"tintable":mask_one}
	var names: Array[String] = []
	for name_ in player.get_animation_list():
		if name_!="RESET": names.append(name_)
	check(names.size()==8 and spec.anims.keys().all(func(n): return n in names),"all eight final action names")
	check(spec.has("hit_point") and not spec.has("hurt_point") and spec.hit_point.size()==3,"client hit_point key")
	check(spec.durations.size()==8 and names.all(func(n): return spec.durations.has(n)),"client durations cover all actions")
	check(is_equal_approx(float(spec.hit_at),float(spec.anims.attack.hit_at)),"top-level hit_at matches attack contact")
	var root_i := skeleton.find_bone("root")
	apply_pose("idle",0)
	var root_pose := skeleton.get_bone_global_pose(root_i)
	for name_ in spec.anims:
		var clip := player.get_animation(name_)
		var data: Dictionary = spec.anims[name_]
		check(absf(clip.length-float(spec.durations[name_]))<.002,name_+" duration matches client JSON")
		check((clip.loop_mode==Animation.LOOP_LINEAR)==bool(data.get("loop",false)),name_+" loop matches JSON")
		var snapshots := []
		var stable_root := true
		for t in [0.0,.25,.5,.75,.999]:
			apply_pose(name_,t*clip.length)
			snapshots.append(poses())
			stable_root = stable_root and skeleton.get_bone_global_pose(root_i).is_equal_approx(root_pose)
		var movement := 0.0
		for p in snapshots: movement=maxf(movement,difference(snapshots[0],p))
		check(movement>.002,name_+" changes bone poses")
		check(stable_root and model.position==Vector3.ZERO,name_+" has no root motion")
		report.animations[name_]={"length":clip.length,"loop":clip.loop_mode==Animation.LOOP_LINEAR,"pose_delta":movement,"root_static":stable_root}
	check(float(spec.anims.windup.length)>=.4 and float(spec.anims.windup.length)<=.7,"readable windup window")
	check(float(spec.anims.attack.hit_at)>0 and float(spec.anims.attack.hit_at)<float(spec.anims.attack.length),"attack hit time inside clip")
	var config := ConfigFile.new()
	check(config.load(MODEL+".import")==OK,"import config readable")
	var uid := str(config.get_value("remap","uid",""))
	check(uid.begins_with("uid://") and ResourceUID.has_id(ResourceUID.text_to_id(uid)),"Godot-generated UID resolves")
	check(config.get_value("params","gltf/texture_map_mode",-1)==1,"texture map mode one")
	report.uid=uid

func run() -> void:
	if DisplayServer.get_name()=="headless": get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	vp=SubViewport.new()
	vp.size=Vector2i(720,720)
	vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var preview := TextureRect.new()
	preview.texture=vp.get_texture()
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	world=Node3D.new(); vp.add_child(world)
	var environment:=WorldEnvironment.new()
	env=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("DBE0DF")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("FFF5E8")
	env.ambient_light_energy=.65
	environment.environment=env
	world.add_child(environment)
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_color=Color("FFF1DC")
	sun.light_energy=1.05
	world.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.near=.1;camera.far=40
	world.add_child(camera);camera.make_current()
	model=load(MODEL).instantiate();world.add_child(model)
	skeleton=model.find_children("*","Skeleton3D",true,false)[0]
	player=model.find_children("*","AnimationPlayer",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	mesh=model.find_children("*","MeshInstance3D",true,false)[0]
	spec=JSON.parse_string(FileAccess.get_file_as_string(KIT+"mob_rock_beetle.json"))
	for i in 5: await get_tree().process_frame
	validate()
	apply_pose("idle",0)
	for view in [["front",0.0,0.0],["side",90.0,0.0],["top",0.0,89.99],["hero",35.0,35.0]]:
		aim(Vector3(0,.23,0),1.25,view[1],view[2])
		await save_view(view[0])
	aim(Vector3(0,.30,0),1.45,30,30)
	for name_ in spec.anims:
		var t: float = spec.anims[name_].length*.45
		if name_=="attack": t=float(spec.anims[name_].hit_at)
		if name_=="die": t=float(spec.anims[name_].length)
		apply_pose(name_,t)
		await save_view("action_"+name_)
	for i in 4:
		apply_pose("stunned",i*.25)
		await save_view("stunned_%d"%i)
	apply_pose("idle",0)
	await tint_check()
	await mine_view()
	report.checks=checks
	report.passed=checks.all(func(c): return c.passed)
	report.renderer=RenderingServer.get_current_rendering_method()
	report.adapter=RenderingServer.get_video_adapter_name()
	FileAccess.open(OUT+"validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("BEETLE_GODOT ",report.passed," checks=",checks.size()," triangles=",report.triangles)
	get_tree().quit(0 if report.passed else 1)

func tint_check() -> void:
	aim(Vector3(0,.23,0),1.25,0,0)
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform float amount=0.0; void fragment(){ ALBEDO=COLOR.rgb*mix(vec3(1.0),vec3(1.5,0.6,1.2),UV2.x*amount); ROUGHNESS=0.78; SPECULAR=0.28; }"
	var material := ShaderMaterial.new()
	material.shader=shader
	mesh.material_override=material
	await save_view("tint_base")
	material.set_shader_parameter("amount",1.0)
	await save_view("tint_changed")
	mesh.material_override=null
	var a: Array=mesh.mesh.surface_get_arrays(0)
	var sum:=Vector3.ZERO
	var count:=0
	for i in a[Mesh.ARRAY_VERTEX].size():
		var c: Color=a[Mesh.ARRAY_COLOR][i]
		var v: Vector3=a[Mesh.ARRAY_VERTEX][i]
		if c.r<.05 and c.g<.05 and c.b<.05 and v.x>0:
			sum+=v;count+=1
	check(count>0,"protected eye vertices found")
	var pixel:=camera.unproject_position(sum/maxi(count,1))
	report.tint_eye_pixel=[pixel.x,pixel.y]

func mine_view() -> void:
	var art = load("res://modules/mining/mine_art.gd")
	var mine: Node3D = art.floor_scenery(3,true)
	world.add_child(mine)
	model.position=Vector3(4.2,0,-3.2)
	BlobShadow.attach(model,.45)
	var combat = load("res://modules/mining/mine_combat.gd").new()
	world.add_child(combat)
	var slime: Node3D = combat._slime({"radius":.4},false)
	world.add_child(slime);slime.position=Vector3(5.4,0,-3.2)
	for n in ["Health","HealthFill","HealthTrack","Warning"]: slime.get_node(n).visible=false
	var avatar = get_node("/root/Avatar")
	var rig = avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: rig.remove_child(child);child.free()
	rig.assembler=AvatarAssemblerMerged.new()
	world.add_child(rig)
	var oa=load("res://modules/net/online_appearance.gd")
	rig.apply_config(oa.config({"version":1,"slots":{"hairHat":"hairhat1","cloth":"cloth1","shoes":"shoes1"}},true))
	rig.position=Vector3(3.0,0,-3.2)
	var frames:=0
	while rig.is_busy() and frames<240:
		frames+=1;await get_tree().process_frame
	check(not rig.is_busy() and rig.find_children("*","MeshInstance3D",true,false).size()>0,"actual player rig loaded in mine comparison")
	rig.play_motion("idle")
	env.background_color=Color("26232A")
	env.ambient_light_color=Color("e8dfea")
	env.ambient_light_energy=.48
	sun.rotation_degrees=Vector3(-51,-38,0)
	sun.light_color=Color("ffe8ce");sun.light_energy=1.15
	sun.shadow_enabled=true
	sun.shadow_opacity=.58;sun.shadow_bias=.04;sun.shadow_normal_bias=.45
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	aim(Vector3(4.2,.45,-3.2),6.72,45,43)
	vp.size=Vector2i(360,800)
	await save_view("mine_360")
	vp.size=Vector2i(720,1600)
	await save_view("mine_720")
	report.mine={"floor":3,"renderer_source":"Unmodified farm-dev MineArt + MineCombat slime + Avatar rig","camera_pitch":43,"camera_width":6.72,"slime_radius":.4,"beetle_radius":.45}

extends Node
const ART=preload("res://modules/mining/mine_art.gd")
const CAMERA=preload("res://modules/farm/farm_camera.gd")
const OUT="res://../captures/"
var vp: SubViewport
var mine: Node3D
var fixtures: Node3D
var coal: Node3D
var ui: P0Ui
var checks:=[]
var report:={"captures":[],"bands":[]}

class Probe extends "res://scenes/p0/p0_mine.gd":
	func _ready() -> void: _build_light()
	func _view() -> Dictionary: return {}
	func _process(_dt: float) -> void: pass
	func _physics_process(_dt: float) -> void: pass

func _ready() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok: push_error(label)

func capture(name_: String) -> void:
	for i in 8:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	var image:=vp.get_texture().get_image()
	check(image.save_png(OUT+name_+".png")==OK,name_+" screenshot")
	report.captures.append({"name":name_,"size":[image.get_width(),image.get_height()],
		"camera_transform":str(mine.cam.global_transform),"width_m":mine.cam.size,"near":mine.cam.near,"far":mine.cam.far})

func add_asset(path: String,at: Vector3,radius: float) -> Node3D:
	var model: Node3D=load(path).instantiate()
	fixtures.add_child(model);model.position=at
	for child in model.find_children("*","AnimationPlayer",true,false):
		var player:=child as AnimationPlayer
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if player.has_animation("idle"):
			player.play("idle");player.seek(0,true);player.advance(0)
	if radius>0: BlobShadow.attach(model,radius)
	return model

func populate() -> void:
	fixtures=Node3D.new();mine.add_child(fixtures)
	for i in 4:
		var name_: String=["rock_iron_ore","rock_quartz","rock_coal","rock_copper_ore"][i]
		var rock:=add_asset("res://assets/mine/rocks/"+name_+".glb",Vector3(2.6+i*1.4,0,-2.8),.52)
		if name_=="rock_coal": coal=rock
	add_asset("res://assets/monsters/mob_rock_beetle/mob_rock_beetle.glb",Vector3(4.1,0,-4.8),.725)
	add_asset("res://assets/monsters/mob_shroomling/mob_shroomling.glb",Vector3(5.5,0,-4.8),.32)
	add_asset("res://assets/monsters/mob_cave_bat/mob_cave_bat.glb",Vector3(6.35,0,-4.8),.35)
	var combat=load("res://modules/mining/mine_combat.gd").new()
	fixtures.add_child(combat)
	var slime: Node3D=combat._slime({"radius":.4},false)
	fixtures.add_child(slime);slime.position=Vector3(2.75,0,-4.8)
	for name_ in ["Health","HealthFill","HealthTrack","Warning"]: slime.get_node(name_).visible=false
	var rig=get_node("/root/Avatar").create_rig()
	for child in rig.get_children():
		if child is RigActivity: rig.remove_child(child);child.free()
	rig.assembler=AvatarAssemblerMerged.new();fixtures.add_child(rig)
	var appearance=load("res://modules/net/online_appearance.gd")
	rig.apply_config(appearance.config({"version":1,"slots":{"hairHat":"hairhat1","cloth":"cloth1","shoes":"shoes1"}},true))
	rig.position=Vector3(4.75,0,-.75)
	var frames:=0
	while rig.is_busy() and frames<240:
		frames+=1;await get_tree().process_frame
	check(not rig.is_busy(),"actual player rig loaded")
	rig.play_motion("idle")
	for player in rig.find_children("*","AnimationPlayer",true,false):
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.seek(0,true);player.advance(0)

func check_backdrop() -> void:
	var meshes: Array=mine.backdrop.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==1,"single imported backdrop mesh")
	var mesh:=meshes[0] as MeshInstance3D
	check(mesh.mesh.get_surface_count()==1,"single imported surface")
	var arrays: Array=mesh.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_INDEX].size()/3<=4000,"imported triangle budget")
	check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"backdrop casts no shadow")
	var material:=mesh.material_override as ShaderMaterial
	check(is_equal_approx(float(material.get_shader_parameter("vein_mask")),1.0),"types backdrop explicitly uses vein_mask=1")
	report.vein_mask=material.get_shader_parameter("vein_mask")
	var masks: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var zero:=true
	for uv in masks: zero=zero and absf(uv.y)<.0001
	check(zero,"Godot UV2.y zero")
	check(mine.backdrop.find_children("*","CollisionObject3D",true,false).is_empty(),"no backdrop collision")
	var config:=ConfigFile.new()
	check(config.load("res://assets/mine/types/quarry/backdrop.glb.import")==OK,"import config readable")
	var uid:=str(config.get_value("remap","uid",""))
	check(uid.begins_with("uid://") and ResourceUID.has_id(ResourceUID.text_to_id(uid)),"generated UID resolves")
	check(config.get_value("params","import_script/path","missing")=="","no monster material import script")
	check(config.get_value("params","gltf/texture_map_mode",0)==1,"texture map mode one")
	report.uid=uid

func run() -> void:
	if DisplayServer.get_name()=="headless": get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	vp=SubViewport.new();vp.size=Vector2i(360,800);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
	var preview:=TextureRect.new();preview.texture=vp.get_texture();preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(preview)
	ui=P0Ui.new();ui.quick_store="user://quarry_art_review_quick.json";vp.add_child(ui)
	await get_tree().process_frame
	ui.set_view({"energy":{"value":200,"max":200,"next_in":null,"regen_ms":240000},"bag":{"capacity":25,"free":25,"slots":[{"id":"torch","qty":2}]},"plots":[],"coins":40,"skills":{},"rest":{"used":0,"limit":1,"resets_in":1},"inbox":{"parcels":[],"letters":[]}})
	ui.set_mode("mine");ui.set_surface("mine")
	await get_tree().process_frame
	var band:=ui.camera_band();ui.visible=false
	mine=Probe.new();vp.add_child(mine)
	for index in 4:
		vp.size=Vector2i(360,800)
		ART.qa_band=index;ART._floor_cache.clear();MineBackdrop.qa_band=index
		if is_instance_valid(fixtures): fixtures.free()
		mine._build_floor(1)
		for node in mine.objects.get_children():
			if str(node.name).begins_with("Rock"): node.visible=false
		mine.environment.background_color=Color(ART.QA_BANDS[index].fog)
		mine._band=band;mine._focus=Vector3(4.75,0,-.75);mine._zoom=1.0;mine._update_camera()
		await populate()
		if index==0: check_backdrop()
		vp.size=Vector2i(720,1600)
		await capture("band_%d"%(index+1))
		if index==0:
			var coal_mesh: MeshInstance3D=coal.find_children("*","MeshInstance3D",true,false)[0]
			var faces:=coal_mesh.mesh.get_faces()
			report.coal_mask_triangles=[]
			for face in range(0,faces.size(),3):
				var triangle:=[]
				for corner in 3:
					var pixel: Vector2=mine.cam.unproject_position(coal_mesh.to_global(faces[face+corner]))
					triangle.append([pixel.x,pixel.y])
				report.coal_mask_triangles.append(triangle)
		var coal_pixel: Vector2=mine.cam.unproject_position(Vector3(5.4,.48,-2.7))
		var floor_pixel: Vector2=mine.cam.unproject_position(Vector3(6.0,.02,-2.15))
		report.bands.append({"band":ART.QA_BANDS[index],"coal_pixel":[coal_pixel.x,coal_pixel.y],"floor_pixel":[floor_pixel.x,floor_pixel.y]})
		mine.backdrop.visible=false
		await capture("band_%d_backdrop_off"%(index+1))
		mine.backdrop.visible=true
		if index==3:
			add_asset("res://assets/mine/props/guard_arena.glb",Vector3(4.9,0,-3.8),0)
			await capture("guard_30")
	# The overview documents the entire outer relief separately from default framing.
	vp.size=Vector2i(1200,900)
	CAMERA.place(mine.cam,Vector3(4.75,-.2,-4.0));mine.cam.size=22.0;CAMERA.fit_ground_depth(mine.cam)
	await capture("overview")
	report.checks=checks;report.passed=checks.all(func(c):return c.passed)
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.camera={"pitch":43,"yaw":14.5,"logical_size":[360,800],"capture_size":[720,1600],"zoom":1.0,"source":"P0Mine._update_camera at Layout.SPAWN, actual P0Ui camera band; UI hidden only for art captures"}
	FileAccess.open(OUT+"validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("QUARRY_GODOT ",report.passed," checks=",checks.size())
	get_tree().quit(0 if report.passed else 1)

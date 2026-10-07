extends Node3D
## Shared fixture: real movement/collisions/AvatarRig; no production state.
const Controls = preload("res://tools/dev/scene_bench/room_controls.gd")
const SPEED := 3.75
const RADIUS := .21
const HEIGHT := 1.25
var slug := "basic_room"
var output_dir := ""
var layout: Dictionary
var bench: Dictionary
var art: Node3D
var player: CharacterBody3D
var visual: Node3D
var rig: AvatarRig
var controls: Control
var camera: Camera3D
var input_value := Vector2.ZERO
var drive_direction := Vector3.ZERO
var automatic := false
var ready_for_capture := false
var collided_paths: Array[String] = []
var collision_overlay: Node3D
var mode := "manual"
var phase := "initializing"
var seed_frame := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--slug" and i+1<args.size(): slug=args[i+1]
		if args[i] == "--output" and i+1<args.size(): output_dir=args[i+1]
		if args[i] == "--test": mode="test"
		if args[i] == "--record-route": mode="record"
	if output_dir.is_empty(): output_dir=ProjectSettings.globalize_path("user://"+slug)
	DirAccess.make_dir_recursive_absolute(output_dir)
	layout=JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/"+slug+"/layout.json"))
	bench=layout.get("bench", {})
	if bench.is_empty() and slug=="basic_room":
		bench=JSON.parse_string(FileAccess.get_file_as_string("res://tools/dev/scene_bench/fixtures/basic_room.json"))
	art=load("res://scenes/%s/%s_art.tscn"%[slug,slug]).instantiate()
	add_child(art)
	setup_world()
	setup_player()
	var layer:=CanvasLayer.new();add_child(layer)
	controls=Controls.new();layer.add_child(controls)
	controls.movement_changed.connect(func(value:Vector2)->void:input_value=value)
	controls.zoom_changed.connect(func(factor:float)->void:camera.size=clampf(camera.size*factor,4,18))
	controls.recenter_requested.connect(func()->void:camera.look_at(player.position+Vector3.UP*.7))
	if mode!="manual":
		var runner=load("res://tools/dev/scene_bench/test_scene.gd").new()
		add_child(runner);runner.call_deferred("run",self)

func vec(a:Array)->Vector3:return Vector3(float(a[0]),float(a[1]),float(a[2]))

func setup_world()->void:
	var lighting:Dictionary=layout.get("review_lighting",{})
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR
	env.background_color=Color(lighting.get("background","e9e7d4"))
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(lighting.get("ambient_color","c4d5df"))
	env.ambient_light_energy=float(lighting.get("ambient",.52))
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	var world:=WorldEnvironment.new();world.environment=env;add_child(world)
	var sun:=DirectionalLight3D.new();sun.name="WindowSun";add_child(sun)
	sun.position=vec(lighting.get("sun_position",layout.get("sun_direction",[-6,7,1.5])))
	sun.look_at(vec(lighting.get("sun_target",[0,0,0])))
	sun.light_color=Color(lighting.get("sun_color","ffe4b9"))
	sun.light_energy=float(lighting.get("sun",1.05));sun.shadow_enabled=true
	sun.shadow_bias=.025;sun.shadow_normal_bias=.18
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=35;sun.light_angular_distance=1.4
	for data in lighting.get("points",[]):
		var light:=OmniLight3D.new();add_child(light);light.position=vec(data.position)
		light.light_color=Color(data.get("color","ffa35f"));light.light_energy=float(data.get("energy",1.0))
		light.omni_range=float(data.get("range",2.4));light.shadow_enabled=false
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(100,100)
	ground.mesh=plane;ground.position.y=-.43
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(lighting.get("background","e9e7d4"));mat.roughness=1
	ground.material_override=mat;add_child(ground)
	camera=Camera3D.new();camera.name="ReferenceCamera";camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT;camera.size=float(layout.camera.size)*.75
	camera.near=.1;camera.far=70;add_child(camera)
	camera.position=vec(layout.camera.position);camera.look_at(vec(layout.camera.target));camera.current=true

func setup_player()->void:
	player=CharacterBody3D.new();player.name="FixturePlayer";add_child(player)
	player.position=vec(bench.get("spawn",layout.get("spawn",[0,.09,1.5])))
	player.floor_snap_length=.20;player.safe_margin=.012
	var shape:=CapsuleShape3D.new();shape.radius=RADIUS;shape.height=HEIGHT
	var collision:=CollisionShape3D.new();collision.shape=shape;collision.position.y=HEIGHT/2
	player.add_child(collision)
	visual=Node3D.new();player.add_child(visual)
	rig=Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity:child.reduced_distance=50;child.sleep_distance=80
	visual.add_child(rig)
	rig.config_applied.connect(func(_config:AvatarConfig)->void:rig.play_motion("idle");ready_for_capture=true)
	rig.apply_config(Avatar.slot_table.default_config())

func _physics_process(delta:float)->void:
	var key:=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var value:Vector2=key.limit_length(1) if key!=Vector2.ZERO else input_value
	var right:=camera.global_basis.x;right.y=0
	var forward:=-camera.global_basis.z;forward.y=0
	var direction:Vector3=drive_direction if automatic else (right.normalized()*value.x-forward.normalized()*value.y).limit_length(1)
	player.velocity.x=direction.x*SPEED;player.velocity.z=direction.z*SPEED
	player.velocity.y=-2 if player.is_on_floor() else player.velocity.y-18*delta
	player.move_and_slide()
	for i in player.get_slide_collision_count():
		var collider=player.get_slide_collision(i).get_collider()
		if collider and player.get_slide_collision(i).get_normal().y<.7:
			var path:=str(collider.get_path())
			if not collided_paths.has(path):collided_paths.append(path)
	if Vector2(player.velocity.x,player.velocity.z).length()>.05:
		visual.rotation.y=lerp_angle(visual.rotation.y,atan2(direction.x,direction.z),minf(delta*16,1))
		rig.play_motion("run")
	else:rig.play_motion("idle")
	seed_frame+=1
	if seed_frame%6==0:write_state()

func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		input_value=Vector2.ZERO;drive_direction=Vector3.ZERO

func teleport(at:Vector3)->void:
	player.position=at;player.velocity=Vector3.ZERO;drive_direction=Vector3.ZERO;input_value=Vector2.ZERO
	collided_paths.clear()

func save_json(name:String,value:Variant)->void:
	var path:=output_dir+"/"+name
	var file:=FileAccess.open(path+".pending",FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"));file.close()
	DirAccess.rename_absolute(path+".pending",path)

func write_state()->void:
	save_json("state.json",{"pid":OS.get_process_id(),"phase":phase,"ready":ready_for_capture,
		"position":[player.position.x,player.position.y,player.position.z],"animation":rig.get_node("AnimationPlayer").current_animation})

func capture(name:String)->void:
	await RenderingServer.frame_post_draw
	var error:=get_viewport().get_texture().get_image().save_png(output_dir+"/"+name)
	if error!=OK:push_error("Capture failed: "+name)

func show_colliders()->void:
	collision_overlay=Node3D.new();add_child(collision_overlay)
	_draw_colliders(art)

func _draw_colliders(node:Node)->void:
	if node is CollisionShape3D and not node.disabled:
		var mesh:=MeshInstance3D.new();mesh.mesh=node.shape.get_debug_mesh()
		var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color=Color(.08,.82,1.0);mat.no_depth_test=true;mesh.material_override=mat
		collision_overlay.add_child(mesh);mesh.global_transform=node.global_transform
	for child in node.get_children():_draw_colliders(child)

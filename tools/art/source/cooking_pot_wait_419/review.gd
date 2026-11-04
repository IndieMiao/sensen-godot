extends Node
## Offline b1 fixture; no account, gameplay or runtime files are modified.
const PROP := preload("res://assets/props/cooking_pot_wait/cooking_pot_wait.tscn")
const OUT := "res://../renders/"
const STUDIO_PREFIX := "SGODOT-419_cooking_pot_v1.1_"
var viewport: SubViewport
var prop: Node3D
var camera: Camera3D

func _ready() -> void:
	call_deferred("run")

func make_view(size: Vector2i) -> Node3D:
	viewport = SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.size = Vector2(size)
	add_child(display)
	var world := Node3D.new()
	viewport.add_child(world)
	return world

func lighting(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("F5F2E9")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("FFEDD5")
	env.ambient_light_energy = .55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32,0)
	sun.light_energy = 1.1
	sun.light_color = Color("FFF3E0")
	world.add_child(sun)

func aim(at: Vector3, width: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = width
	var yaw := deg_to_rad(25)
	var pitch := deg_to_rad(35)
	camera.position = at + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*2.0
	camera.look_at(at)

func snap(filename: String) -> void:
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(OUT+filename)==OK)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"studio_v11_frames")
	var world := make_view(Vector2i(720,720))
	lighting(world)
	prop = PROP.instantiate()
	world.add_child(prop)
	camera = Camera3D.new()
	world.add_child(camera)
	aim(Vector3(0,.168,0),.43)
	camera.current = true
	var player := prop.get_node("AnimationPlayer") as AnimationPlayer
	player.play("tumble")
	player.pause()
	for i in 45: await get_tree().process_frame
	for shot in [["closed",.12],["lifted",.88],["settled",1.28]]:
		player.seek(shot[1],true)
		await get_tree().process_frame
		await snap(STUDIO_PREFIX+shot[0]+".png")
	player.play("idle")
	player.advance(0)
	player.pause()
	await get_tree().process_frame
	await snap(STUDIO_PREFIX+"idle.png")
	player.play("tumble")
	player.pause()
	for i in 108:
		player.seek(fmod(i/30.0,1.8),true)
		await get_tree().process_frame
		await snap("studio_v11_frames/%04d.png"%i)
	print("RENDERED_STUDIO_108_FRAMES")
	get_tree().quit()

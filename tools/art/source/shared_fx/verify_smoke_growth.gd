extends SceneTree
## Render one stationary puff at two ages to verify actual billboard growth.
## Disable random size/rotation in this control only; production keeps both.
var output: String
func _initialize() -> void: call_deferred("run")
func run() -> void:
 output = OS.get_cmdline_user_args()[0]
 var viewport := SubViewport.new()
 viewport.size = Vector2i(512,512)
 viewport.own_world_3d = true
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 var world := Node3D.new()
 viewport.add_child(world)
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color("484844")
 environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
 world.add_child(environment)
 var fx = load("res://assets/rooms/_shared/fx/fx_chimney_smoke.tscn").instantiate()
 fx.drift = Vector3.ZERO
 fx.wind_acceleration = Vector3.ZERO
 fx.emission_box = Vector3.ZERO
 world.add_child(fx)
 var smoke: GPUParticles3D = fx.get_node("Smoke")
 smoke.amount = 1
 smoke.one_shot = true
 smoke.explosiveness = 1
 smoke.preprocess = 0
 if "--without-scale" in OS.get_cmdline_user_args(): smoke.draw_pass_1.material.billboard_keep_scale = false
 var process: ParticleProcessMaterial = smoke.process_material
 process.scale_min = fx.end_size
 process.scale_max = fx.end_size
 process.angle_min = 0
 process.angle_max = 0
 process.angular_velocity_min = 0
 process.angular_velocity_max = 0
 process.anim_offset_min = 0
 process.anim_offset_max = 0
 var camera := Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 4
 camera.position = Vector3(0,0,5)
 world.add_child(camera)
 camera.current = true
 for i in 8: await process_frame
 smoke.restart()
 smoke.emitting = true
 await create_timer(.24).timeout
 var early := await capture(viewport,"puff-early.png")
 await create_timer(2.36).timeout
 var upper := await capture(viewport,"puff-upper.png")
 var ratio := float(upper.x)/float(early.x)
 var result := {"passed":ratio>1.8 and ratio<2.4,"control":"One stationary puff; fixed frame/angle/size randomness; same production material and scale/alpha curves", "early_seconds":.24,"upper_seconds":2.60,"early_bbox_px":[early.x,early.y],"upper_bbox_px":[upper.x,upper.y],"width_ratio":ratio,"nominal_final_start_ratio":fx.end_size/fx.start_size,"billboard_keep_scale":smoke.draw_pass_1.material.billboard_keep_scale}
 var file := FileAccess.open(output+"/smoke-growth-verification.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(result,"  "))
 print(JSON.stringify(result))
 quit(0 if result.passed else 1)

func capture(viewport: SubViewport, label: String) -> Vector2i:
 await RenderingServer.frame_post_draw
 var picture := viewport.get_texture().get_image()
 picture.save_png(output+"/"+label)
 var lo := Vector2i(512,512)
 var hi := Vector2i.ZERO
 for y in picture.get_height():
  for x in picture.get_width():
   if picture.get_pixel(x,y).r > .65:
    lo = lo.min(Vector2i(x,y))
    hi = hi.max(Vector2i(x,y))
 return hi-lo+Vector2i.ONE

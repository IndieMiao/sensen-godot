extends SceneTree
var checks: Array[String] = []
func require(value: bool, label: String) -> void:
 if not value:
  push_error(label)
  quit(1)
  assert(value,label)
 checks.append(label)
func _initialize() -> void: call_deferred("run")
func collect(node: Node) -> Array:
 var result: Array = []
 if node is GPUParticles3D: result.append(node)
 for child in node.get_children(): result.append_array(collect(child))
 return result
func run() -> void:
 var world := Node3D.new()
 root.add_child(world)
 var lamp := OmniLight3D.new()
 lamp.name = "BorrowedHearthGlow"
 world.add_child(lamp)
 var fire := preload("res://assets/rooms/_shared/fx/fx_hearth_fire.tscn").instantiate()
 fire.light_path = NodePath("../BorrowedHearthGlow")
 world.add_child(fire)
 var smoke := preload("res://assets/rooms/_shared/fx/fx_chimney_smoke.tscn").instantiate()
 smoke.position = Vector3(.7,1,0)
 world.add_child(smoke)
 require(fire.light == lamp and lamp.get_parent() == world and lamp.name == "BorrowedHearthGlow", "Borrow existing light without replacing owner/name")
 var all := collect(world)
 require(all.size() == 3, "Three independent GPU emitters")
 var fire_total := 0
 for particle: GPUParticles3D in collect(fire): fire_total += particle.amount
 require(fire_total == 20,"Default hearth is 16 flames + 4 sparks, <=20")
 for particle: GPUParticles3D in all:
  require(particle.fixed_fps == 30 and particle.preprocess >= particle.lifetime,"30Hz and full-lifetime warmup: "+particle.name)
  require(particle.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and particle.process_material.collision_mode == ParticleProcessMaterial.COLLISION_DISABLED,"No collision or shadow: "+particle.name)
  require(particle.visibility_aabb.size.x>0 and particle.visibility_aabb.size.y>0,"Explicit AABB: "+particle.name)
 var camera := Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 4
 world.add_child(camera)
 camera.position = Vector3(3,2,5)
 camera.look_at(Vector3(0,1,0));camera.current = true
 var low := INF
 var high := -INF
 var start := Time.get_ticks_msec()
 while Time.get_ticks_msec()-start < 5000:
  await process_frame
  low = minf(low,lamp.light_energy)
  high = maxf(high,lamp.light_energy)
 require(low >= 3.1*.9 and high <= 3.1*1.1 and high-low > .03,"Bounded animated light, no extra writer")
 var result := {"passed":true,"checks":checks,"count":checks.size(),"light_min":low,"light_max":high,"self_contained":true,"renderer":RenderingServer.get_current_rendering_method()}
 var f := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
 f.store_string(JSON.stringify(result,"  "))
 print(JSON.stringify(result))
 quit()

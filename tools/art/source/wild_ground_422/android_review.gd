extends Node
## Isolated real-input smoke viewer; same scene and material, local fixture only.
var pond
var runtime
var elapsed := 0.0
var fixture = {"energy":{"value":200,"cap":200}, "coins":180,
	"bag":{"slots":[],"free":22},"fishing":{"cast_energy":5},"travel":{"here":"san_francisco"}}
func _ready(): run.call_deferred()
func run():
	runtime = P0Runtime.new()
	P0Runtime._instance = runtime
	runtime.session.transport = func(_method,_path,_body,_meta): pass
	add_child(runtime)
	runtime.set_process(false)
	runtime.session.set_process(false)
	pond = load("res://review_pond.gd").new()
	pond.setup({"pond_id":"pond_los_angeles_01"})
	add_child(pond)
	var ground = pond.get_node("Scenery/BankGround")
	ground.material_override = load("res://ground_study.gd").material(ground.material_override, "gourd")
	runtime.ui.set_view(fixture)
	runtime.ui.set_action(pond._action_state(fixture))
func _process(dt):
	if not is_instance_valid(pond) or not is_instance_valid(pond.actor): return
	# Real UI signals still route touch input through P0Runtime.attach.
	pond.p0_frame(fixture,dt)
	elapsed += dt
	if elapsed < .5: return
	elapsed = 0
	var m = pond.get_node("Scenery/BankGround").material_override
	var state = {"revision":"water-preserved-v2",
		"grass_detail":m.get_shader_parameter("grass_detail").resource_path,
		"surface_flow":m.get_shader_parameter("surface_flow").resource_path,
		"dry_ground_mask":m.get_shader_parameter("dry_ground_mask").resource_path,
		"water_shader_sha256":FileAccess.get_sha256("res://modules/ponds/pond_water.gdshader"),"actor":[pond.actor.position.x,pond.actor.position.y,pond.actor.position.z],
		"zoom":pond._zoom,"camera_size":pond.cam.size,"assembled":not pond.actor.rig.is_busy(),
		"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),
		"shader":pond.get_node("Scenery/BankGround").material_override.shader.resource_path}
	FileAccess.open("user://ground_state.json",FileAccess.WRITE).store_string(JSON.stringify(state))

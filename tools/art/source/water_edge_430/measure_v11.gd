extends Node
const ROOT="res://assets/landmarks/_shared/water_edge/"
var vp:SubViewport
var world:Node3D
var camera:Camera3D
var material:ShaderMaterial
var output:String
func _ready():run.call_deferred()
func save(name):
 for i in 3:await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png(output+"/"+name+".png")
func run():
 output=ProjectSettings.globalize_path("res://../measure");DirAccess.make_dir_recursive_absolute(output)
 vp=SubViewport.new();vp.size=Vector2i(900,600);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_DISABLED;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 world=Node3D.new();vp.add_child(world)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;world.add_child(env)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_WIDTH;world.add_child(camera);camera.make_current()
 material=load(ROOT+"water_edge_material.tres").duplicate(true)
 var shader=Shader.new();shader.code=material.shader.code.replace("void vertex()","uniform float review_time=0.0;\nvoid vertex()").replace("TIME","review_time").replace("ALBEDO = foam.rgb * foam_color.rgb;","ALBEDO = vec3(1.0);")
 material.shader=shader
 var data={}
 for kind in ["straight","inner","pile_ring"]:
  var root=load(ROOT+"water_edge_"+kind+".glb").instantiate();var meshes=root.find_children("*","MeshInstance3D",true,false)
  if root is MeshInstance3D:meshes.push_front(root)
  var n=MeshInstance3D.new();n.mesh=meshes[0].mesh;n.material_override=material;world.add_child(n);root.free()
  var target=Vector3(0,0,.64);var width=2.4
  if kind=="inner":target=Vector3(-.5,0,.5);width=1.8
  if kind=="pile_ring":target=Vector3.ZERO;width=1.0
  camera.size=width;camera.position=target+Vector3(0,5,0);camera.look_at(target,Vector3(0,0,-1))
  var anchor=Vector3(0,0,.509090909) if kind=="straight" else Vector3(.105,0,0)
  data[kind]={"width_m":width,"pixels_per_m":900.0/width,"contact_pixel":str(camera.unproject_position(anchor)),"center":[target.x,target.z]}
  for i in 12:
   material.set_shader_parameter("review_time",i*.5);await save(kind+"_%02d"%i)
  material.set_shader_parameter("review_time",2.75);await save(kind+"_minimum")
  n.queue_free();await get_tree().process_frame
 FileAccess.open(output+"/projection.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
 get_tree().quit()

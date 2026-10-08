extends RefCounted
## Zhao Yun room adapter; consumes Liu Bei's self-contained effect unchanged.
static func vec(a:Array)->Vector3:return Vector3(float(a[0]),float(a[1]),float(a[2]))
static func attach(room:Node3D,layout:Dictionary)->Node3D:
 var first:Node3D=null
 for spec in layout.get("effects",[]):
  var light:=OmniLight3D.new();light.name=str(spec.name)+"_light";light.position=vec(spec.light.position)
  light.light_color=Color(spec.light.color);light.light_energy=float(spec.light.energy);light.omni_range=float(spec.light.range);light.shadow_enabled=false;room.add_child(light)
  var fx=(load(str(spec.scene)) as PackedScene).instantiate()
  fx.name=str(spec.name);fx.position=vec(spec.position);fx.emission_box=vec(spec.emission_box)
  fx.flame_count=int(spec.flame_count);fx.spark_count=int(spec.spark_count);fx.flame_height=float(spec.flame_height)
  fx.flame_lifetime=float(spec.get("flame_lifetime",.72));fx.flicker_strength=float(spec.get("flicker_strength",.08))
  fx.light_energy=float(spec.light.energy);fx.light_path=NodePath("../"+str(light.name));room.add_child(fx)
  assert(fx.light==light)
  if first==null:first=fx
 return first
static func material_for(base:StandardMaterial3D,spec:Dictionary)->ShaderMaterial:
 var material:=ShaderMaterial.new();material.shader=preload("res://scenes/room_effects/ember_surface.gdshader")
 material.set_shader_parameter("room_atlas",base.albedo_texture)
 material.set_shader_parameter("ember_min",vec(spec.min));material.set_shader_parameter("ember_max",vec(spec.max))
 material.set_shader_parameter("ember_energy",float(spec.get("energy",.38)))
 return material

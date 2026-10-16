@tool
extends Node3D
## SGODOT-308 reusable art and collisions. No gameplay anchors, accounts or saves.
const KIT="res://assets/rooms/mine_hut/"
var assembled=false
func vec(a):return Vector3(a[0],a[1],a[2])
func _ready():
 if assembled:return
 assembled=true
 var layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
 var material=StandardMaterial3D.new()
 material.resource_name="RoomKit_SharedAtlas"
 material.albedo_texture=load(KIT+"room_albedo_ao.png")
 material.roughness=.86;material.metallic_specular=.22
 material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
 for asset in layout.assets:
  var pivot=Node3D.new();pivot.name=asset.name;pivot.position=vec(asset.position);pivot.rotation_degrees.y=asset.yaw_degrees;add_child(pivot)
  var model=load(KIT+asset.file).instantiate();pivot.add_child(model)
  var mat=material
  if layout.material_overrides.has(asset.name):
   mat=material.duplicate();var o=layout.material_overrides[asset.name]
   mat.emission_enabled=true;mat.emission=Color(o.emission);mat.emission_texture=mat.albedo_texture
   mat.emission_operator=BaseMaterial3D.EMISSION_OP_MULTIPLY;mat.emission_energy_multiplier=o.emission_energy
  for mesh in model.find_children("*","MeshInstance3D",true,false):mesh.material_override=mat
  for box in asset.colliders:add_box(pivot,box)
 for box in layout.boundaries:add_box(self,box)
 for point in layout.local_lights:
  var lamp=OmniLight3D.new();lamp.name="LocalLight_"+point.name;lamp.position=vec(point.position);lamp.light_color=Color(point.color)
  lamp.light_energy=point.energy;lamp.omni_range=point.range;lamp.shadow_enabled=false;lamp.add_to_group("art_local_lights");add_child(lamp)
 for id in layout.suggested_anchors:
  var marker=Marker3D.new();marker.name="suggested_"+id;marker.position=vec(layout.suggested_anchors[id].position);marker.rotation_degrees.y=layout.suggested_anchors[id].yaw_degrees;add_child(marker)
func add_box(parent,box):
 var body=StaticBody3D.new();body.name=box.get("name","Collider");body.position=vec(box.at)
 var shape=BoxShape3D.new();shape.size=vec(box.size)
 var collision=CollisionShape3D.new();collision.shape=shape;body.add_child(collision);parent.add_child(body)

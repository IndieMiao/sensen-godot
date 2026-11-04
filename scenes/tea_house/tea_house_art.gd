@tool
extends Node3D
## Art assembly only. Interaction consumers read the immutable anchor names.
const KIT="res://assets/rooms/tea_house/"
var layout: Dictionary
var materials={}
var assembled=false

func vec(a):return Vector3(a[0],a[1],a[2])

func _ready():
	if assembled:return
	assembled=true
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	var opaque=StandardMaterial3D.new();opaque.resource_name="TeaHouse_SharedAtlas"
	opaque.albedo_texture=load(KIT+"room_albedo_ao.png");opaque.roughness=.85;opaque.metallic_specular=.18
	opaque.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;materials.opaque=opaque
	var foliage=opaque.duplicate();foliage.resource_name="TeaHouse_SharedAtlas_Foliage"
	foliage.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;foliage.alpha_scissor_threshold=.45
	foliage.cull_mode=BaseMaterial3D.CULL_DISABLED;materials.foliage=foliage
	var backdrop=opaque.duplicate();backdrop.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.cull_mode=BaseMaterial3D.CULL_DISABLED;materials.backdrop=backdrop
	var glow=opaque.duplicate();glow.emission_enabled=true;glow.emission=Color("FFE0A3")
	glow.emission_energy_multiplier=1.1;glow.emission_texture=opaque.albedo_texture;materials.glow=glow
	var assets={}
	for spec in layout.assets:
		assets[spec.name]=spec
		if not spec.get("review_only",false):add_asset(spec,spec)
	for placement in layout.instances:add_asset(assets[placement.asset],placement)
	for spec in layout.boundaries:add_collider(self,spec)
	for point in layout.anchors:
		var marker=Marker3D.new();marker.name=point.name;marker.position=vec(point.position)
		marker.rotation_degrees.y=point.get("yaw_degrees",0)
		for key in ["module","size"]:
			if point.has(key):marker.set_meta(key,point[key])
		add_child(marker)
	for spec in layout.local_lights:
		var light=OmniLight3D.new();light.name="TeaLanternLight";light.position=vec(spec.position)
		light.light_color=Color(spec.color);light.light_energy=spec.energy;light.omni_range=spec.range
		light.shadow_enabled=false;add_child(light)

func add_asset(spec,placement):
	var pivot=Node3D.new();pivot.name=placement.name;pivot.position=vec(placement.position)
	pivot.rotation_degrees.y=placement.yaw_degrees;pivot.scale=vec(placement.get("scale",[1,1,1]));add_child(pivot)
	var model=load(KIT+spec.file).instantiate();pivot.add_child(model)
	for node in model.find_children("*","MeshInstance3D",true,false):
		node.material_override=materials[spec.material]
		if not spec.cast_shadow:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for collider in spec.colliders:add_collider(pivot,collider)

func add_collider(parent,spec):
	var body=StaticBody3D.new();body.name=spec.get("name","ArtCollider");body.position=vec(spec.at)
	var collision=CollisionShape3D.new()
	if spec.get("shape","box")=="cylinder":
		var shape=CylinderShape3D.new();shape.radius=spec.radius;shape.height=spec.height;collision.shape=shape
	else:
		var shape=BoxShape3D.new();shape.size=vec(spec.size);collision.shape=shape
	body.add_child(collision);parent.add_child(body)

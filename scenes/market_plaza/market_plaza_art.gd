@tool
extends Node3D
## Art, collision shapes and anchor contract only. P0Room builds navigation from
## the final live collision shapes every time it opens this scene.
const KIT := "res://assets/rooms/market_plaza/"
@export_enum("san_francisco","generic") var city_variant:String="san_francisco":
	set(value):
		city_variant=value
		if _assembled and not layout.is_empty():_refresh_variant()
var layout: Dictionary
var _assembled := false
var _materials := {}
func _vec(a) -> Vector3:return Vector3(a[0],a[1],a[2])
func _ready() -> void:
	if _assembled:return
	_assembled=true
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	_materials.matte=load(KIT+"market_matte.tres")
	_materials.paving=load(KIT+"market_paving.tres")
	_materials.grass=load(KIT+"market_grass.tres")
	var fruit:=StandardMaterial3D.new()
	fruit.albedo_texture=load("res://assets/rooms/fruit_shop/room_albedo_ao.png")
	fruit.roughness=.86;fruit.metallic_specular=.22
	_materials.fruit=fruit
	var groups:Dictionary={}
	for group in ["Ground","FarFacades","NearEdges","MarketProps","Garden","LightingDecor","CityBackdrop"]:
		var node:=Node3D.new();node.name=group;add_child(node);groups[group]=node
	for spec in layout.assets:_add_asset(spec,groups.get(spec.get("group","MarketProps"),self))
	for spec in layout.boundaries:_add_collider(self,spec)
	var city:Node3D=load(layout.city_backdrop.scene).instantiate()
	city.name="ReplaceableCityBackdrop";city.variant=city_variant;groups.CityBackdrop.add_child(city)
	for point in layout.anchors:
		var marker:=Marker3D.new();marker.name=point.name;marker.position=_vec(point.position)
		marker.rotation_degrees.y=point.get("yaw_degrees",0)
		for key in point:
			if key not in ["name","position","yaw_degrees"]:marker.set_meta(key,point[key])
		add_child(marker)
func _add_asset(spec:Dictionary,group:Node) -> void:
	var pivot:=Node3D.new();pivot.name=spec.name;pivot.position=_vec(spec.position)
	pivot.rotation_degrees.y=spec.get("yaw_degrees",0);pivot.scale=_vec(spec.get("scale",[1,1,1]))
	# Interactable modules must be direct children, as P0Room.anchor visibility
	# resolves the authored module name directly under the art root.
	if spec.get("anchor_module",false):add_child(pivot)
	else:group.add_child(pivot)
	var filename:String=spec.get("variants",{}).get(city_variant,spec.file)
	var path:String=filename if filename.begins_with("res://") else KIT+filename
	if not ResourceLoader.exists(path) and spec.has("fallback_file"):path=KIT+spec.fallback_file
	var packed:=load(path) as PackedScene
	if packed==null:push_error("Missing market asset: "+path);return
	var model:=packed.instantiate();pivot.add_child(model)
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:meshes.push_front(model)
	for mesh:MeshInstance3D in meshes:
		var material:String=spec.get("material","preserve")
		if _materials.has(material):mesh.material_override=_materials[material]
		mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		if not spec.get("cast_shadow",true):mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_meta("market_occluder",spec.get("occluder",false))
		mesh.set_meta("market_module",spec.name)
	for collider in spec.get("colliders",[]):_add_collider(pivot,collider)
func _refresh_variant() -> void:
	var facades:=get_node_or_null("FarFacades")
	if facades==null:return
	for child in facades.get_children():facades.remove_child(child);child.queue_free()
	for spec in layout.assets:
		if spec.get("group","")=="FarFacades":_add_asset(spec,facades)
	var city=get_node_or_null("CityBackdrop/ReplaceableCityBackdrop")
	if city:city.variant=city_variant
func _add_collider(parent:Node,spec:Dictionary) -> void:
	var body:=StaticBody3D.new();body.name=spec.get("name","ArtCollider");body.position=_vec(spec.at)
	body.rotation_degrees=_vec(spec.get("rotation_degrees",[0,0,0]))
	var collision:=CollisionShape3D.new()
	if spec.get("shape","box")=="cylinder":
		var shape:=CylinderShape3D.new();shape.radius=spec.radius;shape.height=spec.height;collision.shape=shape
	else:
		var shape:=BoxShape3D.new();shape.size=_vec(spec.size);collision.shape=shape
	body.add_child(collision);parent.add_child(body)

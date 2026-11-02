@tool
extends Node3D
## N2 art and colliders; the consumer supplies the camera, character and lighting.
const KIT="res://assets/rooms/poi_service_hall/"
var layout: Dictionary
var shell: Node3D

func _ready():
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	shell=load(layout.shared_shell).instantiate();shell.name="SharedHall"
	shell.atlas_path=KIT+layout.atlas;add_child(shell)
	for spec in layout.placements:
		var pivot=Node3D.new();pivot.name=spec.name;pivot.position=_vec(spec.position)
		pivot.rotation_degrees.y=spec.yaw_degrees;add_child(pivot)
		var model=load(KIT+layout.assets[spec.asset].file).instantiate();pivot.add_child(model)
		for node in model.find_children("*","MeshInstance3D",true,false):
			node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
			if not spec.cast_shadow:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for collider in spec.colliders:_collider(pivot,collider)
	for spec in layout.anchors:
		var marker=Marker3D.new();marker.name=spec.name;marker.position=_vec(spec.position)
		marker.rotation_degrees.y=spec.yaw_degrees;marker.set_meta("module",spec.module)
		if spec.has("size"):marker.set_meta("size",spec.size)
		add_child(marker)

func _vec(a):return Vector3(a[0],a[1],a[2])

func _collider(parent,spec):
	var body=StaticBody3D.new();body.position=_vec(spec.at)
	var node=CollisionShape3D.new()
	if spec.get("kind","")=="cylinder":
		var shape=CylinderShape3D.new();shape.radius=spec.radius;shape.height=spec.height;node.shape=shape
	else:
		var shape=BoxShape3D.new();shape.size=_vec(spec.size);node.shape=shape
	body.add_child(node);parent.add_child(body)

@tool
extends Node3D
## N4 art assembly. Consuming scenes provide environment, sun and camera.
const KIT := "res://assets/rooms/poi_classroom/"
var layout: Dictionary

func _ready() -> void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	var props: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(KIT+"props/prop_manifest.json"))
	var shell=load(layout.shared_shell).instantiate()
	shell.atlas_path=layout.shell_atlas
	add_child(shell)
	for child in shell.get_children():
		if child is Marker3D: child.queue_free()
		else: child.reparent(self)
	shell.queue_free()
	for row in layout.placements:
		var holder:=Node3D.new();holder.name=row.name;holder.position=vec(row.position)
		holder.rotation_degrees.y=float(row.yaw_degrees);add_child(holder)
		holder.set_meta("final_owner",row.owner)
		var model=load(KIT+str(row.model)+".glb").instantiate();holder.add_child(model)
		for prop in props.assets:
			if str(row.model)!="props/"+str(prop.name):continue
			for spec in prop.get("mounts",[]):
				var marker:=Marker3D.new();marker.name=spec.name;marker.position=vec(spec.position)
				holder.add_child(marker)
		if row.has("mount"):
			var parent=get_node(str(row.mount.module))
			var mount=parent.find_child(str(row.mount.node),true,false)
			assert(mount is Node3D,"Missing approved prop mount")
			holder.global_transform=mount.global_transform
		for spec in row.colliders:
			var body:=StaticBody3D.new();body.name="FurnitureCollision"
			body.position=vec(spec.at);holder.add_child(body)
			var collision:=CollisionShape3D.new()
			if spec.get("kind","")=="cylinder":
				var shape:=CylinderShape3D.new();shape.radius=float(spec.radius);shape.height=float(spec.height);collision.shape=shape
			else:
				var shape:=BoxShape3D.new();shape.size=vec(spec.size);collision.shape=shape
			body.add_child(collision)
	for row in layout.local_lights:
		var lamp:=OmniLight3D.new();lamp.name=row.name;lamp.position=vec(row.position)
		lamp.light_color=Color(row.color);lamp.light_energy=float(row.energy)
		lamp.omni_range=float(row.range);lamp.shadow_enabled=false;add_child(lamp)
	for row in layout.anchors:
		var marker:=Marker3D.new();marker.name=row.name;marker.position=vec(row.position)
		marker.rotation_degrees.y=float(row.get("yaw_degrees",0))
		for key in ["module","size","stand","role","pitch_degrees","orthographic_width"]:
			if row.has(key): marker.set_meta(key,row[key])
		add_child(marker)

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

@tool
extends Node3D
## N4 white blockout. Consuming scenes provide camera, lighting and gameplay.
const KIT := "res://assets/rooms/poi_classroom/"
var layout: Dictionary

func _ready() -> void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	var shell=load(layout.shared_shell).instantiate()
	add_child(shell)
	var neutral:=StandardMaterial3D.new()
	neutral.albedo_color=Color("DADCD7");neutral.roughness=.9;neutral.metallic_specular=.18
	for mesh in shell.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original:=mesh.get_active_material(surface) as StandardMaterial3D
			if original.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED:
				mesh.set_surface_override_material(surface,neutral)
	for child in shell.get_children():
		if child is Marker3D: child.queue_free()
		else: child.reparent(self)
	shell.queue_free()
	for row in layout.placements:
		var holder:=Node3D.new();holder.name=row.name;holder.position=vec(row.position)
		holder.rotation_degrees.y=float(row.yaw_degrees);add_child(holder)
		holder.set_meta("blockout",true);holder.set_meta("final_owner",row.owner)
		var model=load(KIT+str(row.model)+".glb").instantiate();holder.add_child(model)
		if row.model not in ["blockout_student_desk","blockout_student_stool"]: model.scale=vec(row.size)
		if row.collidable:
			var body:=StaticBody3D.new();body.name="BlockoutCollision"
			body.position.y=float(row.size[1])/2;holder.add_child(body)
			var collision:=CollisionShape3D.new()
			if row.model in ["blockout_student_stool","blockout_cylinder"]:
				var shape:=CylinderShape3D.new();shape.radius=float(row.size[0])/2;shape.height=float(row.size[1]);collision.shape=shape
			else:
				var shape:=BoxShape3D.new();shape.size=vec(row.size);collision.shape=shape
			body.add_child(collision)
	for row in layout.anchors:
		var marker:=Marker3D.new();marker.name=row.name;marker.position=vec(row.position)
		marker.rotation_degrees.y=float(row.get("yaw_degrees",0))
		for key in ["module","size","stand","role","pitch_degrees","orthographic_width"]:
			if row.has(key): marker.set_meta(key,row[key])
		add_child(marker)

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

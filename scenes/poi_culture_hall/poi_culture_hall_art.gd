@tool
extends Node3D
## N3 white layout; the consumer owns environment, sun and camera.
const KIT:="res://assets/rooms/poi_culture_hall/"
var layout: Dictionary
func vec(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func _ready() -> void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	var shell=load(layout.shared_shell).instantiate();add_child(shell)
	var neutral:=StandardMaterial3D.new();neutral.albedo_color=Color("DADCD7");neutral.roughness=.9;neutral.metallic_specular=.18
	for mesh in shell.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(surface) as StandardMaterial3D
			if material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED:mesh.set_surface_override_material(surface,neutral)
	for child in shell.get_children():
		if child is Marker3D:child.queue_free()
		else:child.reparent(self)
	shell.queue_free()
	for row in layout.placements:
		var holder:=Node3D.new();holder.name=row.name;holder.position=vec(row.position);holder.rotation_degrees.y=float(row.yaw_degrees);add_child(holder)
		holder.set_meta("blockout",true);holder.set_meta("final_owner",row.owner)
		var model=load(KIT+str(row.model)+".glb").instantiate();holder.add_child(model)
		model.scale=vec(row.size)/vec(layout.models.get(row.model,[1,1,1]))
		if row.has("target"):holder.look_at(to_global(vec(row.target)))
		if row.collidable:
			var body:=StaticBody3D.new();body.name="BlockoutCollision";body.position.y=float(row.size[1])/2;holder.add_child(body)
			var collider:=CollisionShape3D.new()
			if row.get("shape","")=="circle":
				var shape:=CylinderShape3D.new();shape.radius=float(row.size[0])/2;shape.height=float(row.size[1]);collider.shape=shape
			else:
				var shape:=BoxShape3D.new();shape.size=vec(row.size);collider.shape=shape
			body.add_child(collider)
	for row in layout.local_lights:
		var lamp:=SpotLight3D.new();lamp.name=row.name;lamp.position=vec(row.position);add_child(lamp)
		lamp.look_at(to_global(vec(row.target)));lamp.light_color=Color(row.color);lamp.light_energy=row.energy
		lamp.spot_range=row.range;lamp.spot_angle=row.angle;lamp.shadow_enabled=false
	for row in layout.anchors:
		var marker:=Marker3D.new();marker.name=row.name;marker.position=vec(row.position);marker.rotation_degrees.y=float(row.get("yaw_degrees",0))
		for key in ["module","stand","size","pitch_degrees","orthographic_width"]:
			if row.has(key):marker.set_meta(key,row[key])
		add_child(marker)

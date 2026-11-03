@tool
extends Node3D
## N3 independent reuse subset; the consumer owns environment, sun and camera.
const KIT:="res://assets/rooms/poi_culture_hall/"
var layout: Dictionary
func vec(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func _ready() -> void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(KIT+"layout.json"))
	var shell=load(layout.shared_shell).instantiate()
	shell.atlas_path=layout.shell_atlas;add_child(shell)
	for child in shell.get_children():
		if child is Marker3D:child.queue_free()
		else:child.reparent(self)
	shell.queue_free()
	for row in layout.placements:
		var holder:=Node3D.new();holder.name=row.name;holder.position=vec(row.position);holder.rotation_degrees.y=float(row.yaw_degrees);add_child(holder)
		holder.set_meta("blockout",str(row.model).begins_with("blockout_"));holder.set_meta("final_owner",row.owner)
		var model=load(KIT+str(row.model)+".glb").instantiate();holder.add_child(model)
		model.scale=vec(row.model_scale) if row.has("model_scale") else vec(row.size)/vec(layout.models.get(row.model,[1,1,1]))
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
		var lamp: Light3D
		if row.get("kind","spot")=="omni":
			var omni:=OmniLight3D.new();omni.omni_range=float(row.range);lamp=omni
		else:
			var spot:=SpotLight3D.new();spot.spot_range=float(row.range);spot.spot_angle=float(row.angle);lamp=spot
		lamp.name=row.name;lamp.position=vec(row.position);add_child(lamp)
		if row.has("target"):lamp.look_at(to_global(vec(row.target)))
		lamp.light_color=Color(row.color);lamp.light_energy=float(row.energy);lamp.shadow_enabled=false
	for row in layout.anchors:
		var marker:=Marker3D.new();marker.name=row.name;marker.position=vec(row.position);marker.rotation_degrees.y=float(row.get("yaw_degrees",0))
		for key in ["module","stand","size","pitch_degrees","orthographic_width"]:
			if row.has(key):marker.set_meta(key,row[key])
		add_child(marker)

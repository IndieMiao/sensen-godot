@tool
extends GPUParticles3D
## Steam-only visual mask. Follow the real animated lid and the host's camera;
## no gameplay, animation, model or UI state is changed.
var _lid_mesh: MeshInstance3D
var _points := PackedVector3Array()
var _steam_material: ShaderMaterial

func _ready() -> void:
	_lid_mesh = get_parent().get_node_or_null("lid_mesh") as MeshInstance3D
	if _lid_mesh == null or draw_pass_1 == null: return
	_steam_material = draw_pass_1.material.duplicate() as ShaderMaterial
	material_override = _steam_material # uniforms belong to this pot instance
	var unique := {}
	for surface in _lid_mesh.mesh.get_surface_count():
		for point in _lid_mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: unique[point]=true
	for point in unique: _points.append(point)
	_update_clearance()

func _process(_delta: float) -> void:
	_update_clearance()

func _update_clearance() -> void:
	if _steam_material == null or not is_instance_valid(_lid_mesh): return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null: return # default cutoff 0 keeps steam hidden without a camera
	var top := viewport.get_visible_rect().size.y
	for point in _points:
		top = minf(top,camera.unproject_position(_lid_mesh.global_transform*point).y)
	# Conservative 0.002-height margin; fade starts above, never on the lid.
	_steam_material.set_shader_parameter("lid_top_uv",clampf(top/viewport.get_visible_rect().size.y-.002,0,1))

extends Node3D
## SGODOT-424 blockout. Local sightseeing only; no network/rewards/save writes.
## Walking, isolated nav map and ScenePan gestures follow Griffith's implementation.
## The brief explicitly requests follow; that addition is local to this scene.

signal exit_requested
const ROOT := "res://assets/landmarks/alcatraz_island/"
const ScenePan := preload("res://modules/farm/scene_pan.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")
const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")
const PHONE_WIDTH := 6.72
const PITCH := 43.0
const WALK_SPEED := 2.3
var layout: Dictionary
var camera_pan := ScenePan.new()
var _camera: Camera3D
var _player: Node3D
var _rig: AvatarRig
var _nav_map: RID
var _path := PackedVector3Array()
var _path_i := 0
var _running := false
var _focus := Vector3.ZERO
var _following := true
var _overview := false
var _environment: WorldEnvironment
var _saved_environment: Environment
var _hud: CanvasLayer
var _exit_button: Button
var _exit_marker: VBoxContainer
var _camera_recenter: Tween
var mesh_nodes: Array[MeshInstance3D] = []
var _mesh_cache := {}
var zones := {}
var batch_nodes: Array[MultiMeshInstance3D] = []
var _detail_batches: Array[MultiMeshInstance3D] = []
var _unshadowed_batches: Array[MultiMeshInstance3D] = []
var _far_zone: Node3D
var _zoom_buttons := {}
var _prototype_shapes := {}
var _backdrop_enabled := true
var _sea_material: ShaderMaterial
var animated_roots: Array[Node3D] = []
var _animation_rng := RandomNumberGenerator.new()
var tree_batches: Array[Dictionary] = []
var _detail_groups: Array[MeshInstance3D] = []
## Opened from the P0 map (q(295)): P0's HUD, stick and door prompt instead of this scene's own controls.
var p0_visit: P0LandmarkVisit
## The landmark's voice (SGODOT-462): P0LandmarkVisit's, read by P0Runtime for the HUD's mic key and people drawer.
var voice_room: Node
var _boundary_rids: Array[RID] = []
## The P0 stick is walking the player: the run plays on (_step_walk without a path would set it idle each frame, and
## play_motion starts a clip over from its first frame, so the player slid; 用户 0.3.2, 424 da2e9368).
var stick_moving := false
var _stick_still := 0.0   # seconds the stick has pushed without moving the player

func setup(args: Dictionary) -> void:
	if P0LandmarkVisit.wanted(args): p0_visit = P0LandmarkVisit.new(self, args)


func _ready() -> void:
	get_viewport().transparent_bg = false
	layout = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "layout.json"))
	if OS.get_environment("ALCATRAZ_REVIEW").is_empty():_animation_rng.randomize()
	else:_animation_rng.seed=424
	_environment = WorldEnvironment.new()
	_environment.environment = Environment.new()
	_environment.environment.background_mode = Environment.BG_COLOR
	# Diagnostic magenta: no review pixel should expose this behind the ocean.
	_environment.environment.background_color = Color("d000d0")
	_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.environment.ambient_light_color = Color("d5e4ee")
	_environment.environment.ambient_light_energy = 0.72
	add_child(_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -34, 0)
	sun.light_color = Color(1.0, 0.965, 0.88)
	sun.light_energy = 0.98
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_opacity = 0.48
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.28
	add_child(sun)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.94
	paint.metallic_specular = 0.15
	for zone_name in layout.zones + ["FarZone"]:
		var zone := get_node_or_null(str(zone_name)) as Node3D
		if zone == null:
			zone = Node3D.new()
			zone.name = str(zone_name)
			add_child(zone)
		zones[zone_name] = zone
	_far_zone = zones["FarZone"]
	var batches := {}
	var surface_groups := {}
	for p in layout.placements:
		if p.has("render_merge_into"):continue
		if p.has("surface_group"):
			var group_key := str(p.zone)+"/"+str(p.surface_group)
			if not surface_groups.has(group_key):surface_groups[group_key]=[]
			surface_groups[group_key].append(p)
			continue
		if bool(p.get("multimesh",false)):
			var key := str(p.zone)+"/"+str(p.asset)
			if not batches.has(key): batches[key]=[]
			batches[key].append(p)
		else:
			_add_asset(p,paint)
	for key in batches:_add_batch(batches[key],paint)
	for key in surface_groups:_add_surface_group(surface_groups[key],paint)
	_build_backdrop()
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(layout.sea_size)
	sea.mesh = plane
	sea.position.y = -0.15
	_sea_material = ShaderMaterial.new()
	_sea_material.shader = preload("res://assets/landmarks/alcatraz_island/sea_backdrop.gdshader")
	_sea_material.set_shader_parameter("water",Color(str(layout.palette.water.near)))
	_sea_material.set_shader_parameter("deep_water",Color(str(layout.palette.water.deep)))
	sea.material_override = _sea_material
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	for specification in layout.anchors:
		var anchor := Marker3D.new()
		anchor.name = str(specification.name)
		anchor.position = _vec(specification.position)
		anchor.rotation.y = deg_to_rad(float(specification.get("yaw_degrees",0)))
		add_child(anchor)
	for boundary in layout.boundaries:
		var body := StaticBody3D.new()
		body.name = str(boundary.name)
		body.position = _vec(boundary.at)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _vec(boundary.size)
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		_boundary_rids.append(body.get_rid())
	_build_navigation()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(_camera)
	_camera.make_current()
	_spawn_player()
	camera_pan.min_zoom = 1.0/3.0
	camera_pan.max_zoom = 1.4
	camera_pan.reset(1.0)
	camera_pan.free_pan = true
	camera_pan.hold_enabled = false
	camera_pan.tapped.connect(walk_to_screen)
	if p0_visit == null: _build_controls()
	_update_camera()
	if p0_visit: p0_visit.start()

static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _mesh(asset: String) -> Mesh:
	if not _mesh_cache.has(asset):
		var source := (load(ROOT + asset + ".glb") as PackedScene).instantiate()
		var found := source.find_children("*", "MeshInstance3D", true, false)
		if source is MeshInstance3D: found.push_front(source)
		_mesh_cache[asset] = (found[0] as MeshInstance3D).mesh
		source.free()
	return _mesh_cache[asset]

static func _scale_vec(value) -> Vector3:
	return _vec(value) if value is Array else Vector3.ONE*float(value)

func _transform_of(p: Dictionary) -> Transform3D:
	var degrees := _vec(p.get("rotation_degrees",[0,rad_to_deg(float(p.get("yaw",0))),0]))
	var basis := Basis.from_euler(degrees*PI/180.0).scaled(_scale_vec(p.scale))
	if p.has("basis_columns"):
		basis = Basis(_vec(p.basis_columns[0]),_vec(p.basis_columns[1]),_vec(p.basis_columns[2]))
	return Transform3D(basis,_vec(p.position))

func _far_material(asset: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/landmarks/alcatraz_island/far_card.gdshader")
	var depth := .94 if asset.contains("bridge") else .96 if asset.contains("city") else .98
	material.set_shader_parameter("depth_fraction",depth)
	var authored := _mesh(asset).surface_get_material(0) if _mesh_cache.has(asset) else null
	if authored is BaseMaterial3D and authored.albedo_texture:
		material.set_shader_parameter("card_texture",authored.albedo_texture)
		material.set_shader_parameter("use_texture",true)
	material.render_priority = -97 if asset.contains("bridge") else -98 if asset.contains("city") else -99
	return material

func _add_asset(p: Dictionary, paint: Material) -> void:
	if p.has("scene_file"):
		var root := (load(ROOT+str(p.scene_file)) as PackedScene).instantiate() as Node3D
		root.name=str(p.name)
		root.transform=_transform_of(p)
		zones[p.zone].add_child(root)
		for child in root.find_children("*","MeshInstance3D",true,false):
			child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_nodes.append(child)
		var animator := root.get_node("AnimationPlayer") as AnimationPlayer
		animator.play(str(p.animation))
		var length := animator.get_animation(str(p.animation)).length
		var phase := (float(p.animation_phase_group)+_animation_rng.randf_range(.1,.9))*length/3.0 if p.asset=="gull" else 0.0
		animator.seek(phase,true)
		root.set_meta("placement",p)
		root.set_meta("initial_phase_s",phase)
		animated_roots.append(root)
		return
	var variants := [str(p.asset)]
	if p.has("lod_group"):variants.append(str(p.asset)+"_far")
	for variant in variants:
		var node := MeshInstance3D.new()
		node.name = variant.to_pascal_case()+str(mesh_nodes.size())
		node.mesh = _mesh(variant)
		node.set_meta("asset",variant)
		if variant=="alc_ground_terraces":
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.append_from(node.mesh,0,Transform3D.IDENTITY)
			for source in layout.placements:
				if source.get("render_merge_into","")==variant:
					surface.append_from(_mesh(str(source.asset)),0,_transform_of(p).affine_inverse()*_transform_of(source))
			node.mesh=surface.commit()
		node.material_override = _far_material(variant) if str(p.zone)=="FarZone" else paint
		if layout.get("ground_materials",{}).has(variant):
			node.material_override=load(ROOT+str(layout.ground_materials[variant])) as Material
		node.transform = _transform_of(p)
		zones[p.zone].add_child(node)
		mesh_nodes.append(node)
		if p.has("pose"):
			for i in node.mesh.get_blend_shape_count():
				node.set_blend_shape_value(i,1.0 if str(node.mesh.get_blend_shape_name(i))==str(p.pose) else 0.0)
		if variant.ends_with("_far"):
			node.visibility_range_begin = 55
			node.visibility_range_begin_margin = 0
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			if p.has("lod_group"):
				node.visibility_range_end = 55
				node.visibility_range_end_margin = 0
			if bool(p.collision):node.create_trimesh_collision()
		if str(p.asset) in ["ferry","gull"]:node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if str(p.zone)=="FarZone":
			node.extra_cull_margin = 100
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_surface_group(items: Array, paint: Material) -> void:
	# Static dock props and water-contact overlays each share a material.
	# Original GLBs and instance transforms remain in the delivery contract.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(paint if items[0].surface_group in ["dock_furnishings","garden_flowers"] else _mesh(str(items[0].asset)).surface_get_material(0))
	for p in items:surface.append_from(_mesh(str(p.asset)),0,_transform_of(p))
	var node := MeshInstance3D.new()
	node.name=str(items[0].surface_group).to_pascal_case()
	node.mesh=surface.commit()
	if items[0].surface_group=="garden_flowers":
		node.set_meta("max_view_width_m",8.0);_detail_groups.append(node)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	zones[items[0].zone].add_child(node)
	mesh_nodes.append(node)

func _add_batch(items: Array, paint: Material) -> void:
	var asset := str(items[0].asset)
	if asset.begins_with("alc_tree_"):
		_add_tree_batches(items,paint)
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh(asset)
	mm.instance_count = items.size()
	for i in items.size():mm.set_instance_transform(i,_transform_of(items[i]))
	var node := MultiMeshInstance3D.new()
	node.name = asset.to_pascal_case()+"Batch"
	node.multimesh = mm
	node.material_override = paint
	for definition in layout.assets:
		if definition.name==asset and definition.get("material","")=="imported":
			node.material_override=null
		if definition.name==asset and not bool(definition.get("cast_shadow",true)):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Hidden past a view width only if nothing in it stands in the way: zoomed out, the flowerbeds, planters, bins,
		# lamps and signs went while their collision and navigation holes stayed, invisible walls (用户 0.3.2, 424 da2e9368).
		if definition.name==asset and definition.has("max_view_width_m") and not items.any(func(p): return bool(p.get("collision", false))):
			node.set_meta("max_view_width_m",float(definition.max_view_width_m))
			_detail_batches.append(node)
	if asset in ["alc_curb","alc_lamp","alc_bin","alc_sign","alc_rail_corner","alc_flowerbed","alc_rock_a","alc_rock_b","alc_rock_c","alc_shrub","alc_grass_tuft"]:node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zones[items[0].zone].add_child(node)
	batch_nodes.append(node)
	if node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		var bounds: Array[AABB] = []
		var transforms: Array[Transform3D] = []
		for p in items:
			var transform := _transform_of(p)
			transforms.append(transform)
			bounds.append(transform*mm.mesh.get_aabb())
		node.set_meta("instance_bounds",bounds)
		node.set_meta("instance_transforms",transforms)
		_unshadowed_batches.append(node)
	for p in items:
		if bool(p.collision):_add_prop_collision(p)

func _add_tree_batches(items: Array, paint: Material) -> void:
	# Each zone keeps its own batches. Select per instance using the shared LOD
	# AABB centre after camera fitting; a whole-island batch cannot use one range.
	var group := {"asset":str(items[0].asset),"transforms":[],"bounds":[],"centres":[],"distance":40.0,"items":items}
	var box := _mesh(str(items[0].asset)).get_aabb()
	for p in items:
		var transform := _transform_of(p)
		var world_box := transform*box
		group.transforms.append(transform);group.bounds.append(world_box)
		group.centres.append(world_box.get_center())
		if bool(p.collision):_add_prop_collision(p)
	for suffix in ["","_far"]:
		var mm := MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=_mesh(str(items[0].asset)+suffix);mm.instance_count=items.size()
		for i in items.size():mm.set_instance_transform(i,group.transforms[i])
		var node := MultiMeshInstance3D.new();node.name=(str(items[0].asset)+suffix).to_pascal_case()+"Batch"
		node.multimesh=mm;node.material_override=paint
		zones[items[0].zone].add_child(node);batch_nodes.append(node)
		group["far" if suffix else "near"]=node
	tree_batches.append(group)

func _update_tree_lods(camera_position: Vector3) -> void:
	for group in tree_batches:
		var counts := [0,0]
		var bounds := [AABB(),AABB()]
		var nodes := [group.near,group.far]
		for i in group.transforms.size():
			var slot := int(camera_position.distance_to(group.centres[i])>=float(group.distance))
			var node: MultiMeshInstance3D = nodes[slot]
			node.multimesh.set_instance_transform(counts[slot],group.transforms[i])
			bounds[slot]=group.bounds[i] if counts[slot]==0 else bounds[slot].merge(group.bounds[i])
			counts[slot]+=1
		for slot in 2:
			var node: MultiMeshInstance3D = nodes[slot]
			node.multimesh.visible_instance_count=counts[slot]
			node.visible=counts[slot]>0
			if counts[slot]>0:node.multimesh.custom_aabb=bounds[slot]

func _add_prop_collision(p: Dictionary) -> void:
	var definitions := {
		"alc_bench":[Vector3(1.5,.9,.5),Vector3(0,.45,0)],
		"alc_lamp":[Vector3(.14,3.5,.14),Vector3(0,1.75,0)],
		"alc_rail_straight":[Vector3(2,1,.18),Vector3(0,.5,0)],
		"alc_rail_corner":[Vector3(.5,1,.5),Vector3(.2,.5,.2)],
		"alc_tree_a":[Vector3(.3,1.4,.3),Vector3(0,.7,0)],
		"alc_tree_b":[Vector3(.3,1.4,.3),Vector3(0,.7,0)],
		"alc_tree_c":[Vector3(.3,1.4,.3),Vector3(0,.7,0)],
		"alc_tree_d":[Vector3(.3,1.4,.3),Vector3(0,.7,0)],
		"alc_flowerbed":[Vector3(1.7,.66,1.7),Vector3(0,.33,0)],
		"alc_bin":[Vector3(.47,.8,.47),Vector3(0,.4,0)],
		"alc_planter":[Vector3(.68,1.14,.68),Vector3(0,.57,0)],
		"alc_sign":[Vector3(.12,1.3,.12),Vector3(0,.65,0)]}
	if not definitions.has(p.asset):return
	if not _prototype_shapes.has(p.asset):
		var box := BoxShape3D.new()
		box.size = definitions[p.asset][0]
		_prototype_shapes[p.asset]=box
	var body := StaticBody3D.new()
	body.name = str(p.name)+"Collision"
	body.transform = _transform_of(p)
	if p.has("basis_columns"):
		body.transform = Transform3D(Basis(Vector3.UP,float(p.get("yaw",0))),_vec(p.position))
	var collision := CollisionShape3D.new()
	collision.shape = _prototype_shapes[p.asset]
	if p.has("basis_columns"):
		var conservative := BoxShape3D.new()
		conservative.size = Vector3(float(p.scale[0])*2,1+absf(float(p.slope_rise_m)),.18)
		collision.shape = conservative
	collision.position = definitions[p.asset][1]
	body.add_child(collision)
	zones[p.zone].add_child(body)

func _build_backdrop() -> void:
	# All scenery is in this independently loadable Node3D; no second viewport/pass.
	var bay := MeshInstance3D.new()
	bay.name = "FarBayFill"
	var quad := QuadMesh.new()
	quad.size = Vector2(512,512)
	bay.mesh = quad
	var material := _far_material("background")
	material.set_shader_parameter("depth_fraction",.995)
	material.set_shader_parameter("tint",Color(str(layout.palette.water.far_fill)))
	material.render_priority = -100
	bay.material_override = material
	bay.extra_cull_margin = 100
	bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_far_zone.add_child(bay)

func _set_backdrop_visible(enabled: bool) -> void:
	if enabled == _backdrop_enabled:return
	_backdrop_enabled = enabled
	_far_zone.visible = enabled
	_sea_material.set_shader_parameter("false_horizon",enabled)

func _build_navigation() -> void:
	_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_nav_map, true)
	NavigationServer3D.map_set_cell_size(_nav_map, 0.25)
	NavigationServer3D.map_set_cell_height(_nav_map, 0.1)
	var vertices := PackedVector3Array()
	for v in layout.navigation.vertices: vertices.append(_vec(v))
	for zone_name in layout.zones:
		var nav := NavigationMesh.new()
		nav.vertices = vertices
		for p in layout.navigation.zone_polygons[zone_name]: nav.add_polygon(PackedInt32Array(p))
		nav.cell_size = 0.25
		nav.cell_height = 0.1
		var region := NavigationRegion3D.new()
		region.name = "Navigation"
		region.navigation_mesh = nav
		zones[zone_name].add_child(region)
		region.set_navigation_map(_nav_map)

func _follow_target() -> Vector3:
	var yaw := deg_to_rad(FarmCamera.YAW_DEG)
	return _player.position + Vector3.UP * .7 - Vector3(sin(yaw),0,cos(yaw)) * 2.8

func _spawn_player() -> void:
	_player = Node3D.new()
	_player.name = "Visitor"
	_player.position = _vec(layout.spawn)
	add_child(_player)
	_rig = Avatar.create_rig()
	_rig.assembler = AvatarAssemblerMerged.new()
	_rig.rotation.y = PI
	for child in _rig.get_children():
		if child is RigActivity:
			child.sleep_distance = 80
			child.reduced_distance = 60
	_player.add_child(_rig)
	_rig.config_applied.connect(func(_c): _animation("idle"))
	_rig.apply_config(Avatar.load_outfit())
	_focus = _follow_target()

func _animation(motion: String) -> void:
	_rig.play_motion(motion)

func navigation_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(_nav_map) > 0 \
		and NavigationServer3D.map_get_closest_point_owner(_nav_map, _player.position).is_valid()

func walk_to_screen(point: Vector2) -> void:
	if not navigation_ready(): return
	var origin := _camera.project_ray_origin(point)
	var normal := _camera.project_ray_normal(point)
	# Actual geometry hit resolves multi-level stairs without projecting through a higher terrace.
	var query := PhysicsRayQueryParameters3D.create(origin, origin + normal * 200.0)
	# The invisible boundary walls stand between the camera and the island's south side: a tap goes through them (it
	# stopped on SouthBoundary, so every tap walked to the south edge of the dock).
	query.exclude = _boundary_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var goal: Vector3
	if hit.is_empty():
		var ground = Plane(Vector3.UP, _player.position.y).intersects_ray(origin, normal)
		if ground == null: return
		goal = NavigationServer3D.map_get_closest_point(_nav_map, ground)
	else:
		goal = NavigationServer3D.map_get_closest_point(_nav_map, hit.position)
	walk_to(goal)

func find_path(start: Vector3, goal: Vector3) -> PackedVector3Array:
	var query := NavigationPathQueryParameters3D.new()
	query.map = _nav_map
	query.start_position = start
	query.target_position = goal
	# Godot defaults to 4096 searched polygons, which truncates this 3-zone island.
	query.path_search_max_polygons = maxi(4096, layout.navigation.polygons.size() + 64)
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query,result)
	return result.get_path()

func walk_to(goal: Vector3) -> void:
	if not navigation_ready(): return
	_path = find_path(_player.position, goal)
	_path_i = 0
	_following = true
	_overview = false
	camera_pan.reset(camera_pan.zoom)
	_stop_camera_recenter()

func _step_walk(delta: float) -> void:
	if _path_i >= _path.size():
		if _running and not stick_moving:   # the stick's walk is the stick's to end (step_stick)
			_running = false
			_animation("idle")
		return
	var goal := _path[_path_i]
	var to := goal - _player.position
	var step := WALK_SPEED * delta
	if to.length() <= step:
		_player.position = goal
		_path_i += 1
	else:
		_player.position += to.normalized() * step
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.01: _player.look_at(_player.position + flat, Vector3.UP)
	if not _running:
		_running = true
		_animation("run")

func _process(delta: float) -> void:
	_step_walk(delta)
	camera_pan.step(delta, _camera)
	if _following and not _overview and not camera_pan.active() and not _camera_recenter:
		_focus = _focus.lerp(_follow_target(), 1.0 - exp(-8.0 * delta))
	_update_camera()

func _update_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.y / maxf(1.0, size.x)
	var zoom_for_view := clampf(camera_pan.zoom,1.0/3.0,1.4)
	var width := (78.0 if _overview else PHONE_WIDTH) / zoom_for_view
	_camera.size = width
	# Low decorations have a screen-size LOD; tree silhouettes and rails remain.
	for node in _detail_groups:node.visible=_overview or width<=float(node.get_meta("max_view_width_m"))
	for node in _detail_batches:
		node.visible = _overview or width<=float(node.get_meta("max_view_width_m"))
	if not camera_pan.active():
		_focus += camera_pan.offset
		camera_pan.offset = Vector3.ZERO
		camera_pan._raw_offset = Vector3.ZERO
	# Bound manual exploration well inside the 512 m ocean backdrop.
	_focus.x = clampf(_focus.x, -50, 50)
	_focus.z = clampf(_focus.z, -40, 40)
	var target := _focus + camera_pan.offset
	var wide := clampf((1.0/zoom_for_view-1.0)/2.0,0.0,1.0) if not _overview else 0.0
	# In P0 the camera keeps FarmCamera's yaw at every zoom, on the player: the wide end's swing to 60° turned it out
	# to sea from the dock (the island's south-west corner), the island off the screen's side.
	if p0_visit: wide = 0.0
	var yaw := deg_to_rad(lerpf(FarmCamera.YAW_DEG,60.0,wide))
	var pitch := deg_to_rad(43.0)
	# Approved oblique framing only at the wide end; default camera is unchanged.
	var close_bias := Vector3.UP*.7-Vector3(sin(deg_to_rad(14.5)),0,cos(deg_to_rad(14.5)))*2.8
	target += (Vector3(-5,7.75,-2)-close_bias)*wide
	_camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*11
	_camera.look_at(target,Vector3.UP)
	FarmCamera.fit_ground_depth(_camera,-.2,28.0)
	_update_tree_lods(_camera.global_position)
	# Compact visible decorations into the existing MultiMesh. Whole-zone bounds
	# would otherwise submit every flower and rock. Shadow casters stay untouched.
	var planes := _camera.get_frustum()
	for node in _unshadowed_batches:
		var eligible := _overview or width<=float(node.get_meta("max_view_width_m",INF))
		var visible_count := 0
		var bounds: Array = node.get_meta("instance_bounds")
		var transforms: Array = node.get_meta("instance_transforms")
		if eligible:
			for i in bounds.size():
				var box: AABB = bounds[i]
				var outside := false
				for plane in planes:
					var minimum := box.position
					if plane.normal.x<0:minimum.x+=box.size.x
					if plane.normal.y<0:minimum.y+=box.size.y
					if plane.normal.z<0:minimum.z+=box.size.z
					if plane.distance_to(minimum)>.02:
						outside=true
						break
				if not outside:
					node.multimesh.set_instance_transform(visible_count,transforms[i])
					visible_count+=1
		node.multimesh.visible_instance_count=visible_count
		node.visible=visible_count>0
	_set_backdrop_visible(not _overview)
	if _exit_button:
		var point := _camera.unproject_position(_vec(layout.exit) + Vector3.UP * .45)
		_exit_marker.visible = not _overview and not _camera.is_position_behind(_vec(layout.exit)) \
			and Rect2(Vector2(30,60), size - Vector2(60,130)).has_point(point)
		_exit_marker.position = point - Vector2(24,20)

func _build_controls() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var title := Label.new()
	title.text = "Alcatraz Island"
	title.position = Vector2(16,14)
	title.add_theme_color_override("font_color", Color("343b3c"))
	title.add_theme_font_size_override("font_size",18)
	_hud.add_child(title)
	_exit_marker = VBoxContainer.new()
	_exit_marker.name = "DockExitMarker"
	_exit_marker.add_theme_constant_override("separation",2)
	_hud.add_child(_exit_marker)
	_exit_button = Button.new()
	_exit_button.name = "DockMapExit"
	_exit_button.icon = preload("res://assets/ui/icons/game/door-open.svg")
	_exit_button.expand_icon = true
	_exit_button.add_theme_constant_override("icon_max_width",22)
	_exit_button.custom_minimum_size = Vector2(48,44)
	_exit_button.pressed.connect(_leave)
	_exit_marker.add_child(_exit_button)
	var map_name := Label.new()
	map_name.text = "Map"
	map_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name.add_theme_font_size_override("font_size",13)
	var name_background := StyleBoxFlat.new()
	name_background.bg_color = Color(0.18,0.22,0.23,.9)
	map_name.add_theme_stylebox_override("normal",name_background)
	_exit_marker.add_child(map_name)
	var controls := HBoxContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -56
	controls.offset_bottom = -12
	controls.offset_left = 12
	controls.offset_right = -12
	_hud.add_child(controls)
	for caption in ["Follow"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(88,44)
		controls.add_child(button)
		button.pressed.connect(recenter_on_player if caption == "Follow" else toggle_overview)
	var zoom_row := VBoxContainer.new()
	zoom_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zoom_row.position = Vector2(-60,-48)
	_hud.add_child(zoom_row)
	for spec in [["ZoomIn","+",1.15],["ZoomOut","−",1.0/1.15]]:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.custom_minimum_size = Vector2(44,44)
		zoom_row.add_child(button)
		_zoom_buttons[spec[0]]=button
		button.pressed.connect(func(): _zoom_by(float(spec[2])))

func _zoom_by(factor: float) -> void:
	_stop_camera_recenter()
	camera_pan.reset(clampf(camera_pan.zoom*factor,1.0/3.0,1.4))
	_overview = false
	_update_camera()

func _input(event: InputEvent) -> void:
	if p0_visit == null: _handle_camera_input(event, false)

func _unhandled_input(event: InputEvent) -> void:
	if p0_visit == null: _handle_camera_input(event, true)

func _handle_camera_input(event: InputEvent, allow_start: bool) -> bool:
	if camera_pan.handle(event, _camera, allow_start):
		if camera_pan.dragged or camera_pan.multi:
			_following = false
			_stop_camera_recenter()
		_update_camera()
		get_viewport().set_input_as_handled()
		return true
	return false

func _stop_camera_recenter() -> void:
	if _camera_recenter:
		_camera_recenter.kill()
		_camera_recenter = null

func recenter_on_player() -> void:
	_stop_camera_recenter()
	camera_pan.reset(camera_pan.zoom)
	_overview = false
	_following = true
	var start := _focus
	_camera_recenter = create_tween()
	_camera_recenter.tween_method(func(w: float):
		_focus = start.lerp(_follow_target(), w)
		_update_camera(), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_recenter.finished.connect(func(): _camera_recenter = null)

func toggle_overview() -> void:
	_stop_camera_recenter()
	camera_pan.reset()
	_overview = not _overview
	_following = not _overview
	_focus = Vector3(0,6,0) if _overview else _follow_target()
	_update_camera()

func _leave() -> void:
	exit_requested.emit()
	var router := get_node_or_null("/root/AppRouter")
	if router and router.top_instance() == self: router.handle_back()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		camera_pan.cancel()
		_stop_camera_recenter()

func suspend() -> void:
	_stop_camera_recenter()
	camera_pan.cancel()
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	if _hud: _hud.visible = false
	_set_backdrop_visible(false)
	_camera.current = false
	_saved_environment = _environment.environment
	_environment.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	if _hud: _hud.visible = true
	get_viewport().transparent_bg = false
	_environment.environment = _saved_environment
	_camera.make_current()
	_update_camera()
	if p0_visit: p0_visit.resume()

func _exit_tree() -> void:
	if p0_visit: p0_visit.clear()
	_stop_camera_recenter()
	camera_pan.cancel()
	if _nav_map.is_valid():
		NavigationServer3D.free_rid(_nav_map)
		_nav_map = RID()

# ---------------------------------------------------------------- P0 world (P0LandmarkVisit, q(295))
func p0_surface() -> String: return "visit"
## q(311) ② (不知火舞 on #988): what can hide a person on the island from the camera — every placement that stands in
## the way (collision: the dock's props since 474, rails, benches, lamps …; not the dock's own deck) as its mesh's box
## in its own space, with its transform and name: [Transform3D, AABB, name]. Read once.
var _occluders: Array = []
func occluders() -> Array:
	if _occluders.is_empty():
		for p in layout.placements:
			if not bool(p.get("collision", false)) or str(p.asset) == "dock" or str(p.zone) == "FarZone": continue
			var m := _mesh(str(p.asset))
			if m == null: continue
			_occluders.append([_transform_of(p), m.get_aabb(), str(p.name)])   # as drawn (a sloped rail's basis too)
	return _occluders
## q(311) ④: the arrival cover waits for the room to say where the player stands (P0LandmarkVisit.landing).
func p0_landing_pending() -> bool: return p0_visit != null and p0_visit.landing_pending()
func p0_frame(_v: Dictionary, dt: float) -> void: p0_visit.frame(dt)
func p0_tap(screen: Vector2) -> void: p0_visit.tap(screen)
func p0_recenter() -> void: recenter_on_player()
func p0_zoom_end() -> void: pass

func p0_joystick(v: Vector2) -> void:
	p0_visit.stick = v
	if v != Vector2.ZERO: _path = PackedVector3Array()   # the stick takes over from a tap's walk

## A pinch: about the player, who stays followed (P0 has no free pan here).
func p0_zoom(f: float, _at := Vector2.INF) -> void:
	_stop_camera_recenter()
	camera_pan.reset(clampf(camera_pan.zoom * f, camera_pan.min_zoom, camera_pan.max_zoom))
	_following = true
	_update_camera()

func p0_dev(step: Array) -> bool: return p0_visit.dev(step)

## Dev: a named review point (layout `review_points`), INF for none; the player stood there, the camera on them.
func dev_point(n: String) -> Vector3:
	var pts: Dictionary = layout.get("review_points", {})
	return _vec(pts[n]) if pts.has(n) else Vector3.INF

func dev_stand(at: Vector3) -> void:
	_path = PackedVector3Array()
	_player.position = NavigationServer3D.map_get_closest_point(_nav_map, at) if navigation_ready() else at
	_focus = _follow_target()

func player_position() -> Vector3: return _player.position
## The walkable ground (P0LandmarkVisit: the others stood on it, SGODOT-462).
func nav_map() -> RID: return _nav_map
func exit_position() -> Vector3: return _vec(layout.exit)
func walking() -> bool: return _path_i < _path.size()

## The stick (P0LandmarkVisit.stick_step): the followed player runs while it is pushed, along an edge at the slide's
## speed; held against one it cannot pass, it stands after P0Actor.PUSH_IDLE_S (SGODOT-306, the slide spec).
func step_stick(v: Vector2, dt: float) -> void:
	if not navigation_ready(): return
	var went := P0LandmarkVisit.stick_step(_player, _nav_map, _camera, WALK_SPEED, v, dt)
	stick_moving = went >= 0.0
	if not stick_moving:
		_stick_idle()
		return
	_following = true
	_overview = false
	_stick_still = _stick_still + dt if went < PlayerMover.STUCK_RATIO else 0.0
	var run := _stick_still < P0Actor.PUSH_IDLE_S
	if run != _running:
		_running = run
		_animation("run" if run else "idle")
	P0LandmarkVisit.run_speed(_rig, went if run and went >= PlayerMover.STUCK_RATIO else 1.0)

func _stick_idle() -> void:
	_stick_still = 0.0
	P0LandmarkVisit.run_speed(_rig, 1.0)
	if _running and not walking():
		_running = false
		_animation("idle")

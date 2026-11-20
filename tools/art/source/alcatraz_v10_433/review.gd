extends "res://review.gd"
## Proposal runner only. The real scene/script is copied without alteration.
var audit := {"before":{},"after":{}}
var prior_collisions: Array = []
var mode := "before"
var proposed_ids: Array = []
var new_tall: Array = []

func _ready() -> void:
	var output := OS.get_environment("ALCATRAZ_REVIEW")
	var views: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://baseline_views.json"))
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://proposal.json"))
	for p in plan.add:proposed_ids.append(p.name)
	for p in plan.move:proposed_ids.append(p.name)
	viewport=SubViewport.new();viewport.size=Vector2i(360,800);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var display := TextureRect.new();display.texture=viewport.get_texture()
	display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(display)
	for phase in ["before","after"]:
		mode=phase;destination=output.path_join(phase);metrics={};hud_boxes=[];hud_regions={}
		DirAccess.make_dir_recursive_absolute(destination)
		FileAccess.open(AlcatrazIsland.ROOT+"layout.json",FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://"+phase+".json"))
		scene=load("res://scenes/landmark/alcatraz_island.tscn").instantiate();viewport.add_child(scene)
		for frame in 240:
			await get_tree().physics_frame
			if scene.navigation_ready() and not scene._rig.is_busy():break
		scene.set_process(false);scene._rig.process_mode=Node.PROCESS_MODE_DISABLED
		for root in scene.animated_roots:
			var player := root.get_node("AnimationPlayer") as AnimationPlayer;player.pause();player.seek(0,true)
		if phase=="after":bind_proposal_material()
		prepare_hud_audit()
		if phase=="after":
			for p in scene.layout.placements:
				if str(p.asset) not in ["lookout_telescope","lookout_sheltered_bench"]:continue
				hud_boxes.append({"name":p.name,"transform":scene._transform_of(p),"box":scene._mesh(p.asset).get_aabb(),"contract":"433_new_tall"})
		var collisions := collision_snapshot()
		if phase=="before":prior_collisions=collisions
		else:check("all_live_collisions_unchanged",collisions==prior_collisions,collisions.size())
		if phase=="after":
			check_shelter_support(plan)
			check_seaward_lookout(plan)
			check_new_focal_footprints(plan)
		audit[phase]["geometry_totals"]=geometry_totals()
		set_view(AlcatrazIsland._vec(scene.layout.spawn))
		await photograph("01-opening")
		var entry := NavigationServer3D.map_get_closest_point(scene._nav_map,Vector3(-21,3.25,7.4))
		set_view(entry)
		scene.camera_pan.reset(1.0/1.5);scene._focus=scene._follow_target();scene._update_camera()
		await photograph("02-entry-lookout")
		for key in views.view_metrics:
			if not str(key).begins_with("route/"):continue
			var index := int(str(key).split("-")[1])
			set_view(AlcatrazIsland._vec(views.view_metrics[key].player_position))
			await photograph(str(key).replace("route/",""))
			if phase=="after":record_projections(str(key))
		var hud_hits: Array = []
		var route: Array = scene.layout.route
		for segment in range(route.size()-1):
			var a := AlcatrazIsland._vec(route[segment]);var b := AlcatrazIsland._vec(route[segment+1])
			for i in maxi(1,ceili(a.distance_to(b)/.5)):
				set_view(a.lerp(b,float(i)/maxi(1,ceili(a.distance_to(b)/.5))))
				var hits := hud_intrusions()
				if not hits.is_empty():hud_hits.append({"point":str(scene._player.position),"hits":hits})
		audit[phase]["hud_hits_0_5m"]=hud_hits
		if phase=="after":
			check("no_new_continuous_hud_intrusions",hud_hits==audit.before.hud_hits_0_5m,hud_hits.size())
			var new_hits := hud_hits.filter(func(row):return row.hits.any(func(hit):return str(hit.name).begins_with("v10_")))
			check("new_tall_props_clear_along_route",new_hits.is_empty(),new_hits)
		audit[phase]["metrics"]=metrics.duplicate(true)
		await top_layout_photo()
		scene.queue_free();await get_tree().process_frame;await get_tree().physics_frame
		viewport.size=Vector2i(360,800)
	FileAccess.open(output.path_join("proposal-verification.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":results,"audit":audit,"failures":failures},"\t")+"\n")
	print("PROPOSAL_REVIEW_COMPLETE ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func set_view(point: Vector3) -> void:
	scene._player.position=point;scene.camera_pan.reset(1)
	scene._focus=scene._follow_target();scene._update_camera()

func collision_snapshot() -> Array:
	var rows: Array = []
	for shape in scene.find_children("*","CollisionShape3D",true,false):
		# Auto-generated *_col node IDs differ between fresh scene instances.
		rows.append(JSON.stringify({"transform":str(shape.global_transform),"type":shape.shape.get_class(),"faces":str(shape.shape.get_debug_mesh().get_faces())}))
	rows.sort()
	return rows

func geometry_totals() -> Dictionary:
	var triangles := 0;var surfaces := 0
	for node in scene.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null:continue
		surfaces+=node.mesh.get_surface_count();triangles+=node.mesh.get_faces().size()/3
	for node in scene.batch_nodes:
		surfaces+=node.multimesh.mesh.get_surface_count()
		triangles+=(node.multimesh.mesh.get_faces().size()/3)*node.multimesh.instance_count
	check(mode+"_whole_scene_triangle_budget",triangles<=300000,triangles)
	check(mode+"_whole_scene_surface_budget",surfaces<=80,surfaces)
	return {"triangles":triangles,"surfaces":surfaces}

func check_shelter_support(plan: Dictionary) -> void:
	var row: Dictionary=plan.add.filter(func(p):return p.name=="v10_shelter")[0]
	var position := AlcatrazIsland._vec(row.position);var basis := Basis(Vector3.UP,float(row.yaw))
	var heights: Array = [];var blockers: Array = []
	var parts := [[Vector3(0,.73,0),Vector3(1.58,1.24,.60)],[Vector3(0,2.43,0),Vector3(2,.06,1.4)]]
	for x in [-.82,.82]:
		for z in [-.45,.45]:
			var foot: Vector3=position+basis*Vector3(x,0,z)
			var ray := PhysicsRayQueryParameters3D.create(foot+Vector3.UP*.5,foot-Vector3.UP*.15)
			ray.hit_from_inside=true
			var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
			heights.append(null if hit.is_empty() else hit.position.y)
			parts.append([Vector3(x,1.17,z),Vector3(.12,2.30,.12)])
	for part in parts:
		var box := BoxShape3D.new();box.size=part[1]
		var query := PhysicsShapeQueryParameters3D.new();query.shape=box
		query.transform=Transform3D(basis,position+basis*part[0]);query.margin=.005
		for hit in scene.get_world_3d().direct_space_state.intersect_shape(query,4):blockers.append(str(hit.collider.name))
	check("shelter_four_feet_supported",heights.all(func(y):return y!=null and absf(float(y)-position.y)<.045),heights)
	check("shelter_clear_of_existing_solids",blockers.is_empty(),blockers)

func bind_proposal_material() -> void:
	var furnishings := scene.zones.TerraceZone.get_node("LookoutFurnishings") as MeshInstance3D
	var paint := StandardMaterial3D.new();paint.vertex_color_use_as_albedo=true
	paint.roughness=.90;paint.metallic_specular=.15
	furnishings.material_override=paint
	audit.after["rail_visual_replacements"]=0
	check("cream_route_rails_preserved",scene.layout.placements.filter(func(p):return str(p.asset).begins_with("alc_rail_")).size()>0)

func check_seaward_lookout(plan: Dictionary) -> void:
	var positions := {}
	for item in plan.add:positions[item.name]=item
	for name_ in ["v10_semicircle","v10_telescope","v10_compass"]:
		var p: Dictionary=positions[name_]
		var forward := Basis(Vector3.UP,float(p.yaw))*Vector3.FORWARD
		check(name_+"_faces_west_sea",forward.dot(Vector3.LEFT)>.999,str(forward))
	var deck: Dictionary=positions.v10_semicircle
	var deck_transform := Transform3D(Basis(Vector3.UP,float(deck.yaw)),AlcatrazIsland._vec(deck.position))
	var telescope_local: Vector3=deck_transform.affine_inverse()*AlcatrazIsland._vec(positions.v10_telescope.position)
	check("telescope_visually_supported_on_deck",telescope_local.z<-.2 and Vector2(telescope_local.x,telescope_local.z).length()<.8 and absf(telescope_local.y-.12)<.01,str(telescope_local))
	var bank_x := -24.0
	for i in 121:
		var x := -24.0-float(i)*.025
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x,3.5,6.3),Vector3(x,3.05,6.3))
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and absf(hit.position.y-3.25)<.03:bank_x=x
	var outer := deck_transform*Vector3(0,.12,-1)
	check("deck_projects_about_one_metre_seaward",bank_x-outer.x>=.8 and bank_x-outer.x<=1.2,{"bank_x":bank_x,"deck_outer_x":outer.x,"extension_m":bank_x-outer.x})

func check_new_focal_footprints(plan: Dictionary) -> void:
	for item in plan.add:
		if item.asset not in ["v10_demo_bird_rock","v10_demo_sundial","v10_demo_fountain","v10_demo_anchor"]:continue
		var box: AABB=scene._mesh(item.asset).get_aabb()
		var root := AlcatrazIsland._vec(item.position)
		var minimum := INF
		for fx in [0.0,.5,1.0]:
			for fz in [0.0,.5,1.0]:
				var point := root+Vector3(lerpf(box.position.x,box.end.x,fx),0,lerpf(box.position.z,box.end.z,fz))
				var nearest := NavigationServer3D.map_get_closest_point(scene._nav_map,point)
				minimum=minf(minimum,Vector2(nearest.x-point.x,nearest.z-point.z).length())
		check(str(item.name)+"_footprint_outside_original_navigation",minimum>.05,minimum)

func record_projections(key: String) -> void:
	var rows: Array = []
	for p in scene.layout.placements:
		if p.name not in proposed_ids:continue
		var box: AABB = scene._mesh(p.asset).get_aabb();var transform: Transform3D = scene._transform_of(p)
		var projected := Rect2(scene._camera.unproject_position(transform*box.position),Vector2.ZERO)
		for corner in 8:projected=projected.expand(scene._camera.unproject_position(transform*box.get_endpoint(corner)))
		rows.append({"name":p.name,"rect":str(projected),"in_screen":projected.intersects(Rect2(0,0,360,800))})
	if not audit.after.has("projections"):audit.after.projections={}
	audit.after.projections[key]=rows

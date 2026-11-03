extends SceneTree
var checks:=[]
func _initialize() -> void: run.call_deferred()
func vec(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])
func check(ok: bool,label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://navigation-fixture.json"))
	var art=load("res://scenes/poi_classroom/poi_classroom_art.tscn").instantiate();root.add_child(art)
	for row in data.plan.placements:
		check(art.has_node(str(row.name)),"assembled module exists: "+str(row.name))
	check(art.find_children("seat_*","Marker3D",true,false).size()==6,"assembly completed all six seat anchors")
	for i in 3:await physics_frame
	var space:=root.get_world_3d().direct_space_state
	var cfg: Dictionary=data.grid
	var paths:=[]
	for mode in cfg.modes:
		var radius:=float(mode.radius)
		var grid:=AStarGrid2D.new();grid.region=Rect2i(0,0,int(cfg.width),int(cfg.depth))
		grid.cell_size=Vector2.ONE*float(cfg.step);grid.offset=Vector2(cfg.origin[0],cfg.origin[1])
		grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
		for index in mode.blocked:grid.set_point_solid(Vector2i(int(index)%int(cfg.width),int(index)/int(cfg.width)))
		var capsule:=CapsuleShape3D.new();capsule.radius=radius;capsule.height=1.745
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.margin=.0001
		var spawn:=vec(data.plan.spawn)
		var start:=Vector2i(((Vector2(spawn.x,spawn.z)-grid.offset)/grid.cell_size).round())
		var targets: Array=data.targets.duplicate(true)
		if radius<.3:
			for i in data.analysis.standing_16.size():targets.append({"name":"standing_%02d"%i,"position":data.analysis.standing_16[i]})
		for target in targets:
			var at:=vec(target.get("main_position",target.position) if radius>.3 else target.position)
			var end:=Vector2i(((Vector2(at.x,at.z)-grid.offset)/grid.cell_size).round())
			var route:=grid.get_point_path(start,end)
			var clear:=not route.is_empty()
			if clear:
				route.insert(0,Vector2(spawn.x,spawn.z));route.append(Vector2(at.x,at.z))
				for i in range(1,route.size()):
					query.transform.origin=Vector3(route[i-1].x,.08+1.745/2+.003,route[i-1].y)
					query.motion=Vector3(route[i].x-route[i-1].x,0,route[i].y-route[i-1].y)
					if space.cast_motion(query)[0]<.999:clear=false;break
			check(clear,"assembled-scene capsule %.2f m to %s"%[radius,target.name])
			paths.append({"name":target.name,"radius":radius,"clear":clear,"points_xz":Array(route).map(func(p):return [p.x,p.y])})
	var nav:=P0RoomNav.build(P0RoomNav.shapes_from(art))
	for target in data.targets:
		var at: Vector3=vec(target.position)+nav.offset
		var nearest: Vector3=P0RoomNav.nearest_walkable(nav.bp,at)
		check(Vector2(at.x,at.z).distance_to(Vector2(nearest.x,nearest.z))<.12,"native navigation target "+target.name)
	var passed:=checks.all(func(c):return c.passed)
	FileAccess.open("res://../navigation.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"paths":paths},"\t")+"\n")
	print("CLASSROOM_NAVIGATION ",passed," checks=",checks.size())
	quit(0 if passed else 1)

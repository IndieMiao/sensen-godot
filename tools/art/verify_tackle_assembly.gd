extends SceneTree
## Compare authored colliders with actual scene nodes, then exercise the real
## P0RoomNav mask and connected paths. No layout boundaries/floor_size fallback.
var report = {"checks": [], "colliders": [], "paths": {}}
func _initialize(): run.call_deferred()
func vec(a): return Vector3(a[0],a[1],a[2])
func check(ok,label):
	report.checks.append({"check":label,"passed":ok})
	if not ok:push_error(label)
func run():
	var room = load("res://scenes/tackle_shop/tackle_shop_art.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var layout = room.layout
	var by_name = {}
	var placements = []
	for asset in layout.assets:by_name[asset.name]=asset;placements.append([asset,asset])
	for instance in layout.instances:placements.append([by_name[instance.asset],instance])
	var expected_count = 0
	for pair in placements:
		var asset = pair[0];var placement = pair[1];var container = room.get_node(placement.name)
		for i in asset.colliders.size():
			expected_count += 1
			var data = asset.colliders[i]
			var collision = container.get_node_or_null("Collider_%02d/Shape" % i)
			check(collision is CollisionShape3D,"Actual collider exists: %s/%d" % [placement.name,i])
			if collision == null:continue
			var rotation = vec(data.get("rotation",[0,0,0])) * PI/180.0
			var expected = container.global_transform * Transform3D(Basis.from_euler(rotation),vec(data.at))
			check(collision.global_transform.is_equal_approx(expected),"Collider placement/rotation/instance scale: %s/%d" % [placement.name,i])
			check(not collision.disabled and collision.get_parent() is StaticBody3D,"Collider enabled and physical: %s/%d" % [placement.name,i])
			if data.get("kind","box") == "box":
				check(collision.shape is BoxShape3D and collision.shape.size.is_equal_approx(vec(data.size)),"Collider box dimensions: %s/%d" % [placement.name,i])
			else:
				check(collision.shape is CylinderShape3D and is_equal_approx(collision.shape.radius,float(data.radius)) and is_equal_approx(collision.shape.height,float(data.height)),"Collider cylinder dimensions: %s/%d" % [placement.name,i])
			report.colliders.append({"module":placement.name,"index":i,"world_position":[collision.global_position.x,collision.global_position.y,collision.global_position.z]})
	var actual = room.find_children("*","CollisionShape3D",true,false)
	check(actual.size()==expected_count,"Every asset/instance collider instantiated exactly once")
	var nav_script = load("res://modules/p0/p0_room_nav.gd")
	var shapes = nav_script.shapes_from(room)
	check(shapes.size()==expected_count,"P0RoomNav reads all actual collision shapes")
	var nav = nav_script.build(shapes)
	var bp = nav.bp
	check(is_equal_approx(nav.floor_y,.08),"P0RoomNav derives floor Y=.08 from collider")
	check(nav.bounds.size.is_equal_approx(Vector2(6.8,6.4)),"P0RoomNav derives 6.8x6.4 bounds from largest floor collider")
	var start = bp.world_to_cell(room.get_node("spawn").position + nav.offset)
	check(bp.is_walkable(start),"Native navigation spawn is walkable")
	var visited = {};var queue = [start];var cursor = 0;visited[start]=true
	while cursor < queue.size():
		var cell = queue[cursor];cursor+=1
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next = cell+step
			if not visited.has(next) and bp.is_walkable(next):visited[next]=true;queue.append(next)
	for anchor in layout.anchors:
		if not anchor.name.begins_with("stand_") and not anchor.name.begins_with("npc_"):continue
		var cell = bp.world_to_cell(vec(anchor.position)+nav.offset)
		var reachable = visited.has(cell)
		check(reachable,"Spawn reaches native navigation cell: "+anchor.name)
		report.paths[anchor.name]={"cell":[cell.x,cell.y],"reachable":reachable}
	for name in ["curved_counter","right_low_shelf","rod_rack","left_rope_crate","rafa_fish_creel"]:
		var point = room.get_node(name).position
		check(not bp.is_walkable(bp.world_to_cell(point+nav.offset)),"Native navigation blocks furniture: "+name)
	var exit_approach = Vector3(0,.08,3.0)
	check(visited.has(bp.world_to_cell(exit_approach+nav.offset)) and exit_approach.distance_to(room.get_node("exit").position)<.6,
		"Native path reaches front exit trigger radius")
	for point in [Vector3(-3.27,0,0),Vector3(0,0,-3.07),Vector3(3.36,0,0),Vector3(1.5,0,3.16)]:
		check(not bp.is_walkable(bp.world_to_cell(point+nav.offset)),"Native navigation blocks authored wall/edge "+str(point))
	# Negative control: remove only counter shapes in memory; its occupied cell
	# becomes walkable, proving this test reads physical geometry, not metadata.
	var without_counter = []
	for i in shapes.size():
		if report.colliders[i].module != "curved_counter":without_counter.append(shapes[i])
	var bad = nav_script.build(without_counter)
	check(bad.bp.is_walkable(bad.bp.world_to_cell(room.get_node("curved_counter").position+bad.offset)),
		"Negative control: removing counter collision opens its native navigation cell")
	report.native_grid={"size":[bp.grid.x,bp.grid.y],"floor_y":nav.floor_y,"reachable_cells":visited.size(),"walkable_rows":Array(bp.masks.walkable)}
	report.sources=JSON.parse_string(FileAccess.get_file_as_string("res://nav-review-sources.json"))
	report.failures=report.checks.filter(func(c):return not c.passed)
	var out=ProjectSettings.globalize_path("res://../v11/assembly-nav-validation.json")
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("ASSEMBLY_NAV_QA ",report.checks.size()," checks; ",report.failures.size()," failures")
	quit(0 if report.failures.is_empty() else 1)

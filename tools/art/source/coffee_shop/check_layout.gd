extends SceneTree
## Per-scene geometric checks. Full avatar/input evidence comes from scene_bench.
var room: Node3D
var space: PhysicsDirectSpaceState3D
var checks: Array = []
func _initialize() -> void: call_deferred("check_layout")
func vec(a: Array) -> Vector3: return Vector3(float(a[0]),float(a[1]),float(a[2]))
func record(name: String, ok: bool, detail: Variant) -> void:
	checks.append({"name":name,"pass":ok,"detail":detail})
	print("COFFEE_LAYOUT ",name," ",ok)
func sweep(a: Array,b: Array,radius: float) -> float:
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 1.25
	q.shape = capsule
	q.transform.origin = vec(a) + Vector3(0,.63,0)
	q.motion = vec(b)-vec(a)
	q.margin = .001
	var fractions := space.cast_motion(q)
	return fractions[0] if fractions.size() > 0 else 0.0
func check_layout() -> void:
	var output := OS.get_cmdline_user_args()[0]
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/coffee_shop/layout.json"))
	room = (load("res://scenes/coffee_shop/coffee_shop_art.tscn") as PackedScene).instantiate()
	root.add_child(room)
	for i in range(3): await physics_frame
	space = room.get_world_3d().direct_space_state
	for point: Dictionary in layout.bench.route:
		var at := vec(point.position)
		var query := PhysicsRayQueryParameters3D.create(at+Vector3(0,.35,0),at-Vector3(0,.60,0))
		var hit := space.intersect_ray(query)
		record("floor_"+point.name,not hit.is_empty() and absf(hit.position.y-at.y)<.22,hit.position.y if not hit.is_empty() else "no floor")
	for point: Dictionary in layout.bench.blocked:
		var fraction := sweep(point.from,point.to,.21)
		record("blocked_"+point.name,fraction<.98,fraction)
	for gap: Dictionary in layout.bench.gaps:
		if gap.name == "entry": continue # slope traversal belongs to the character harness
		var fraction := sweep(gap.from,gap.to,.35)
		record("width_0.70m_"+gap.name,fraction>.999,fraction)
	var failed := checks.filter(func(c): return not c.pass)
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"scene geometry only; not avatar/input or route traversal acceptance","renderer":RenderingServer.get_current_rendering_method(),"checks":checks,"failed":failed.size()},"  ")+"\n")
	quit(0 if failed.is_empty() else 1)

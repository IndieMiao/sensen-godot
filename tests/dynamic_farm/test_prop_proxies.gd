extends SceneTree
## Tests the imported (not inventory-AABB) geometry and the actual build → walk path.
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Proxy = Scenery.Proxy
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Outline = preload("res://tests/dynamic_farm/prop_outline.gd")
const MIN_SIZE := 0.8  # PM default: the walker footprint is 80–100% of the outline
const MAX_GAP_M := 0.03  # visible ground left between the body and the model at contact
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func xz(v: Vector3) -> Vector2: return Vector2(v.x,v.z)
func v3(p: Vector2) -> Vector3: return Vector3(p.x,0,p.y)

func grid() -> Dictionary:
	var data := {"cell_m":0.8,"grid_size":Vector2i(20,20),"spawn":Vector2i(10,10),"by_cell":{}}
	for y in 20:
		for x in 20: data.by_cell[Vector2i(x,y)] = true
	return data

## Boundary and interior samples of the primitive's footprint, in its own orientation.
func footprint(proxy: Proxy) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 96:
		var direction := Vector3(cos(i*TAU/96),0,sin(i*TAU/96))
		var world := proxy.pose.basis * direction
		world.y = 0
		# Walk out to the edge: the footprint is convex and contains its centre.
		var lo := 0.0
		var hi := 2.0
		for _j in 30:
			var mid := (lo+hi)*0.5
			if proxy.gap(proxy.pose.origin + world.normalized()*mid) <= 0.0: lo = mid
			else: hi = mid
		for radius in [0.0,0.25,0.5,0.75,1.0]:
			points.append(xz(proxy.pose.origin + world.normalized()*lo*radius))
	return points

func size_ratio(proxy: Proxy, inside: Callable) -> float:
	# Linear size from areas, independent of the trunk polygon's orientation.
	var c := xz(proxy.pose.origin)
	var in_proxy := 0
	var in_outline := 0
	for iy in range(-200,200):
		for ix in range(-200,200):
			var p := c + Vector2(ix+0.5,iy+0.5)*0.004
			if proxy.gap(v3(p)) <= 0.0: in_proxy += 1
			if inside.call(p): in_outline += 1
	return sqrt(float(in_proxy)/in_outline)

func width_ratio(proxy: Proxy, outline: Outline, inside: Callable, axis: Vector3) -> float:
	var c := xz(proxy.pose.origin)
	var d := xz(axis).normalized()
	return 2.0*proxy.reach(axis)/(outline.reach(c,d,inside)+outline.reach(c,-d,inside))

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	var fit: float = catalog.collision_fit_fraction
	check(catalog.assets.size()==13,"complete approved inventory")
	check(fit>=0.8 and fit<=1.0,"tuning range")
	for asset: Dictionary in catalog.assets:
		var profile: Dictionary = asset.collision_proxy
		var tree: bool = asset.role=="tree"
		var blocking: bool = asset.role in ["tree","shrub","rock"]
		var mesh := Scenery.Art.mesh_for(asset.id)
		var outline := Outline.new(mesh,tree,float(profile.get("height_m",0.0)))
		check(profile.shape in ["box","capsule","cylinder"],asset.id+" approved primitive")
		var full := Proxy.new(profile,Transform3D.IDENTITY,1.0)
		check(full.solid==blocking,asset.id+" role policy")
		var center := xz(full.pose.origin)
		# The card's visible outline: the model's top-down projection.
		var within := true
		for p in footprint(full): within = within and outline.inside(p)
		check(within,asset.id+" within the measured silhouette at full fit")
		if not blocking: continue
		var local := Proxy.new(profile,Transform3D.IDENTITY,fit)
		var fitted: Callable = outline.inside
		var covering := false
		if tree:
			# Inside the trunk/root hull — or, where splayed roots defeat every inscribed
			# primitive, the smallest cylinder that keeps the walker off the roots.
			var in_hull := true
			for p in footprint(full): in_hull = in_hull and outline.in_hull(p)
			covering = not in_hull
			check(in_hull or (profile.shape=="cylinder" and local.reach(Vector3.RIGHT)+Walk.BODY_RADIUS <= outline.spread(center)+0.005),
				asset.id+" trunk hull, or the least root cover")
			fitted = outline.in_hull
		check(size_ratio(local,fitted)>=MIN_SIZE,asset.id+" default footprint at least 80% of the outline")
		if not covering:
			for axis in [local.pose.basis.x,local.pose.basis.z]:
				check(width_ratio(local,outline,fitted,axis)>=MIN_SIZE,asset.id+" default width at least 80% along its axes")
		# Production build and walker at an arbitrary translated/rotated/scaled placement,
		# without an extension-cell or role flag: every layer gets the same profile.
		var data := grid()
		var walk := Walk.new(data)
		var tr := Transform3D(Basis(Vector3.UP,0.53).scaled(Vector3.ONE*0.85),Vector3(-0.83,0,1.37))
		var scene := Scenery.build({"layout":[{"asset":asset.id,"transform":tr,"shadow":false,"triangles":asset.triangles}]},walk)
		check(scene.ok,asset.id+" builds")
		var proxy := Proxy.new(profile,tr,fit)
		# Against the real model: the walker's centre can reach no solid model point.
		var entered := 0
		for p in outline.solid_points:
			if walk.clear_position(tr*v3(p)): entered += 1
		check(entered==0,asset.id+" model points unreachable (%d reachable)"%entered)
		var widest_gap := 0.0
		for i in 16:
			# Approach from all sides: stop at the model, not a gap away and not inside it.
			var d := Vector3(cos(i*TAU/16),0,sin(i*TAU/16))
			var c := proxy.pose.origin*Vector3(1,0,1)
			walk.position = c+d*2.5
			walk.move(-d*2.5)
			var local_d := xz(tr.basis.inverse()*d).normalized()
			var gap := walk.position.distance_to(c)-Walk.BODY_RADIUS-outline.reach(center,local_d,fitted)*0.85
			widest_gap = maxf(widest_gap,gap)
			# A root cover necessarily stops the body short of the hull between roots.
			check(covering or gap<=MAX_GAP_M,asset.id+" contact without a gap from %d°"%(i*360/16))
			# Sliding: a command 6° into the touched face keeps its tangential part.
			var contact := walk.position
			var normal := proxy.away(contact)
			var tangent := normal.cross(Vector3.UP)
			var command := tangent*cos(deg_to_rad(6.0))-normal*sin(deg_to_rad(6.0))
			for _s in 60: walk.move(command/60.0)
			check((walk.position-contact).dot(tangent)>=0.9*cos(deg_to_rad(6.0)) and walk.clear_position(walk.position),
				asset.id+" slides past the face from %d°"%(i*360/16))
		if covering: print("%s root cover: up to %.3f m between body and root hull at 0.85 scale" % [asset.id,widest_gap])
		scene.root.free()
	_walls_and_corners()
	print("DYNAMIC_PROP_PROXY_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func _walls_and_corners() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	var profiles := {}
	for asset: Dictionary in catalog.assets: profiles[asset.id] = asset
	# Reviewer case: wild_pz_rock_08 turned 84°, approached along its face normal.
	var data := grid()
	var walk := Walk.new(data)
	var rock: Dictionary = profiles.wild_pz_rock_08
	var tr := Transform3D(Basis(Vector3.UP,deg_to_rad(84.0)),Vector3.ZERO)
	var scene := Scenery.build({"layout":[{"asset":rock.id,"transform":tr,"shadow":false,"triangles":rock.triangles}]},walk)
	var proxy := Proxy.new(rock.collision_proxy,tr,catalog.collision_fit_fraction)
	var normal := proxy.pose.basis.z
	walk.position = proxy.pose.origin*Vector3(1,0,1)+normal*2.0
	walk.move(-normal*2.0)
	var stop := walk.position
	var command := (proxy.pose.basis.x*cos(deg_to_rad(6.0))-normal*sin(deg_to_rad(6.0)))
	for _i in 60: walk.move(command/60.0)
	check((walk.position-stop).dot(proxy.pose.basis.x)>=0.9*cos(deg_to_rad(6.0)),"rotated rock face: 6° inward command slides")
	scene.root.free()
	# Crevice between two rocks: sliding never tunnels or leaves clear ground.
	walk = Walk.new(data)
	var a := Transform3D(Basis.IDENTITY,Vector3(-0.95,0,0))
	var b := Transform3D(Basis(Vector3.UP,PI),Vector3(0.95,0,0))
	scene = Scenery.build({"layout":[{"asset":rock.id,"transform":a,"shadow":false,"triangles":rock.triangles},
		{"asset":rock.id,"transform":b,"shadow":false,"triangles":rock.triangles}]},walk)
	var always_clear := true
	for start in [Vector3(0.3,0,2.0),Vector3(-0.3,0,2.0),Vector3(0,0,-2.0)]:
		walk.position = start
		for _i in 120:
			walk.move((Vector3(0,0,-signf(start.z))+Vector3(signf(start.x),0,0)*0.4).normalized()*0.05)
			always_clear = always_clear and walk.clear_position(walk.position)
	check(always_clear,"crevice: every step stays clear")
	scene.root.free()
	# Ground edge at a shallow angle still slides (grid boundary normals).
	walk = Walk.new(data)
	walk.position = walk.point(Vector2i(19,10))
	for _i in 60: walk.move(Vector3(cos(deg_to_rad(6.0)),0,-sin(deg_to_rad(6.0)))/60.0*2.0)
	var before := walk.position
	for _i in 60: walk.move(Vector3(sin(deg_to_rad(6.0)),0,-cos(deg_to_rad(6.0)))/60.0)
	check(absf(walk.position.x-before.x)<0.001 and before.z-walk.position.z>=0.9*cos(deg_to_rad(6.0)),"ground edge: 6° inward command slides")
	check(walk.clear_position(walk.position),"ground edge: stays on the ground")
	# Ground edge and a rock together: the slide re-checks both, never leaving the ground.
	walk = Walk.new(data)
	var pocket := Transform3D(Basis.IDENTITY,walk.point(Vector2i(19,8))+Vector3(-0.2,0,0))
	scene = Scenery.build({"layout":[{"asset":rock.id,"transform":pocket,"shadow":false,"triangles":rock.triangles}]},walk)
	walk.position = walk.point(Vector2i(19,12))
	always_clear = true
	for _i in 120:
		walk.move(Vector3(sin(deg_to_rad(6.0)),0,-cos(deg_to_rad(6.0)))*0.03)
		always_clear = always_clear and walk.clear_position(walk.position)
	check(always_clear,"ground edge beside a rock: every step stays clear")
	scene.root.free()

extends SceneTree
## Tests the imported (not inventory-AABB) geometry and the actual build → walk path.
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Proxy = Scenery.Proxy
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func xz(v: Vector3) -> Vector2: return Vector2(v.x,v.z)

func silhouette_fits(mesh: Mesh, proxy: Proxy, trunk: bool) -> bool:
	var faces := mesh.get_faces()
	var tris: Array[PackedVector2Array] = []
	var slice: Array[PackedVector2Array] = []
	var height := proxy.pose.origin.y * 2.0
	for i in range(0,faces.size(),3):
		var triangle := PackedVector2Array([xz(faces[i]),xz(faces[i+1]),xz(faces[i+2])])
		if absf((triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])) > 1e-10:
			tris.append(triangle)
		if not trunk: continue
		# Cross-section at the top of the trunk proxy excludes the canopy.
		var hits := PackedVector2Array()
		for j in 3:
			var a := faces[i+j]
			var b := faces[i+(j+1)%3]
			if (a.y>height) != (b.y>height): hits.append(xz(a.lerp(b,(height-a.y)/(b.y-a.y))))
		if hits.size()==2: slice.append(hits)
	var extent := Vector2.ONE
	if proxy.shape is CylinderShape3D: extent *= (proxy.shape as CylinderShape3D).radius
	else: extent = xz((proxy.shape as BoxShape3D).size)*0.5
	# Boundary and interior of the 100%-fit primitive, in its own orientation.
	for i in 96:
		var direction := Vector2.from_angle(i*TAU/96)
		if proxy.shape is BoxShape3D: direction /= maxf(absf(direction.x),absf(direction.y))
		for radius in [0.0,0.25,0.5,0.75,1.0]:
			var p: Vector2 = direction * extent * radius
			p = xz(proxy.pose * Vector3(p.x,0,p.y))
			if trunk:
				var crossings := 0
				for line in slice:
					var a := line[0]
					var b := line[1]
					if (a.y>p.y)!=(b.y>p.y) and p.x<a.x+(p.y-a.y)*(b.x-a.x)/(b.y-a.y): crossings+=1
				if crossings%2==0: return false
			else:
				var inside := false
				for tri in tris:
					if Geometry2D.point_is_inside_triangle(p,tri[0],tri[1],tri[2]):
						inside=true
						break
				if not inside: return false
	return true

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenery.INVENTORY_PATH))
	check(catalog.assets.size()==13,"complete approved inventory")
	check(catalog.collision_fit_fraction>=0.8 and catalog.collision_fit_fraction<=1.0,"tuning range")
	var data := {"cell_m":0.8,"grid_size":Vector2i(20,20),"spawn":Vector2i(10,10),"by_cell":{}}
	for y in 20:
		for x in 20: data.by_cell[Vector2i(x,y)] = true
	for asset: Dictionary in catalog.assets:
		var profile: Dictionary = asset.collision_proxy
		var local := Proxy.new(profile,Transform3D.IDENTITY,1.0)
		check(silhouette_fits(Scenery.Art.mesh_for(asset.id),local,asset.role=="tree"),asset.id+" measured silhouette")
		var blocking: bool = asset.role in ["tree","shrub","rock"]
		check(local.solid==blocking,asset.id+" role policy")
		var walk := Walk.new(data)
		# Arbitrary translated/rotated/scaled placement without an extension-cell or
		# role flag: core/forest/edge all get the same profile through the build path.
		var tr := Transform3D(Basis(Vector3.UP,0.53).scaled(Vector3.ONE*0.85),Vector3(-0.83,0,1.37))
		var scene := Scenery.build({"layout":[{"asset":asset.id,"transform":tr,"shadow":false,"triangles":asset.triangles}]},walk)
		var proxy := Proxy.new(profile,tr,catalog.collision_fit_fraction)
		var center := proxy.pose.origin * Vector3(1,0,1)
		check(scene.ok and walk.clear_position(center)!=blocking,asset.id+" instance policy")
		var axis := proxy.pose.basis.x
		var other := proxy.pose.basis.z
		var r := (proxy.shape as CylinderShape3D).radius if proxy.shape is CylinderShape3D else (proxy.shape as BoxShape3D).size.x*0.5
		var contact := center+axis*(r+Walk.BODY_RADIUS)
		if blocking:
			check(not walk.clear_position(contact-axis*0.001) and walk.clear_position(contact+axis*0.001),asset.id+" contact within 1mm")
			walk.position = contact+axis*0.002-other*1.5
			walk.move(other*3.0)
			check(walk.position.distance_to(contact+axis*0.002+other*1.5)<0.001,asset.id+" pass tangentially")
		else:
			walk.position = center-axis
			walk.move(axis*2.0)
			check(walk.position.distance_to(center+axis)<0.001,asset.id+" traverse")
		scene.root.free()
	print("DYNAMIC_PROP_PROXY_TESTS checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

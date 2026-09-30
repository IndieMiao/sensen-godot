class_name FishingWater
extends Node3D

var water_material: ShaderMaterial
var site_id := ""
var site_spec: Dictionary = {}
const FLOW = preload("res://assets/farm/art/water/surface_flow.png")

func interact(point: Vector3, strength: float) -> void:
	if water_material:
		water_material.set_shader_parameter("interaction", Vector4(point.x, point.z, 0, strength))

static func build(site_id: String, site_override: Dictionary = {}) -> FishingWater:
	var water := FishingWater.new()
	water.name = site_id
	water.site_id = site_id
	var spec := FishingModel.site(site_id, site_override).duplicate(true)
	water.site_spec = spec
	var outline := PackedVector3Array()
	if spec.has("polygon"):
		for point in spec.polygon: outline.append(Vector3(point[0], 0.055, point[1]))
	elif spec.has("center"):
		for i in 64:
			var angle := float(i) / 64.0 * TAU
			outline.append(Vector3(float(spec.center[0]) + cos(angle) * float(spec.radii[0]), 0.055, float(spec.center[1]) + sin(angle) * float(spec.radii[1])))
	else:
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in spec.path.size():
			var p: Array = spec.path[i]
			var a: Array = spec.path[maxi(0, i - 1)]
			var b: Array = spec.path[mini(spec.path.size() - 1, i + 1)]
			var dir := Vector3(float(b[0]) - float(a[0]), 0, float(b[1]) - float(a[1])).normalized()
			var normal := Vector3(-dir.z, 0, dir.x) * float(spec.width) * 0.5
			var point := Vector3(p[0], 0.055, p[1])
			left.append(point + normal)
			right.append(point - normal)
		outline.append_array(left)
		# Rounded ends match the shared capsule geometry used for cast validation.
		for endpoint in [spec.path.size() - 1, 0]:
			var at: Array = spec.path[endpoint]
			var neighbour: Array = spec.path[endpoint - 1 if endpoint > 0 else 1]
			var outward := Vector2(float(at[0]) - float(neighbour[0]), float(at[1]) - float(neighbour[1])).normalized()
			var normal := Vector2(-outward.y, outward.x)
			var angle := normal.angle()
			for i in range(1, 13):
				var offset := Vector2.from_angle(angle - float(i) / 12.0 * PI) * float(spec.width) * 0.5
				outline.append(Vector3(float(at[0]) + offset.x, 0.055, float(at[1]) + offset.y))
			if endpoint > 0:
				right.reverse()
				outline.append_array(right)
	var polygon := PackedVector2Array()
	for point in outline: polygon.append(Vector2(point.x, point.z))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(outline[index])
	var mesh := MeshInstance3D.new()
	mesh.name = "FishingWaterSurface"
	mesh.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/fishing/water.gdshader")
	material.set_shader_parameter("pebble_bed", preload("res://assets/farm/art/water/sediment.png"))
	material.set_shader_parameter("surface_flow", FLOW)
	material.set_shader_parameter("caustics", preload("res://assets/farm/art/water/caustic_light.png"))
	mesh.layers = 2
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.water_material = material
	if spec.has("polygon"):
		material.shader = preload("res://modules/ponds/pond_water.gdshader")
		material.set_shader_parameter("polygon_water", true)
		material.set_shader_parameter("pond_shore", load("res://assets/ponds/%s_shore.png" % str(spec.template_id)))
		material.set_shader_parameter("pond_extent", Vector2(spec.extent[0], spec.extent[1]))
		material.set_shader_parameter("basin_bed", load("res://assets/ponds/art/%s_bed.png" % str(spec.template_id)))
		material.set_shader_parameter("caustics", preload("res://assets/ponds/art/caustic_web.png"))
		material.set_shader_parameter("ripple_field", preload("res://assets/ponds/art/pond_ripple_field.png"))
		material.set_shader_parameter("foam_pattern", preload("res://assets/ponds/art/foam/foam_pattern.png"))
		var foam_contact_path := "res://assets/ponds/art/foam/%s.png" % site_id
		if ResourceLoader.exists(foam_contact_path):
			material.set_shader_parameter("foam_contact", load(foam_contact_path))
			material.set_shader_parameter("has_foam_contact", true)
		material.set_shader_parameter("fish_paths", _pond_fish_paths(spec))
	elif spec.has("center"):
		material.set_shader_parameter("basin", Vector4(spec.center[0], spec.center[1], spec.radii[0], spec.radii[1]))
	else:
		material.set_shader_parameter("river", true)
		material.set_shader_parameter("river_half_width", float(spec.width) * 0.5)
		for index in 3:
			var a: Array = spec.path[index]
			var b: Array = spec.path[index + 1]
			material.set_shader_parameter(["river_a", "river_b", "river_c"][index], Vector4(a[0], a[1], b[0], b[1]))
	water.add_child(mesh)
	var visibility := VisibleOnScreenNotifier3D.new()
	visibility.name = "WaterVisibility"
	visibility.aabb = mesh.mesh.get_aabb().grow(0.4)
	water.add_child(visibility)
	if spec.has("center"): water._build_lilies(spec)
	if spec.has("polygon"): water._build_pond_lilies(spec)
	water.add_child(WaterShore.build(site_id, spec))
	return water

func _ready() -> void:
	_setup_reflections.call_deferred()

func _setup_reflections() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() == "gl_compatibility": return
	var scenery: Node = get_parent().get_node_or_null("Scenery")
	if scenery == null and site_spec.get("space", "") == "street": scenery = get_parent()
	if scenery == null: return
	for node in scenery.find_children("*", "GeometryInstance3D", true, false):
		if not (node is MeshInstance3D or node is MultiMeshInstance3D): continue
		if node.name in ["NeighbourhoodRoads", "BankGround"]: continue
		var parent: Node = node
		var is_water := false
		var is_bank := false
		while parent and parent != scenery:
			if parent is WaterShore: is_bank = true
			if parent is FishingWater: is_water = true
			parent = parent.get_parent()
		if not is_water or is_bank: node.set_layer_mask_value(3, true)
	# Farm water is a sibling of Scenery, so its own bank needs explicit tagging.
	for node in get_node("NaturalWaterBank").find_children("*", "MeshInstance3D", true, false):
		if node.name != "BankGround": node.set_layer_mask_value(3, true)
	var reflection := WaterReflection.new()
	reflection.name = "PlanarBankReflection"
	reflection.material = water_material
	add_child(reflection)

static func _pond_fish_paths(spec: Dictionary) -> PackedVector4Array:
	var paths := PackedVector4Array()
	var polygon := FishingModel._polygon(spec)
	# A circular clearance bounds the full fish orbit, including its tail.
	for z in range(4, 13):
		for x in range(3, 10):
			var point := Vector2(x, -z)
			if not Geometry2D.is_point_in_polygon(point, polygon): continue
			var clearance := point.distance_to(FishingModel._nearest_polygon(point, polygon))
			if clearance < .95: continue
			var separate := true
			for path in paths:
				if point.distance_to(Vector2(path.x, path.y)) < 1.8: separate = false
			if not separate: continue
			var radius := minf(.7, (clearance - .35) / sqrt(2.0))
			paths.append(Vector4(point.x, point.y, radius, radius * .8))
			if paths.size() == 3: return paths
	while paths.size() < 3:
		paths.append(paths[0] if not paths.is_empty() else Vector4(-100, -100, .1, .1))
	return paths

func _build_pond_lilies(spec: Dictionary) -> void:
	var surface := SurfaceTool.new()
	var flowers := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.decoration_seed)
	var clusters: Array[Vector3] = []
	var pad_shadows := PackedVector4Array()
	for attempt in 240:
		var point := Vector3(rng.randf_range(2, 10), 0.09, rng.randf_range(-12, -4))
		if not FishingModel.contains(site_id, point, 0, spec): continue
		var edge := FishingModel._nearest_polygon(Vector2(point.x, point.z), FishingModel._polygon(spec))
		var depth := Vector2(point.x, point.z).distance_to(edge)
		if depth < .65 or depth > 1.15: continue
		var separate := true
		for center in clusters:
			if center.distance_to(point) < 2.0: separate = false
		if not separate: continue
		clusters.append(point)
		for leaf in 5:
			var offset := Vector3(cos(leaf * 2.4), 0, sin(leaf * 2.4)) * sqrt(float(leaf)) * .25
			var at := point + offset + Vector3.UP * leaf * .003
			if not FishingModel.contains(site_id, at, -.28, spec): continue
			var radius := rng.randf_range(.18,.29)
			_pond_lily_leaf(surface, at, radius, rng.randf_range(0,TAU), Color("8eae46").lerp(Color("a8bf5d"), rng.randf()))
			pad_shadows.append(Vector4(at.x, at.z, radius, 0))
		if clusters.size() % 2 == 1:
			for ring in 2:
				for petal in 8:
					var angle := TAU * petal / 8.0 + ring * .35
					var at := point + Vector3(cos(angle), 0, sin(angle)) * (.07 - ring * .025) + Vector3.UP * (.05 + ring * .05)
					var basis := Basis(Vector3.UP,-angle) * Basis(Vector3.FORWARD,-.3 - ring * .3)
					PlaceScenery._oval(flowers, Vector3(.205,.082,.106),at,Color("ed93b3").lerp(Color("ffd8d8"),ring*.65).srgb_to_linear(),basis)
			PlaceScenery._oval(flowers,Vector3(.048,.04,.048),point + Vector3.UP*.12,Color("ffdb75").srgb_to_linear())
		if clusters.size() >= 3: break
	if clusters.is_empty(): return
	water_material.set_shader_parameter("lily_count", pad_shadows.size())
	pad_shadows.resize(15)
	water_material.set_shader_parameter("lily_pads", pad_shadows)
	var material := ShaderMaterial.new()
	material.shader = preload("res://modules/ponds/pond_lily.gdshader")
	var leaves := MeshInstance3D.new()
	leaves.name = "PondLilies"
	surface.index()
	leaves.mesh = surface.commit()
	leaves.material_override = material
	add_child(leaves)
	var blooms := MeshInstance3D.new()
	blooms.name = "PondBlooms"
	flowers.index()
	blooms.mesh = flowers.commit()
	var bloom_material := StandardMaterial3D.new()
	bloom_material.vertex_color_use_as_albedo = true
	bloom_material.roughness = .75
	blooms.material_override = bloom_material
	add_child(blooms)

func _build_lilies(spec: Dictionary) -> void:
	var surface := SurfaceTool.new()
	var flowers := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 190924 if site_id == "farm_pond" else 190925
	for angle in [2.3, 0.55, 4.1]:
		var cluster := Vector3(float(spec.center[0]) + cos(angle) * float(spec.radii[0]) * 0.72, 0.088,
			float(spec.center[1]) + sin(angle) * float(spec.radii[1]) * 0.72)
		for leaf in 7:
			var offset := Vector3(cos(leaf * 2.4), 0, sin(leaf * 2.4)) * sqrt(float(leaf)) * 0.16
			var point := cluster + offset + Vector3.UP * (float(leaf) * 0.002)
			var radius := rng.randf_range(0.12, 0.22)
			_lily_leaf(surface, point, radius, rng.randf_range(0, TAU), Color("80993c").lerp(Color("b7c962"), rng.randf()))
		for ring in 2:
			var count := 10 if ring == 0 else 7
			for petal in count:
				var a := float(petal) / count * TAU + ring * 0.4
				var size := Vector3(0.16, 0.03, 0.06) if ring == 0 else Vector3(0.115, 0.034, 0.055)
				var offset := Vector3(cos(a), 0, sin(a)) * (0.065 if ring == 0 else 0.035)
				var basis := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -0.20 if ring == 0 else -0.50)
				PlaceScenery._oval(flowers, size, cluster + offset + Vector3.UP * (0.035 + ring * 0.025), Color("fff6dc").srgb_to_linear(), basis)
		PlaceScenery._oval(flowers, Vector3(0.06, 0.045, 0.06), cluster + Vector3.UP * 0.07, Color("e6bd4a").srgb_to_linear())
		# Small floating leaves break up the edge of each patch without a solid mat.
		for leaf in 18:
			var point := cluster + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			if FishingModel.contains(site_id, point, -0.20, site_spec):
				_lily_leaf(surface, point, rng.randf_range(0.018, 0.040), rng.randf_range(0, TAU), Color("b2bc54"))
	var leaves := MeshInstance3D.new()
	leaves.name = "FloatingLilies"
	surface.index()
	leaves.mesh = surface.commit()
	var leaf_material := ShaderMaterial.new()
	leaf_material.shader = preload("res://modules/fishing/lily_leaf.gdshader")
	leaves.material_override = leaf_material
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaves)
	var blooms := MeshInstance3D.new()
	blooms.name = "WaterLilies"
	flowers.index()
	blooms.mesh = flowers.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.60
	blooms.material_override = material
	blooms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blooms)

static func _pond_lily_leaf(surface: SurfaceTool, center: Vector3, radius: float, yaw: float, color: Color) -> void:
	# Closed fleshy pad: a quiet domed top, rounded lip and visible green sidewall.
	# These centimetre-thick pads are confined to the system ponds.
	var profile := [Vector2(0,.032), Vector2(.40,.035), Vector2(.84,.034), Vector2(.96,.029), Vector2(1,.017), Vector2(1,-.014), Vector2(.93,-.025), Vector2(0,-.025)]
	for ring in profile.size() - 1:
		for segment in 40:
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner in [Vector2(segment,ring), Vector2(segment+1,ring), Vector2(segment+1,ring+1), Vector2(segment,ring+1)]:
				var angle: float = corner.x / 40.0 * TAU + yaw
				var band: Vector2 = profile[int(corner.y)]
				var roundness := 1.0 + sin(angle * 3.0 + yaw) * .016
				var q := Vector2(cos(angle),sin(angle)) * band.x * roundness
				points.append(center + Vector3(q.x * radius, band.y * radius / .24, q.y * radius))
				var side := Vector3(cos(angle),0,sin(angle))
				var normal := Vector3.UP
				if ring >= 6: normal = Vector3.DOWN
				elif ring >= 4: normal = side
				elif ring == 3: normal = (Vector3.UP + side * .8).normalized()
				else: normal = (Vector3.UP + side * band.x * .09).normalized()
				normals.append(normal)
				uvs.append(q * .5 + Vector2.ONE * .5)
			for i in [0,2,1,0,3,2]:
				surface.set_color(color.srgb_to_linear() * (0.82 if ring >= 4 else 1.0))
				surface.set_normal(normals[i])
				surface.set_uv(uvs[i])
				surface.add_vertex(points[i])

static func _lily_leaf(surface: SurfaceTool, center: Vector3, radius: float, yaw: float, color: Color) -> void:
	for ring in 4:
		for step in 32:
			var a := yaw + 0.14 + float(step) / 32.0 * (TAU - 0.28)
			var b := yaw + 0.14 + float(step + 1) / 32.0 * (TAU - 0.28)
			var inner := float(ring) / 4.0
			var outer := float(ring + 1) / 4.0
			var coords := [Vector2(cos(a), sin(a)) * inner, Vector2(cos(b), sin(b)) * inner,
				Vector2(cos(b), sin(b)) * outer, Vector2(cos(a), sin(a)) * outer]
			for index in [0, 2, 1, 0, 3, 2]:
				var q: Vector2 = coords[index]
				var lift := q.length_squared() * 0.012 + sin(q.angle() * 4.0) * q.length_squared() * 0.003
				surface.set_normal(Vector3.UP)
				surface.set_uv(q * 0.5 + Vector2.ONE * 0.5)
				surface.set_color(color.srgb_to_linear())
				surface.add_vertex(center + Vector3(q.x * radius, lift, q.y * radius))

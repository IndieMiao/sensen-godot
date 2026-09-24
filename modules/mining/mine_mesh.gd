extends RefCounted
## Batched, deterministic sculpted meshes. All dimensions are in gameplay metres.
static var _materials: Dictionary = {}

static func surface() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s

static func material(kind := "stone") -> StandardMaterial3D:
	if _materials.has(kind): return _materials[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.92
	if kind in ["stone", "earth", "wood"]:
		var noise := FastNoiseLite.new()
		noise.seed = 924
		noise.frequency = 0.042 if kind == "earth" else 0.065
		noise.fractal_octaves = 3
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.noise = noise
		texture.seamless = true
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.92, 0.92, 0.92) if kind == "earth" else Color(0.90, 0.90, 0.90))
		gradient.set_color(1, Color.WHITE)
		texture.color_ramp = gradient
		m.albedo_texture = texture
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * (0.38 if kind == "earth" else 1.25)
	elif kind == "metal":
		m.roughness = 0.56
		m.metallic = 0.28
	elif kind == "glow":
		m.emission_enabled = true
		m.emission = Color("ffc771")
		m.emission_energy_multiplier = 1.7
	elif kind == "crystal":
		m.roughness = 0.26
		m.metallic = 0.18
		m.emission_enabled = true
		m.emission = Color("6055ac")
		m.emission_energy_multiplier = 0.38
	elif kind == "shadow":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.disable_receive_shadows = true
	_materials[kind] = m
	return m

static func finish(s: SurfaceTool, node_name: String, kind := "stone") -> MeshInstance3D:
	s.index()
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = s.commit()
	result.material_override = material(kind)
	return result

static func tri(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot's front faces are clockwise.
	var normal := (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		s.set_color(color)
		s.set_normal(normal)
		s.add_vertex(point)

static func quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(s, a, b, c, color)
	tri(s, a, c, d, color)

static func soft_disc(s: SurfaceTool, point: Vector3, size: Vector2, yaw := 0.0) -> void:
	var basis := Basis(Vector3.UP,yaw)
	for i in 16:
		var a := TAU*i/16
		var b := TAU*(i+1)/16
		for tier in 2:
			var inner := 0.02 if tier == 0 else 0.60
			var outer := 0.60 if tier == 0 else 1.0
			var p := Vector3(cos(a)*size.x,0,sin(a)*size.y)
			var q := Vector3(cos(b)*size.x,0,sin(b)*size.y)
			for v in [p*inner,p*outer,q*outer,p*inner,q*outer,q*inner]:
				var at_edge: bool = v.length_squared() > 0.0001 and is_equal_approx(Vector2(v.x/size.x,v.z/size.y).length(),1.0)
				s.set_color(Color(0.20,0.13,0.18,0.0 if at_edge else (0.12 if tier == 1 else 0.16)))
				s.set_normal(Vector3.UP)
				s.add_vertex(point+basis*v)

static func block(s: SurfaceTool, center: Vector3, size: Vector3, color: Color, seed_value := 0, bevel := 0.13, yaw := 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 101
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, hz))
	var vertical_bevel := minf(b, size.y * 0.4)
	var outline := [Vector2(-hx + b, -hz), Vector2(hx - b, -hz), Vector2(hx, -hz + b), Vector2(hx, hz - b),
		Vector2(hx - b, hz), Vector2(-hx + b, hz), Vector2(-hx, hz - b), Vector2(-hx, -hz + b)]
	var rings: Array = []
	var basis := Basis(Vector3.UP, yaw)
	for tier in 4:
		var ring: Array[Vector3] = []
		var y: float = [-size.y * 0.5, -size.y * 0.5 + vertical_bevel, size.y * 0.5 - vertical_bevel, size.y * 0.5][tier]
		var inset := b * 0.42 if tier in [0, 3] else 0.0
		for p: Vector2 in outline:
			var variation := rng.randf_range(-vertical_bevel * 0.18, vertical_bevel * 0.18)
			ring.append(center + basis * Vector3(p.x - signf(p.x) * inset, y + variation, p.y - signf(p.y) * inset))
		rings.append(ring)
	for tier in 3:
		for i in 8:
			var j := (i + 1) % 8
			var tint := color.lightened(rng.randf_range(0.0, 0.065)) if tier == 2 else color.darkened(rng.randf_range(0.0, 0.07))
			quad(s, rings[tier][i], rings[tier][j], rings[tier + 1][j], rings[tier + 1][i], tint)
	for i in 8:
		tri(s, center + Vector3.UP * size.y * 0.5, rings[3][i], rings[3][(i + 1) % 8], color.lightened(0.08))

static func pebble(s: SurfaceTool, point: Vector3, size: Vector3, color: Color, seed_value: int) -> void:
	block(s, point, size, color, seed_value, minf(size.x, size.y) * 0.38, seed_value * 0.79)

static func slab(s: SurfaceTool, outline: PackedVector2Array, top: float, depth: float, color: Color) -> void:
	var center := Vector3(4.75, top, -3.9)
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var a := Vector3(p.x, top, p.y)
		var b := Vector3(q.x, top, q.y)
		tri(s, center, a, b, color)
		quad(s, a, a - Vector3.UP * depth, b - Vector3.UP * depth, b, color.darkened(0.25))

static func ribbon(s: SurfaceTool, points: Array[Vector3], width: float, color: Color, normal := Vector3.UP) -> void:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).cross(normal).normalized() * width * 0.5
		quad(s, a - side, b - side, b + side, a + side, color)

static func beam(s: SurfaceTool, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	PlaceScenery._beam(s, a, b, width, color)

static func box(s: SurfaceTool, point: Vector3, size: Vector3, color: Color) -> void:
	PlaceScenery._box(s, size, point, color)

static func oval(s: SurfaceTool, point: Vector3, size: Vector3, color: Color) -> void:
	PlaceScenery._oval(s, size, point, color)

static func ring(s: SurfaceTool, point: Vector3, radius: float, width: float, color: Color, basis := Basis.IDENTITY) -> void:
	var shape := TorusMesh.new()
	shape.inner_radius = maxf(0.001, radius - width)
	shape.outer_radius = radius + width
	shape.rings = 16
	shape.ring_segments = 6
	PlaceScenery._append(s, shape, Transform3D(basis, point), color)

static func crystal(s: SurfaceTool, point: Vector3, radius: float, height: float, color: Color, lean: Vector3) -> void:
	var basis := Basis(Quaternion(Vector3.UP, (Vector3.UP + lean).normalized()))
	for i in 6:
		var a := TAU * i / 6
		var b := TAU * (i + 1) / 6
		var p := Vector3(cos(a) * radius, 0, sin(a) * radius)
		var q := Vector3(cos(b) * radius, 0, sin(b) * radius)
		var r := p + Vector3.UP * height * 0.66
		var t := q + Vector3.UP * height * 0.66
		var tint := color.lightened(float(i % 3) * 0.12)
		quad(s, point + basis * p, point + basis * q, point + basis * t, point + basis * r, tint)
		tri(s, point + basis * r, point + basis * t, point + basis * Vector3(0, height, 0), tint.lightened(0.14))

static func pool(point: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0))
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0)
	texture.gradient = gradient
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	var shape := PlaneMesh.new()
	shape.size = Vector2.ONE * radius * 2
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.position = point
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

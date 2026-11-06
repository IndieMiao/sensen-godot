extends "res://modules/mining/monsters/monster_view.gd"
## The Slime drawn in code (355 b1, contract-efg §10; moved unchanged from mine_combat.gd _slime and the P0 mine's
## wind-up look in p0_mine_combat.gd): the jelly body with its face, the elite's crown, the HP bar over it and the
## wind-up's band on the ground. Its children keep the names the fight and its tests read: Body, Warning, Health,
## HealthTrack, HealthFill, Band. No model will replace it: the slime kings are this, larger and recoloured (3D brings
## only their head ornaments).

const Meshes = preload("res://modules/mining/mine_mesh.gd")
## A slime's eyes, glints and cheeks (perf Q6, SGODOT-260): one mesh of 16 × 8 spheres in one vertex-colour material,
## instead of six default 64 × 32 spheres (about 24k triangles a slime) with a material each.
const FACE_SEGMENTS := Vector2i(16, 8)
## The lunge band (不知火舞 288 785a6a5b, 上官婉儿 c8a7507a, 李白 on 288): from the wind-up's first frame a strip on the
## ground from the slime's feet along the locked lunge, as long as the lunge reaches (dash speed × time + the hit
## radius) and as wide as the hit, its far end round; it sweeps from the feet to its far end over the wind-up, the
## slime leaps when it is full, the band stays through the lunge and fades over 0.15 s after it (不知火舞 7d4f0231).
## Orange-red #E8603C at 30 %; the elite's in full, a slime's paler. The direction is the one the wind-up locked: the
## lunge follows the band, never re-aims.
const BAND_COLOR := Color("e8603c")
const BAND_FILL := 0.30
const BAND_FADE_S := 0.15
const BAND_PALE := 0.6       # a common slime's band, against the elite's
const BAND_Y := 0.03
## The wind-up squash on Body only (pivot at its feet, so they stay on the ground), a small shake of its position over
## the last 0.2 s, and a 0.08 s rebound as it leaps (上官婉儿 c8a7507a).
const SQUASH := Vector3(1.18, 0.78, 1.18)
const SHAKE_S := 0.2
const SHAKE_M := 0.03
const REBOUND_S := 0.08
## The fight's phases as the contract's actions (a model would play these).
const ACTIONS := {"idle": "idle", "chase": "move", "windup": "windup", "dash": "attack", "recover": "recover", "stunned": "hit"}

static var _face_material: StandardMaterial3D

func build(spec: Dictionary, elite: bool) -> void:
	var color := Color("79cdb6") if not elite else Color("ad7cda")
	set_meta("color", color)
	var radius := float(spec.radius)
	var body := _mesh(_slime_body(radius), color, Vector3.ZERO)
	body.name = "Body"
	var jelly := body.material_override as StandardMaterial3D
	jelly.roughness = 0.29
	jelly.rim_enabled = true
	jelly.rim = 0.28
	jelly.rim_tint = 0.65
	add_child(body)
	BlobShadow.attach(self, radius * 1.15)
	var face := Meshes.surface()
	for side in [-1, 1]:
		_face_sphere(face, radius * 0.09, radius * 0.27, Color("333345"), Vector3(side * radius * 0.30, radius * 0.69, radius * 0.92))   # eye
		_face_sphere(face, radius * 0.026, radius * 0.058, Color("fff9e7"), Vector3(side * radius * 0.30 - radius * 0.02, radius * 0.76, radius * 1.002))   # glint
		_face_sphere(face, radius * 0.10, radius * 0.10, Color("e5a7ca") if elite else Color("b8e1cb"),
			Vector3(side * radius * 0.51, radius * 0.53, radius * 0.89), Vector3(1, 1, 0.36))   # cheek, flattened as before
	face.index()
	var face_mesh := MeshInstance3D.new()
	face_mesh.name = "Face"
	face_mesh.mesh = face.commit()
	face_mesh.material_override = _face_jelly()
	body.add_child(face_mesh)
	var smile := Meshes.surface()
	Meshes.ribbon(smile,[Vector3(-0.09,0.61,0.986)*radius,Vector3(0,0.57,1.015)*radius,Vector3(0.09,0.61,0.986)*radius],radius*0.033,Color("494056"),Vector3.FORWARD)
	body.add_child(Meshes.finish(smile,"Smile"))
	if elite:
		var crown := Meshes.surface()
		var base := Vector3(0,radius*1.42,0)
		Meshes.ring(crown,base,radius*0.24,radius*0.035,Color("e9b34e"))
		for i in 5:
			var a := TAU*i/5
			var b := TAU*(i+1)/5
			var p := Vector3(cos(a)*radius*0.24,0,sin(a)*radius*0.24)
			var q := Vector3(cos(b)*radius*0.24,0,sin(b)*radius*0.24)
			var tip := p + Vector3.UP*radius*0.23
			Meshes.tri(crown,base+p,base+q,base+tip,Color("f1c05b"))
			Meshes.tri(crown,base+p,base+tip,base+q,Color("c9913d"))
			Meshes.oval(crown,base+tip,Vector3.ONE*radius*0.09,Color("ffe09a"))
		body.add_child(Meshes.finish(crown,"Crown","metal"))
	var warning := TorusMesh.new()
	warning.inner_radius = radius + 0.04
	warning.outer_radius = radius + 0.16
	var ring := _mesh(warning, Color("f66458"), Vector3(0, 0.035, 0))
	ring.scale.y = 0.15
	ring.name = "Warning"
	ring.visible = false
	add_child(ring)
	var label := _label("", 36)
	label.pixel_size = 0.012
	label.position.y = radius * 2.2 + 0.35
	label.name = "Health"
	add_child(label)
	for is_fill in [false, true]:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.94, 0.06, 0.045)
		var health := _mesh(bar, Color("dd7384") if is_fill else Color("334e4a"), Vector3(0, radius * 2.2 + 0.06, 0.05 if is_fill else 0))
		health.name = "HealthFill" if is_fill else "HealthTrack"
		add_child(health)
	_no_cast(self)
	add_child(_band(spec, elite))

## One frame of the slime's look after its brain: the old mine's (the hit flash, the wind-up's red and squash, the idle
## bob — only when the fight ran this frame), then the P0 mine's (the band sweeping out along the locked direction,
## the squash with its shake, the rebound on the leap), which go on while the fight holds still.
func update(enemy: Dictionary, was: String, delta: float, stepped: bool, elapsed: float) -> void:
	super.update(enemy, was, delta, stepped, elapsed)
	var phase := str(enemy.phase)
	play(str(ACTIONS.get(phase, "idle")))
	var body := get_node("Body") as MeshInstance3D
	if stepped:
		var material := body.material_override as StandardMaterial3D
		material.albedo_color = Color("fff3bd") if enemy.flash > 0 else (Color("f38870") if phase == "windup" else get_meta("color"))
		body.scale = Vector3(1.12, 0.7, 1.12) if phase == "windup" else Vector3(1, 1 + sin(elapsed * 7) * 0.04, 1)
	if phase == "windup" and was != "windup": enemy["band_dir"] = Vector3(enemy.direction)
	if phase == "dash" and was == "windup": enemy["rebound"] = REBOUND_S
	var band := get_node_or_null("Band") as Node3D
	if band:
		# shown through the wind-up and the lunge, then fading out (不知火舞 7d4f0231)
		if phase in ["windup", "dash"]: enemy["band_fade"] = BAND_FADE_S
		else: enemy["band_fade"] = maxf(0.0, float(enemy.get("band_fade", 0.0)) - clampf(delta, 0, 0.1))
		var fade := 1.0 if phase in ["windup", "dash"] else float(enemy.band_fade) / BAND_FADE_S
		band.visible = fade > 0.0
		if band.visible: lay_band(band, enemy, fade)
	get_node("Warning").visible = false   # the band says it now
	if phase == "windup":
		body.scale = SQUASH
		var left := float(enemy.timer)
		body.position = Vector3(sin(elapsed * 70.0), 0, cos(elapsed * 55.0)) * SHAKE_M if left <= SHAKE_S else Vector3.ZERO
	else:
		body.position = Vector3.ZERO
		var r := float(enemy.get("rebound", 0.0))
		if r > 0:
			enemy["rebound"] = maxf(0.0, r - clampf(delta, 0, 0.1))
			var k := r / REBOUND_S
			body.scale = Vector3(1.0 - 0.08 * k, 1.0 + 0.14 * k, 1.0 - 0.08 * k)

## The band from the slime's feet along the locked direction, swept out over the wind-up (full from the leap on), its
## round end at the tip, at `fade` of its opacity.
func lay_band(band: Node3D, e: Dictionary, fade := 1.0) -> void:
	var dir: Vector3 = e.get("band_dir", e.direction)
	if dir.length() < 0.01: dir = Vector3.FORWARD
	var done := 1.0
	if str(e.phase) == "windup":
		done = clampf(1.0 - float(e.timer) / maxf(0.01, float(e.spec.windup_seconds)), 0.0, 1.0)
	var reach := float(band.get_meta("reach", 2.0))
	var half := float(band.get_meta("width", 1.0)) * 0.5
	var tip := maxf(0.05, reach * done)
	# the strip runs to where the round end's centre sits, so the disc rounds the tip exactly at the reach
	var strip_len := maxf(0.01, tip - half)
	band.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
	# the band stays where the wind-up laid it while the slime lunges along it
	band.global_position = e.get("band_from", band.global_position) if str(e.phase) != "windup" else global_position
	if str(e.phase) == "windup": e["band_from"] = band.global_position
	var strip := band.get_node("Strip") as MeshInstance3D
	strip.scale = Vector3(1, 1, strip_len)
	strip.position.z = strip_len * 0.5
	strip.visible = tip > half
	var cap := band.get_node("Cap") as MeshInstance3D
	cap.position.z = maxf(0.0, tip - half)
	var cap_scale := minf(1.0, tip / maxf(0.01, half * 2.0)) if tip < half * 2.0 else 1.0
	cap.scale = Vector3(cap_scale, 1, cap_scale)
	var m := strip.material_override as StandardMaterial3D
	m.albedo_color.a = float(band.get_meta("alpha", BAND_FILL)) * fade

## A wind-up band's reach and width for a spec (the fight's band_of, tests, the 288 report).
static func band_size(spec: Dictionary) -> Dictionary:
	return {"reach": float(spec.dash_speed) * float(spec.dash_seconds) + float(spec.radius) + 0.35,
		"width": (float(spec.radius) + 0.35) * 2.0, "windup": float(spec.windup_seconds)}

## One wind-up's band: a flat strip on the ground under the slime's root, out of Body's squash, hidden until a wind-up.
func _band(spec: Dictionary, elite: bool) -> Node3D:
	var band := Node3D.new()
	band.name = "Band"
	band.visible = false
	var size := band_size(spec)
	var reach := float(size.reach)
	var width := float(size.width)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(BAND_COLOR, BAND_FILL * (1.0 if elite else BAND_PALE))
	# The strip (unit length, scaled along z as it sweeps) and its round far end (a disc the strip's width, moved to
	# the tip), one material so the overlap reads as one shape
	var strip := MeshInstance3D.new()
	strip.name = "Strip"
	var quad := PlaneMesh.new()
	quad.size = Vector2(width, 1.0)
	strip.mesh = quad
	strip.material_override = m
	strip.position.y = BAND_Y
	band.add_child(strip)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var disc := CylinderMesh.new()
	disc.top_radius = width * 0.5
	disc.bottom_radius = width * 0.5
	disc.height = 0.001
	disc.radial_segments = 24
	disc.rings = 1
	cap.mesh = disc
	cap.material_override = m
	cap.position.y = BAND_Y
	band.add_child(cap)
	_no_cast(band)   # flat on the ground, like the rest of the slime (perf Q6)
	band.set_meta("reach", reach)
	band.set_meta("width", width)
	band.set_meta("alpha", m.albedo_color.a)
	return band

func _mesh(shape: Mesh, color: Color, point: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	mesh.material_override = material
	return mesh

func _label(text: String, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = GameUi.theme().default_font
	label.font_size = font_size
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	label.modulate = Color("f3fff4")
	return label

## One sphere of the face as the SphereMesh it was (that radius and height), at 16 × 8 segments, scaled, in its colour.
func _face_sphere(s: SurfaceTool, sphere_radius: float, height: float, color: Color, point: Vector3, scale_by := Vector3.ONE) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = height
	sphere.radial_segments = FACE_SEGMENTS.x
	sphere.rings = FACE_SEGMENTS.y
	PlaceScenery._append(s, sphere, Transform3D(Basis.from_scale(scale_by), point), color)

## The face's material, shared by every slime: the parts' own look (roughness 0.3), its colour from the vertices.
static func _face_jelly() -> StandardMaterial3D:
	if _face_material == null:
		_face_material = StandardMaterial3D.new()
		_face_material.vertex_color_use_as_albedo = true
		_face_material.vertex_color_is_srgb = true
		_face_material.roughness = 0.3
	return _face_material

## A slime casts no real shadow (perf Q6): its blob shadow is the one on the ground, so the shadow pass skips it.
static func _no_cast(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _slime_body(radius: float) -> ArrayMesh:
	var surface := Meshes.surface()
	var profile := [Vector2(0.78,0.025),Vector2(0.98,0.10),Vector2(1.0,0.32),Vector2(0.94,0.60),
		Vector2(0.83,0.88),Vector2(0.65,1.12),Vector2(0.40,1.33),Vector2(0.04,1.43)]
	for tier in range(profile.size()-1):
		for i in 32:
			var a := TAU*i/32
			var b := TAU*(i+1)/32
			var p: Vector2 = profile[tier]*radius
			var q: Vector2 = profile[tier+1]*radius
			Meshes.quad(surface,Vector3(cos(a)*p.x,p.y,sin(a)*p.x),Vector3(cos(b)*p.x,p.y,sin(b)*p.x),
				Vector3(cos(b)*q.x,q.y,sin(b)*q.x),Vector3(cos(a)*q.x,q.y,sin(a)*q.x),Color.WHITE)
	surface.generate_normals()
	surface.index()
	return surface.commit()

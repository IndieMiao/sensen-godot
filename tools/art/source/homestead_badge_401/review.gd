extends Node
## Actual b1 P0Farm, lighting/HUD/player intact. Only the local plaque art is substituted.
var rt: P0Runtime
var farm
var fixture: Dictionary
var checks := []
var report := {}
var digits := {}
const TIERS := ["wood", "bronze", "silver", "gold"]
const LEVELS := [3, 7, 10, 17]

func _ready() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"check": label, "passed": ok})
	if not ok: push_error(label)
func respond(cmd: Dictionary) -> void:
	rt.session._finish(HTTPRequest.RESULT_SUCCESS, 200, JSON.stringify({"ok": true, "state": fixture, "events": []}).to_utf8_buffer(), cmd)
func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
func label(mount: Node3D, text: String, cap: float) -> Label3D:
	var node := Label3D.new()
	node.text = text; node.font = load("res://assets/ui/fonts/nunito_w800.tres")
	node.pixel_size = .002; node.font_size = roundi(cap / (.705 * node.pixel_size))
	node.outline_size = 0; node.modulate = Color("3B2F25")
	node.shaded = false; node.double_sided = false
	node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	mount.add_child(node)
	return node
func decorate(badge: Node3D, tier: String, level: int) -> Label3D:
	for name in TIERS: badge.find_child("Tier_" + name, true, false).visible = name == tier
	var number := label(badge.find_child("BadgeNumber", true, false), str(level), .315)
	label(badge.find_child("BadgeLv", true, false), "Lv", .080)
	return number
func camera_state(cam: Camera3D) -> Dictionary:
	return {"transform": str(cam.global_transform), "pitch": cam.rotation_degrees.x,
		"size": cam.size, "zoom": farm._zoom, "opening_zoom": farm._opening_zoom,
		"logical_size": str(get_viewport().get_visible_rect().size), "actor": str(farm.actor.position)}
func shot(file: String, viewport: Viewport = null) -> Image:
	await frames(4)
	RenderingServer.force_draw(true)
	var image := (viewport if viewport != null else get_viewport()).get_texture().get_image()
	check(image.save_png("res://../" + file + ".png") == OK, "saved " + file)
	return image
func point(cam: Camera3D, pos: Vector3) -> Array:
	var p := cam.unproject_position(pos)
	return [p.x, p.y]
func run() -> void:
	rt = P0Runtime.ensure(); fixture = JSON.parse_string(FileAccess.get_file_as_string("res://view-lv3.json"))
	rt.session.view = fixture; rt.session._received_ms = Time.get_ticks_msec()
	rt.session.transport = func(_method, _path, _body, cmd): respond.call_deferred(cmd)
	await frames(3)
	farm = load("res://scenes/p0/p0_farm.tscn").instantiate(); add_child(farm)
	await get_tree().create_timer(6.0).timeout
	var badge: Node3D = farm._plaque_node
	check(badge.visible and badge.scale.is_equal_approx(Vector3.ONE), "visible badge at runtime scale 1.0")
	check(badge.position.is_equal_approx(P0Garden.plaque_point(farm.bp)), "PLAQUE_CELL (7,14) retained")
	check(absf(badge.rotation_degrees.y - 14.5) < .001, "farm yaw 14.5 degrees")
	check(not farm.actor.rig.is_busy(), "player assembled")
	var face := badge.find_child("BadgeFace", true, false) as Node3D
	var number := badge.find_child("BadgeNumber", true, false) as Marker3D
	var lv := badge.find_child("BadgeLv", true, false) as Marker3D
	check(number != null and lv != null, "both sockets import as Marker3D")
	check(face.position.is_equal_approx(Vector3(0, 1, 0)) and absf(face.rotation_degrees.x + 25) < .001, "badge centre 1.0 m / tilt -25 degrees")
	check(number.position.is_equal_approx(Vector3(0, 0, .055)) and lv.position.is_equal_approx(Vector3(0, .238, .055)), "socket positions on face, +3 mm")
	check(number.basis.is_equal_approx(Basis.IDENTITY) and lv.basis.is_equal_approx(Basis.IDENTITY), "socket +Z inherits the face normal")
	var total := 0; var stored := 0; var visible_tris := 0; var visible_surfaces := 0
	for mesh in badge.find_children("*", "MeshInstance3D", true, false):
		check(str(mesh.mesh.resource_name).ends_with("_mobile"), "mobile mesh name: " + str(mesh.name))
		for surface in mesh.mesh.get_surface_count():
			var tris: int = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3
			total += tris; stored += 1
			if mesh.is_visible_in_tree(): visible_tris += tris; visible_surfaces += 1
			var mat := mesh.get_active_material(surface) as StandardMaterial3D
			check(mat.vertex_color_use_as_albedo and not mat.vertex_color_is_srgb and is_equal_approx(mat.roughness, .9) and mat.metallic == 0 and is_equal_approx(mat.metallic_specular, .18), "farm matte vertex paint: " + str(mesh.name))
	check(total <= 900 and visible_surfaces <= 2, "all tiers <=900 triangles / shared base + one tier <=2 visible surfaces")
	check(badge.find_children("*", "Skeleton3D", true, false).is_empty() and badge.find_children("*", "CollisionObject3D", true, false).is_empty(), "no skeleton / added collision")
	var digit := decorate(badge, "wood", 3)
	await frames(4)
	report.opening_camera = camera_state(farm.cam)
	for i in 4:
		for tier in TIERS: badge.find_child("Tier_" + tier, true, false).visible = tier == TIERS[i]
		digit.text = str(LEVELS[i]); await shot("opening_" + str(LEVELS[i]))
	# Same native joystick command as P0_SHOT_STEPS="wait:6,walk:0:-1:1.2,wait:3".
	farm.p0_joystick(Vector2(0, -1))
	print("BADGE_WALK_START")
	await get_tree().create_timer(1.2).timeout
	farm.p0_joystick(Vector2.ZERO)
	await get_tree().create_timer(3.0).timeout
	print("BADGE_WALK_DONE ", farm._zoom, " ", farm.cam.size)
	check(is_equal_approx(farm._zoom, 1.0) and absf(farm.cam.size - 6.72) < .001 and absf(farm.cam.rotation_degrees.x + 43) < .001, "walked native follow camera: zoom 1 / 6.72 m / 43 degrees")
	report.follow_camera = camera_state(farm.cam)
	report.tiers = []
	for i in 4:
		for tier in TIERS: badge.find_child("Tier_" + tier, true, false).visible = tier == TIERS[i]
		digit.text = str(LEVELS[i])
		var image := await shot("follow_" + str(LEVELS[i]))
		var box := digit.get_aabb()
		check(box.size.x < .62, "two-digit line width fits face, Lv" + str(LEVELS[i]))
		var row := {"level": LEVELS[i], "tier": TIERS[i], "label_aabb": str(box), "font_size": digit.font_size,
			"number_centre": point(farm.cam, number.global_position),
			"disc_left": point(farm.cam, face.to_global(Vector3(-.4, 0, .052))),
			"disc_right": point(farm.cam, face.to_global(Vector3(.4, 0, .052))),
			"number_corners": [point(farm.cam, digit.to_global(box.position)), point(farm.cam, digit.to_global(box.end))],
			"physical_image_size": [image.get_width(), image.get_height()]}
		digit.visible = false; await shot("control_no_digits_" + str(LEVELS[i])); digit.visible = true
		report.tiers.append(row)
	# Four model instances, same farm World3D and unchanged real lights. Comparison camera only.
	badge.visible = false
	farm.actor.visible = false # Keep a cropped pair of player legs out of this prop-only close-up.
	var vp := SubViewport.new(); vp.size = Vector2i(1600, 820); vp.world_3d = farm.get_world_3d()
	vp.msaa_3d = Viewport.MSAA_4X; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(vp)
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH; cam.size = 4.7; cam.near = .1; cam.far = 40
	vp.add_child(cam); cam.make_current(); cam.global_basis = farm.cam.global_basis
	var centre: Vector3 = farm.actor.position + Vector3(0, 0, 1.8)
	for i in 4:
		var item: Node3D = load("res://assets/farm/art/homestead_badge.glb").instantiate()
		badge.get_parent().add_child(item); item.global_position = centre + cam.global_basis.x * ((i-1.5)*1.04)
		item.rotation.y = deg_to_rad(14.5); decorate(item, TIERS[i], LEVELS[i])
	cam.global_position = centre + Vector3(0, .72, 0) + cam.global_basis.z * 11
	await shot("four_tiers", vp)
	report.close_camera = {"transform": str(cam.global_transform), "width": cam.size, "image_size": [1600, 820]}
	report.triangles = total; report.stored_surfaces = stored
	report.visible_triangles = visible_tris; report.visible_surfaces = visible_surfaces
	report.renderer = RenderingServer.get_current_rendering_method(); report.gpu = RenderingServer.get_video_adapter_name()
	report.asset_sha256 = FileAccess.get_sha256("res://assets/farm/art/homestead_badge.glb")
	report.checks = checks; report.passed = checks.all(func(c): return c.passed)
	FileAccess.open("res://../render-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("BADGE_RENDER ", report.passed, " ", checks.size(), " checks")
	vp.queue_free(); farm.queue_free(); rt.queue_free(); await frames(2)
	get_tree().quit(0 if report.passed else 1)

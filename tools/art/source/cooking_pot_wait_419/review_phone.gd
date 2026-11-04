extends "res://review.gd"
## Temporary b1 kitchen art + existing UiHeatRing; labels/bar are review fixtures.
## This is a visibility check, not cooking integration or final UI acceptance.
var ring: UiHeatRing

func label_at(text: String, at: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.theme = UiKit.theme()
	label.text = text
	label.position = at
	label.size = Vector2(width,32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("344C40"))
	viewport.add_child(label)
	return label

func panel(at: Vector2, size: Vector2, colour: Color, radius: int) -> Panel:
	var p := Panel.new()
	p.position = at
	p.size = size
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel",box)
	viewport.add_child(p)
	return p

func vertices(node: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	if node is MeshInstance3D and node.is_visible_in_tree():
		for s in node.mesh.get_surface_count():
			for p in node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: out.append(node.global_transform*p)
	for c in node.get_children(): out.append_array(vertices(c))
	return out

func projected(points: PackedVector3Array) -> Rect2:
	var rect := Rect2(camera.unproject_position(points[0]),Vector2.ZERO)
	for p in points: rect = rect.expand(camera.unproject_position(p))
	return rect

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"phone_frames")
	var world := make_view(Vector2i(360,800))
	var room := P0Room.new()
	room.use_runtime = false
	room.anchors_path = "res://assets/p0/rooms/farmhouse.anchors.json"
	room.level = 3
	world.add_child(room)
	room.set_process(false)
	room.set_physics_process(false)
	room.actor.visible = false
	prop = PROP.instantiate()
	room.art.add_child(prop)
	prop.position = Vector3(-2.5,.98,-2.495)
	camera = room.cam
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = .78
	var mouth := prop.to_global(Vector3(0,.18,0))
	var yaw := deg_to_rad(25)
	var pitch := deg_to_rad(43)
	camera.position = mouth + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*3
	camera.look_at(mouth)
	camera.current = true
	var rigid := vertices(prop.get_node("PotRig/StovePot/pot_big"))
	camera.size *= projected(rigid).size.x/120.0
	camera.position -= camera.global_basis.y*(400-235)*camera.size/360.0
	panel(Vector2(14,24),Vector2(332,44),Color("F7F6EA"),18)
	label_at("San Francisco · Farmhouse",Vector2(20,30),320,16)
	panel(Vector2(122,340),Vector2(116,44),Color(.98,.97,.92,.90),16)
	label_at("0:42",Vector2(122,340),116,32)
	panel(Vector2(80,392),Vector2(200,8),Color("E1DAC8"),4)
	panel(Vector2(80,392),Vector2(116,8),Color("3E7D43"),4)
	panel(Vector2(14,604),Vector2(332,180),Color("F7F6EA"),22)
	label_at("Fresh Fish Soup",Vector2(30,622),300,22)
	label_at("Cooking",Vector2(30,655),300,16)
	label_at("Tap when the needle hits gold!",Vector2(20,700),320,16)
	ring = UiHeatRing.new()
	ring.position = Vector2(120,175)
	ring.gold = .27
	ring.width = .25
	ring.turn = .23
	viewport.add_child(ring)
	var player := prop.get_node("AnimationPlayer") as AnimationPlayer
	player.play("tumble")
	player.pause()
	for i in 45: await get_tree().process_frame
	player.seek(.88,true)
	await get_tree().process_frame
	await snap("SGODOT-419_cooking_pot_v1_phone_ring.png")
	ring.visible = false
	await get_tree().process_frame
	await snap("SGODOT-419_cooking_pot_v1_phone_clear.png")
	ring.visible = true
	var rect := projected(vertices(prop))
	var lid := prop.get_node("PotRig/StovePot/pot_big/lid") as Node3D
	player.seek(0,true)
	var lid_rest := projected(vertices(lid)).position
	var body_rest := projected(vertices(prop.get_node("PotRig/StovePot/pot_big/big_body"))).position
	var max_lid := 0.0
	var max_body := 0.0
	var steam_rect := Rect2()
	var steam := prop.find_child("Steam",true,false) as GPUParticles3D
	for i in 181:
		player.seek(i*.01,true)
		rect = rect.merge(projected(vertices(prop)))
		max_lid = maxf(max_lid,lid_rest.distance_to(projected(vertices(lid)).position))
		max_body = maxf(max_body,body_rest.distance_to(projected(vertices(prop.get_node("PotRig/StovePot/pot_big/big_body"))).position))
		# Conservative trajectory envelope: max velocity/age/gravity + the largest
		# camera-facing quad half-size, transformed with the moving lid.
		var envelope := PackedVector3Array()
		for x in [-.016,.020]:
			for y in [0.0,.088]:
				for z in [-.012,.012]:
					var centre := steam.to_global(Vector3(x,y,z))
					for sx in [-1,1]:
						for sy in [-1,1]: envelope.append(centre+camera.global_basis.x*sx*.021+camera.global_basis.y*sy*.027)
		var sr := projected(envelope)
		steam_rect = sr if i==0 else steam_rect.merge(sr)
	var m := camera.unproject_position(mouth)
	var whole := rect.merge(steam_rect)
	var measurements := {"viewport":[360,800],"camera_pitch_degrees":43,"pot_width_px":projected(rigid).size.x,"mouth_px":[m.x,m.y],"animated_geometry_rect_px":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"whole_with_conservative_steam_envelope_px":[whole.position.x,whole.position.y,whole.size.x,whole.size.y],"max_lid_screen_displacement_px":max_lid,"max_body_screen_displacement_px":max_body,"fixture":"b1 native Basic Room + original UiHeatRing; countdown and progress are temporary review controls; no gameplay integration"}
	assert(max_lid<=12 and max_body<=2)
	assert(abs(m.x-180)<1 and abs(m.y-235)<1)
	assert(Rect2(80,150,200,180).encloses(whole))
	FileAccess.open("res://../phone-validation.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t")+"\n")
	for i in 108:
		player.seek(fmod(i/30.0,1.8),true)
		ring.visible = i>=54
		ring.turn = fmod(i/30.0,1.4)/1.4
		await get_tree().process_frame
		await snap("phone_frames/%04d.png"%i)
	print("RENDERED_PHONE ",JSON.stringify(measurements))
	get_tree().quit()

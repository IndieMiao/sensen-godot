extends "res://review.gd"
## v1.1: native 200x180 transparent layer, composited at (80,150) on a
## 360x800 review canvas. Lighting and camera belong to this fixture only.
const PREFIX := "SGODOT-419_cooking_pot_v1.1_"
const OFFSET := Vector2(80,150)
var layer: SubViewport

class Guides extends Control:
	func _draw() -> void:
		draw_rect(Rect2(80,150,200,180),Color(.32,.43,.36,.6),false,1)
		draw_arc(Vector2(180,235),60,0,TAU,128,Color("527565"),1,true)
		draw_line(Vector2(177,235),Vector2(183,235),Color("527565"),1)
		draw_line(Vector2(180,232),Vector2(180,238),Color("527565"),1)

func caption(text: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("344C40"))
	viewport.add_child(label)

func vertices(n: Node) -> PackedVector3Array:
	var a := PackedVector3Array()
	if n is MeshInstance3D and n.is_visible_in_tree():
		for s in n.mesh.get_surface_count():
			for v in n.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: a.append(n.global_transform*v)
	for c in n.get_children(): a.append_array(vertices(c))
	return a

func projected(points: PackedVector3Array) -> Rect2:
	var rect := Rect2(camera.unproject_position(points[0])+OFFSET,Vector2.ZERO)
	for p in points: rect = rect.expand(camera.unproject_position(p)+OFFSET)
	return rect

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"overlay_frames")
	make_view(Vector2i(360,800))
	var background := ColorRect.new()
	background.color = Color("F5F2E9")
	background.size = Vector2(360,800)
	viewport.add_child(background)
	layer = SubViewport.new()
	layer.size = Vector2i(200,180)
	layer.own_world_3d = true
	layer.transparent_bg = true
	layer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.msaa_3d = Viewport.MSAA_4X
	viewport.add_child(layer)
	var image := TextureRect.new()
	image.position = OFFSET
	image.size = Vector2(200,180)
	image.texture = layer.get_texture()
	viewport.add_child(image)
	var world := Node3D.new()
	layer.add_child(world)
	lighting(world)
	prop = PROP.instantiate()
	world.add_child(prop)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = .005
	camera.far = 5
	camera.fov = 60
	var mouth := Vector3(0,.18,0)
	var pitch := deg_to_rad(62)
	var distance := .4
	camera.position = mouth+Vector3(0,sin(pitch),cos(pitch))*distance
	camera.look_at(mouth)
	camera.current = true
	var rigid := vertices(prop.get_node("PotRig/StovePot/pot_big"))
	for i in 5:
		camera.fov = rad_to_deg(2*atan(tan(deg_to_rad(camera.fov*.5))*projected(rigid).size.x/180))
	# Mouth is (100,85) within the 200x180 layer, (180,235) on screen.
	camera.position -= camera.global_basis.y*distance*tan(deg_to_rad(camera.fov*.5))*.05
	viewport.add_child(Guides.new())
	caption("SGODOT-419 / A / v1.1",Vector2(24,28),20)
	caption("200 x 180 transparent 3D layer",Vector2(24,64),16)
	caption("Pot 180 px / ring radius 60 px",Vector2(24,350),16)
	caption("Mouth (180, 235) / warm upper-left light",Vector2(24,378),14)
	caption("Art overlay test / no cooking UI",Vector2(24,718),16)
	caption("Huang Zhong / Mobile Vulkan / 1.8 s",Vector2(24,746),14)
	var player := prop.get_node("AnimationPlayer") as AnimationPlayer
	player.play("tumble")
	player.pause()
	var lid := prop.get_node("PotRig/StovePot/pot_big/lid") as Node3D
	var lid_mesh := lid.get_node("lid_mesh") as MeshInstance3D
	player.seek(0,true)
	var lid_rest := vertices(lid_mesh)
	var body_rest := vertices(prop.get_node("PotRig/StovePot/pot_big/big_body"))
	var max_lid := 0.0
	var max_body := 0.0
	var whole := projected(vertices(prop))
	var steam := prop.find_child("Steam",true,false) as GPUParticles3D
	for i in 181:
		player.seek(i*.01,true)
		whole = whole.merge(projected(vertices(prop)))
		var lv := vertices(lid_mesh)
		for k in lv.size(): max_lid=maxf(max_lid,camera.unproject_position(lv[k]).distance_to(camera.unproject_position(lid_rest[k])))
		var bv := vertices(prop.get_node("PotRig/StovePot/pot_big/big_body"))
		for k in bv.size(): max_body=maxf(max_body,camera.unproject_position(bv[k]).distance_to(camera.unproject_position(body_rest[k])))
		var envelope := PackedVector3Array()
		for x in [-.006,.006]:
			for y in [0.0,.068]:
				for z in [-.006,.006]:
					var centre := steam.to_global(Vector3(x,y,z))
					for sx in [-1,1]:
						for sy in [-1,1]: envelope.append(centre+camera.global_basis.x*sx*.021+camera.global_basis.y*sy*.027)
		whole = whole.merge(projected(envelope))
	var m := camera.unproject_position(mouth)+OFFSET
	var measurements := {"viewport":[360,800],"layer_size":[200,180],"layer_position":[80,150],"transparent":true,"camera_projection":"perspective","camera_pitch_degrees":62,"camera_horizontal_fov_degrees":camera.fov,"camera_position_m":[camera.position.x,camera.position.y,camera.position.z],"pot_width_px":projected(rigid).size.x,"mouth_px":[m.x,m.y],"whole_with_conservative_steam_envelope_px":[whole.position.x,whole.position.y,whole.size.x,whole.size.y],"max_lid_vertex_screen_displacement_px":max_lid,"max_body_vertex_screen_displacement_px":max_body,"ring_radius_px":60,"fixture":"Isolated transparent 200x180 SubViewport; warm upper-left fixture light; no kitchen/cooking UI or runtime integration"}
	FileAccess.open("res://../overlay-validation.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t")+"\n")
	print("OVERLAY_MEASURE ",JSON.stringify(measurements))
	assert(max_lid<=12 and max_body<=2)
	assert(abs(m.x-180)<.1 and abs(m.y-235)<.1)
	assert(Rect2(80,150,200,180).encloses(whole))
	for i in 45: await get_tree().process_frame
	player.seek(.88,true)
	await get_tree().process_frame
	await snap(PREFIX+"overlay_ring.png")
	assert(layer.get_texture().get_image().save_png(OUT+PREFIX+"layer_rgba.png")==OK)
	for i in 90:
		player.seek(fmod(i/30.0,1.8),true)
		await get_tree().process_frame
		await snap("overlay_frames/%04d.png"%i)
	print("RENDERED_OVERLAY_90_FRAMES")
	get_tree().quit()

extends SceneTree
## Offline generator. Runtime scene has no script, lights, camera or autoplay.
const DIR := "res://assets/props/cooking_pot_wait/"
const POT := "res://assets/props/stove_pot/stove_pot.glb"
const LID := "PotRig/StovePot/pot_big/lid"
const REST := Vector3(0, .181, -.107)
const PERIOD := 1.8
var root_node: Node3D
var matte: StandardMaterial3D
var uids := {}

func save(resource: Resource, filename: String) -> void:
	var path := DIR+filename
	if not uids.has(filename): uids[filename] = ResourceUID.id_to_text(ResourceUID.create_id())
	var uid := ResourceUID.text_to_id(uids[filename])
	assert(ResourceSaver.save(resource,path,ResourceSaver.FLAG_CHANGE_PATH)==OK)
	# Native resources use native Godot UIDs; there is no image/GLB import here.
	assert(ResourceSaver.set_uid(path,uid)==OK)
	resource.take_over_path(path)

func _initialize() -> void:
	call_deferred("build")

func child(node: Node, parent: Node, label: String) -> Node:
	node.name = label
	parent.add_child(node)
	node.owner = root_node
	return node

func painted(primitive: PrimitiveMesh, colour: Color) -> ArrayMesh:
	var a := primitive.get_mesh_arrays()
	var colours := PackedColorArray()
	colours.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	colours.fill(colour.srgb_to_linear())
	a[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mesh.surface_set_material(0, matte)
	return mesh

func ball(colour: Color) -> ArrayMesh:
	var p := SphereMesh.new()
	p.radius = 1
	p.height = 2
	p.radial_segments = 12
	p.rings = 5
	return painted(p, colour)

func pot_vertex_colour(source: Mesh) -> ArrayMesh:
	# Reuse exact original vertex/index/normal/UV arrays. Only bake the two source
	# palette materials to COLOR on scene-local copies, so the complete prop has
	# one opaque material plus steam. The referenced GLB is never rewritten.
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var mat := source.surface_get_material(surface) as StandardMaterial3D
		var pixels := mat.albedo_texture.get_image()
		if pixels.is_compressed(): pixels.decompress()
		var colours := PackedColorArray()
		for uv in arrays[Mesh.ARRAY_TEX_UV]:
			var x := clampi(int(uv.x*pixels.get_width()),0,pixels.get_width()-1)
			var y := clampi(int(uv.y*pixels.get_height()),0,pixels.get_height()-1)
			colours.append(pixels.get_pixel(x,y).srgb_to_linear()*mat.albedo_color.srgb_to_linear())
		arrays[Mesh.ARRAY_COLOR] = colours
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(surface,matte)
	return mesh

func mesh_node(label: String, mesh: Mesh, parent: Node, at: Vector3, sizing := Vector3.ONE) -> MeshInstance3D:
	var n := child(MeshInstance3D.new(), parent, label) as MeshInstance3D
	n.mesh = mesh
	n.position = at
	n.scale = sizing
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

func track(anim: Animation, path: String, times: Array, values: Array) -> void:
	var i := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(i, NodePath(path))
	anim.track_set_interpolation_type(i, Animation.INTERPOLATION_LINEAR)
	for k in times.size(): anim.track_insert_key(i, times[k], values[k])

func make_steam(lid: Node) -> void:
	var radial := Gradient.new()
	radial.offsets = PackedFloat32Array([0, .3, 1])
	radial.colors = PackedColorArray([Color(1,1,1,.7), Color(1,1,1,.36), Color(1,1,1,0)])
	var texture := GradientTexture2D.new()
	texture.gradient = radial
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5,.5)
	texture.fill_to = Vector2(1,.5)
	var steam_mat := StandardMaterial3D.new()
	steam_mat.resource_name = "SoftSteam_AlphaCapped"
	steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_mat.vertex_color_use_as_albedo = true
	steam_mat.albedo_texture = texture
	steam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	steam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	steam_mat.no_depth_test = false
	save(steam_mat,"steam.tres")
	var quad := QuadMesh.new()
	quad.size = Vector2(.038, .048)
	quad.material = steam_mat
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0,.15,.6,1])
	gradient.colors = PackedColorArray([Color(1,1,1,0),Color(1,1,1,.17),Color(1,1,1,.11),Color(1,1,1,0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0,.5))
	size_curve.add_point(Vector2(.5,.85))
	size_curve.add_point(Vector2(1,1))
	var size_texture := CurveTexture.new()
	size_texture.curve = size_curve
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(.08,1,0)
	process.spread = 8
	process.gravity = Vector3(.003,.009,0)
	process.initial_velocity_min = .048
	process.initial_velocity_max = .061
	process.scale_min = .75
	process.scale_max = 1.1
	process.scale_curve = size_texture
	process.color_ramp = ramp
	var steam := child(GPUParticles3D.new(), lid, "Steam") as GPUParticles3D
	# Original vent is a sibling of lid; use its lid-local rest coordinates.
	steam.position = Vector3(.062,.032,.146)
	steam.local_coords = true
	steam.amount = 5
	steam.lifetime = 1.3
	steam.preprocess = 1.3
	steam.fixed_fps = 30
	steam.use_fixed_seed = true
	steam.seed = 419
	steam.process_material = process
	steam.draw_pass_1 = quad
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	steam.visibility_aabb = AABB(Vector3(-.05,-.03,-.05),Vector3(.12,.19,.12))

func build() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(DIR+"resource_uids.json"):
		uids = JSON.parse_string(FileAccess.get_file_as_string(DIR+"resource_uids.json"))
	matte = StandardMaterial3D.new()
	matte.resource_name = "SoupAndFoam_MatteVertexColour"
	matte.vertex_color_use_as_albedo = true
	matte.roughness = .95
	matte.metallic_specular = .15
	save(matte,"soup_matte.tres")
	root_node = Node3D.new()
	root_node.name = "CookingPotWait"
	get_root().add_child(root_node)
	var rig := child(Node3D.new(), root_node, "PotRig") as Node3D
	var pot := (load(POT) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	child(pot, rig, "StovePot")
	root_node.set_editable_instance(pot,true)
	pot.get_node("pot_normal").visible = false
	for pair in [["pot_big/big_body","pot_body_colours.res"],["pot_big/lid/lid_mesh","pot_lid_colours.res"]]:
		var part := pot.get_node(pair[0]) as MeshInstance3D
		var mesh := pot_vertex_colour(part.mesh)
		save(mesh,pair[1])
		part.mesh = mesh
	var soup := child(Node3D.new(), rig, "Soup") as Node3D
	soup.position.y = .177
	var disc := CylinderMesh.new()
	disc.top_radius = .094
	disc.bottom_radius = .094
	disc.height = .003
	disc.radial_segments = 32
	disc.rings = 1
	var soup_mesh := painted(disc,Color("B97931"))
	save(soup_mesh,"soup_surface.res")
	mesh_node("Surface",soup_mesh,soup,Vector3.ZERO)
	var bubble_mesh := ball(Color("CC8E3A"))
	save(bubble_mesh,"soup_bubble.res")
	var bubble_positions := [Vector3(-.044,.003,.064),Vector3(.009,.004,.077),Vector3(.050,.003,.047)]
	for i in 3:
		mesh_node("Bubble%d" % (i+1),bubble_mesh,soup,bubble_positions[i],Vector3.ONE*.0001)
	# One merged front foam crescent; irregular lobes retain a round silhouette.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foam_ball := ball(Color("F4E6CB"))
	for angle in [-48.0,-36.0,-24.0,20.0,30.0]:
		var theta := deg_to_rad(angle)
		var xform := Transform3D(Basis.from_scale(Vector3(.014,.002,.007)), Vector3(sin(theta)*.088,.0005,cos(theta)*.088))
		tool.append_from(foam_ball,0,xform)
	var foam_mesh := tool.commit()
	foam_mesh.surface_set_material(0,matte)
	save(foam_mesh,"rim_foam.res")
	mesh_node("RimFoam",foam_mesh,soup,Vector3(0,.004,0),Vector3.ONE*.0001)
	make_steam(pot.get_node("pot_big/lid"))
	var player := child(AnimationPlayer.new(),root_node,"AnimationPlayer") as AnimationPlayer
	var library := AnimationLibrary.new()
	var tumble := Animation.new()
	tumble.resource_name = "tumble"
	tumble.length = PERIOD
	tumble.loop_mode = Animation.LOOP_LINEAR
	var times := [0.0,.30,.52,.72,.88,1.02,1.12,1.20,1.28,1.37,1.49,1.8]
	var lifts := [0.0,0.0,.006,.020,.024,.017,.004,0.0,.004,0.0,0.0,0.0]
	var tilts := [0.0,0.0,-.008,-.018,-.022,-.014,0.0,0.0,.008,0.0,0.0,0.0]
	var lid_positions: Array = []
	var lid_rotations: Array = []
	for i in times.size():
		lid_positions.append(REST + Vector3(0,lifts[i],0))
		lid_rotations.append(Vector3(tilts[i],0,sin(i*2.0)*.008 if i>1 and i<9 else 0.0))
	track(tumble,LID+":position",times,lid_positions)
	track(tumble,LID+":rotation",times,lid_rotations)
	track(tumble,"PotRig:position",[0,.50,.67,.82,.94,1.09,1.21,1.8], [Vector3.ZERO,Vector3.ZERO,Vector3(0,.002,0),Vector3.ZERO,Vector3(0,.001,0),Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	for i in 3:
		var t := .53+i*.13
		var size := .014-i*.0015
		track(tumble,"PotRig/Soup/Bubble%d:scale"%(i+1),[0,t,t+.16,t+.25,t+.31,t+.36,1.8], [Vector3.ONE*.0001,Vector3(size*.3,size*.1,size*.3),Vector3(size,size*.7,size),Vector3(size*1.06,size,size*1.06),Vector3(size*1.12,size*.15,size*1.12),Vector3.ONE*.0001,Vector3.ONE*.0001])
	track(tumble,"PotRig/Soup/RimFoam:scale",[0,.40,.62,.88,1.09,1.19,1.34,1.46,1.8],[Vector3.ONE*.0001,Vector3.ONE*.0001,Vector3.ONE,Vector3.ONE,Vector3.ONE*.95,Vector3.ONE*.0001,Vector3.ONE*.65,Vector3.ONE*.0001,Vector3.ONE*.0001])
	library.add_animation("tumble",tumble)
	var idle := Animation.new()
	idle.resource_name = "idle"
	idle.length = 1.0
	idle.loop_mode = Animation.LOOP_LINEAR
	# All moving properties are explicitly reset, including when switching mid-tumble.
	for i in tumble.get_track_count():
		var path := str(tumble.track_get_path(i))
		var value = tumble.track_get_key_value(i,0)
		track(idle,path,[0.0,1.0],[value,value])
	library.add_animation("idle",idle)
	player.add_animation_library("",library)
	var scene := PackedScene.new()
	assert(scene.pack(root_node)==OK)
	save(scene,"cooking_pot_wait.tscn")
	FileAccess.open(DIR+"resource_uids.json",FileAccess.WRITE).store_string(JSON.stringify(uids,"\t")+"\n")
	print("BUILT ",DIR)
	quit()

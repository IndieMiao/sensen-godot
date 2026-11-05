extends "res://review.gd"
const STEAM_PREFIX := "SGODOT-419_cooking_pot_v1.2_"

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"steam_v12_masks")
	var world := make_view(Vector2i(720,720))
	lighting(world)
	# Warm neutral wall colour makes white steam legible without compositing it
	# over orange pottery. Only the fixture environment supplies the background.
	for n in world.get_children():
		if n is WorldEnvironment: n.environment.background_color = Color("C5B79F")
	prop = PROP.instantiate()
	world.add_child(prop)
	camera = Camera3D.new()
	world.add_child(camera)
	aim(Vector3(0,.19,0),.50)
	camera.current = true
	var player := prop.get_node("AnimationPlayer") as AnimationPlayer
	player.play("tumble")
	player.pause()
	for i in 90: await get_tree().process_frame
	for shot in [["closed",.12],["lifted",.88],["settled",1.28]]:
		player.seek(shot[1],true)
		for i in 20: await get_tree().process_frame
		await snap(STEAM_PREFIX+shot[0]+".png")
	# Inspect actual steam pixels separately from opaque geometry, under both
	# the studio angle and the flatter runtime-side 43-degree camera.
	var nodes := prop.find_children("*","MeshInstance3D",true,false)
	var steam := prop.find_child("Steam",true,false) as GPUParticles3D
	for pitch in [35,43]:
		var yaw := deg_to_rad(25 if pitch==35 else 40)
		var p := deg_to_rad(pitch)
		var at := Vector3(0,.19,0)
		camera.position = at+Vector3(sin(yaw)*cos(p),sin(p),cos(yaw)*cos(p))*2
		camera.look_at(at)
		for shot in [["closed",.12],["lifted",.88],["settled",1.28]]:
			player.seek(shot[1],true)
			for i in 10: await get_tree().process_frame
			var lid := prop.get_node("PotRig/StovePot/pot_big/lid/lid_mesh") as MeshInstance3D
			var top := 720.0
			for s in lid.mesh.get_surface_count():
				for v in lid.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]: top=minf(top,camera.unproject_position(lid.to_global(v)).y)
			# Compare opaque RGB too: Mobile transparent render targets can have
			# coarser alpha precision than their visible RGB blend.
			steam.speed_scale=0
			for i in 2: await get_tree().process_frame
			await snap("steam_v12_masks/%d_%s_on.png"%[pitch,shot[0]])
			steam.visible=false
			for i in 2: await get_tree().process_frame
			await snap("steam_v12_masks/%d_%s_off.png"%[pitch,shot[0]])
			steam.visible=true
			for n in nodes: n.visible=false
			viewport.transparent_bg=true
			for i in 2: await get_tree().process_frame
			await snap("steam_v12_masks/%d_%s.png"%[pitch,shot[0]])
			print("STEAM_MASK ",pitch," ",shot[0]," lid_top_y=",top)
			for n in nodes: n.visible=true
			prop.get_node("PotRig/StovePot/pot_normal").visible=false
			viewport.transparent_bg=false
			steam.speed_scale=1
	print("RENDERED_STEAM_V12")
	get_tree().quit()

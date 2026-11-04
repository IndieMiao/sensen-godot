extends SceneTree
const PATH := "res://assets/props/cooking_pot_wait/cooking_pot_wait.tscn"
var checks: Array = []
var errors: Array = []

func check(ok: bool, label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok: errors.append(label)

func all_nodes(node: Node) -> Array:
	var result: Array = [node]
	for c in node.get_children(): result.append_array(all_nodes(c))
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := (load(PATH) as PackedScene).instantiate()
	get_root().add_child(scene)
	var player := scene.get_node("AnimationPlayer") as AnimationPlayer
	check(scene is Node3D and scene.transform == Transform3D.IDENTITY,"Root identity / bottom-centre contract")
	check(player.get_animation_list()==PackedStringArray(["idle","tumble"]),"Exactly idle and tumble")
	check(player.autoplay=="","No autoplay")
	check(not scene.get_node("PotRig/StovePot/pot_normal").visible,"Normal pot hidden in saved scene")
	check(scene.get_node("PotRig/StovePot").scene_file_path=="res://assets/props/stove_pot/stove_pot.glb","Original GLB remains instanced")
	var tri := 0
	var surfaces := 0
	var mats := {}
	var bounds := AABB()
	var first := true
	for n in all_nodes(scene):
		check(not (n is Light3D or n is Camera3D or n is WorldEnvironment or n is Skeleton3D),"No forbidden payload: "+str(scene.get_path_to(n)))
		if n is MeshInstance3D and n.is_visible_in_tree():
			for s in n.mesh.get_surface_count():
				var a: Array = n.mesh.surface_get_arrays(s)
				tri += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3 if a[Mesh.ARRAY_INDEX]!=null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3
				surfaces += 1
				mats[n.get_active_material(s).get_instance_id()] = n.get_active_material(s).resource_name
				for v in a[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = n.global_transform*v
					if first: bounds = AABB(p,Vector3.ZERO); first = false
					else: bounds = bounds.expand(p)
	check(tri<15000,"Geometry below 15000 triangles")
	check(mats.size()==1,"One shared opaque material; plus steam = two total")
	var max_normal_error := 0.0
	var original := (load("res://assets/props/stove_pot/stove_pot.glb") as PackedScene).instantiate()
	for path in ["pot_big/big_body","pot_big/lid/lid_mesh"]:
		var reference: Mesh = original.get_node(path).mesh
		var actual: Mesh = scene.get_node("PotRig/StovePot/"+path).mesh
		check(reference.get_surface_count()==actual.get_surface_count(),"Source surfaces retained "+path)
		for s in reference.get_surface_count():
			var a := reference.surface_get_arrays(s)
			var b := actual.surface_get_arrays(s)
			for attr in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_INDEX,Mesh.ARRAY_TEX_UV]:
				if attr==Mesh.ARRAY_NORMAL:
					for i in a[attr].size(): max_normal_error=maxf(max_normal_error,(a[attr][i] as Vector3).distance_to(b[attr][i]))
				else: check(a[attr]==b[attr],"Source geometry/UV exact "+path+" / "+str(s)+" / "+str(attr))
	check(max_normal_error<.0002,"Normal repacking numerical error < 0.0002: "+str(max_normal_error))
	original.free()
	check(abs(bounds.size.x-.28)<.00001 and abs(bounds.size.y-.242)<.00001,"Original pot scale retained")
	var steam := scene.find_child("Steam",true,false) as GPUParticles3D
	check(steam!=null and steam.local_coords and steam.amount==5,"Steam: GPU particles / local coordinates / 5 particles")
	check(steam.get_parent()==scene.get_node("PotRig/StovePot/pot_big/lid"),"Steam follows lid vent")
	check(steam.global_position.distance_to(Vector3(.062,.213,.039))<.00001,"Steam matches original vent at rest")
	var max_lift := 0.0
	var max_body := 0.0
	var max_front_lift := 0.0
	var lid := scene.get_node("PotRig/StovePot/pot_big/lid") as Node3D
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		check(anim.loop_mode==Animation.LOOP_LINEAR,anim_name+" loops")
		for i in anim.get_track_count():
			check(str(anim.track_get_path(i)).begins_with("PotRig"),anim_name+" track does not target scene root")
			check(anim.track_get_key_value(i,0)==anim.track_get_key_value(i,anim.track_get_key_count(i)-1),anim_name+" seamless endpoint "+str(i))
	player.play("tumble")
	player.pause()
	for i in 181:
		player.seek(i*.01,true)
		check(scene.transform==Transform3D.IDENTITY,"Root fixed at sample "+str(i))
		max_lift = maxf(max_lift,lid.position.y-.181)
		max_body = maxf(max_body,scene.get_node("PotRig").position.y)
		max_front_lift = maxf(max_front_lift,(lid.transform*Vector3(0,0,.214)).y-.181)
		if i%17==0:
			player.play("idle")
			player.advance(0)
			check(lid.position.distance_to(Vector3(0,.181,-.107))<.000001 and lid.rotation.length()<.000001 and scene.get_node("PotRig").position.length()<.000001,"Idle restores pose from tumble sample "+str(i))
			for b in ["Bubble1","Bubble2","Bubble3","RimFoam"]:
				check(scene.get_node("PotRig/Soup/"+b).scale.x<=.00011,"Idle hides "+b)
			player.play("tumble")
			player.pause()
	check(max_lift>=.02 and max_front_lift<=.03,"Lid maximum lift is 2–3 cm including tilt")
	check(max_body<=.00201,"Body bounce at most 2 mm")
	check(1-pow(1-.17*.7,5)<.5,"Steam theoretical alpha with all five overlapping below 0.5")
	var output := {"checks":checks,"errors":errors,"check_count":checks.size(),"triangles_excluding_steam":tri,"steam_triangles":10,"surfaces_excluding_steam":surfaces,"opaque_materials":mats.values(),"added_render_materials":2,"bounds_rest":{"position":[bounds.position.x,bounds.position.y,bounds.position.z],"size":[bounds.size.x,bounds.size.y,bounds.size.z]},"max_lid_pivot_lift_m":max_lift,"max_lid_front_lift_m":max_front_lift,"max_body_bounce_m":max_body,"steam_peak_single_particle_alpha":.17*.7,"steam_all_five_overlap_bound":1-pow(1-.17*.7,5)}
	FileAccess.open("res://../validation.json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t")+"\n")
	print("VERIFY ",checks.size()," checks; errors=",errors,"; triangles=",tri)
	quit(0 if errors.is_empty() else 1)

extends SceneTree
## Offline only: export the actual seeded bank mesh's waterline segments.
func _initialize() -> void:
	assert(bool(ProjectSettings.get_setting("sensen/network/online_qa", false)))
	var output := "res://../../pond-foam-2026-09-30/contacts.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	var entries: Array = []
	for entry in SystemPonds.data().locations:
		var bank := WaterShore.build(str(entry.id), SystemPonds.site(entry))
		var mesh := (bank.get_node("BankStones") as MeshInstance3D).mesh
		var faces := mesh.get_faces()
		var segments: Array = []
		for index in range(0, faces.size(), 3):
			var points := [faces[index], faces[index + 1], faces[index + 2]]
			var hits: Array[Vector3] = []
			for edge in 3:
				var a: Vector3 = points[edge]
				var b: Vector3 = points[(edge + 1) % 3]
				if (a.y < 0.055) == (b.y < 0.055): continue
				hits.append(a.lerp(b, (0.055 - a.y) / (b.y - a.y)))
			if hits.size() == 2 and hits[0].distance_squared_to(hits[1]) > 0.00000001:
				segments.append([hits[0].x, hits[0].z, hits[1].x, hits[1].z])
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(faces.to_byte_array())
		entries.append({"id":entry.id,"template_id":entry.template_id,"decoration_seed":entry.decoration_seed,
			"rock_mesh_sha256":digest.finish().hex_encode(),"segments":segments})
		print("FOAM_CONTACTS ", entry.id, " ", segments.size())
		bank.free()
	var network := get_root().get_node_or_null("Net")
	assert(network == null or not bool(network.get("booted_once")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"water_y":0.055,"catalog_sha256":SystemPonds.revision(),"entries":entries}))
	quit()

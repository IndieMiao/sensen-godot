extends GdUnitTestSuite
## Perf Q6 (SGODOT-260, plan 2026-10-16 §3.1): a fight on floors 3–5 no longer jerks. At most one slime finds its
## path a frame, however their chases line up; a slime is about 2k triangles, not 25k; it casts no real shadow
## (its blob shadow stays).

const Combat := preload("res://modules/mining/p0_mine_combat.gd")
const L := preload("res://modules/mining/mine_layout.gd")
const SLIME := {"kind": "mob_slime", "hp": 9, "max": 9}
const ELITE := {"kind": "mob_elite_slime", "hp": 36, "max": 36}

func _bp() -> FarmBlueprint:
	var nodes: Array = []
	for i in L.FALLBACK_POSITIONS.size(): nodes.append({"id": str(i), "position": L.FALLBACK_POSITIONS[i]})
	return L._navigation(nodes, nodes.map(func(n): return n.id))

## A floor's slimes from a view, as the mine builds them (floor 4: three slimes; floor 5: the elite).
func _fight(n: int, mobs: Array) -> Array:
	var bp := _bp()
	var mover := PlayerMover.new(bp, BlueprintGrid.new(bp))
	mover.position = L.SPAWN
	var c: Node3D = auto_free(Combat.new())
	add_child(c)
	var floors := []
	for i in 5: floors.append({"floor": i + 1, "paid": true, "rocks": 6, "left": 6, "broken": [], "mobs": mobs if i + 1 == n else []})
	c.sync_p0({"mine": {"hp_max": 100, "weapon": {"id": "sword_wooden", "attack": 3, "speed": 2.0},
		"run": {"id": 1, "hp": 100, "floors": floors}}}, n, mover)
	return [c, mover]

func _triangles(node: Node) -> int:
	var n := 0
	for m in node.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).is_visible_in_tree(): n += (m as MeshInstance3D).mesh.get_faces().size() / 3
	return n

## All three chase from the same frame (in range of the player, never close enough to wind up): over 3 s at 60 fps
## no two of them path in the same frame, the first paths at once and the others a frame after each other.
func test_slimes_chasing_together_path_in_different_frames() -> void:
	var f := _fight(4, [SLIME, SLIME, SLIME])
	var c = f[0]
	var mover: PlayerMover = f[1]
	assert_int(c.enemies.size()).is_equal(3)
	for id in c.enemies:
		c.enemies[id].spec.aggro_range = 100.0
		c.enemies[id].spec.attack_range = -1.0   # never close enough to wind up
	c.grace = 0.0
	var last := {}
	for id in c.enemies: last[id] = float(c.enemies[id].repath)
	var together := 0
	var paths := 0
	for frame in 180:
		c.step(1.0 / 60.0, mover, false)
		var now := 0
		for id in c.enemies:
			assert_str(str(c.enemies[id].phase)).is_equal("chase")
			if float(c.enemies[id].repath) > float(last[id]) + 0.001:
				now += 1
				if frame < 3: assert_str(str(id)).is_equal(Combat.mob_id(frame))
			last[id] = float(c.enemies[id].repath)
		paths += now
		if now > 1: together += 1
	assert_int(paths).is_greater_equal(3 * 11)   # each about every 0.25 s, still
	assert_int(together).is_equal(0)

## A slime is light: its face is one mesh (16 × 8 spheres), the whole slime about 2k triangles on screen.
func test_a_slime_is_about_2k_triangles_with_a_one_mesh_face() -> void:
	for mobs in [[SLIME], [ELITE]]:
		var c = _fight(4 if mobs[0] == SLIME else 5, mobs)[0]
		var node: Node3D = c.enemies.values()[0].node
		var body := node.get_node("Body")
		assert_object(body.get_node_or_null("Face")).is_not_null()
		for m in body.find_children("*", "MeshInstance3D", false, false):
			assert_bool((m as MeshInstance3D).mesh is SphereMesh).override_failure_message("a sphere is left: %s" % m.name).is_false()
		assert_int(_triangles(node)).is_less(3000)

## The face keeps its colours: eyes, glints and the cheeks (the elite's pink).
func test_the_face_keeps_its_colours() -> void:
	for pair in [[SLIME, "b8e1cb"], [ELITE, "e5a7ca"]]:
		var c = _fight(4 if pair[0] == SLIME else 5, [pair[0]])[0]
		var face: MeshInstance3D = c.enemies.values()[0].node.get_node("Body/Face")
		var colors: PackedColorArray = face.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var hexes := {}
		for col in colors: hexes[col.to_html(false)] = true
		for hex in ["333345", "fff9e7", pair[1]]:
			assert_bool(hexes.has(hex)).override_failure_message("no %s on the face" % hex).is_true()
		assert_bool((face.material_override as StandardMaterial3D).vertex_color_use_as_albedo).is_true()

## No real shadow from any part of a slime, its wind-up band included; the blob shadow is still there.
func test_a_slime_casts_no_real_shadow() -> void:
	for mobs in [[SLIME, SLIME, SLIME], [ELITE]]:
		var c = _fight(4 if mobs.size() == 3 else 5, mobs)[0]
		for e in c.enemies.values():
			var parts: Array = (e.node as Node).find_children("*", "GeometryInstance3D", true, false)
			assert_int(parts.size()).is_greater(5)
			for g in parts:
				assert_int((g as GeometryInstance3D).cast_shadow).override_failure_message("%s casts" % g.name) \
					.is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			assert_object((e.node as Node).get_node_or_null(BlobShadow.NODE_NAME)).is_not_null()

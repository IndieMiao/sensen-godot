extends SceneTree
## Bake the LOOK-PICK thumbnails (SGODOT-282; 不知火舞 49498df6, 上官婉儿 e4d03424): one PNG per look stage and look,
## assets/p0/looks/look_lv<level>_<a|b>.png, 316 × 200 (the card's 158 × 100 at 2×), from the same parts the farm builds
## (P0Garden.look_parts / stone_wall / look_house), so a thumbnail always matches what the card previews. P1 bakes
## the placeholder models; when the designed ones land, re-run this with the same cameras (上官婉儿 asked for the
## camera numbers to be kept here, so the shots can be repeated):
##
##   godot --path . --script res://tools/dev/look_thumbs.gd        (needs a window: it renders; not --headless)
##
## Cameras (CAMERAS): perspective, FOV 32°, looking at the house anchor + `look_at`, from the anchor + `from` (metres;
## +x right, +y up, +z toward the field, the farm's own axes). Light: one sun from (-0.55, -1, -0.45), energy 1.1,
## soft ambient 0.55 from a pale sky; ground a flat meadow green. Nothing else of the farm is in the shot.

const FarmArt = preload("res://modules/farm/farm_art.gd")
const OUT := "res://assets/p0/looks/look_lv%d_%s.png"
const SIZE := Vector2i(316, 200)
const CAMERAS := {
	"fence": {"from": Vector3(-3.4, 3.2, 5.6), "look_at": Vector3(-0.6, 0.4, 1.6)},
	"porch": {"from": Vector3(-1.9, 1.9, 4.2), "look_at": Vector3(0.0, 0.7, 1.3)},
	"kitchen_extension": {"from": Vector3(-4.6, 2.6, 3.4), "look_at": Vector3(-1.2, 0.8, -0.4)},
	"master_farmhouse": {"from": Vector3(-2.6, 2.4, 5.2), "look_at": Vector3(0.0, 1.0, 0.0)},
}

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var bp := P0Garden.blueprint()
	var anchor := bp.cell_to_world(P0Garden.ANCHORS.house)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/p0/looks"))
	for stage in P0Logic.look_stages():
		for look in ["a", "b"]:
			var vp := SubViewport.new()
			vp.size = SIZE
			vp.own_world_3d = true
			vp.msaa_3d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			_scene(vp, bp, anchor, str(stage.id), look)
			var cam := Camera3D.new()
			cam.fov = 32.0
			vp.add_child(cam)
			var c: Dictionary = CAMERAS[str(stage.id)]
			cam.look_at_from_position(anchor + c.from, anchor + c.look_at)
			cam.make_current()
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var path := OUT % [int(stage.level), look]
			vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("LOOK_THUMB ", path)
			vp.queue_free()
	quit()

## The house (the Lv10 look at Lv10, else the cottage), the stage's parts and, for Fence & Mailbox, the fence or the
## Stone Wall with the mailbox; lit and grounded.
func _scene(vp: SubViewport, bp: FarmBlueprint, anchor: Vector3, stage: String, look: String) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cfe6f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("e8f0f4")
	env.environment.ambient_light_energy = 0.55
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	vp.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.55, -1.0, -0.45))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("9cc56e")
	green.roughness = 1.0
	ground.material_override = green
	ground.position = anchor + Vector3(0, -0.01, 0)
	vp.add_child(ground)
	vp.add_child(FarmArt.instance(P0Garden.look_house(look if stage == "master_farmhouse" else ""), anchor))
	var parts: Array = []
	if stage == "fence":
		var segs := P0Garden.fence_front(bp) + P0Garden.fence_ring(bp)
		if look == "b": parts = P0Garden.stone_wall(segs)
		else: for s in segs: parts.append({"asset": "fence", "pos": s.pos, "yaw": s.yaw, "scale": Vector3(float(s.stretch), 1, 1)})
		parts.append({"asset": "", "pos": P0Garden.mailbox_point(bp)})
	else:
		parts = P0Garden.look_parts(bp, stage, look)
	for p in parts:
		if str(p.asset) == "":   # the red post box, as the farm shows it
			var box := (load("res://assets/props/mailbox_placeholder/red_post_box.glb") as PackedScene).instantiate() as Node3D
			box.position = p.pos
			box.scale = Vector3.ONE * 0.65
			var mat := StandardMaterial3D.new()   # as p0_farm's _mailbox_prop
			mat.albedo_texture = load("res://assets/props/mailbox_placeholder/room_albedo_ao.png")
			mat.roughness = 0.9
			for mi in box.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).material_override = mat
			vp.add_child(box)
			continue
		var m := FarmArt.instance(str(p.asset))
		m.transform = Transform3D(Basis(Vector3.UP, float(p.yaw)) * Basis.from_scale(p.scale), p.pos)
		vp.add_child(m)

extends SceneTree
## Bake the Bite Board's and the pond card's pond thumbnails (SGODOT-283; 不知火舞's spec on 283, 上官婉儿 on the
## cameras): one PNG per fishing template, assets/p0/ponds/pond_thumb_<pond|river|coast>.png, 144 × 112, from the same
## pond world the game builds (PondScenery + FishingWater on the pond's own template and decoration seed, the pond
## scene's sky, light and sun), so a thumbnail always matches the pond the player walks into. Coast uses the existing
## pond art until its own scene lands (不知火舞's P1 spec); when it does, re-run this with the same cameras:
##
##   godot --path . --script res://tools/dev/pond_thumbs.gd        (needs a window: it renders; not --headless)
##
## Cameras (CAMERAS): perspective, FOV 34°, from `from` looking at `look_at`, in the pond's own metres (+x right, +y up,
## +z toward the bank the player arrives on; every pond template spans about x 2–10, z −13 … −3). Each template is shot
## from the arrival bank, a little high, the water filling the middle of the frame. Light as the pond scene (p0_pond.gd):
## the daylight sky, ambient 0.65, the sun at (−55°, −137°), energy 1.15, soft shadows.

const OUT := "res://assets/p0/ponds/pond_thumb_%s.png"
const SIZE := Vector2i(144, 112)
const FOV := 34.0
## The pond each template is shot at (San Francisco's: Fern Pond is the Pond, Blossom Pond a River, Clover Pond the Coast).
const PONDS := {"pond": "pond_san_francisco_03", "river": "pond_san_francisco_06", "coast": "pond_san_francisco_02"}
const CAMERAS := {
	"pond": {"from": Vector3(6.0, 8.6, 2.6), "look_at": Vector3(6.0, 0.0, -8.2)},
	"river": {"from": Vector3(6.0, 8.6, 2.8), "look_at": Vector3(6.0, 0.0, -7.8)},
	"coast": {"from": Vector3(5.8, 8.6, 2.8), "look_at": Vector3(5.8, 0.0, -7.9)},
}
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/p0/ponds"))
	for site in PONDS:
		var entry: Dictionary = P0Ponds.location(str(PONDS[site]))
		var vp := SubViewport.new()
		vp.size = SIZE
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		_scene(vp, entry)
		var cam := Camera3D.new()
		cam.fov = FOV
		cam.near = 0.05
		cam.far = 80
		vp.add_child(cam)
		var c: Dictionary = CAMERAS[site]
		cam.look_at_from_position(c.from, c.look_at)
		cam.make_current()
		for i in 8: await process_frame   # the water's reflection and caustics settle
		await RenderingServer.frame_post_draw
		var path := OUT % site
		vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("POND_THUMB ", path)
		vp.queue_free()
	quit()

## The pond world as P0Pond builds it: sky and ambient, the sun, the scenery and the water.
func _scene(vp: SubViewport, entry: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = preload("res://assets/ponds/art/pond_daylight_sky.tres")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e4f0ff")
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -137, 0)
	sun.light_color = Color("fff3dc")
	sun.light_energy = 1.15
	sun.light_specular = 0.13
	sun.shadow_enabled = true
	sun.shadow_blur = 3.0
	sun.shadow_opacity = 0.82
	sun.light_angular_distance = 1.0
	sun.directional_shadow_max_distance = 65
	vp.add_child(sun)
	vp.add_child(PondScenery.build(entry))
	var water := FishingWater.build(str(entry.id), SystemPonds.site(entry))
	water.water_material.set_shader_parameter("sun_direction", sun.global_basis.z.normalized())
	vp.add_child(water)

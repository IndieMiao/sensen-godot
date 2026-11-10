extends GdUnitTestSuite
## The farm's way out to the map (SGODOT-443, the user 11-07; q(298); 不知火舞's spec v1.2): its map-pin `Map` prompt
## shows from any distance; a tap on it walks there and the arrival goes to the map; the joystick or a tap elsewhere
## stops the walk; walked into the ring with the joystick it goes only once armed — never armed on coming into the farm,
## only after having been EXIT_ARM_M away (不知火舞 443 603fe5ea).

const STORE := "user://test_p0_farm_exit.json"
const P0Farm := preload("res://scenes/p0/p0_farm.gd")
const FarmCamera := preload("res://modules/farm/farm_camera.gd")

var rt: P0Runtime

func _farm() -> Node3D:
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nvar left := 0\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\nfunc leave_by_exit() -> void: left += 1\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	auto_free(farm)
	farm.rt = rt
	farm.bp = P0Garden.blueprint()
	farm.grid = BlueprintGrid.new(farm.bp)
	farm.cam = Camera3D.new()
	farm.add_child(farm.cam)
	farm.actor = P0Actor.new()
	farm.add_child(farm.actor)
	farm.actor.setup(farm.bp, farm.grid, farm.cam)
	farm._exit = P0Farm.EXIT_AT
	return farm

func _run(farm: Node3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds and farm.left == 0:
		farm.actor.step(1.0 / 30.0)
		farm._exit_check()
		t += 1.0 / 30.0

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func test_its_prompt_is_the_ringed_pin_and_map_and_shows_from_anywhere() -> void:
	var p := P0WorldPrompts.farm_exit(P0Farm.EXIT_ICON)
	assert_str(p.text).is_equal("Map")
	assert_str((p.icon as Texture2D).resource_path).is_equal("res://assets/p0/icons/exit_pin.svg")   # the pin in its ring (q(298))
	assert_int(P0WorldPrompts.show("exit", "", 40.0, p)).is_equal(P0WorldPrompts.Show.ICON)   # past RANGE, still there
	assert_int(P0WorldPrompts.show("exit", "exit", 1.0, p)).is_equal(P0WorldPrompts.Show.BAR)
	assert_int(P0WorldPrompts.show("workbench", "", 40.0, P0WorldPrompts.workbench())).is_equal(P0WorldPrompts.Show.NONE)   # others as before

func test_a_tap_walks_there_and_the_arrival_goes_to_the_map() -> void:
	var farm := _farm()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -4))   # into the farm, 4 m off
	farm.walk_to_exit()
	assert_bool(farm._exit_walk).is_true()
	_run(farm, 6.0)
	assert_int(farm.left).is_equal(1)

func test_the_joystick_or_a_panel_stops_the_walk_where_it_is() -> void:
	var farm := _farm()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -4))
	farm.walk_to_exit()
	for i in 10: farm.actor.step(1.0 / 30.0)
	farm.p0_joystick(Vector2(1, 0))
	assert_bool(farm._exit_walk).is_false()
	farm.p0_joystick(Vector2.ZERO)
	var at: Vector3 = farm.actor.position
	_run(farm, 2.0)
	assert_int(farm.left).is_equal(0)
	assert_float(farm.actor.position.distance_to(at)).is_less(0.3)   # stopped there, not still walking out

func test_landing_and_standing_still_never_leaves() -> void:
	var farm := _farm()
	var spawn: Vector3 = farm.bp.cell_to_world(farm.bp.anchor("spawn"))
	assert_float(P0FarmMaterials.flat(spawn, farm._exit)).is_greater(P0Farm.EXIT_ARM_M)   # 5.4 m: no two steps out (bot 389)
	farm.actor.teleport(spawn)   # back from the map
	_run(farm, 1.0)
	assert_int(farm.left).is_equal(0)

func test_from_the_landing_walking_into_the_ring_leaves_once() -> void:
	var farm := _farm()
	farm.actor.teleport(farm.bp.cell_to_world(farm.bp.anchor("spawn")))
	farm.actor.mover.set_target_position(farm._exit + Vector3(0.1, 0, 0))   # the walk there is the player's own
	_run(farm, 6.0)
	assert_int(farm.left).is_equal(1)
	for v in [Vector2(-1, 0), Vector2(0, 1), Vector2(1, 0)]:   # turning round in the ring: not again
		farm.actor.face(farm.actor.position + Vector3(v.x, 0, v.y))
		farm.actor.mover.set_target_position(farm.actor.position + Vector3(v.x, 0, v.y) * 0.2)
		for i in 6:
			farm.actor.step(1.0 / 30.0)
			farm._exit_check()
	assert_int(farm.left).is_equal(1)

func test_away_past_the_arming_distance_and_back_into_the_ring_leaves() -> void:
	var farm := _farm()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -(P0Farm.EXIT_ARM_M + 0.3)))
	farm._exit_check()
	assert_bool(farm._exit_armed).is_true()
	farm.actor.mover.set_target_position(farm._exit + Vector3(0.1, 0, 0))
	_run(farm, 5.0)
	assert_int(farm.left).is_equal(1)
	var back := _farm()   # out of the farmhouse: not armed however it was
	back._exit_armed = true
	back.resume()
	assert_bool(back._exit_armed).is_false()

func test_the_exit_stands_on_the_farms_walk() -> void:
	var bp := P0Garden.blueprint()
	P0Garden.block_points(bp, P0Garden.fence_block_points(bp))   # the yard fence, as the farm blocks it
	var exit := P0Farm.EXIT_AT
	assert_bool(bp.is_walkable(bp.world_to_cell(exit))).is_true()
	# the ring drawn inside the Lv3 fence ring (C7: its west and front stretches beside it); the cells under its edge are
	# the fence's on the walk grid, the trigger's middle cell is not
	var r := P0Farm.EXIT_RING_R
	var f := P0Garden.FENCE_RING
	assert_float(exit.x - r).is_greater(f.west)
	assert_float(exit.z + r).is_less(f.front)
	var grid := BlueprintGrid.new(bp)
	assert_bool(grid.path(bp.anchor("spawn"), bp.world_to_cell(exit)).is_empty()).is_false()

## 周瑜 on #860: the exit is one of the facilities whose strip opens nearest (its `Map` strip, spec v1.2 §3).
func test_beside_it_its_map_strip_opens() -> void:
	var farm := _farm()
	assert_str(FileAccess.get_file_as_string("res://scenes/p0/p0_farm.gd")).contains("exit_card()]")   # in _card_candidates
	var far := ["mailbox", farm._exit + Vector3(6, 0, -6), P0Farm.SIGN_NEAR]
	assert_str(P0Garden.pick_card([far, farm.exit_card()], farm._exit + Vector3(0.8, 0, 0), "")).is_equal("exit")
	assert_str(P0Garden.pick_card([far, farm.exit_card()], farm._exit + Vector3(4, 0, 0), "")).is_equal("")   # past its reach

## 不知火舞 / 上官婉儿 on 443: 赵云's pin and ring keep their red and yellow — vertex colours, which their glTF materials
## do not read (white in the game) — so both wear the farm art's vertex-colour material.
func test_the_pin_and_its_ring_keep_their_colours() -> void:
	if not ResourceLoader.exists(P0Farm.EXIT_PIECE): return   # the piece not in this build yet
	var farm := _farm()
	farm._exit_piece()
	var meshes: Array = farm.get_node("ExitPin").find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_greater_equal(2)   # the pin and the ring
	for m in meshes:
		var mat := (m as MeshInstance3D).material_override as BaseMaterial3D
		assert_object(mat).override_failure_message(str(m.name)).is_not_null()
		assert_bool(mat.vertex_color_use_as_albedo).override_failure_message(str(m.name)).is_true()

## V4 review C7 (0.3.6): the ring and its trigger clear every bed, the last to open (62, Lv17) too — its edge 0.21 m
## off the trigger — and the drawn ring is inside the trigger.
func test_the_ring_clears_every_bed() -> void:
	var bp := P0Garden.blueprint()
	var half := bp.cell_m * 0.5
	var nearest := INF
	for id in P0Garden.max_plots():
		var c := bp.cell_to_world(P0Garden.cell_of(id))
		var off := Vector2(maxf(0.0, absf(P0Farm.EXIT_AT.x - c.x) - half), maxf(0.0, absf(P0Farm.EXIT_AT.z - c.z) - half))
		nearest = minf(nearest, off.length())
	assert_float(nearest - P0Farm.EXIT_RADIUS_M).is_greater_equal(0.2)
	assert_float(P0Farm.EXIT_RING_R).is_less_equal(P0Farm.EXIT_RADIUS_M)

## C7: the ring drawn EXIT_RING_R round on the ground; the pin as 赵云 made it.
func test_the_ring_is_drawn_smaller_and_the_pin_is_not() -> void:
	if not ResourceLoader.exists(P0Farm.EXIT_PIECE): return
	var farm := _farm()
	farm._exit_piece()
	var piece: Node3D = farm.get_node("ExitPin")
	var ring := piece.find_child(P0Farm.EXIT_RING_NODE, true, false) as MeshInstance3D
	assert_object(ring).is_not_null()
	assert_float(ring.mesh.get_aabb().size.x * 0.5 * ring.scale.x).is_equal_approx(P0Farm.EXIT_RING_R, 0.005)
	assert_float(ring.mesh.get_aabb().size.z * 0.5 * ring.scale.z).is_equal_approx(P0Farm.EXIT_RING_R, 0.005)
	var pin := piece.find_child(P0Farm.EXIT_PIN_NODE, true, false) as Node3D
	assert_vector(pin.scale).is_equal(Vector3.ONE)

## C7: a tap by the exit is the exit's, but on bed 62 beside it (open at Lv17) the bed's, though within EXIT_TAP_PX.
func test_a_tap_on_the_bed_beside_it_is_not_the_exits() -> void:
	var farm := _farm()
	rt.session.view = {"garden": {"plots": P0Garden.max_plots()}}
	farm.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	farm.cam.keep_aspect = Camera3D.KEEP_WIDTH
	farm.cam.size = get_viewport().get_visible_rect().size.x / 30.0   # 30 px a metre: the bed within the exit's 40 px
	farm.cam.current = true
	FarmCamera.place(farm.cam, P0Farm.EXIT_AT + Vector3.UP * 0.7)
	var exit_px: Vector2 = farm.cam.unproject_position(P0Farm.EXIT_AT + P0Farm.EXIT_HIT)
	var bed_px: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(P0Garden.cell_of(62)))
	assert_float(bed_px.distance_to(exit_px)).is_less(P0Farm.EXIT_TAP_PX)
	assert_bool(farm._exit_tapped(exit_px)).is_true()
	assert_bool(farm._exit_tapped(bed_px)).is_false()
	assert_bool(farm._exit_tapped(exit_px + Vector2(P0Farm.EXIT_TAP_PX + 1.0, 0))).is_false()   # past its 40 px

## 不知火舞 on #943: the player within EXIT_FADE_M, the pin fades out (seen behind it); away, back and opaque again; the
## ring never fades.
func test_near_the_exit_its_pin_fades() -> void:
	if not ResourceLoader.exists(P0Farm.EXIT_PIECE): return
	var farm := _farm()
	farm._exit_piece()
	var piece: Node3D = farm.get_node("ExitPin")
	var pin := piece.find_child(P0Farm.EXIT_PIN_NODE, true, false) as MeshInstance3D
	var ring := piece.find_child(P0Farm.EXIT_RING_NODE, true, false) as MeshInstance3D
	var pin_mat := pin.material_override as StandardMaterial3D
	assert_object(ring.material_override).is_not_same(pin_mat)
	farm.actor.teleport(farm._exit + Vector3(0, 0, -0.8))   # behind the pin, outside the trigger
	farm._exit_fade(1.0)
	assert_float(pin_mat.albedo_color.a).is_equal(0.0)   # out (不知火舞 443 d3ff5572: 0.3 read pink on the player)
	assert_int(pin_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_int(pin.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)   # no shadow while faded (上官婉儿)
	assert_int(ring.cast_shadow).is_not_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_float((ring.material_override as StandardMaterial3D).albedo_color.a).is_equal(1.0)
	farm.actor.teleport(farm._exit + Vector3(0, 0, -2.0))
	farm._exit_fade(1.0)
	assert_float(pin_mat.albedo_color.a).is_equal(1.0)
	assert_int(pin_mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert_int(pin.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

## 上官婉儿 443 190fa019: the Lv3 ring's front stretch opens either side of the exit (the ring in the opening, no rail
## across it), the stone wall on the same run; the way in still open, the rest of the front closed.
func test_the_fence_opens_at_the_exit() -> void:
	var bp := P0Garden.blueprint()
	var f := P0Garden.FENCE_RING
	var front := P0Garden.fence_ring(bp).filter(func(seg): return absf(seg.pos.z - f.front) < 0.01)
	var half := P0Garden.FENCE_SEG * 0.5
	for seg in front:
		var lo: float = seg.pos.x - half * seg.stretch
		var hi: float = seg.pos.x + half * seg.stretch
		assert_bool(hi <= P0Farm.EXIT_AT.x - P0Farm.EXIT_RING_R or lo >= P0Farm.EXIT_AT.x + P0Farm.EXIT_RING_R) \
			.override_failure_message("rail %.2f–%.2f across the ring" % [lo, hi]).is_true()
	assert_float(front.map(func(seg): return seg.pos.x).min() - half * front[0].stretch).is_greater_equal(P0Farm.EXIT_AT.x + P0Farm.EXIT_RING_R)   # west of the ring: no rail
	assert_int(P0Garden.stone_wall(front).size()).is_equal(front.size() * P0Garden.STONE_PER_SEG)

## 不知火舞 / 上官婉儿 443: its `Map` strip, open at its mark over the player's head or upper body on screen (any distance),
## rises clear of the head (its bottom EXIT_STRIP_HEAD_PX over the head's top) at once; once it would not be, it eases
## back over EXIT_STRIP_BACK_S.
func _strip_open(farm: Node3D) -> void:
	rt.ui.name_bar("exit", null, "Map", "", farm.cam.unproject_position(farm._exit + P0Farm.EXIT_MARK), true)

func test_its_strip_clears_the_head_and_eases_back() -> void:
	var farm := _farm()
	farm.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	farm.cam.keep_aspect = Camera3D.KEEP_WIDTH
	farm.cam.size = 8.0
	farm.cam.current = true
	FarmCamera.place(farm.cam, P0Farm.EXIT_AT + Vector3.UP * 0.7)
	_strip_open(farm)
	assert_bool(rt.ui.name_bar_rect("exit").has_area()).is_true()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -0.8))   # behind the pin: the strip over the head
	farm._exit_strip_lift(1.0 / 30.0)
	var centre: float = farm.cam.unproject_position(farm._exit + P0Farm.EXIT_MARK).y + farm._exit_lift
	var head: float = farm.actor.screen_box(farm.cam).position.y
	assert_float(farm._exit_lift).is_less(0.0)
	assert_float(centre + UiWorldNameBar._H * 0.5).is_less_equal(head - P0Farm.EXIT_STRIP_HEAD_PX + 0.01)
	var up: float = farm._exit_lift
	farm.actor.teleport(farm._exit + Vector3(0, 0, -1.2))   # past 1 m, still under the strip: still clear
	farm._exit_strip_lift(1.0)
	assert_float(farm._exit_lift).is_less(0.0)
	up = farm._exit_lift
	farm.actor.teleport(farm._exit + Vector3(2.0, 0, 0.0))   # off to its side: easing back, not at once
	farm._exit_strip_lift(P0Farm.EXIT_STRIP_BACK_S * 0.5)
	assert_float(farm._exit_lift).is_greater(up)
	assert_float(farm._exit_lift).is_less(0.0)
	farm._exit_strip_lift(P0Farm.EXIT_STRIP_BACK_S * 0.6)
	assert_float(farm._exit_lift).is_equal(0.0)

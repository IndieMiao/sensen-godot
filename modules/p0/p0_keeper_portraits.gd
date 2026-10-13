extends Node
## Keeper portraits drawn from their look (SGODOT-300): a generated city's keeper (Ezra, Hugo …) has no hand-painted
## art, so the greeting card and the counter's keeper bar draw them from the same look preset their 3D figure wears
## (world.keeper_looks). texture() answers at once with a blank picture that the renderer fills in a few frames later;
## the card and the bar show it as soon as it is drawn (a TextureRect redraws when its texture changes). The four
## hand-painted keepers (Ama, Finn, Mei, Sigrid) keep their art: P0CounterDrawer.keeper_portrait asks here only when no
## file exists. Drawn once per look and use; the most recent CARD_LIMIT cards and HEAD_LIMIT heads are kept (a card is
## ~770 KB, a head ~270 KB: about 12 MB at most, 上官婉儿 on #339), an older one is drawn again when asked for.
##
## The stage is AvatarFocusButton's (one rig in its own SubViewport, orthographic camera, a soft sun and ambient):
##   card  300 × 660, the whole figure, for the greeting card's 100 × 220 portrait;
##   head  264 × 264, the head in a circle, for the keeper bar's 36 px head (2× for sharpness).

const CARD := Vector2i(300, 660)
const HEAD := Vector2i(264, 264)
const TURN := 0.32   # a three-quarter view, as the painted keepers stand
const CARD_SKY := Color("e4f1ee")   # the card's backdrop: the painted cards stand in a scene, never on white
const CARD_LIMIT := 8
const HEAD_LIMIT := 24

static var _cache: Dictionary = {}   # "<look>|card" / "<look>|head" → ImageTexture (blank until drawn), oldest first
static var _queue: Array[Dictionary] = []   # {key, tex}: a texture already handed out is drawn even if evicted meanwhile
static var _host: Node = null
static var drawn := 0   # pictures drawn this session (tests, shots)

var _viewport: SubViewport
var _camera: Camera3D
var _busy := false

## The portrait for a keeper look, or null for no look / an unknown one. The same texture every time it is asked for.
static func texture(look: String, card: bool) -> Texture2D:
	if look == "": return null
	var key := "%s|%s" % [look, "card" if card else "head"]
	if _cache.has(key):
		var hit: ImageTexture = _cache[key]
		_cache.erase(key)   # most recently used last
		_cache[key] = hit
		return hit
	if not _slots(look).size(): return null
	var size := CARD if card else HEAD
	var blank := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)   # transparent until drawn
	var tex := ImageTexture.create_from_image(blank)
	_cache[key] = tex
	_trim(card)
	_queue.append({"key": key, "tex": tex})
	_wake()
	return tex

## Keep the most recent CARD_LIMIT cards / HEAD_LIMIT heads; a card or bar still showing an evicted one keeps it.
static func _trim(card: bool) -> void:
	var suffix := "|card" if card else "|head"
	var mine := _cache.keys().filter(func(k): return str(k).ends_with(suffix))
	while mine.size() > (CARD_LIMIT if card else HEAD_LIMIT): _cache.erase(mine.pop_front())

## How many pictures of a use are kept (tests).
static func kept(card: bool) -> int:
	var suffix := "|card" if card else "|head"
	return _cache.keys().filter(func(k): return str(k).ends_with(suffix)).size()

static func _slots(look: String) -> Dictionary:
	return P0Logic.content().get("world", {}).get("keeper_looks", {}).get(look, {})

## One renderer under the tree root, made the first time a portrait is asked for.
static func _wake() -> void:
	if DisplayServer.get_name() == "headless": return   # no pictures to draw: the blank stays (tests)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	if _host == null or not is_instance_valid(_host):
		_host = load("res://modules/p0/p0_keeper_portraits.gd").new()
		_host.name = "P0KeeperPortraits"
		tree.root.add_child.call_deferred(_host)
	_host.call_deferred("_drain")

func _drain() -> void:
	if _busy or not is_inside_tree(): return
	_busy = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		await _draw(str(job.key), job.tex)
	_busy = false

func _stage(size: Vector2i) -> void:
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.own_world_3d = true
		_viewport.transparent_bg = true
		_viewport.handle_input_locally = false
		_viewport.msaa_3d = Viewport.MSAA_2X
		add_child(_viewport)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_CLEAR_COLOR
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("edf0ff")
		environment.environment.ambient_light_energy = 0.72
		_viewport.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-32, -28, 0)
		sun.light_energy = 0.95
		_viewport.add_child(sun)
		_camera = Camera3D.new()
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.near = 0.02
		_camera.far = 6
		_viewport.add_child(_camera)
		_camera.make_current()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

## The card's picture stands on a soft backdrop; the round head stays clear for the bar's ring.
func _backdrop(card: bool) -> void:
	_viewport.transparent_bg = not card
	var env := (_viewport.get_child(0) as WorldEnvironment).environment
	env.background_mode = Environment.BG_COLOR if card else Environment.BG_CLEAR_COLOR   # clear colour is the engine's grey
	env.background_color = CARD_SKY

func _draw(key: String, tex: ImageTexture) -> void:
	var parts := key.split("|")
	var look := parts[0]
	var card := parts[1] == "card"
	var slots := _slots(look)
	if tex == null or slots.is_empty(): return
	_stage(CARD if card else HEAD)
	_backdrop(card)
	var rig := Avatar.create_rig()
	for child in rig.get_children():   # a still picture: no distance polling
		if child is RigActivity:
			rig.remove_child(child)
			child.free()
	rig.rotation.y = TURN
	_viewport.add_child(rig)
	rig.apply_config(OnlineAppearance.config({"version": 1, "slots": slots}, true))
	while rig.is_busy(): await get_tree().process_frame
	rig.play_motion("idle")
	var animation := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation: animation.pause()
	await get_tree().process_frame
	var bounds := DressingCamera.merged_aabb(rig)
	if card:
		# the whole figure, feet to hat, filling the 100 × 220 portrait as the painted keepers do (a wide hat may touch
		# the sides; the height decides)
		var aspect := float(CARD.x) / float(CARD.y)
		_camera.size = maxf(bounds.size.y * 1.04, bounds.size.x / aspect * 0.92)
		var focus := bounds.get_center() + Vector3.DOWN * 0.01
		_camera.position = focus + Vector3(0, 0.05, 2.4)
		_camera.look_at(focus, Vector3.UP)
	else:
		var head := Vector3(0, 1.15, 0)
		if rig.skeleton:
			var bone := rig.skeleton.find_bone("Head_M")
			if bone >= 0: head = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone).origin
		_camera.size = clampf(bounds.end.y - head.y + 0.55, 0.88, 1.35)
		var focus := head + Vector3.UP * (_camera.size * 0.5 - 0.40)
		_camera.position = focus + Vector3(0, 0.02, 2.4)
		_camera.look_at(focus, Vector3.UP)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var picture := _viewport.get_texture().get_image()
	_viewport.remove_child(rig)
	rig.free()
	if picture == null or picture.is_empty(): return
	if not card: AvatarFocusButton._round_portrait(picture)
	tex.set_image(picture)   # the card / bar showing it redraws
	drawn += 1

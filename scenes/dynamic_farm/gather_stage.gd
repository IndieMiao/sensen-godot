extends Node3D
## C-236: gathering in the 3D scene, per SEN-C-234's approved design (D-558, owner SEN-Q-345) with SEN-C-235's art.
## One object at a time is played by its own gathering scene (Linden, Cobble, flower_20, ...: C-235's "one active target
## scene"), standing where the object's batch instance stood, which is hidden meanwhile; every other object stays in
## its batch. Each hit sways or squashes it, deepens its scar (two stages, `>=` the approved thresholds) and throws chips
## and leaves or shards and sparks; the last one fells the tree away from the gatherer, shatters the rock into four
## pieces or pulls the herb up whole (C-234#50: no root, no leaves left). What comes of it waits for the server
## (`common.reward_gate`): `reward` drops a log or a stone where it fell (a herb is already in the hand), `refuse` puts the
## object back as it was. Sounds (the synthesised set) and haptics play here too; the Energy, the bag, the key and the
## floats are ParcelFarming's. Only art: the walk, collision and the layout never change here.
const Fx = preload("res://modules/dynamic_farm/gather_fx.gd")
const BURSTS = preload("res://assets/dynamic_farm/gathering/GatherBursts.tscn")
## The 3D drop per item (C-235: Timber and Stone; a herb never touches the ground).
const DROPS := {"wood": preload("res://assets/dynamic_farm/gathering/Timber.tscn"),
	"stone": preload("res://assets/dynamic_farm/gathering/Stone.tscn")}
## The approved petal colours (particles.petals), used when the herb's own colour is not known.
const PETAL_PINK := Color("#E59AC8")
## How many sound players may overlap (a chop's thud over the next chop).
const VOICES := 4

## What played, in order ("hit tree 1/3", "fall tree", "drop wood", "refuse tree", ...): QA reads it.
var played := []
## Camera shake and haptics go through these (the scene's; tests leave them empty).
var shake_camera: Callable
## Where the last drop popped (QA).
var drop_at := Vector3.ZERO
var vibrate: Callable = func(ms: int) -> void: Input.vibrate_handheld(ms)

var _target: Node3D
var _anim: AnimationPlayer
var _key := ""
var _kind := ""
var _model := ""
var _rest := Transform3D.IDENTITY
## The batch instance the target stands in for: [MultiMeshInstance3D, index, its transform], or [].
var _hidden := []
## The fall direction (ground plane, away from the gatherer) and where the trunk meets the ground once down.
var _away := Vector3.BACK
var _bursts: Node3D
var _voices: Array[AudioStreamPlayer] = []
var _drop: Node3D
var _petals := PETAL_PINK
## The clip the last hit ended with (fall / shatter / pull / collapse), for `refuse`.
var _final_clip := ""

func _ready() -> void:
	_bursts = BURSTS.instantiate() as Node3D
	_bursts.name = "GatherBursts"
	add_child(_bursts)
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		add_child(voice)
		_voices.append(voice)

func key() -> String:
	return _key

func active() -> bool:
	return _target != null

## Stands the gathering scene of `model` in for one object. `rest`: the object's placement (scale and yaw are kept);
## `drawn`: [its batch, its instance] (hidden meanwhile); `from`: the gatherer, a tree falls away from them. `tint`:
## the batch's per-instance colour (the autumn trees), `plant`: a herb's or weed's recoloured batch mesh, `bloom`: its
## petal colour. The same key again keeps the scene as it is (its scar and all). False when the model has no scene.
func focus(key_: String, model: String, kind_: String, rest: Transform3D, drawn: Array, from: Vector3,
		tint := Color.WHITE, plant: Mesh = null, bloom := PETAL_PINK) -> bool:
	if key_ == _key and _target != null: return true
	release()
	var packed := Fx.scene_of(model)
	if packed == null: return false
	_key = key_
	_kind = kind_
	_model = model
	_rest = rest
	_petals = bloom
	_target = packed.instantiate() as Node3D
	_target.name = "GatherTarget"
	_anim = _target.get_node_or_null("AnimationPlayer") as AnimationPlayer
	add_child(_target)
	var away := rest.origin - from
	away.y = 0.0
	_away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	if _kind == "tree":
		# C-235: local +Z falls away from the gatherer; the stump and crown keep the placed yaw, the scar faces the gatherer.
		var heading := atan2(_away.x, _away.z)
		var rest_yaw := atan2(rest.basis.z.x, rest.basis.z.z)
		_target.transform = Transform3D(Basis(Vector3.UP, heading).scaled(rest.basis.get_scale()), rest.origin)
		var art := _art()
		if art != null:
			var turn := Basis(Vector3.UP, rest_yaw - heading)
			for part: Node3D in [art.get_node_or_null("Stump"), art.get_node_or_null("CrownPivot/Crown")]:
				if part != null: part.basis = turn * part.basis
	else:
		_target.transform = rest
	_paint(tint, plant)
	_play("reset")
	if drawn.size() >= 2 and is_instance_valid(drawn[0]):
		var batch: MultiMeshInstance3D = drawn[0]
		var i: int = drawn[1]
		if i < batch.multimesh.instance_count:
			_hidden = [batch, i, batch.multimesh.get_instance_transform(i)]
			batch.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), rest.origin))
	played.append("focus %s %s" % [_kind, model])
	return true

## Back to the batch: the target goes, its instance shows again (unless `keep_hidden`: it is gone or drawn otherwise now).
func release(keep_hidden := false) -> void:
	if not _hidden.is_empty() and is_instance_valid(_hidden[0]) and not keep_hidden:
		var batch: MultiMeshInstance3D = _hidden[0]
		if int(_hidden[1]) < batch.multimesh.instance_count: batch.multimesh.set_instance_transform(_hidden[1], _hidden[2])
	_hidden = []
	if _target != null:
		_target.queue_free()
		_target = null
	_anim = null
	_key = ""
	_final_clip = ""

## A hit that does not finish the object (`done` of `hits`): its scar, its sway or squash, chips and leaves or shards
## and sparks, its sound and a light buzz.
func strike(done: int, hits: int) -> void:
	if _target == null: return
	var stage := Fx.stage(_kind, done, hits)
	if _anim != null and _anim.has_animation("stage_%d" % stage):
		_play("stage_%d" % stage)
	if _kind == "rock": _set_param(&"fracture_stage", stage)
	_play("hit")
	var hit: Dictionary = Fx.kind(_kind).get("hit", {})
	match _kind:
		"tree", "bush":
			_burst("Chips", _contact(), int(hit.get("chips", 4)))
			_burst("Leaves", _crown(), int(hit.get("leaves", 3)))
		"rock":
			_burst("Shards", _contact(), int(hit.get("shards", 5)))
			_burst("Sparks", _contact(), int(hit.get("sparks", 2)))
	_sound(str(Fx.kind(_kind).get("sfx", {}).get("hit", "")))
	_buzz(int(Fx.common().get("haptic_hit_ms", 12)))
	played.append("hit %s %d/%d stage %d" % [_kind, done, hits, stage])

## A pull's first part (the herb or weed is gripped and stretched as the gatherer leans back): starts with the swing.
func begin_pull() -> void:
	if _target == null or not _kind in ["flower", "weed"]: return
	_play("pull")
	_final_clip = "pull"
	_sound(str(Fx.kind(_kind).get("sfx", {}).get("hit", "rustle")))
	played.append("pull %s" % _kind)

## The last hit. Returns how long after it the reward may show at the earliest (the approved "picture time"; the
## reply may come later): a tree once it lies on the ground, a rock once its pieces have flown, a herb at the pop.
func finish(reduced: bool) -> float:
	if _target == null: return 0.0
	var k := Fx.kind(_kind)
	var sfx: Dictionary = k.get("sfx", {})
	_sound(str(sfx.get("final", "")))
	var final_ms := int(k.get("haptic_final_ms", Fx.common().get("haptic_final_ms", 30)))
	_buzz(final_ms)
	var scale := 0.5 if reduced else 1.0
	played.append("finish %s" % _kind)
	match _kind:
		"tree":
			var fall: Dictionary = k.get("fall", {})
			_final_clip = "reduced_fall" if reduced else "fall"
			_play(_final_clip)
			if reduced: return 0.3
			var land := (float(fall.get("crack_delay", 120)) + float(fall.get("tilt_ms", 760))) / 1000.0
			get_tree().create_timer(land).timeout.connect(_landed.bind(_key, scale))
			# The log pops a beat after the thud, never before it.
			return land + 0.05
		"rock":
			_final_clip = "shatter"
			_play("shatter")
			_burst("Dust", _rest.origin + Vector3(0, 0.1, 0), int(float(k.get("fall", {}).get("dust", 8)) * scale))
			return float(k.get("fall", {}).get("chunk_ms", 420)) / 1000.0
		"bush":
			_final_clip = "collapse"
			_play("collapse")
			_burst("Leaves", _crown(), int(float(k.get("fall", {}).get("leaves", 8)) * scale))
			_burst("Dust", _rest.origin + Vector3(0, 0.05, 0), int(float(k.get("fall", {}).get("dust", 4)) * scale))
			return float(k.get("fall", {}).get("shrink_ms", 300)) / 1000.0
		_:
			# The herb or weed comes out whole at the pop (pull's 0.6 s, the swing's contact): petals or clippings.
			if _kind == "flower":
				_tint_petals(_petals)
				_burst("Petals", _rest.origin + Vector3(0, 0.3, 0), int(float(k.get("hit", {}).get("petals", 7)) * scale))
			else: _burst("Clippings", _rest.origin + Vector3(0, 0.15, 0), int(float(k.get("hit", {}).get("clippings", 6)) * scale))
			var pop := float(k.get("drop", {}).get("ui_pop_at", 700)) - Fx.contact_s(_kind) * 1000.0
			return maxf(pop, 0.0) / 1000.0

## The tree hits the ground (unless another object took over): its thud, dust and leaves along the trunk outside the
## crown (V-723), the camera's small shake.
func _landed(at_key: String, scale: float) -> void:
	if at_key != _key or _target == null: return
	var fall: Dictionary = Fx.kind("tree").get("fall", {})
	_sound(str(Fx.kind("tree").get("sfx", {}).get("land", "")))
	_burst("Dust", trunk_point(0.55), int(float(fall.get("dust", 10)) * scale))
	_burst("Leaves", trunk_point(0.85), int(float(fall.get("leaves", 12)) * scale))
	if shake_camera.is_valid(): shake_camera.call(float(fall.get("camera_shake_m", 0.05)), float(fall.get("camera_shake_ms", 180)))
	played.append("landed tree")

## A point along the fallen trunk on the ground, `along` from the stump (0) to where the crown begins (1).
func trunk_point(along: float) -> Vector3:
	var reach := _crown_start() * along
	return _rest.origin + _away * reach + Vector3(0, 0.08, 0)

## V-774: where the log pops along the fallen trunk, seen from the default view. The trunk falls about the stump's top,
## so it lies at the stump's height; the log comes off it on the camera's side, part way along, at half that height, so
## the stump, the trunk and its branches never stand between it and the camera (the player usually stands on that side).
func log_point() -> Vector3:
	var art := _art()
	var pivot := art.get_node_or_null("CrownPivot") as Node3D if art != null else null
	var scale := _rest.basis.get_scale().y
	var height := (pivot.position.y if pivot != null else 0.7) * scale * 0.5
	var at := _rest.origin + _away * _crown_start() * 0.4 + Vector3(0, height, 0)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		var to_camera := camera.global_position - at
		to_camera.y = 0.0
		var side := to_camera - _away * to_camera.dot(_away)
		at += (side.normalized() if side.length() > 0.001 else -_away) * 0.5 * scale
	return at

## What the object gave, once the server said so: a log along the fallen trunk or the stone from the pieces pops up;
## the caller pulls it to the player (`pull_drop`). Null for a herb (already in the hand) or an item without a drop.
func reward(item: String) -> Node3D:
	played.append("drop %s" % item)
	if not DROPS.has(item) or _target == null: return null
	_drop = DROPS[item].instantiate() as Node3D
	_drop.name = "GatherDrop"
	add_child(_drop)
	var at := log_point() if _kind == "tree" else _rest.origin + _away * 0.35 + Vector3(0, 0.02, 0)
	_drop.position = at
	drop_at = at
	_drop.rotation.y = atan2(_away.x, _away.z) + PI * 0.5
	var player := _drop.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation("pop"): player.play("pop")
	return _drop

## The popped drop flies into the player (`pickup.magnet_ms`, quad-in) and is gone; `item_pickup` plays as it arrives.
func pull_drop(to: Callable) -> void:
	var drop := _drop
	_drop = null
	if drop == null: return
	var from := drop.position
	var ms := float(Fx.config().get("pickup", {}).get("magnet_ms", 320))
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(k: float):
		if is_instance_valid(drop): drop.position = from.lerp(to.call(), k)
		, 0.0, 1.0, UiMotion.secs(ms))
	tw.tween_callback(func():
		if is_instance_valid(drop): drop.queue_free()
		_sound(str(Fx.config().get("pickup", {}).get("sfx", "item_pickup"))))

## The pickup sound alone (a herb: from the hand into the bag).
func picked_up() -> void:
	_sound(str(Fx.config().get("pickup", {}).get("sfx", "item_pickup")))

## The server refused the last hit (rare: Energy spent elsewhere, the object regrowing): the tree stands back up and
## its scar closes, the pieces fly back together, the herb drops back into place (approved `refuse` timings).
func refuse() -> void:
	played.append("refuse %s" % _kind)
	if _target == null or _anim == null: return
	if _final_clip == "pull" or _kind in ["flower", "weed"]:
		_target.visible = true
		_play("settle")
		return
	if _final_clip.is_empty() or not _anim.has_animation(_final_clip):
		_play("reset")
		return
	var clip := _final_clip
	var at := _anim.current_animation_position if _anim.current_animation == clip else _anim.get_animation(clip).length
	_anim.pause()
	var ms := float(Fx.common().get("refuse_rewind_ms", 300))
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if _anim != null and _anim.has_animation(clip):
			_anim.play(clip)
			_anim.seek(t, true)
			_anim.pause()
		, at, 0.0, UiMotion.secs(ms))
	tw.tween_callback(func():
		_play("reset")
		_set_param(&"fracture_stage", 0))

## Fades the whole target out (a cleared yard obstacle leaves nothing: no stump, no scree), then lets it go.
func vanish() -> void:
	if _target == null:
		release(true)
		return
	var target := _target
	_hidden = []
	_target = null
	_anim = null
	_key = ""
	var tw := create_tween()
	tw.tween_method(func(c: float):
		if is_instance_valid(target):
			for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
				var m := mesh.material_override as ShaderMaterial
				if m != null: m.set_shader_parameter(&"coverage", c)
				elif c <= 0.0: mesh.visible = false
		, 1.0, 0.0, UiMotion.secs(300.0))
	tw.tween_callback(func(): if is_instance_valid(target): target.queue_free())

## The stump and scree meshes a spent tree or rock leaves (the outer regrow state), by model: {mesh, material} or {}.
static func spent_piece(model: String) -> Dictionary:
	if not _spent_cache.has(model):
		_spent_cache[model] = {}
		var packed := Fx.scene_of(model)
		if packed != null:
			var node := packed.instantiate()
			for name in ["Stump", "Scree"]:
				var found := node.find_child(name, true, false) as MeshInstance3D
				if found != null:
					_spent_cache[model] = {"mesh": found.mesh, "material": found.material_override}
					break
			node.free()
	return _spent_cache[model]

static var _spent_cache := {}

func _art() -> Node3D:
	if _target == null: return null
	var art := _target.get_node_or_null("Art") as Node3D
	return art.get_child(0) as Node3D if art != null and art.get_child_count() > 0 else null

## Where a tool meets the object: the trunk at waist height on the gatherer's side, the rock's upper front.
func _contact() -> Vector3:
	var art := _art()
	if _kind == "tree" and art != null:
		var pivot := art.get_node_or_null("CrownPivot") as Node3D
		var y := (pivot.position.y if pivot != null else 0.6) * _rest.basis.get_scale().y
		return _rest.origin - _away * 0.18 + Vector3(0, y * 0.85, 0)
	var box := _box()
	return _rest.origin - _away * box.size.x * 0.35 + Vector3(0, box.size.y * 0.7, 0)

## The middle of the crown (leaves fall from it).
func _crown() -> Vector3:
	var art := _art()
	var crown := art.get_node_or_null("CrownPivot/Crown") as MeshInstance3D if art != null else null
	if crown != null: return crown.global_transform * crown.get_aabb().get_center()
	return _rest.origin + Vector3(0, _box().size.y * 0.6, 0)

## Ground distance from the stump to where the crown begins once the tree lies down.
func _crown_start() -> float:
	var art := _art()
	var pivot := art.get_node_or_null("CrownPivot") as Node3D if art != null else null
	var crown := art.get_node_or_null("CrownPivot/Crown") as MeshInstance3D if art != null else null
	var y := (pivot.position.y if pivot != null else 0.7) + (crown.get_aabb().position.y if crown != null else 0.3)
	return y * _rest.basis.get_scale().y + 0.25

func _box() -> AABB:
	var box := AABB()
	var first := true
	if _target == null: return AABB(Vector3.ZERO, Vector3.ONE * 0.5)
	for mesh: MeshInstance3D in _target.find_children("*", "MeshInstance3D", true, false):
		var b := mesh.transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return Transform3D(_rest.basis, Vector3.ZERO) * box

## The batch's colour on the target: a tree's per-instance tint on its pigment, a plant's recoloured mesh as is.
func _paint(tint: Color, plant: Mesh) -> void:
	# `pigment` is a source_color: the renderer takes it as sRGB and makes it linear, while the batch multiplied the
	# same tint in as it is; handing it over sRGB-encoded gives the batch's colour back.
	_set_param(&"pigment", tint.linear_to_srgb())
	if plant != null:
		for mesh: MeshInstance3D in _target.find_children("pg_*", "MeshInstance3D", true, false): mesh.mesh = plant

func _set_param(name: StringName, value: Variant) -> void:
	if _target == null: return
	var done := {}
	for mesh: MeshInstance3D in _target.find_children("*", "MeshInstance3D", true, false):
		var m := mesh.material_override as ShaderMaterial
		if m != null and not done.has(m):
			m.set_shader_parameter(name, value)
			done[m] = true

func _play(clip: String) -> void:
	if _anim == null or not _anim.has_animation(clip): return
	_anim.stop()
	_anim.play(clip)
	_anim.advance(0)

## Moves one of the bank's emitters there and fires `count` (C-235: one bank for the whole presentation).
func _burst(emitter: String, at: Vector3, count: int) -> void:
	var node := _bursts.get_node_or_null(emitter) as GPUParticles3D if _bursts != null else null
	if node == null or count <= 0: return
	node.global_position = at
	if node.amount != count: node.amount = count
	node.restart()
	node.emitting = true

## V-723: petals take the picked herb's own colour (the daisy white, the cream), not always the drawn pink: the card's
## texture is pink, so its colour is scaled channel by channel toward the herb's.
func _tint_petals(bloom: Color) -> void:
	var node := _bursts.get_node_or_null("Petals") as GPUParticles3D if _bursts != null else null
	if node == null or not node.draw_pass_1 is QuadMesh: return
	var card := node.draw_pass_1 as QuadMesh
	var ink := card.material as StandardMaterial3D
	if ink == null: return
	if not card.resource_local_to_scene:
		card = card.duplicate(true) as QuadMesh
		node.draw_pass_1 = card
		ink = card.material as StandardMaterial3D
	ink.albedo_color = Color(bloom.r / PETAL_PINK.r, bloom.g / PETAL_PINK.g, bloom.b / PETAL_PINK.b, 1.0)

func _sound(name: String) -> void:
	if name.is_empty() or _voices.is_empty(): return
	var stream := Fx.sound(name)
	if stream == null: return
	var voice := _voices[0]
	for v in _voices:
		if not v.playing:
			voice = v
			break
	var jitter := float(Fx.common().get("sfx_pitch_jitter", 0.06))
	voice.stream = stream
	voice.volume_db = float(Fx.common().get("sfx_volume_db", -6.0))
	voice.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	voice.play()
	played.append("sound " + name)

func _buzz(ms: int) -> void:
	if ms > 0 and vibrate.is_valid(): vibrate.call(ms)

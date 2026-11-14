extends Node3D
## All 299 remote players remain visible. Eight nearby rigs animate; the rest use instanced silhouettes.

const DETAIL_LIMIT := 8
## The P0 outposts' "sit" action (appended after OnlineSpace.ACTIONS by the P0 server, SGODOT-227).
const SIT_ACTION := 15
## Name tags show "HP / max" in combat spaces; the P0 outposts have no health.
var show_health := true
## Optional (id) -> float: ground height of a member (P0 outposts lift seated players onto their seat).
var height_of := Callable()
var actors: Dictionary = {}
## Peer ids speaking now (P0 voice, SGODOT-383 §3): their name tag goes primary green while they do.
var speaking: Dictionary = {}
const SPEAKING_COLOR := Color("3E7D43")   # UiTokens.COLOR_PRIMARY
var rigs: Array[Dictionary] = []
var bodies: MultiMeshInstance3D
var heads: MultiMeshInstance3D
var gestures: MultiMeshInstance3D
var _time := 0.0
var _selection_at := 0.0

func _ready() -> void:
	var body := CapsuleMesh.new()
	body.radius = .18
	body.height = .8
	body.radial_segments = 8
	body.rings = 2
	bodies = _instances(body, Color("779fc5"))
	var head := SphereMesh.new()
	head.radius = .17
	head.height = .34
	head.radial_segments = 8
	head.rings = 4
	heads = _instances(head, Color("edd4b9"))
	var gesture := BoxMesh.new()
	gesture.size = Vector3(.06, .06, .65)
	gestures = _instances(gesture, Color("e8d49e"))

func _instances(mesh: Mesh, color: Color) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	mesh.surface_set_material(0, material)
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = true
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = 300
	node.multimesh.visible_instance_count = 0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func clear() -> void:
	actors.clear()
	for entry in rigs:
		_stop_fishing(entry)
		entry.id = -1
		entry.root.hide()
	if bodies: bodies.multimesh.visible_instance_count = 0
	if heads: heads.multimesh.visible_instance_count = 0
	if gestures: gestures.multimesh.visible_instance_count = 0

## The name over a member's head (SGODOT-491; spec v1.1 §4): the name they chose (the roster's `name`, P0 accounts) —
## never translated, cut with `…` past the widest default name's width as drawn (`Traveller wwww`) — else the default
## `Traveller 8c3f`, which translates as before.
const P0Names := preload("res://modules/p0/p0_names.gd")
static func tag_text(member: Dictionary, label: Label3D) -> String:
	var chosen := str(member.get("name", "")).strip_edges()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if chosen != "" else Node.AUTO_TRANSLATE_MODE_INHERIT
	if chosen == "": return L10n.format_text("Traveller %s", str(member.get("player", "")).substr(0, 4))
	return P0Names.fit(chosen, label.font, label.font_size, P0Names.tag_width(label.font, label.font_size))

func roster(members: Dictionary) -> void:
	for id in actors.keys():
		if not members.has(id):
			for entry in rigs:
				if entry.id == id: _stop_fishing(entry)
			actors.erase(id)
	for id in members:
		if not actors.has(id): actors[id] = {"member": members[id], "ready": false, "position": Vector3.ZERO,
			"from": Vector3.ZERO, "target": Vector3.ZERO, "at": 0.0, "duration": .1, "yaw": 0.0,
			"hp": 0, "max_hp": 1, "action": 0, "serial": 0, "gesture_until": 0.0}
		else: actors[id].member = members[id]
		var config := OnlineAppearance.config(members[id].get("appearance"))
		actors[id].config = config
		actors[id].outfit_key = str(members[id].player) + config.to_json_text()
	_selection_at = 0

func fishing_snapshot(states: Array) -> void:
	for actor in actors.values(): actor.fishing = {}
	for state in states:
		var id := int(state.get("id", -1))
		if actors.has(id):
			actors[id].fishing = state
			actors[id].fishing_at = _time

func _stop_fishing(entry: Dictionary) -> void:
	if is_instance_valid(entry.get("fishing_view")): entry.fishing_view.finish()
	entry.fishing_view = null
	entry.animation = ""

func sample(id: int, state: Dictionary) -> void:
	if not actors.has(id): return
	var actor: Dictionary = actors[id]
	actor.duration = clampf(_time - float(actor.at), .08, .5)
	actor.from = actor.position if actor.ready else state.position
	actor.target = state.position
	actor.at = _time
	actor.ready = true
	actor.yaw = state.yaw
	actor.hp = state.hp
	actor.max_hp = state.max_hp
	actor.action = state.action
	if int(actor.serial) != int(state.serial): actor.gesture_until = _time + .3
	actor.serial = state.serial

func step(delta: float, local_position: Vector3) -> void:
	_time += delta
	if _time >= _selection_at:
		_selection_at = _time + .5
		_select_rigs(local_position)
	var detailed := {}
	for entry in rigs:
		if actors.has(entry.id) and not entry.rig.is_busy(): detailed[entry.id] = entry
		else:
			_stop_fishing(entry)
			entry.root.hide()
	var simple := 0
	var gesture_count := 0
	for id in actors:
		var actor: Dictionary = actors[id]
		if not actor.ready: continue
		actor.position = (actor.from as Vector3).lerp(actor.target, clampf((_time - float(actor.at)) / float(actor.duration), 0, 1))
		var point: Vector3 = actor.position
		if height_of.is_valid(): point.y = float(height_of.call(id))
		var work := int(actor.action) in [3, 4, 5, 6, 7, 10, 11, 12]
		var wave := int(actor.action) == 8
		var fishing: Dictionary = actor.get("fishing", {}) if _time - float(actor.get("fishing_at", 0)) < 1.0 else {}
		var fishing_action := int(actor.action) in [13, 14]
		var attacking := _time < float(actor.gesture_until)
		if detailed.has(id):
			var entry: Dictionary = detailed[id]
			entry.root.show()
			entry.rig.show()
			entry.root.position = point
			if not fishing.is_empty():
				if is_instance_valid(entry.get("fishing_view")) and int(entry.fishing_view.remote_state.get("sequence", -1)) != int(fishing.sequence): _stop_fishing(entry)
				if not is_instance_valid(entry.get("fishing_view")):
					entry.fishing_view = FishingPresentation.new()
					add_child(entry.fishing_view)
					entry.fishing_view.configure_remote(fishing, entry.root, entry.rig, get_viewport().get_camera_3d())
				else: entry.fishing_view.remote_state = fishing
			else:
				if is_instance_valid(entry.get("fishing_view")): _stop_fishing(entry)
				entry.rig.rotation.y = float(actor.yaw)
			var animation := str(OnlineSpace.ACTIONS[mini(int(actor.action), OnlineSpace.ACTIONS.size() - 1)])
			if animation == "mine": animation = "labour_drain"
			if animation == "attack": animation = "labour_harvest"
			if fishing_action: animation = "idle"
			if int(actor.action) == SIT_ACTION: animation = "sit_idle"
			if fishing.is_empty() and animation != entry.animation:
				entry.animation = animation
				entry.rig.play_motion(animation)
			entry.label.text = tag_text(actor.member, entry.label) + ("\n%d / %d" % [int(actor.hp), int(actor.max_hp)] if show_health else "")
			entry.label.modulate = SPEAKING_COLOR if speaking.has(id) else Color.WHITE
			entry.label.outline_modulate = Color.WHITE if speaking.has(id) else Color.BLACK   # green on light, as 383 V1 reads
		else:
			var basis := Basis(Vector3.UP, float(actor.yaw))
			if work: basis = basis.rotated(Vector3.RIGHT, sin(_time * 5) * .25)
			var bob := absf(sin(_time * 9 + id)) * .025 if int(actor.action) in [1, 2] else 0.0
			bodies.multimesh.set_instance_transform(simple, Transform3D(basis, point + Vector3(0, .55 + bob, 0)))
			heads.multimesh.set_instance_transform(simple, Transform3D(Basis.IDENTITY, point + Vector3(0, 1.12 + bob, 0)))
			var tint := Color.from_hsv(fmod(float(id) * .618, 1.0), .28, .95)
			bodies.multimesh.set_instance_color(simple, tint)
			simple += 1
		if attacking or work or wave or (fishing_action and not detailed.has(id)):
			var yaw := float(actor.yaw) + (0.0 if fishing_action else sin(_time * (18 if attacking else 6)) * .8)
			gestures.multimesh.set_instance_transform(gesture_count,
				Transform3D(Basis(Vector3.UP, yaw), point + Vector3(sin(yaw) * .45, 1.0 if wave else .7, cos(yaw) * .45)))
			gesture_count += 1
	bodies.multimesh.visible_instance_count = simple
	heads.multimesh.visible_instance_count = simple
	gestures.multimesh.visible_instance_count = gesture_count

func _select_rigs(local_position: Vector3) -> void:
	var ids := actors.keys().filter(func(id): return bool(actors[id].ready))
	ids.sort_custom(func(a, b): return (actors[a].target as Vector3).distance_squared_to(local_position) < (actors[b].target as Vector3).distance_squared_to(local_position))
	ids = ids.slice(0, DETAIL_LIMIT)
	for entry in rigs:
		if not ids.has(entry.id):
			_stop_fishing(entry)
			entry.id = -1
	for id in ids:
		var existing := rigs.filter(func(entry): return entry.id == id)
		if not existing.is_empty():
			_apply_appearance(existing[0], id)
			continue
		var found: Dictionary = {}
		for entry in rigs:
			if entry.id == -1:
				found = entry
				break
		if found.is_empty():
			# Assemble at most one new rig per selection interval to bound a crowded entry spike.
			if rigs.size() >= DETAIL_LIMIT: break
			found = _new_rig()
			rigs.append(found)
			_apply_appearance(found, id)
			break
		_apply_appearance(found, id)

func _apply_appearance(entry: Dictionary, id: int) -> void:
	entry.id = id
	var actor: Dictionary = actors[id]
	if entry.outfit_key == actor.outfit_key: return
	_stop_fishing(entry)
	entry.outfit_key = actor.outfit_key
	entry.animation = ""
	entry.root.hide()
	entry.rig.hide()
	entry.rig.apply_config(actor.config)

func _new_rig() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var rig := Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 45
			child.sleep_distance = 65
	root.add_child(rig)
	var label := Label3D.new()
	label.font = GameUi.theme().default_font
	label.font_size = 28
	label.pixel_size = .006
	label.position.y = 1.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	return {"id": -1, "root": root, "rig": rig, "label": label, "animation": "", "outfit_key": ""}

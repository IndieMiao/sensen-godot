extends Node3D
## SGODOT-341 / q(222): the existing Pip look beside the first bed, driven only by the resolved server view.
## No new collider, automatic dialogue, task state or inventory mutation. Loaded explicitly (no editor import).

const NPCS := "res://assets/p0/outpost_npcs.json"
const PIP := "res_pip"
const TAG := "farm:guide_pip"
const WATER_TAG := "farm:guide_water:"
const STAND := Vector2i(5, 1)   # front/left of the first bed, between teaching plots 0/1; clear of Reed Bank's badge

var farm: Node3D
var pip_root: Node3D
var rig: AvatarRig
var _waved := false
var _wave_left := 0.0
var _highlights := {}
var _water_badges := {}

func setup(host: Node3D) -> Node3D:
	farm = host
	return self

func frame(view: Dictionary, dt: float) -> void:
	var info := P0Guide.pip(view)
	var here := bool(info.get("here", false))
	if here and pip_root == null: _spawn()
	if pip_root != null:
		# If the guide ends while the player stands here, keep the model until leave(); all guidance stops now.
		var head: Vector2 = farm.cam.unproject_position(pip_root.to_global(Vector3(0, 2.0, 0)))
		var visible_head: bool = not farm.cam.is_position_behind(pip_root.global_position) and farm.get_viewport().get_visible_rect().has_point(head)
		var talking: bool = farm.rt.ui.speaker() == PIP
		var near: bool = P0FarmMaterials.flat(farm.actor.position, pip_root.position) < 2.6
		farm.rt.ui.npc_tag(TAG, "Pip", head, visible_head, near, talking,
			UiStatusBadge.State.REQUEST if here and bool(info.get("bang", false)) else -1)
		if _wave_left > 0.0:
			_wave_left -= dt
			if _wave_left <= 0.0: rig.play_motion("idle")
		if here and visible_head and not farm.rt.ui.has_modal() and not _waved and not rig.is_busy():
			_waved = true
			var player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if player != null and player.has_animation("emote_wave"):
				rig.play_motion("emote_wave")
				_wave_left = player.get_animation("emote_wave").length
	_highlight(view)
	_water_marks(view)

func _spawn() -> void:
	var def: Dictionary = P0RoomAnchors.read_json(NPCS).get("npcs", {}).get(PIP, {})
	if def.is_empty(): return
	pip_root = Node3D.new()
	pip_root.name = "GuidePip"
	pip_root.position = farm.bp.cell_to_world(STAND)
	pip_root.scale = Vector3.ONE * float(def.get("scale", 0.88))
	add_child(pip_root)
	pip_root.look_at(Vector3(farm.actor.global_position.x, pip_root.global_position.y, farm.actor.global_position.z), Vector3.UP)
	rig = Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rig.rotation.y = PI   # the reused rig faces +Z, while look_at points -Z at the player
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	pip_root.add_child(rig)
	rig.config_applied.connect(func(_c): rig.play_motion("idle"))
	rig.apply_config(OnlineAppearance.config({"version": 1, "slots": def.get("slots", {})}, true))

func _highlight(view: Dictionary) -> void:
	var ids := P0Guide.teaching_plots(view)
	for id in ids:
		if not _highlights.has(id):
			var outline: MeshInstance3D = farm._bed_highlight()
			outline.position = farm.bp.cell_to_world(P0Garden.cell_of(id)) + Vector3(0, P0Garden.BED_H + 0.013, 0)
			add_child(outline)
			_highlights[id] = outline
	for id in _highlights:
		var highlighted: bool = view.get("plots", []).any(func(p): return int(p.get("id", -1)) == int(id) and str(p.get("state", "")) in ["tilled", "ready"])
		_highlights[id].visible = ids.has(id) and highlighted and not farm.rt.ui.has_modal() and not farm.rt.ui.placing()
	# The ordinary near-bed outline must not introduce a third teaching highlight; actions stay enabled everywhere.
	if not ids.is_empty() and str(view.get("guide", {}).get("step", "")) == "t_sow_quick": farm._hi.visible = false

## Sown teaching beds need water, not another sow outline (340 S3). Read the actual plot state and server targets;
## never infer a target from the step name or keep a drop after a confirmed watering. Display-only kit badges.
func _water_marks(view: Dictionary) -> void:
	var wanted := {}
	if not farm.rt.ui.has_modal() and not farm.rt.ui.placing():
		var ids := P0Guide.teaching_plots(view)
		for plot in view.get("plots", []):
			var id := int(plot.get("id", -1))
			if not ids.has(id) or str(plot.get("state", "")) != "sown": continue
			var at: Vector3 = farm.bp.cell_to_world(P0Garden.cell_of(id)) + Vector3(0, P0Garden.BED_H + 0.6, 0)
			if farm.cam.is_position_behind(at): continue
			wanted[id] = true
			_water_badges[id] = true
			farm.rt.ui.badge(WATER_TAG + str(id), UiStatusBadge.State.AVAILABLE,
				farm.cam.unproject_position(at), true, "", P0Logic.icon("water"))
			_water_clear_of_pip(id)
	for id in _water_badges:
		if not wanted.has(id): farm.rt.ui.badge(WATER_TAG + str(id), UiStatusBadge.State.AVAILABLE, Vector2.ZERO, false)

## Pip stands beside the first teaching bed. Keep its droplet fully readable without moving his locked name tag;
## prefer just above the tag, or below it at the top edge of the world band. Neither mark takes the other's input.
func _water_clear_of_pip(id: int) -> void:
	var badge: UiStatusBadge = farm.rt.ui._badges.get(WATER_TAG + str(id))
	var tag: Control = farm.rt.ui._npc_tags.get(TAG)
	if badge == null or not badge.visible or tag == null or not tag.visible: return
	var rect := badge.get_global_rect()
	var name_rect := tag.get_global_rect()
	if not rect.intersects(name_rect): return
	var area: Rect2 = farm.rt.ui._marker_area()
	var above := name_rect.position.y - rect.size.y - UiTokens.SPACE_WITHIN
	var below := name_rect.end.y + UiTokens.SPACE_WITHIN
	if above >= area.position.y:
		badge.global_position.y = above
	elif below + rect.size.y <= area.end.y:
		badge.global_position.y = below
	else:
		badge.hide()   # no clear world space, as for an anchor outside the viewport

func tap(screen: Vector2, card: String) -> bool:
	if pip_root == null or farm.rt.ui.has_modal(): return false
	if farm.cam.is_position_behind(pip_root.global_position): return false
	var at: Vector2 = farm.cam.unproject_position(pip_root.to_global(Vector3(0, 0.8, 0)))
	if card != TAG and at.distance_to(screen) > UiTokens.SIZE_TOUCH * 0.5: return false
	farm.actor.face(pip_root.position)
	farm.rt.ui.open_resident(PIP)
	return true

func hide_marks() -> void:
	farm.rt.ui.npc_tag(TAG, "", Vector2.ZERO, false)
	for outline in _highlights.values(): outline.visible = false
	for id in _water_badges: farm.rt.ui.badge(WATER_TAG + str(id), UiStatusBadge.State.AVAILABLE, Vector2.ZERO, false)

## Farm suspension counts as leaving (including going inside): never disappear in front of the player.
func leave() -> void:
	if pip_root != null:
		pip_root.queue_free()
		pip_root = null
		rig = null
		_wave_left = 0.0
	hide_marks()

func near_resident() -> String:
	return PIP if pip_root != null and P0FarmMaterials.flat(farm.actor.position, pip_root.position) < 2.6 else ""

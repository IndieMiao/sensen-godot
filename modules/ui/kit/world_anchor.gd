class_name WorldAnchor
extends Control
## Keeps screen-space markers (facility finger cards, status badges, name tags) attached to 3D anchor
## nodes (SGODOT-211, WP7-B / WP7-C; LOCK-07, LOCK-11). Add this layer full-rect over the world, then
## track(marker, anchor_node, opts) for each marker. Every frame each marker is projected, hidden when
## behind the camera or covered by an occluder (an open drawer), optionally clamped inside the screen
## edge, and lower-priority markers are nudged upward when they overlap higher-priority ones.
## Anchor names follow the WP7-B F-03 ③ naming table (layout.json `anchors`, 2026-10-07). A marker with
## point_at(local_x) is told where its anchor lies inside it after placement, so a pointer can follow it.

var camera: Camera3D   ## defaults to the viewport's current 3D camera
## Screen rects that hide markers inside them (e.g. the open drawer from ModalStack).
var occluders: Array[Rect2] = []
var edge_margin: float = UiTokens.SPACE_WITHIN

var _tracked: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## opts: offset (Vector2 screen offset of the marker's bottom centre, default above the point),
## world_offset (Vector3), clamp (bool: keep inside the screen instead of hiding when off-screen),
## priority (int, higher wins overlaps).
func track(marker: Control, anchor: Node3D, opts := {}) -> void:
	untrack(marker)
	if marker.get_parent() == null: add_child(marker)
	_tracked.append({marker = marker, anchor = anchor, offset = opts.get("offset", Vector2(0, -UiTokens.SPACE_WITHIN)),
		world_offset = opts.get("world_offset", Vector3.ZERO), clamp = opts.get("clamp", false), priority = int(opts.get("priority", 0))})

func untrack(marker: Control) -> void:
	_tracked = _tracked.filter(func(t): return t.marker != marker)

func _process(_dt: float) -> void: update_now()

func update_now() -> void:
	var cam := camera if camera != null else get_viewport().get_camera_3d()
	var view := get_viewport_rect()
	var placed: Array[Dictionary] = []
	for t in _tracked:
		var m: Control = t.marker
		if not is_instance_valid(t.anchor) or not is_instance_valid(m) or cam == null:
			if is_instance_valid(m): m.visible = false
			continue
		var p := project(cam, (t.anchor as Node3D).global_position + t.world_offset)
		if not p.visible:
			m.visible = false
			continue
		var rect := place(m.get_combined_minimum_size().max(m.size), p.pos + t.offset, view, edge_margin, t.clamp)
		if not rect.has_area() or _covered(p.pos):
			m.visible = false
			continue
		placed.append({marker = m, rect = rect, priority = t.priority, point = p.pos + t.offset})
	var rects := placed.map(func(e): return e.rect)
	var prio := placed.map(func(e): return e.priority)
	var solved := resolve_overlaps(rects, prio, edge_margin)
	for i in placed.size():
		var m: Control = placed[i].marker
		m.visible = true
		m.position = (solved[i] as Rect2).position - global_position
		# Markers with a pointer (UiEntryCard) keep it on the anchor after clamping or de-overlap moved them.
		if m.has_method(&"point_at"): m.point_at((placed[i].point as Vector2).x - (solved[i] as Rect2).position.x)

func _covered(pos: Vector2) -> bool:
	for r in occluders:
		if r.has_point(pos): return true
	return false

## Screen position of a world point; visible = false when it is behind the camera.
static func project(cam: Camera3D, world: Vector3) -> Dictionary:
	if cam.is_position_behind(world): return {visible = false, pos = Vector2.ZERO}
	return {visible = true, pos = cam.unproject_position(world)}

## Marker rect whose bottom centre sits at `point`. Off-screen markers are clamped inside `view` (minus
## margin) when `clamp_inside`, otherwise an empty rect is returned so the marker hides.
static func place(marker_size: Vector2, point: Vector2, view: Rect2, margin: float, clamp_inside: bool) -> Rect2:
	var r := Rect2(point - Vector2(marker_size.x * 0.5, marker_size.y), marker_size)
	var inner := view.grow(-margin)
	if inner.encloses(r): return r
	if not clamp_inside: return Rect2()
	r.position.x = clampf(r.position.x, inner.position.x, inner.end.x - r.size.x)
	r.position.y = clampf(r.position.y, inner.position.y, inner.end.y - r.size.y)
	return r

## A card over a facility kept off the player (不知火舞 on #190, the body box of SGODOT-269): when `r` — the whole marker,
## pointer included — comes within `gap` of `body`, it moves straight up until it clears it by `gap`, but never above
## `min_y`. Only y changes, so its pointer still aims at the facility across.
static func lift_clear(r: Rect2, body: Rect2, gap: float, min_y: float) -> Rect2:
	if not r.intersects(body.grow(gap)): return r
	r.position.y = maxf(min_y, minf(r.position.y, body.position.y - gap - r.size.y))
	return r

## Greedy de-overlap: markers are settled in priority order (then top to bottom); each later marker moves
## up above any settled marker it overlaps. Returns the new rects in the input order.
static func resolve_overlaps(rects: Array, priorities: Array, gap: float) -> Array:
	var order := range(rects.size())
	order.sort_custom(func(a, b):
		if priorities[a] != priorities[b]: return priorities[a] > priorities[b]
		return (rects[a] as Rect2).position.y < (rects[b] as Rect2).position.y)
	var out := rects.duplicate()
	var settled: Array[Rect2] = []
	for i in order:
		var r: Rect2 = out[i]
		var moved := true
		var guard := 0
		while moved and guard < rects.size():
			moved = false
			guard += 1
			for s in settled:
				if r.grow(gap * 0.5).intersects(s.grow(gap * 0.5)):
					r.position.y = s.position.y - gap - r.size.y
					moved = true
		out[i] = r
		settled.append(r)
	return out

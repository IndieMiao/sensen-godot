extends RefCounted
## 340: one 600 ms pulse when a target appears, at most one more on re-entry in the same server step.
## Recover changes and rebuilt controls do not refill the budget. No input, selection or server state changes.
var _step := ""
var _counts := {}
var _present := {}
var _rings: Array[WeakRef] = []

func update(view: Dictionary, targets: Dictionary) -> void:
	var step := str(view.guide.step) + ":" + str(view.guide.get("at", "")) if P0Guide.guide_on(view) else ""
	if step != _step:
		_step = step
		_counts.clear()
		_present.clear()
		cancel()
	if step == "": return
	var now := {}
	for key in targets:
		var target: Dictionary = targets[key]
		var node: Control = target.get("node")
		if not visible_target(node): continue
		now[key] = true
		if _present.has(key) or int(_counts.get(key, 0)) >= 2: continue
		# An unavailable command is a fact, not a request to press it. It can pulse when it first becomes usable.
		if node is UiCommandButton and (node.is_unavailable() or node.is_busy() or node.is_offline()):
			now.erase(key)
			continue
		_counts[key] = int(_counts.get(key, 0)) + 1
		if bool(target.get("flash", false)) and node is UiItemCell:
			node.flash()
		else:
			var shape: UiGuidePulse.Shape = target.get("shape", UiGuidePulse.Shape.PILL)
			var rect: Rect2 = target.get("rect", Rect2(Vector2.ZERO, node.size))
			if node is UiCommandButton:
				var style := node.get_theme_stylebox(&"normal")
				if style is UiStyleBox: rect = style.visible_rect(rect)
			var overlay: Control = target.get("overlay", node)
			if overlay != node: rect.position += node.global_position - overlay.global_position
			var ring := UiGuidePulse.play(overlay, rect, shape, float(target.get("radius", 16.0)))
			if overlay != node: ring.set_meta("guide_target", weakref(node))
			_rings.append(weakref(ring))
	_present = now
	_rings = _rings.filter(func(r): return is_instance_valid(r.get_ref()))

## Drawer item rings sit outside the scrolling grid's clip, but follow the cell while it moves.
func follow() -> void:
	for ref in _rings:
		var ring = ref.get_ref()
		if not is_instance_valid(ring) or not ring.has_meta("guide_target"): continue
		var node: Control = ring.get_meta("guide_target").get_ref()
		if not is_instance_valid(node):
			ring.queue_free()
			continue
		ring.visible = visible_target(node)
		ring.position = node.global_position - ring.get_parent().global_position - Vector2.ONE * (ring.grow_px + ring.stroke)

static func visible_target(node: Control) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree() or not node.size.x > 0 or not node.size.y > 0: return false
	var rect := node.get_global_rect()
	if not node.get_viewport().get_visible_rect().encloses(rect): return false
	var parent := node.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents and not parent.get_global_rect().encloses(rect): return false
		parent = parent.get_parent()
	return true

func cancel() -> void:
	for ref in _rings:
		var ring = ref.get_ref()
		if is_instance_valid(ring): ring.queue_free()
	_rings.clear()

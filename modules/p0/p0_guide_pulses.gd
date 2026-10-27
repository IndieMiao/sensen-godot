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
			_rings.append(weakref(UiGuidePulse.play(node, Rect2(), shape)))
	_present = now
	_rings = _rings.filter(func(r): return is_instance_valid(r.get_ref()))

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

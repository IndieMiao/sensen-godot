class_name TouchScrollContainer
extends ScrollContainer
## Let content share the native scroll gesture, including children added on refresh.
## ScrollContainer owns the deadzone, inertia and SCROLL_BEGIN click cancellation.

func _init() -> void:
	child_entered_tree.connect(_watch_content)

func _ready() -> void:
	# A horizontal strip inside a vertical sheet must pass unused motion outwards.
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			mouse_filter = Control.MOUSE_FILTER_PASS
			break
		ancestor = ancestor.get_parent()
	for child in get_children(): _watch_content(child)

func _watch_content(node: Node) -> void:
	if not is_ancestor_of(node): return
	# Keep scrollbars, text selection and numeric/slider editing native.
	# Nested scroll containers configure their own descendants.
	if node is ScrollContainer or node is Range or node is LineEdit or node is TextEdit:
		return
	if node is Control and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is BaseButton:
		# OptionButton/CheckButton otherwise activate on touch-down, before a drag
		# can be distinguished from a tap. Keyboard activation is still native.
		node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if not node.child_entered_tree.is_connected(_watch_content):
		node.child_entered_tree.connect(_watch_content)
	for child in node.get_children(): _watch_content(child)

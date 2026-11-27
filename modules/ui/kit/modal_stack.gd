class_name ModalStack
extends Control
## Drawer and card layers with one back rule (SGODOT-211, WP7-B F-04 §5).
## - At most one drawer (bag, counter, kitchen, inbox, Today) and one card (detail / info sheet, Energy
##   card, keeper greeting, resident bar) at a time. Opening a drawer replaces the drawer and closes the
##   card; opening a card replaces only the card.
## - Back key, scrim tap and explicit close all close the top layer only: card first, then drawer.
##   With nothing open, back is left to the rest of the app.
## - Closing a card leaves the drawer node untouched, so its selection, scroll and filter survive.
## Toasts and system banners are separate layers above this one and never block input.

signal opened(layer: Layer, content: Control)
signal closed(layer: Layer, content: Control)

enum Layer { DRAWER, CARD }

var _content := {}    # Layer -> Control
var _scrim := {}      # Layer -> ColorRect
var _on_close := {}   # Layer -> Callable
var _animate_out := {}   # Layer -> true: the layer leaves with its exit motion (C-186)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func has_drawer() -> bool: return _content.has(Layer.DRAWER)
func has_card() -> bool: return _content.has(Layer.CARD)
func is_empty() -> bool: return _content.is_empty()
func drawer() -> Control: return _content.get(Layer.DRAWER)
func card() -> Control: return _content.get(Layer.CARD)
func top() -> Control: return card() if has_card() else drawer()

## opts: scrim (opacity, default UiTokens.OPACITY_SCRIM_DRAWER), scrim_closes (default true),
## on_close (Callable run after the drawer is removed), animate_out (default false; C-186, C-185 MS-14: the layer is
## closed at once — the stack forgets it and input is let go — but stays drawn while it leaves: a drawer's play_out(),
## else M-05 from the card's bottom middle; then both it and its scrim are freed).
func open_drawer(content: Control, opts := {}) -> void:
	close_card()
	_close(Layer.DRAWER)
	_open(Layer.DRAWER, content, float(opts.get("scrim", UiTokens.OPACITY_SCRIM_DRAWER)), opts)

## Same options as open_drawer; the default scrim is UiTokens.OPACITY_SCRIM_MODAL.
func open_card(content: Control, opts := {}) -> void:
	_close(Layer.CARD)
	_open(Layer.CARD, content, float(opts.get("scrim", UiTokens.OPACITY_SCRIM_MODAL)), opts)

func close_card() -> void: _close(Layer.CARD)
func close_drawer() -> void:
	close_card()
	_close(Layer.DRAWER)
func close_all() -> void: close_drawer()

## Close the top layer. Returns false when nothing was open (the caller may handle back itself).
func back() -> bool:
	if has_card():
		close_card()
		return true
	if has_drawer():
		close_drawer()
		return true
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		back()

func _open(layer: Layer, content: Control, scrim_opacity: float, opts: Dictionary) -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim%s" % Layer.keys()[layer].capitalize()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = UiKit.alpha(UiTokens.COLOR_SCRIM, scrim_opacity)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	if opts.get("scrim_closes", true):
		scrim.gui_input.connect(_on_scrim_input.bind(layer))
	add_child(scrim)
	add_child(content)
	if content is UiDrawer: (content as UiDrawer).scrim = scrim   # it fades as the drawer is dragged down (SGODOT-265)
	_scrim[layer] = scrim
	_content[layer] = content
	if opts.has("on_close"): _on_close[layer] = opts.on_close
	if opts.get("animate_out", false): _animate_out[layer] = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	opened.emit(layer, content)

func _close(layer: Layer) -> void:
	if not _content.has(layer): return
	var content: Control = _content[layer]
	_content.erase(layer)
	var scrim: Control = _scrim[layer]
	_scrim.erase(layer)
	if _animate_out.get(layer, false) and content.get_parent() == self and content.is_inside_tree():
		_animate_out.erase(layer)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.propagate_call(&"set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])   # no tap on what is leaving
		content.name = String(content.name) + "_Leaving"
		var gone := func() -> void:
			if is_instance_valid(scrim): scrim.queue_free()
			if is_instance_valid(content): content.queue_free()
		if content.has_method(&"play_out"): content.call(&"play_out", scrim, gone)
		else: UiMotion.panel_out(content, scrim, gone, Vector2(0.5, 1.0))
	else:
		_animate_out.erase(layer)
		remove_child(scrim)
		scrim.queue_free()
		if content.get_parent() == self: remove_child(content)
		content.queue_free()
	var cb: Callable = _on_close.get(layer, Callable())
	_on_close.erase(layer)
	closed.emit(layer, content)
	if cb.is_valid(): cb.call()

func _on_scrim_input(e: InputEvent, layer: Layer) -> void:
	var released: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed) \
		or (e is InputEventScreenTouch and not e.pressed and not DisplayServer.is_touchscreen_available())
	if not released: return
	# Only the top layer's scrim reacts; the drawer scrim is covered by the card scrim anyway.
	if layer == Layer.CARD or not has_card(): back()
	accept_event()

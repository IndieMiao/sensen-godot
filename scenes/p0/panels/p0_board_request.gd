class_name P0BoardRequest
extends RefCounted
## One board request's sheet (SGODOT-224; 不知火舞 on 224): opened from a board row's title ›.
##   BOARD-1 482:284        ObjectHeader (title · Open / Tracked / Ready to deliver · what to bring where), NeedTiles,
##                          Reward, the other slot's wait (Next request · Second board slot · Available in 72h),
##                          Show / Show on map (where the items come from), Drop request › (tracked only: an open
##                          request swaps itself after 72 h), Details › (the item), Back to the list.
##   BOARD-3 482:288        Drop request: what dropping does, Next request after drop 8h, Details ›, your items stay
##                          in your bag, Drop request (destructive) / Keep tracking.
##   BOARD-DROPPED 482:322  Dropped: your items remain in your bag, Next request 8h, Details ›, Close back to the list.
## A bottom Sheet (radius 24, 1 px edge) with Close 44 floating above its top-right corner; the decision line sits at
## the bottom.

const _PAD := 16.0
const _GAP := 8

## BOARD-1 for request `id` of `role`'s board; a request gone meanwhile (delivered, refilled) lands back on the list.
static func open(ui: P0Ui, role: String, id: String) -> void:
	var d := P0Board.detail(ui.view, P0Board.board_id(role), id)
	if d.is_empty():
		ui.open_counter(role, {"section": "board"})
		return
	var back := func(): ui.open_counter(role, {"section": "board"})
	var col := _sheet(ui, "board_request", "Back", back)
	col.add_child(UiObjectHeader.new({title = d.title, state = d.state, effect = d.effect}))
	if str(d.get("example", "")) != "":   # Far Pond (q(128)): the fish to try, nearest first, at the player's level now
		var example := UiKit.label(str(d.example), UiTokens.STYLE_CAPTION_R12, UiTokens.COLOR_SECONDARY)
		example.name = "Example"
		example.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(example)
	var tiles: Array = []
	for n in d.needs:
		var tile := UiNeedTile.new(str(n.name), int(n.have), int(n.need), UiNeedTile.Size.S, n.icon)
		var item := str(n.id)
		tile.pressed.connect(func(): ui._show_need_source(tile, item))
		tiles.append(tile)
	if not tiles.is_empty(): col.add_child(UiNeedTile.group(tiles))
	col.add_child(UiFactRow.new("Reward", str(d.delivery)))   # the frames' word, as the list card's (不知火舞 on #285)
	if not (d.next as Dictionary).is_empty():
		col.add_child(UiItemRow.new({icon = P0Logic.icon("clock"), title = "Next request", effect = str(d.next.slot)}))
		col.add_child(UiFactRow.new("Available in", str(d.next.within)))
	var go := str(d.go)
	var show := P0Ui.show_label(go, ui.space_here(), ui.spot_reachable())
	if show != "":
		_nav(col, show, func():
			ui.close_modal()
			if show == "Show": ui.show_spot.emit(go)
			else: ui.show_on_map.emit(P0Ui.map_target(go)))
	if bool(d.tracked): _nav(col, "Drop request", func(): confirm_drop(ui, role, id))
	_details(ui, col, str(d.item))

## BOARD-3: the drop confirmation; Drop request sends `drop` and waits for the server's dropped event
## (P0Ui.board_dropped → BOARD-DROPPED); Keep tracking goes back to BOARD-1.
static func confirm_drop(ui: P0Ui, role: String, id: String) -> void:
	var d := P0Board.detail(ui.view, P0Board.board_id(role), id)
	if d.is_empty():
		ui.open_counter(role, {"section": "board"})
		return
	var col := _sheet(ui, "board_drop", "Keep tracking", func(): open(ui, role, id))
	col.add_child(UiObjectHeader.new({title = d.title, state = "Drop request",
		effect = "Dropping removes tracking and delays the next request."}))
	col.add_child(UiFactRow.new("Next request after drop", P0Board.drop_wait()))
	_details(ui, col, str(d.item))
	var keep := UiKit.label("Your %s stay in your bag." % str(d.noun), UiTokens.STYLE_BODY_XB14)
	keep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(keep)
	var drop := UiCommandButton.new("Drop request", UiCommandButton.Kind.DESTRUCTIVE)
	drop.sends = true   # drop (§10.7.1 Offline)
	drop.activated.connect(func():
		ui.pending_drop = {"role": role, "id": id, "title": str(d.title), "noun": str(d.noun), "item": str(d.item)}
		ui.command.emit({"type": "drop", "request": id}))
	col.add_child(drop)

## BOARD-DROPPED: what dropping left (the server confirmed); Close goes back to the list.
static func dropped(ui: P0Ui, gone: Dictionary) -> void:
	var role := str(gone.get("role", "homestead"))
	var back := func(): ui.open_counter(role, {"section": "board"})
	var col := _sheet(ui, "board_dropped", "Close", back)
	col.add_child(UiObjectHeader.new({title = str(gone.get("title", "")), state = "Dropped",
		effect = "Your %s remain in your bag." % str(gone.get("noun", "items"))}))
	col.add_child(UiFactRow.new("Next request", P0Board.drop_wait()))
	_details(ui, col, str(gone.get("item", "")))

## Details ›: the item's InfoSheet laid over this sheet on a scrim (不知火舞 on 224) — read only, ×0 when the bag has
## none; a tap outside it or Back goes back to the sheet under it. None for a request with no single item.
static func _details(ui: P0Ui, col: Control, item: String) -> void:
	if item == "": return
	_nav(col, "Details", func(): info(ui, item))

## The InfoSheet over the open request sheet (P0ItemInfo's bag card without its buttons: nothing to do from here), on
## its scrim (UiInfoSheet.layered); Back (P0Ui.close_top_layer) or a tap on the scrim closes the card, back to the
## sheet under it.
static func info(ui: P0Ui, item: String) -> UiInfoSheet:
	var sheet := UiInfoSheet.layered(ui._modal, Vector2(UiTokens.SIZE_QUICK_BAR_X, _PAD + ui.safe_bottom()))
	sheet.rules = func(id: String, _c: StringName, o: Dictionary) -> Dictionary:
		var spec := P0ItemInfo.spec(ui.view, id, &"bag", o)
		spec.buttons = []
		spec.info = false
		spec.quantity_shown = true
		return spec
	sheet.open(item, &"bag")   # Back closes it first: P0Ui.close_top_layer looks for a layered card
	return sheet

static func _nav(col: Control, label: String, on_press: Callable) -> void:
	var b := UiNavButton.new(label)
	b.pressed.connect(on_press)
	col.add_child(b)

## The Sheet: a bottom panel with the content column (returned), the dismiss line at its foot (`bye` → `back`), Close
## 44 six above its top-right corner (closes all). Back / Android Back run `back`.
static func _sheet(ui: P0Ui, kind: String, bye: String, back: Callable) -> VBoxContainer:
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(_PAD, _PAD, _PAD, 12 + ui.safe_bottom()))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 12)
	panel.add_child(outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", _GAP)
	outer.add_child(col)
	var dismiss := UiDismissButton.new(bye)
	dismiss.pressed.connect(back)
	outer.add_child(dismiss)
	holder.add_child(panel)
	var close := UiCloseButton.new()
	close.pressed.connect(ui.close_modal)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - _PAD - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = kind
	ui._modal_back = back
	return col

extends Control
## Display only: zoom/pan never generate cells or change their server coordinates.
signal cell_selected(kind: String)
signal view_changed(zoom: float)

const COLORS := {
	"water": Color("509ac4"), "residential": Color("b9c87d"),
	"public": Color("b7accd"), "green": Color("6c9c72"),
	"mixed": Color("d5aa76"), "commercial": Color("b29d88"),
	"unknown": Color("aab2ae"), "path": Color("d9cdb5"),
	"building": Color("bb7d63"),
}
const ZONE_COLORS := {"core": Color("bc6953"), "extension": Color("5c8c9a")}
const MIN_ZOOM := 1.0
const MAX_ZOOM := 4.0
const DRAG_THRESHOLD := 8.0
var _palette: Dictionary = COLORS.duplicate()
var _cells: Array = []
var _bounds := Rect2()
var _selected := -1
var _buildings := {}
var _zones := {}
var _zoom := 1.0
var _pan := Vector2.ZERO
var _touches := {}
var _touch_start := Vector2.ZERO
var _gesture := false
var _touch_moved := false
var _mouse_down := false
var _mouse_start := Vector2.ZERO
var _mouse_moved := false

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	visibility_changed.connect(_clear_gesture)

func set_cells(cells: Array, palette: Dictionary = {}) -> void:
	_palette = COLORS.duplicate() if palette.is_empty() else palette
	_cells = cells
	_selected = -1
	_buildings.clear()
	_zones.clear()
	_bounds = Rect2()
	if not cells.is_empty():
		var first: Dictionary = cells[0]
		var low := Vector2(first.x, first.y)
		var high := low + Vector2.ONE
		for cell: Dictionary in cells:
			low = low.min(Vector2(cell.x, cell.y))
			high = high.max(Vector2(cell.x + 1, cell.y + 1))
			if cell.has("zone"):
				_zones[Vector2i(cell.x, cell.y)] = cell.zone
			if cell.kind == "building":
				_buildings[Vector2i(cell.x, cell.y)] = true
		_bounds = Rect2(low, high - low)
	fit()

func fit() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_clear_gesture()
	queue_redraw()
	view_changed.emit(_zoom)

func zoom_at(value: float, anchor: Vector2) -> void:
	var next := clampf(value, MIN_ZOOM, MAX_ZOOM)
	var ratio := next / _zoom
	_pan = anchor - size * 0.5 - (anchor - size * 0.5 - _pan) * ratio
	_zoom = next
	_clamp_pan()
	queue_redraw()
	view_changed.emit(_zoom)

func pan_by(delta: Vector2) -> void:
	_pan += delta
	_clamp_pan()
	queue_redraw()

func _base_scale() -> float:
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return 1.0
	var available := (size - Vector2(32, 32)).max(Vector2.ONE)
	return minf(available.x / _bounds.size.x, available.y / _bounds.size.y)

func _clamp_pan() -> void:
	var extent := _bounds.size * _base_scale() * _zoom
	var limit := ((extent - size + Vector2(32, 32)) * 0.5).max(Vector2.ZERO)
	_pan = _pan.clamp(-limit, limit)

func _on_resized() -> void:
	_clamp_pan()
	_clear_gesture()
	queue_redraw()

func _clear_gesture() -> void:
	_touches.clear()
	_gesture = false
	_touch_moved = false
	_mouse_down = false

func cell_rect(index: int) -> Rect2:
	if index < 0 or index >= _cells.size() or _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return Rect2()
	var scale_value := _base_scale() * _zoom
	var offset := (size - _bounds.size * scale_value) * 0.5 + _pan
	var cell: Dictionary = _cells[index]
	var position := Vector2(cell.x - _bounds.position.x, _bounds.end.y - cell.y - 1)
	return Rect2(offset + position * scale_value, Vector2.ONE * scale_value)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("e9eee6"))
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		var rect := cell_rect(i)
		if not Rect2(Vector2.ZERO, size).intersects(rect):
			continue
		draw_rect(rect, _palette.get(cell.kind, COLORS.unknown))
		if rect.size.x >= 3.0 and cell.get("zone", "core") == "core":
			draw_rect(rect, Color(0.16, 0.23, 0.19, 0.20), false, 0.6)
		if cell.has("zone"):
			_draw_zone_edge(rect, Vector2i(cell.x, cell.y), cell.zone)
		if cell.kind == "building":
			_draw_building_edge(rect, Vector2i(cell.x, cell.y))
	if _selected >= 0:
		draw_rect(cell_rect(_selected).grow(1), Color("243d32"), false, 2.0)

func _draw_building_edge(rect: Rect2, coordinate: Vector2i) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var neighbors := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	for edge in 4:
		if not _buildings.has(coordinate + neighbors[edge]):
			draw_line(corners[edge], corners[(edge + 1) % 4], Color("594438"), 1.5, true)

func _select_at(point: Vector2) -> void:
	for i in _cells.size():
		if cell_rect(i).has_point(point):
			_selected = i
			cell_selected.emit("zone:" + str(_cells[i].zone) if _cells[i].has("zone") else str(_cells[i].kind))
			queue_redraw()
			return

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touches.is_empty():
				_touch_start = event.position
				_touch_moved = false
				_gesture = false
			_touches[event.index] = event.position
			_gesture = _gesture or _touches.size() > 1
		elif _touches.has(event.index):
			if _touches.size() == 1 and not _gesture and not _touch_moved and not event.canceled:
				_select_at(event.position)
			_touches.erase(event.index)
		accept_event()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var previous: Vector2 = _touches[event.index]
		if _touches.size() == 2:
			var keys := _touches.keys()
			var other: Vector2 = _touches[keys[1] if keys[0] == event.index else keys[0]]
			var old_center := (previous + other) * 0.5
			var new_center: Vector2 = (event.position + other) * 0.5
			var old_distance := previous.distance_to(other)
			if old_distance > 1.0:
				zoom_at(_zoom * event.position.distance_to(other) / old_distance, old_center)
			pan_by(new_center - old_center)
		elif _touches.size() == 1:
			_touch_moved = _touch_moved or event.position.distance_to(_touch_start) > DRAG_THRESHOLD
			if _touch_moved:
				pan_by(event.position - previous)
		_touches[event.index] = event.position
		accept_event()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(_zoom * (1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_mouse_moved = false
				_mouse_start = event.position
			else:
				if _mouse_down and not _mouse_moved:
					_select_at(event.position)
				_mouse_down = false
		accept_event()
	elif event is InputEventMouseMotion and _mouse_down:
		_mouse_moved = _mouse_moved or event.position.distance_to(_mouse_start) > DRAG_THRESHOLD
		if _mouse_moved:
			pan_by(event.relative)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(_zoom * event.factor, event.position)
		accept_event()

func _draw_zone_edge(rect: Rect2, coordinate: Vector2i, zone: String) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var neighbors := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	for edge in 4:
		var adjacent: String = _zones.get(coordinate + neighbors[edge], "")
		if (zone == "core" and adjacent != "core") or (zone == "extension" and adjacent.is_empty()):
			draw_line(corners[edge], corners[(edge + 1) % 4], ZONE_COLORS[zone], 1.5, true)

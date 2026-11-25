class_name UiTaskDropDown
extends VBoxContainer
## UI v3 task drop-down (C-T1–C-T3, M-13; C-107, design C-85 ⑧-A): under the HUD, at most three glass task rows
## (UiTaskRow GLASS, 4 apart), then `More…` when there are more, which opens the phone's task page. No scrim: rows take
## no touches, only `More…` does, so the scene plays on under it. It folds itself away after 4 s untouched.
##   open(rows, more)   rows: [{title, state: UiTaskRow.State}]; each row drops in y −8 → 0 and fades in over 160,
##                      40 apart (cubic out)
##   fold()             every row fades out together over 120 (cubic in), then `folded`
##   complete(index)    the row's finishing beat (UiTaskRow.complete); one second on it slides out and the rest close up
## Reduced motion (UiMotion.reduced): rows fade in and out over 120 without moving.

signal more_pressed
signal folded

const MORE := "More…"
const MAX_ROWS := 3
const STAY_S := 4.0
const DROP := 8.0
## A finished row stays this long before it slides out (C-85 ⑧ motion 2).
const DONE_STAY_S := 1.0

var rows: Array[UiTaskRow] = []
var more: UiTaskRow
var showing := false
var _timer: SceneTreeTimer
var _stamp := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", int(UiTokens.SPACE_S2))
	visible = false

## Shows `list` (at most MAX_ROWS of it) and `More…` when `has_more`; restarts the 4 s fold.
func open(list: Array, has_more: bool) -> void:
	_clear()
	showing = true
	visible = true
	modulate.a = 1.0
	for i in mini(list.size(), MAX_ROWS):
		var row := UiTaskRow.new(str(list[i].title), list[i].state, UiTaskRow.Look.GLASS)
		row.name = "Task%d" % i
		row.tappable = false
		rows.append(row)
		add_child(row)
	if has_more:
		more = UiTaskRow.new(MORE, UiTaskRow.State.TODO, UiTaskRow.Look.GLASS)
		more.name = "More"
		more.pressed.connect(func():
			fold()
			more_pressed.emit())
		add_child(more)
	var shown: Array = rows.duplicate()
	if more != null: shown.append(more)
	for i in shown.size(): _drop_in(shown[i], i)
	touch()

## Any touch on the drop-down (or the caller's) holds it up another 4 s.
func touch() -> void:
	_stamp += 1
	var stamp := _stamp
	if not is_inside_tree(): return
	_timer = get_tree().create_timer(STAY_S, true, false, true)
	_timer.timeout.connect(func(): if stamp == _stamp and showing: fold())

func fold() -> void:
	if not showing: return
	showing = false
	_stamp += 1
	if not is_inside_tree():
		_clear()
		visible = false
		folded.emit()
		return
	var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_EXIT)
	tw.tween_property(self, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	tw.tween_callback(func():
		if showing: return
		_clear()
		visible = false
		folded.emit())

## Plays row `index`'s finishing beat; a second later it slides out and `after` (the caller's new rows) is shown.
func complete(index: int, after: Callable = Callable()) -> void:
	if index < 0 or index >= rows.size() or not showing: return
	var row := rows[index]
	row.complete()
	touch()
	if not is_inside_tree(): return
	var stamp := _stamp
	await get_tree().create_timer(DONE_STAY_S, true, false, true).timeout
	if stamp != _stamp or not showing or not is_instance_valid(row): return
	var tw := UiMotion.tween(row, UiTokens.MOTION_EASING_EXIT)
	tw.tween_property(row, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	await tw.finished
	if stamp != _stamp or not showing: return
	if after.is_valid(): after.call()

func _drop_in(row: Control, i: int) -> void:
	row.modulate.a = 0.0
	if not is_inside_tree(): return
	var tw := UiMotion.tween(row, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_interval(UiMotion.secs(UiTokens.MOTION_STAGGER_MS_LIST * i))
	var ms := UiTokens.MOTION_DURATION_FAST_MS if UiMotion.reduced else UiTokens.MOTION_DURATION_QUICK_MS
	tw.tween_property(row, "modulate:a", 1.0, UiMotion.secs(ms))
	if not UiMotion.reduced:
		# The rows sit in this box: move what they draw (a container resets their position on layout).
		tw.parallel().tween_method(func(y: float): _shift(row, y), -DROP, 0.0, UiMotion.secs(ms))

func _shift(row: Control, y: float) -> void:
	if not is_instance_valid(row): return
	for child in row.get_children():
		if child is Control: (child as Control).position.y = y

func _clear() -> void:
	var all: Array = rows.duplicate()
	if more != null: all.append(more)
	for row in all:
		if is_instance_valid(row):
			remove_child(row)
			row.queue_free()
	rows.clear()
	more = null

class_name ActionRunner
extends RefCounted
## 劳作动作队列：逐格执行，每格占 ACTION_S 秒。
##
## 为什么要队列而不是一次性提交：PRD §6.3 要求逐格播放动画，玩家能看见自己在干活；
## 行级工具也只是省手势，不缩短时长。队列是这条规则唯一的落点。
##
## 只管**节奏与顺序**，不发网络请求：每格开始时 emit cell_started，宿主拿它去预测、
## 播动画、发命令。这样单测不需要网络也能钉住时序。

signal cell_started(cell: Vector2i, action: String)
signal cell_done(cell: Vector2i, action: String)
signal queue_empty()

## 单格动作时长。星露谷挥一次锄约 0.5 秒；自由种植下一笔能刷二三十格，
## 原来的 2.0 秒意味着一次要等一分钟。
const ACTION_S := 0.45

var _queue: Array = []          ## [{cell, action}]
## 暂停：当前格已开工（cell_started 已发）但计时不走——宿主用它实现「先走到地头再干活」。
var paused := false
var _current = null
var _elapsed := 0.0
var duration_for := Callable()
var action_seconds := ACTION_S

## 已在队列里（或正在做）的格不重复入队：大按钮连按两下不该把 9 格清理排成 18 格。
func contains(cell: Vector2i) -> bool:
	if _current != null and _current.cell == cell:
		return true
	for q in _queue:
		if q.cell == cell:
			return true
	return false

func enqueue(cells: Array, action: String) -> int:
	var added := 0
	for c in cells:
		if contains(c as Vector2i):
			continue
		_queue.append({"cell": c as Vector2i, "action": action})
		added += 1
	return added

func is_busy() -> bool:
	return _current != null or not _queue.is_empty()

func pending_count() -> int:
	return _queue.size() + (1 if _current != null else 0)

func queued_cells() -> Array:
	return _queue.map(func(item): return item.cell)

func current_cell():
	return _current.cell if _current != null else null

func current_action() -> String:
	return str(_current.action) if _current != null else ""

## 当前格已走完的比例 0..1，给进度圈用。
func progress() -> float:
	return 0.0 if _current == null else clampf(_elapsed / action_seconds, 0.0, 1.0)

## 取消尚未开始的格；**正在进行的那格照常走完**——命令可能已经发出去了，
## 中途丢弃会让本地与服务端对不上。
func cancel_pending() -> int:
	var n := _queue.size()
	_queue.clear()
	return n

## 放弃**当前**这格（本地预测就判定不合法时用）：不发 cell_done，所以不会发命令；
## 队列里后面的格照常继续。
##
## paused 描述的是**当前这格**的「先走到地头」阶段，所以放弃当前格必须一并清掉：
## 否则下一格即使不需要走路也会卡在 step() 的 `if paused: return`，表现为
## 「忙着但永远不前进」，HUD 还一直显示在赶路。
func abort_current() -> void:
	paused = false
	if _current == null:
		return
	_current = null
	_elapsed = 0.0
	if _queue.is_empty():
		emit_signal("queue_empty")

func step(dt: float) -> void:
	if _current == null:
		if _queue.is_empty():
			return
		_start_next()
		# 起手这一帧不计时：否则第一格会被吞掉一个 dt，长队列越走越偏。
		return
	if paused:
		return
	_elapsed += dt
	if _elapsed < action_seconds:
		return
	var done: Dictionary = _current
	_current = null
	_elapsed = 0.0
	emit_signal("cell_done", done.cell, done.action)
	if _queue.is_empty():
		emit_signal("queue_empty")
	else:
		_start_next()

func _start_next() -> void:
	_current = _queue.pop_front()
	action_seconds = maxf(0.05, float(duration_for.call(_current.cell, _current.action))) if duration_for.is_valid() else ACTION_S
	_elapsed = 0.0
	emit_signal("cell_started", _current.cell, _current.action)

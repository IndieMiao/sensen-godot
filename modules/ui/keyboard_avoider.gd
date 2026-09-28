class_name KeyboardAvoider
extends Node
## 软键盘避让：键盘升起时把正在输入的框（以及它下面紧跟的一段内容）推到键盘上方。
##
## Godot 不会替我们做这件事：Android / iOS 的键盘直接盖在画面上。这里每帧读系统键盘高度，
## 只在焦点落在 target 内部的输入框时，把 target 整体上移；键盘收起就平滑回位。
## vivo 真机（2026-09-28）：选城搜索结果和账号面板下半部分都被键盘挡住，因此加了它。

## 被整体平移的节点（通常是页面的根容器）。
var target: Control
## 输入框下方还要露出的高度（视口单位），比如搜索结果列表。
var extra_below := 64.0
## 键盘上沿与内容之间的留白。
var gap := 12.0
## 测试注入：返回视口单位的键盘高度。默认读 DisplayServer。
var keyboard_height: Callable
var _base_y := 0.0
var _offset := 0.0
var _tracking := false

static func attach(p_target: Control, p_extra_below := 64.0) -> KeyboardAvoider:
	var a := KeyboardAvoider.new()
	a.name = "KeyboardAvoider"
	a.target = p_target
	a.extra_below = p_extra_below
	p_target.add_child(a)
	return a

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _viewport_keyboard_height() -> float:
	if keyboard_height.is_valid(): return float(keyboard_height.call())
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return 0.0
	var px := DisplayServer.virtual_keyboard_get_height()
	if px <= 0: return 0.0
	var window := DisplayServer.window_get_size()
	var view := get_viewport().get_visible_rect().size
	return float(px) * view.y / maxf(1.0, float(window.y))

## 目标偏移：让焦点输入框底部 + extra_below 落在键盘上沿之上。只向上推，不向下拉。
func desired_offset() -> float:
	if not is_instance_valid(target): return 0.0
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit) or not target.is_ancestor_of(focus): return 0.0
	var kb := _viewport_keyboard_height()
	if kb <= 0.0: return 0.0
	var visible_bottom := get_viewport().get_visible_rect().size.y - kb - gap
	var field := focus.get_global_rect()
	# Measure from where the field would sit without our shift, so the offset does not chase itself.
	var natural_bottom := field.end.y - _offset + extra_below
	var needed := visible_bottom - natural_bottom
	# Never push the field itself above the top of the screen.
	var floor_offset := 8.0 - (field.position.y - _offset)
	return clampf(needed, floor_offset, 0.0) if needed < 0.0 else 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(target): return
	var want := desired_offset()
	if not _tracking and absf(want) < 0.5 and absf(_offset) < 0.5: return
	if not _tracking:
		_base_y = target.position.y
		_tracking = true
	_offset = lerpf(_offset, want, clampf(delta * 14.0, 0.0, 1.0))
	if absf(_offset - want) < 0.5: _offset = want
	target.position.y = _base_y + _offset
	if absf(_offset) < 0.5 and absf(want) < 0.5:
		target.position.y = _base_y
		_offset = 0.0
		_tracking = false

class_name KeyboardAvoider
extends Node
## 软键盘遮挡自动避让（08-30 调研 §3.1「文本输入是 Godot 做社交 App 的最大体验坑」）。
## Godot 不会自己把被键盘盖住的输入框顶上去：这里每帧读 DisplayServer.virtual_keyboard_get_height()，
## 把 target 向上平移到焦点输入框露出键盘之上；键盘收起归零。
## iOS 键盘升起是带动画的，前几帧高度不准——逐帧跟随本身就是解法，不做一次性取值。
## 高度 / 窗口 / 焦点全部可注入，单测不依赖真机。
## Android IME 光标不同步（godot #68338）是引擎层问题，GDScript 无解，只能靠真机回归盯着。

## SHIFT：整页向上平移，表单类页用（登录 / 资料编辑）。
## SHRINK：把 target 的底边收上来（offset_bottom），让中间可伸缩的列表变矮、底部输入框浮到键盘上方，
## 标题与已有内容不动——聊天页用。真机截图（2026-09-07 iPhone 13）里 SHIFT 会把标题和消息全推出屏幕。
## SHRINK 要求 target 的父节点不是 Container（容器每次重排会把 offset 盖掉），AppPage 里挂在 SafeArea 上。
enum Mode { SHIFT, SHRINK }

@export var target: Control
@export var margin := 12.0
@export var mode := Mode.SHIFT

## () -> int，物理像素。默认 DisplayServer.virtual_keyboard_get_height()。
var keyboard_height_provider: Callable
## () -> Vector2i，窗口物理尺寸。默认 DisplayServer.window_get_size()。
var window_size_provider: Callable
## () -> Control，当前焦点。默认 viewport.gui_get_focus_owner()。
var focus_provider: Callable

var current_shift := 0.0

## 键盘物理高度换算到视口单位（与 UIMetrics.safe_margins 同一套比例）。
static func keyboard_height_in_viewport(kb_px: int, window_h: int, viewport_h: float) -> float:
	if kb_px <= 0 or window_h <= 0 or viewport_h <= 0.0:
		return 0.0
	return float(kb_px) * viewport_h / float(window_h)

## 需要上移多少：焦点控件底边 + margin 越过键盘顶边的部分；键盘收起为 0。
static func shift_for(control_bottom: float, viewport_h: float, keyboard_h: float, p_margin: float) -> float:
	if keyboard_h <= 0.0:
		return 0.0
	return maxf(0.0, control_bottom + p_margin - (viewport_h - keyboard_h))

static func is_text_input(c: Control) -> bool:
	return c is LineEdit or c is TextEdit

func _process(_delta: float) -> void:
	poll()

func poll() -> void:
	if target == null or not is_inside_tree():
		return
	var focus := _focus()
	var kb_px := _keyboard_px()
	var shift := 0.0
	if focus != null and is_text_input(focus) and target.is_ancestor_of(focus) and kb_px > 0:
		var vp_h := get_viewport().get_visible_rect().size.y
		var kb_vp := keyboard_height_in_viewport(kb_px, _window_size().y, vp_h)
		# 用未平移前的位置算：控件全局矩形已含当前 shift，先加回去。
		var bottom := focus.get_global_rect().end.y + current_shift
		shift = shift_for(bottom, vp_h, kb_vp, margin)
	_apply(shift)

func _apply(shift: float) -> void:
	if is_equal_approx(shift, current_shift):
		return
	current_shift = shift
	if mode == Mode.SHRINK:
		target.offset_bottom = -shift
	else:
		target.position.y = -shift

func _focus() -> Control:
	if focus_provider.is_valid():
		return focus_provider.call() as Control
	return get_viewport().gui_get_focus_owner()

func _keyboard_px() -> int:
	if keyboard_height_provider.is_valid():
		return int(keyboard_height_provider.call())
	return DisplayServer.virtual_keyboard_get_height()

func _window_size() -> Vector2i:
	if window_size_provider.is_valid():
		return window_size_provider.call()
	return DisplayServer.window_get_size()

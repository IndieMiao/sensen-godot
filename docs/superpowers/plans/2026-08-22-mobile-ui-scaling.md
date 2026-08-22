# 移动端 UI 缩放、安全区与换装取景 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Android 真机上 UI 过小、控件贴边点不到的问题，并把换装房间改为底部抽屉布局 + 相机按角色包围盒自适应取景。

**Architecture:** 三层解耦——(1) `project.godot` 的 `canvas_items` 拉伸把基准降到 360×640，使 1 基准单位 ≈ 1dp；(2) `UIMetrics` 承载全部纯计算（安全区换算、取景距离与偏移），无节点依赖故可 headless 单测；(3) `SafeAreaMargin` 与 `DressingCamera` 是薄运行时胶水，只负责取系统值调用 `UIMetrics` 并写回节点属性。

**Tech Stack:** Godot 4.7.2（Mobile 渲染管线）、GDScript、gdUnit4。

## Global Constraints

- 拉伸基准固定 **360×640**，`stretch/mode="canvas_items"`、`stretch/aspect="expand"`；所有 UI 尺寸数值以基准单位书写，1 单位 ≈ 1dp。
- 触摸控件最小高 **48** 单位（Android 48dp 标准）。
- 缩略图按钮 **72×72** 单位；容器间距 **8** 单位；安全区兜底最小边距 **16** 单位。
- 换装抽屉内容高 **312** 单位（原推导 296 有误：漏算 Drawer 自身 PanelContainer 的 content_margin，且标签栏/按钮行实测为 59/51 而非假设的 48）；缩略图网格 **4** 列。
- `Drawer` 必须用自有 StyleBox 覆盖全局 PanelContainer 样式：横向内边距 **0**（安全区已提供离屏边 16），纵向 **12**。否则 4×72+3×8=312 的网格放不进 328−32=296 的真实内宽。
- 换装相机 `fov = 35°`、`rotation = 0`、包围盒余量系数 `padding = 1.12`。
- `canvas_items` 只缩放 2D，3D 必须仍按屏幕原生分辨率渲染——任何改动不得改成 `viewport` 模式。
- 测试命令统一为 `tools/run_tests.sh [res://tests/子目录]`；退出码 0 且报告中 `orphans` 为 0 才算通过。
- 提交信息用中文 conventional commits，与既有历史一致。

---

### Task 1: 缩放配置与全局主题

把根因（缺 stretch 配置）和尺寸基线一次性落地。完成后真机上所有 UI 立刻放大 3×，按钮达到 48dp。

**Files:**
- Modify: `project.godot`（`[display]` 段、新增 `[gui]` 段）
- Create: `assets/ui/app_theme.tres`
- Test: `tests/ui/test_app_theme.gd`

**Interfaces:**
- Consumes: 无
- Produces: 项目设置 `display/window/stretch/mode = "canvas_items"`、`display/window/size/viewport_width = 360`、`display/window/size/viewport_height = 640`；主题资源路径常量 `res://assets/ui/app_theme.tres`，其 `Button` 默认字号 16、`Button` normal StyleBox 上下内容边距 14 / 左右 16。

- [ ] **Step 1: 写失败测试**

创建 `tests/ui/test_app_theme.gd`：

```gdscript
extends GdUnitTestSuite
## 守护缩放基准与主题尺寸基线：这两项一旦被改回默认值，真机 UI 会重新变得点不到。

const THEME_PATH := "res://assets/ui/app_theme.tres"

func test_stretch_settings_are_canvas_items_at_360x640() -> void:
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/mode"))).is_equal("canvas_items")
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/aspect"))).is_equal("expand")
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_width"))).is_equal(360)
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_height"))).is_equal(640)

func test_desktop_window_override_keeps_720x1280() -> void:
	assert_int(int(ProjectSettings.get_setting("display/window/size/window_width_override"))).is_equal(720)
	assert_int(int(ProjectSettings.get_setting("display/window/size/window_height_override"))).is_equal(1280)

func test_theme_is_registered_and_loads() -> void:
	assert_str(str(ProjectSettings.get_setting("gui/theme/custom"))).is_equal(THEME_PATH)
	assert_object(load(THEME_PATH)).is_not_null()

func test_button_reaches_48_unit_touch_target() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_object(theme).is_not_null()
	assert_int(theme.default_font_size).is_equal(16)
	var sb := theme.get_stylebox(&"normal", &"Button")
	assert_object(sb).is_not_null()
	# 16 号字约 19 单位高，上下各 14 → 约 47~48，达到 48dp 触摸标准
	assert_float(sb.content_margin_top).is_equal(14.0)
	assert_float(sb.content_margin_bottom).is_equal(14.0)
	assert_float(sb.content_margin_left).is_equal(16.0)
	assert_float(sb.content_margin_right).is_equal(16.0)

func test_container_separation_is_8() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_int(theme.get_constant(&"separation", &"HBoxContainer")).is_equal(8)
	assert_int(theme.get_constant(&"separation", &"VBoxContainer")).is_equal(8)
	assert_int(theme.get_constant(&"h_separation", &"GridContainer")).is_equal(8)
	assert_int(theme.get_constant(&"v_separation", &"GridContainer")).is_equal(8)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui`
Expected: FAIL —— 设置项返回空/默认值，`load(THEME_PATH)` 为 null。

- [ ] **Step 3: 改 `project.godot`**

`[display]` 段整体替换为：

```ini
[display]

window/size/viewport_width=360
window/size/viewport_height=640
window/size/window_width_override=720
window/size/window_height_override=1280
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=1
```

在 `[editor_plugins]` 之前插入新段：

```ini
[gui]

theme/custom="res://assets/ui/app_theme.tres"
```

- [ ] **Step 4: 创建 `assets/ui/app_theme.tres`**

```
[gd_resource type="Theme" load_steps=5 format=3]

[sub_resource type="StyleBoxFlat" id="SB_btn_normal"]
content_margin_left = 16.0
content_margin_top = 14.0
content_margin_right = 16.0
content_margin_bottom = 14.0
bg_color = Color(0.243137, 0.243137, 0.286275, 1)
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_right = 8
corner_radius_bottom_left = 8

[sub_resource type="StyleBoxFlat" id="SB_btn_pressed"]
content_margin_left = 16.0
content_margin_top = 14.0
content_margin_right = 16.0
content_margin_bottom = 14.0
bg_color = Color(0.376471, 0.376471, 0.443137, 1)
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_right = 8
corner_radius_bottom_left = 8

[sub_resource type="StyleBoxFlat" id="SB_btn_hover"]
content_margin_left = 16.0
content_margin_top = 14.0
content_margin_right = 16.0
content_margin_bottom = 14.0
bg_color = Color(0.305882, 0.305882, 0.360784, 1)
corner_radius_top_left = 8
corner_radius_top_right = 8
corner_radius_bottom_right = 8
corner_radius_bottom_left = 8

[sub_resource type="StyleBoxFlat" id="SB_panel"]
content_margin_left = 16.0
content_margin_top = 16.0
content_margin_right = 16.0
content_margin_bottom = 16.0
bg_color = Color(0.117647, 0.117647, 0.141176, 0.941176)
corner_radius_top_left = 16
corner_radius_top_right = 16

[resource]
default_font_size = 16
Button/font_sizes/font_size = 16
Button/styles/disabled = SubResource("SB_btn_normal")
Button/styles/focus = SubResource("SB_btn_hover")
Button/styles/hover = SubResource("SB_btn_hover")
Button/styles/normal = SubResource("SB_btn_normal")
Button/styles/pressed = SubResource("SB_btn_pressed")
GridContainer/constants/h_separation = 8
GridContainer/constants/v_separation = 8
HBoxContainer/constants/separation = 8
Label/font_sizes/font_size = 16
PanelContainer/styles/panel = SubResource("SB_panel")
VBoxContainer/constants/separation = 8
```

- [ ] **Step 5: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/ui`
Expected: PASS（5 个用例），orphans 0。

- [ ] **Step 6: 跑全量确认无回归**

Run: `tools/run_tests.sh`
Expected: PASS，orphans 0。基准分辨率变化不应影响任何既有用例；若 `tests/scenes` 或 `tests/integration` 失败，说明有用例隐式依赖了 720×1280，需在该用例中显式传入尺寸而非改回基准。

- [ ] **Step 7: 提交**

```bash
git add project.godot assets/ui/app_theme.tres tests/ui/test_app_theme.gd
git commit -m "fix(ui): 补齐 canvas_items 拉伸(基准 360x640)+全局主题，按钮达 48dp"
```

---

### Task 2: UIMetrics 纯计算层

安全区换算与取景数学全部集中于此，无节点依赖，可完全 headless 覆盖边界。

**Files:**
- Create: `modules/ui/ui_metrics.gd`
- Test: `tests/ui/test_ui_metrics.gd`

**Interfaces:**
- Consumes: 无
- Produces: `class_name UIMetrics`，四个静态函数：
  - `UIMetrics.safe_margins(safe_area: Rect2i, window_size: Vector2i, viewport_size: Vector2, min_margin: float) -> Vector4` 返回 (left, top, right, bottom) 视口单位
  - `UIMetrics.free_ratios(viewport_h: float, margin_top: float, margin_bottom: float, drawer_h: float) -> Vector2` 返回 (ratio, center_ratio)，无可用区时返回 `Vector2.ZERO`
  - `UIMetrics.frame_distance(subject: AABB, aspect: float, ratio: float, fov_deg: float, padding: float) -> float`
  - `UIMetrics.frame_v_offset(subject: AABB, ratio: float, center_ratio: float, padding: float) -> float`

- [ ] **Step 1: 写失败测试**

创建 `tests/ui/test_ui_metrics.gd`：

```gdscript
extends GdUnitTestSuite
## UIMetrics 纯函数边界覆盖。全部无节点依赖。

const VP := Vector2(360, 800)
const WIN := Vector2i(1080, 2400)

func test_safe_margins_converts_physical_insets_to_viewport_units() -> void:
	# 顶部 90px 刘海、底部 60px 手势条，换算系数 360/1080 = 1/3
	var safe := Rect2i(Vector2i(0, 90), Vector2i(1080, 2250))
	var m := UIMetrics.safe_margins(safe, WIN, VP, 16.0)
	assert_float(m.y).is_equal_approx(30.0, 0.01)   # 90/3
	assert_float(m.w).is_equal_approx(20.0, 0.01)   # (2400-2340)/3
	assert_float(m.x).is_equal_approx(16.0, 0.01)   # 实际 0，被 min_margin 抬到 16
	assert_float(m.z).is_equal_approx(16.0, 0.01)

func test_safe_margins_falls_back_to_min_when_no_inset() -> void:
	var safe := Rect2i(Vector2i.ZERO, WIN)
	var m := UIMetrics.safe_margins(safe, WIN, VP, 16.0)
	assert_float(m.x).is_equal_approx(16.0, 0.01)
	assert_float(m.y).is_equal_approx(16.0, 0.01)
	assert_float(m.z).is_equal_approx(16.0, 0.01)
	assert_float(m.w).is_equal_approx(16.0, 0.01)

func test_safe_margins_treats_empty_rect_as_full_window() -> void:
	# 系统未上报安全区时返回空矩形，不能因此算出整屏宽的右/下边距
	var m := UIMetrics.safe_margins(Rect2i(), WIN, VP, 16.0)
	assert_float(m.z).is_equal_approx(16.0, 0.01)
	assert_float(m.w).is_equal_approx(16.0, 0.01)

func test_safe_margins_handles_zero_window() -> void:
	var m := UIMetrics.safe_margins(Rect2i(), Vector2i.ZERO, VP, 16.0)
	assert_float(m.x).is_equal_approx(16.0, 0.01)
	assert_float(m.w).is_equal_approx(16.0, 0.01)

func test_free_ratios_typical_phone() -> void:
	# 视口 800 高，上下安全区各 24，抽屉 296 → 可用 456
	var r := UIMetrics.free_ratios(800.0, 24.0, 24.0, 296.0)
	assert_float(r.x).is_equal_approx(0.57, 0.01)
	assert_float(r.y).is_equal_approx(0.315, 0.01)

func test_free_ratios_returns_zero_when_drawer_eats_screen() -> void:
	assert_vector(UIMetrics.free_ratios(800.0, 24.0, 24.0, 800.0)).is_equal(Vector2.ZERO)
	assert_vector(UIMetrics.free_ratios(0.0, 16.0, 16.0, 296.0)).is_equal(Vector2.ZERO)

func test_frame_distance_uses_height_for_tall_subject() -> void:
	var subject := AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4))
	var d := UIMetrics.frame_distance(subject, 0.45, 0.57, 35.0, 1.12)
	# visible_h = 1.6*1.12/0.57 = 3.144; dist_h = 3.144/2/tan(17.5°) = 4.986
	assert_float(d).is_equal_approx(4.99, 0.05)

func test_frame_distance_switches_to_width_for_wide_subject() -> void:
	# 超宽挂件（路障帽）：宽度约束应压过高度约束
	var wide := AABB(Vector3(-1.5, 0.0, -0.2), Vector3(3.0, 1.6, 0.4))
	var tall := AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_distance(wide, 0.45, 0.57, 35.0, 1.12)) \
		.is_greater(UIMetrics.frame_distance(tall, 0.45, 0.57, 35.0, 1.12))

func test_frame_distance_guards_degenerate_input() -> void:
	var zero := AABB(Vector3.ZERO, Vector3.ZERO)
	assert_float(UIMetrics.frame_distance(zero, 0.45, 0.57, 35.0, 1.12)).is_equal(0.0)
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_distance(subject, 0.0, 0.57, 35.0, 1.12)).is_equal(0.0)
	assert_float(UIMetrics.frame_distance(subject, 0.45, 0.0, 35.0, 1.12)).is_equal(0.0)

func test_frame_v_offset_is_negative_to_raise_subject() -> void:
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	var v := UIMetrics.frame_v_offset(subject, 0.57, 0.315, 1.12)
	# visible_h = 3.144; v = -3.144*(0.5-0.315) = -0.582
	assert_float(v).is_equal_approx(-0.58, 0.02)
	assert_bool(v < 0.0).is_true()

func test_frame_v_offset_is_zero_when_centered() -> void:
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_v_offset(subject, 0.57, 0.5, 1.12)).is_equal_approx(0.0, 0.001)

func test_frame_v_offset_guards_degenerate_input() -> void:
	var zero := AABB(Vector3.ZERO, Vector3.ZERO)
	assert_float(UIMetrics.frame_v_offset(zero, 0.57, 0.315, 1.12)).is_equal(0.0)
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_v_offset(subject, 0.0, 0.315, 1.12)).is_equal(0.0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui`
Expected: FAIL —— `UIMetrics` 未定义（解析错误）。

- [ ] **Step 3: 实现 `modules/ui/ui_metrics.gd`**

```gdscript
class_name UIMetrics
extends RefCounted
## 移动端 UI 布局纯计算：安全区换算与相机取景数学。
## 不触碰节点与 DisplayServer，全部逻辑可 headless 单测。

## 系统安全区（物理像素）换算为视口单位的四边内缩 (left, top, right, bottom)。
## min_margin 是兜底：无刘海机型或桌面上系统上报整屏，此时仍需舒适边距。
static func safe_margins(
		safe_area: Rect2i,
		window_size: Vector2i,
		viewport_size: Vector2,
		min_margin: float) -> Vector4:
	if window_size.x <= 0 or window_size.y <= 0:
		return Vector4(min_margin, min_margin, min_margin, min_margin)
	var area := safe_area
	if area.size.x <= 0 or area.size.y <= 0:
		area = Rect2i(Vector2i.ZERO, window_size)  # 未上报 → 视作无内缩
	var s := viewport_size / Vector2(window_size)
	return Vector4(
		maxf(float(area.position.x) * s.x, min_margin),
		maxf(float(area.position.y) * s.y, min_margin),
		maxf(float(window_size.x - area.end.x) * s.x, min_margin),
		maxf(float(window_size.y - area.end.y) * s.y, min_margin))

## 角色可用区（安全区上边 → 抽屉顶边）在视口高中的占比与中心位置占比。
## 返回 (ratio, center_ratio)；无可用区返回 Vector2.ZERO，调用方据此跳过取景。
static func free_ratios(
		viewport_h: float,
		margin_top: float,
		margin_bottom: float,
		drawer_h: float) -> Vector2:
	if viewport_h <= 0.0:
		return Vector2.ZERO
	var free_top := margin_top
	var free_h := viewport_h - margin_bottom - drawer_h - free_top
	if free_h <= 0.0:
		return Vector2.ZERO
	return Vector2(free_h / viewport_h, (free_top + free_h * 0.5) / viewport_h)

## 让 subject 完整落入占比 ratio 的可用区所需的相机距离。
## fov_deg 为竖直视角（Godot 默认 keep_aspect=KEEP_HEIGHT）；aspect 为视口 宽/高。
## 取高度约束与宽度约束的较大值，宽挂件才不会被左右裁切。
static func frame_distance(
		subject: AABB,
		aspect: float,
		ratio: float,
		fov_deg: float,
		padding: float) -> float:
	if ratio <= 0.0 or aspect <= 0.0 or subject.size.y <= 0.0:
		return 0.0
	var half_tan := tan(deg_to_rad(fov_deg) * 0.5)
	if half_tan <= 0.0:
		return 0.0
	var dist_h := (subject.size.y * padding / ratio) * 0.5 / half_tan
	var dist_w := subject.size.x * padding * 0.5 / (half_tan * aspect)
	return maxf(dist_h, dist_w)

## 把 subject 中心从画面 50% 移到 center_ratio 所需的 Camera3D.v_offset。
## 注意 Godot 的 v_offset 是沿相机局部 Y 平移相机本身（见 Camera3D.get_camera_transform），
## 不是平移视锥；因此负值使被摄体在画面中上移，且不产生俯仰造成的梯形畸变。
static func frame_v_offset(
		subject: AABB,
		ratio: float,
		center_ratio: float,
		padding: float) -> float:
	if ratio <= 0.0 or subject.size.y <= 0.0:
		return 0.0
	return -(subject.size.y * padding / ratio) * (0.5 - center_ratio)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/ui`
Expected: PASS（Task 1 的 5 个 + 本任务 12 个），orphans 0。

- [ ] **Step 5: 提交**

```bash
git add modules/ui/ui_metrics.gd tests/ui/test_ui_metrics.gd
git commit -m "feat(ui): UIMetrics 纯计算层（安全区换算+取景距离/偏移）"
```

---

### Task 3: SafeAreaMargin 容器

两个场景共用的安全区容器。把 `DisplayServer` 取值与计算分离，`apply_margins` 可注入合成值直接测。

**Files:**
- Create: `modules/ui/safe_area_margin.gd`
- Test: `tests/ui/test_safe_area_margin.gd`

**Interfaces:**
- Consumes: `UIMetrics.safe_margins`
- Produces: `class_name SafeAreaMargin extends MarginContainer`
  - 导出属性 `min_margin: float`（默认 16.0）
  - `apply_margins(safe_area: Rect2i, window_size: Vector2i, viewport_size: Vector2) -> void` — 纯注入入口，供测试与 `refresh()` 调用
  - `refresh() -> void` — 从 `DisplayServer` 取真实值调用 `apply_margins`
  - 信号 `margins_applied(margins: Vector4)` — 供 `dressing_room.gd` 把实际边距喂给相机

- [ ] **Step 1: 写失败测试**

创建 `tests/ui/test_safe_area_margin.gd`：

```gdscript
extends GdUnitTestSuite
## SafeAreaMargin 是薄胶水：验证它把算出的边距真正写进 theme constant override 并广播信号。

func _make() -> SafeAreaMargin:
	var c := SafeAreaMargin.new()
	c.min_margin = 16.0
	add_child(auto_free(c))
	return c

func test_apply_margins_writes_theme_constant_overrides() -> void:
	var c := _make()
	c.apply_margins(Rect2i(Vector2i(0, 90), Vector2i(1080, 2250)), Vector2i(1080, 2400), Vector2(360, 800))
	assert_int(c.get_theme_constant(&"margin_top")).is_equal(30)
	assert_int(c.get_theme_constant(&"margin_bottom")).is_equal(20)
	assert_int(c.get_theme_constant(&"margin_left")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_right")).is_equal(16)

func test_apply_margins_emits_signal() -> void:
	var c := _make()
	var got: Array[Vector4] = []
	c.margins_applied.connect(func(m: Vector4): got.append(m))
	c.apply_margins(Rect2i(Vector2i.ZERO, Vector2i(1080, 2400)), Vector2i(1080, 2400), Vector2(360, 800))
	assert_int(got.size()).is_equal(1)
	assert_float(got[0].y).is_equal_approx(16.0, 0.01)

func test_apply_margins_never_goes_below_min() -> void:
	var c := _make()
	c.apply_margins(Rect2i(), Vector2i(1080, 2400), Vector2(360, 800))
	assert_int(c.get_theme_constant(&"margin_left")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_right")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_top")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_bottom")).is_equal(16)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/ui`
Expected: FAIL —— `SafeAreaMargin` 未定义。

- [ ] **Step 3: 实现 `modules/ui/safe_area_margin.gd`**

```gdscript
class_name SafeAreaMargin
extends MarginContainer
## 按系统安全区设置四边内缩（视口单位）。刘海、挖孔、手势条统一由系统上报值兜住；
## 系统未上报（桌面/老机型）时退回 min_margin，任何情况下都不贴边。

signal margins_applied(margins: Vector4)

@export var min_margin: float = 16.0

func _ready() -> void:
	refresh()
	get_tree().root.size_changed.connect(refresh)

func refresh() -> void:
	apply_margins(
		DisplayServer.get_display_safe_area(),
		DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size)

## 注入式入口：测试直接传合成值，不依赖真机 DisplayServer。
func apply_margins(safe_area: Rect2i, window_size: Vector2i, viewport_size: Vector2) -> void:
	var m := UIMetrics.safe_margins(safe_area, window_size, viewport_size, min_margin)
	add_theme_constant_override(&"margin_left", roundi(m.x))
	add_theme_constant_override(&"margin_top", roundi(m.y))
	add_theme_constant_override(&"margin_right", roundi(m.z))
	add_theme_constant_override(&"margin_bottom", roundi(m.w))
	margins_applied.emit(m)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/ui`
Expected: PASS，orphans 0。若报 orphan，检查 `_make()` 是否漏了 `auto_free`。

- [ ] **Step 5: 提交**

```bash
git add modules/ui/safe_area_margin.gd tests/ui/test_safe_area_margin.gd
git commit -m "feat(ui): SafeAreaMargin 安全区容器（含最小边距兜底）"
```

---

### Task 4: 换装房间底部抽屉布局

右侧 40% 竖条改为全宽底部抽屉；槽位标签可横滑；缩略图 4 列。

**Files:**
- Modify: `scenes/dressing_room/dressing_room.tscn`
- Modify: `scenes/dressing_room/dressing_room.gd`
- Modify: `scenes/dressing_room/parts_panel.gd`
- Test: `tests/scenes/test_dressing_room_layout.gd`

**Interfaces:**
- Consumes: `SafeAreaMargin`（Task 3）、主题（Task 1）
- Produces: 场景节点路径 `UI/SafeArea`（SafeAreaMargin）、`UI/SafeArea/VBox/Spacer`、`UI/SafeArea/VBox/Drawer`（PanelContainer，`custom_minimum_size.y = 312`）、`UI/SafeArea/VBox/Drawer/VBox`（parts_panel.gd）、`UI/SafeArea/VBox/Drawer/VBox/Buttons/{SaveButton,ResetButton,SceneButton}`；`parts_panel.gd` 常量 `THUMB_SIZE := Vector2(72, 72)`。

- [ ] **Step 1: 写失败测试**

创建 `tests/scenes/test_dressing_room_layout.gd`：

```gdscript
extends GdUnitTestSuite
## 布局回归：抽屉高度、网格列数、标签可横滚、角色区触摸穿透。
## 这四条任一退化都会直接复现"点不到/看不到"的线上问题。

const SCENE := "res://scenes/dressing_room/dressing_room.tscn"

func _instantiate() -> Node:
	var scene := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

func test_drawer_sits_at_bottom_with_expected_height() -> void:
	var s := _instantiate()
	var drawer := s.get_node("UI/SafeArea/VBox/Drawer") as PanelContainer
	assert_object(drawer).is_not_null()
	assert_float(drawer.custom_minimum_size.y).is_equal(312.0)

func test_spacer_passes_touches_through_for_rotation() -> void:
	var s := _instantiate()
	var spacer := s.get_node("UI/SafeArea/VBox/Spacer") as Control
	assert_object(spacer).is_not_null()
	# IGNORE 才能让 _unhandled_input 收到拖拽事件转动角色
	assert_int(spacer.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(spacer.size_flags_vertical).is_equal(Control.SIZE_EXPAND_FILL)

func test_parts_grid_has_four_columns() -> void:
	var s := _instantiate()
	var grid := s.get_node("UI/SafeArea/VBox/Drawer/VBox/PartsScroll/PartsGrid") as GridContainer
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(4)

func test_slot_tabs_are_horizontally_scrollable() -> void:
	var s := _instantiate()
	var scroll := s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll") as ScrollContainer
	assert_object(scroll).is_not_null()
	# 标签必须能横滑，否则槽位多时最后几个（如 glasses）溢出屏幕点不到
	assert_bool(scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED).is_true()
	assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_object(s.get_node("UI/SafeArea/VBox/Drawer/VBox/TabsScroll/SlotTabs")).is_not_null()

func test_action_buttons_share_width() -> void:
	var s := _instantiate()
	for name in ["SaveButton", "ResetButton", "SceneButton"]:
		var b := s.get_node("UI/SafeArea/VBox/Drawer/VBox/Buttons/" + name) as Button
		assert_object(b).is_not_null()
		assert_int(b.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: FAIL —— 节点路径 `UI/SafeArea/...` 不存在（旧结构是 `UI/Panel/VBox/...`）。

- [ ] **Step 3: 重写 `dressing_room.tscn` 的 UI 子树**

把 `[node name="UI" type="CanvasLayer" parent="."]` 起至文件末尾的全部节点替换为：

```
[node name="UI" type="CanvasLayer" parent="."]

[node name="SafeArea" type="MarginContainer" parent="UI"]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("3_safearea")

[node name="VBox" type="VBoxContainer" parent="UI/SafeArea"]
layout_mode = 2
mouse_filter = 2

[node name="Spacer" type="Control" parent="UI/SafeArea/VBox"]
layout_mode = 2
size_flags_vertical = 3
mouse_filter = 2

[node name="Drawer" type="PanelContainer" parent="UI/SafeArea/VBox"]
custom_minimum_size = Vector2(0, 312)
layout_mode = 2

[node name="VBox" type="VBoxContainer" parent="UI/SafeArea/VBox/Drawer"]
layout_mode = 2
script = ExtResource("2_parts")

[node name="TabsScroll" type="ScrollContainer" parent="UI/SafeArea/VBox/Drawer/VBox"]
custom_minimum_size = Vector2(0, 48)
layout_mode = 2
horizontal_scroll_mode = 2
vertical_scroll_mode = 0

[node name="SlotTabs" type="HBoxContainer" parent="UI/SafeArea/VBox/Drawer/VBox/TabsScroll"]
layout_mode = 2

[node name="PartsScroll" type="ScrollContainer" parent="UI/SafeArea/VBox/Drawer/VBox"]
layout_mode = 2
size_flags_vertical = 3
horizontal_scroll_mode = 0

[node name="PartsGrid" type="GridContainer" parent="UI/SafeArea/VBox/Drawer/VBox/PartsScroll"]
layout_mode = 2
size_flags_horizontal = 3
columns = 4

[node name="Buttons" type="HBoxContainer" parent="UI/SafeArea/VBox/Drawer/VBox"]
layout_mode = 2

[node name="SaveButton" type="Button" parent="UI/SafeArea/VBox/Drawer/VBox/Buttons"]
layout_mode = 2
size_flags_horizontal = 3
text = "保存"

[node name="ResetButton" type="Button" parent="UI/SafeArea/VBox/Drawer/VBox/Buttons"]
layout_mode = 2
size_flags_horizontal = 3
text = "重置"

[node name="SceneButton" type="Button" parent="UI/SafeArea/VBox/Drawer/VBox/Buttons"]
layout_mode = 2
size_flags_horizontal = 3
text = "压测场景"
```

并在文件头的 `[ext_resource]` 区加入（`load_steps` 相应 +1）：

```
[ext_resource type="Script" path="res://modules/ui/safe_area_margin.gd" id="3_safearea"]
```

注：`mouse_filter = 2` 即 `MOUSE_FILTER_IGNORE`，`horizontal_scroll_mode = 2` 即 `SCROLL_MODE_AUTO`，`vertical_scroll_mode = 0` 即 `SCROLL_MODE_DISABLED`。

- [ ] **Step 4: 更新 `dressing_room.gd` 的节点路径**

把 `_ready()` 中三处按钮连接与 `parts_panel` 的 `@onready` 路径改为新结构：

```gdscript
@onready var parts_panel = $UI/SafeArea/VBox/Drawer/VBox
```

```gdscript
	$UI/SafeArea/VBox/Drawer/VBox/Buttons/SaveButton.pressed.connect(_on_save)
	$UI/SafeArea/VBox/Drawer/VBox/Buttons/ResetButton.pressed.connect(_on_reset)
	$UI/SafeArea/VBox/Drawer/VBox/Buttons/SceneButton.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/stress_test/stress_test.tscn"))
```

- [ ] **Step 5: 更新 `parts_panel.gd` 的尺寸与节点路径**

顶部加常量，并把两处 `Vector2(96, 96)` 换成 `THUMB_SIZE`：

```gdscript
const THUMB_SIZE := Vector2(72, 72)  # 基准单位≈dp；1080 宽屏实际 216px
```

`@onready` 路径改为：

```gdscript
@onready var tabs: HBoxContainer = $TabsScroll/SlotTabs
@onready var grid: GridContainer = $PartsScroll/PartsGrid
```

`_show_slot()` 内 `none_btn.custom_minimum_size = Vector2(96, 96)` → `THUMB_SIZE`；
循环内 `b.custom_minimum_size = Vector2(96, 96)` → `THUMB_SIZE`。

- [ ] **Step 6: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: PASS（本任务 5 个 + 既有 `test_stress_spawn`），orphans 0。

- [ ] **Step 7: 跑全量确认无回归**

Run: `tools/run_tests.sh`
Expected: PASS，orphans 0。重点看 `tests/integration/test_dressing_flow.gd` 仍通过。

- [ ] **Step 8: 提交**

```bash
git add scenes/dressing_room/ tests/scenes/test_dressing_room_layout.gd
git commit -m "feat(ui): 换装房间改底部抽屉（全宽/标签横滚/4列缩略图/安全区）"
```

---

### Task 5: 换装相机自适应取景

FOV 35° 平透视 + 按包围盒算距离与 v_offset，戴高帽/宽挂件不裁切。

**Files:**
- Create: `scenes/dressing_room/dressing_camera.gd`
- Modify: `scenes/dressing_room/dressing_room.tscn`（Camera3D 挂脚本、设 fov）
- Modify: `scenes/dressing_room/dressing_room.gd`（接 `config_applied` 与 `margins_applied`）
- Test: `tests/scenes/test_dressing_camera.gd`

**Interfaces:**
- Consumes: `UIMetrics.free_ratios` / `frame_distance` / `frame_v_offset`（Task 2）、`SafeAreaMargin.margins_applied`（Task 3）
- Produces: `class_name DressingCamera extends Camera3D`
  - 常量 `FOV_DEG := 35.0`、`PADDING := 1.12`
  - 属性 `drawer_height: float`、`safe_margin_top: float`、`safe_margin_bottom: float`
  - `static func merged_aabb(root: Node3D) -> AABB`
  - `func reframe(subject_root: Node3D, viewport_size: Vector2) -> void`

- [ ] **Step 1: 写失败测试**

创建 `tests/scenes/test_dressing_camera.gd`：

```gdscript
extends GdUnitTestSuite
## 取景回归：包围盒合并正确、距离随高度/宽度增长、v_offset 把角色抬到上方可用区。

func _cam() -> DressingCamera:
	var c := DressingCamera.new()
	c.drawer_height = 312.0
	c.safe_margin_top = 24.0
	c.safe_margin_bottom = 24.0
	add_child(auto_free(c))
	return c

func _box(pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos + size * 0.5   # BoxMesh 以原点为中心
	return mi

func test_merged_aabb_unions_all_visual_children() -> void:
	var root := Node3D.new()
	add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	root.add_child(_box(Vector3(-0.5, 1.6, -0.5), Vector3(1.0, 0.5, 1.0)))  # 高帽子
	var box := DressingCamera.merged_aabb(root)
	assert_float(box.size.y).is_equal_approx(2.1, 0.01)
	assert_float(box.size.x).is_equal_approx(1.0, 0.01)

func test_merged_aabb_of_empty_root_is_degenerate() -> void:
	var root := Node3D.new()
	add_child(auto_free(root))
	assert_float(DressingCamera.merged_aabb(root).size.y).is_equal(0.0)

func test_reframe_sets_flat_perspective_and_no_rotation() -> void:
	var cam := _cam()
	var root := Node3D.new()
	add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	cam.reframe(root, Vector2(360, 800))
	assert_float(cam.fov).is_equal(35.0)
	assert_vector(cam.rotation).is_equal_approx(Vector3.ZERO, Vector3(0.001, 0.001, 0.001))
	assert_float(cam.position.z).is_greater(4.0)     # 拉远，透视变平
	assert_bool(cam.v_offset < 0.0).is_true()        # 负值把角色抬到画面上方

func test_reframe_pulls_back_further_for_tall_hat() -> void:
	var plain := Node3D.new(); add_child(auto_free(plain))
	plain.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	var hatted := Node3D.new(); add_child(auto_free(hatted))
	hatted.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	hatted.add_child(_box(Vector3(-0.5, 1.6, -0.5), Vector3(1.0, 0.6, 1.0)))
	var a := _cam(); a.reframe(plain, Vector2(360, 800))
	var b := _cam(); b.reframe(hatted, Vector2(360, 800))
	assert_float(b.position.z).is_greater(a.position.z)

func test_reframe_is_noop_for_empty_subject() -> void:
	var cam := _cam()
	cam.position = Vector3(1.0, 2.0, 3.0)
	var root := Node3D.new(); add_child(auto_free(root))
	cam.reframe(root, Vector2(360, 800))
	assert_vector(cam.position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3(0.001, 0.001, 0.001))

func test_reframe_is_noop_when_drawer_fills_screen() -> void:
	var cam := _cam()
	cam.drawer_height = 800.0
	cam.position = Vector3(1.0, 2.0, 3.0)
	var root := Node3D.new(); add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	cam.reframe(root, Vector2(360, 800))
	assert_vector(cam.position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3(0.001, 0.001, 0.001))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: FAIL —— `DressingCamera` 未定义。

- [ ] **Step 3: 实现 `scenes/dressing_room/dressing_camera.gd`**

```gdscript
class_name DressingCamera
extends Camera3D
## 换装房间相机：窄视角平透视 + 按角色包围盒自适应取景，
## 保证全身（含高帽、宽挂件）完整落在抽屉之上的可用区内。

const FOV_DEG := 35.0    # 现状 75° 默认值透视过强（头大脚小）
const PADDING := 1.12    # 包围盒四周留白系数

var drawer_height: float = 312.0
var safe_margin_top: float = 16.0
var safe_margin_bottom: float = 16.0

func _ready() -> void:
	fov = FOV_DEG
	rotation = Vector3.ZERO

## 合并 root 子树内所有可见 VisualInstance3D 的全局包围盒。
## 子树为空或全不可见时返回 size 为 0 的退化 AABB，调用方据此跳过取景。
static func merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for node in _visuals(root):
		var box := node.get_global_transform() * node.get_aabb()
		if found:
			out = out.merge(box)
		else:
			out = box
			found = true
	return out

static func _visuals(node: Node) -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	var vi := node as VisualInstance3D
	if vi and vi.is_visible_in_tree():
		result.append(vi)
	for c in node.get_children():
		result.append_array(_visuals(c))
	return result

## 重新取景。viewport_size 由调用方传入而非内部取，便于 headless 测试。
func reframe(subject_root: Node3D, viewport_size: Vector2) -> void:
	var subject := merged_aabb(subject_root)
	if subject.size.y <= 0.0:
		return
	var ratios := UIMetrics.free_ratios(
		viewport_size.y, safe_margin_top, safe_margin_bottom, drawer_height)
	if ratios.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var dist := UIMetrics.frame_distance(
		subject, viewport_size.x / viewport_size.y, ratios.x, FOV_DEG, PADDING)
	if dist <= 0.0:
		return
	var center := subject.position + subject.size * 0.5
	fov = FOV_DEG
	rotation = Vector3.ZERO
	position = Vector3(center.x, center.y, center.z + dist)
	v_offset = UIMetrics.frame_v_offset(subject, ratios.x, ratios.y, PADDING)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: PASS，orphans 0。

- [ ] **Step 5: 在场景中挂载相机脚本**

`dressing_room.tscn` 的 Camera3D 节点替换为：

```
[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.8, 5.5)
fov = 35.0
script = ExtResource("4_dresscam")
```

（删掉原来的 `position`/`rotation_degrees`。保留一个合理的初始位姿只是为了首帧不穿模——
真正的取景由 `reframe()` 在运行时覆盖；`rotation` 必须为 0。）
`[ext_resource]` 区加入（`load_steps` 再 +1）：

```
[ext_resource type="Script" path="res://scenes/dressing_room/dressing_camera.gd" id="4_dresscam"]
```

- [ ] **Step 6: 在 `dressing_room.gd` 中接线**

顶部 `@onready` 区加入：

```gdscript
@onready var cam: DressingCamera = $Camera3D
@onready var safe_area: SafeAreaMargin = $UI/SafeArea
@onready var drawer: PanelContainer = $UI/SafeArea/VBox/Drawer
```

`_ready()` 内，把取景连接放在**已有那句 `rig.config_applied.connect(...)` 的紧邻下一行**
（即 `rig.apply_config(...)` 之前）：

```gdscript
	rig.config_applied.connect(func(_c): _reframe())
```

再在 `parts_panel.setup(rig)` 之前加入安全区接线：

```gdscript
	safe_area.margins_applied.connect(func(m: Vector4):
		cam.safe_margin_top = m.y
		cam.safe_margin_bottom = m.w
		_reframe())
	# Godot 中子节点 _ready() 先于父节点执行，SafeArea 的首发 margins_applied
	# 在此之前就已发出（本仓库 6fd571a 踩过同类时序坑）。这里主动补一次 refresh，
	# 让相机拿到真实安全区，而不是停在默认的 16。
	safe_area.refresh()
```

文件末尾加入：

```gdscript
func _reframe() -> void:
	# 等一帧让装配后的网格与骨骼姿态落定，否则包围盒可能仍是上一套部件的
	await get_tree().process_frame
	if not is_instance_valid(rig) or not is_instance_valid(cam):
		return
	var h := drawer.size.y if drawer.size.y > 0.0 else drawer.custom_minimum_size.y
	cam.drawer_height = h
	cam.reframe(rig, get_viewport().get_visible_rect().size)
```

- [ ] **Step 7: 跑全量确认无回归**

Run: `tools/run_tests.sh`
Expected: PASS，orphans 0。

- [ ] **Step 8: 提交**

```bash
git add scenes/dressing_room/ tests/scenes/test_dressing_camera.gd
git commit -m "feat(ui): 换装相机 FOV 35 平透视 + 按包围盒自适应取景"
```

---

### Task 6: 压测 HUD 安全区适配

本次范围内 HUD 只做最小适配：套安全区、滑条可拖。不重排布局。

**Files:**
- Modify: `scenes/stress_test/stress_test.tscn`
- Modify: `scenes/stress_test/stress_test.gd`（节点路径）
- Test: `tests/scenes/test_stress_hud_layout.gd`

**Interfaces:**
- Consumes: `SafeAreaMargin`（Task 3）、主题（Task 1）
- Produces: 节点路径 `HUD/SafeArea/VBox/{StatsLabel,CountSlider,StrategyButton,SceneButton}`

- [ ] **Step 1: 写失败测试**

创建 `tests/scenes/test_stress_hud_layout.gd`：

```gdscript
extends GdUnitTestSuite
## HUD 回归：不再零边距贴边（压状态栏），滑条高度达到可拖尺寸。

const SCENE := "res://scenes/stress_test/stress_test.tscn"

func _instantiate() -> Node:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		return null
	var scene := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

func test_hud_is_wrapped_in_safe_area() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	assert_object(s.get_node("HUD/SafeArea") as SafeAreaMargin).is_not_null()
	assert_object(s.get_node("HUD/SafeArea/VBox")).is_not_null()

func test_slider_is_tall_enough_to_drag() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	var slider := s.get_node("HUD/SafeArea/VBox/CountSlider") as HSlider
	assert_object(slider).is_not_null()
	assert_float(slider.custom_minimum_size.y).is_greater_equal(48.0)
	assert_int(slider.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: FAIL —— `HUD/SafeArea` 不存在（旧结构为 `HUD/VBox`）。

- [ ] **Step 3: 改 `stress_test.tscn` 的 HUD 子树**

把 `[node name="HUD" ...]` 之后的 UI 节点替换为：

```
[node name="HUD" type="CanvasLayer" parent="."]

[node name="SafeArea" type="MarginContainer" parent="HUD"]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("3_safearea")

[node name="VBox" type="VBoxContainer" parent="HUD/SafeArea"]
layout_mode = 2
size_flags_vertical = 0

[node name="StatsLabel" type="Label" parent="HUD/SafeArea/VBox"]
layout_mode = 2
text = "角色: 0  策略: merged
FPS: 0  帧时: 0.00ms
DrawCalls: 0
显存: 0.0MB"

[node name="CountSlider" type="HSlider" parent="HUD/SafeArea/VBox"]
custom_minimum_size = Vector2(0, 48)
layout_mode = 2
size_flags_horizontal = 3
min_value = 1.0
max_value = 20.0
step = 1.0
value = 10.0

[node name="StrategyButton" type="Button" parent="HUD/SafeArea/VBox"]
layout_mode = 2
text = "策略: merged"

[node name="SceneButton" type="Button" parent="HUD/SafeArea/VBox"]
layout_mode = 2
text = "换装房间"
```

`[ext_resource]` 区加入（`load_steps` +1）：

```
[ext_resource type="Script" path="res://modules/ui/safe_area_margin.gd" id="3_safearea"]
```

- [ ] **Step 4: 更新 `stress_test.gd` 节点路径**

```gdscript
@onready var stats: Label = $HUD/SafeArea/VBox/StatsLabel
@onready var slider: HSlider = $HUD/SafeArea/VBox/CountSlider
@onready var strategy_btn: Button = $HUD/SafeArea/VBox/StrategyButton
```

`_ready()` 内：

```gdscript
	$HUD/SafeArea/VBox/SceneButton.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/dressing_room/dressing_room.tscn"))
```

- [ ] **Step 5: 跑测试确认通过**

Run: `tools/run_tests.sh res://tests/scenes`
Expected: PASS，orphans 0。既有 `test_stress_spawn.gd` 也须仍通过（它只用 `Rigs` 路径，不受 HUD 改动影响）。

- [ ] **Step 6: 提交**

```bash
git add scenes/stress_test/ tests/scenes/test_stress_hud_layout.gd
git commit -m "fix(stress): HUD 套安全区不再压状态栏 + 滑条加高到可拖"
```

---

### Task 7: 全量回归与文档更新

**Files:**
- Modify: `docs/mobile_export.md`（真机走查步骤补 UI 验收项）
- Modify: `README.md`（目录结构补 `modules/ui/`）

**Interfaces:**
- Consumes: Task 1–6 全部产出
- Produces: 无代码接口

- [ ] **Step 1: 跑全量测试**

Run: `tools/run_tests.sh`
Expected: PASS，orphans 0。若有失败，先修再继续——本步骤是后续真机验收的前置门槛。

- [ ] **Step 2: 两场景 headless 冒烟**

```bash
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
"$GODOT_BIN" --headless --path . --quit-after 120 res://scenes/dressing_room/dressing_room.tscn
"$GODOT_BIN" --headless --path . --quit-after 120 res://scenes/stress_test/stress_test.tscn
```

Expected: 两条命令退出码均为 0，stderr 无 `ERROR:` / `SCRIPT ERROR:`。

- [ ] **Step 3: 更新 `docs/mobile_export.md`**

在「## 4. 真机验收步骤」的步骤 2 之后插入新的一步（原步骤 3 起顺延）：

```markdown
3. **UI 走查**（本次缩放/安全区改动的验收项，逐条确认）：
   - 换装房间底部「保存 / 重置 / 压测场景」三个按钮都能一次点中，不需要瞄准；
   - 槽位标签栏可以横向滑动，能滑到最后一个槽位（如 `glasses`）并点中；
   - 角色全身（含头顶）完整可见，不被底部抽屉遮挡；换上高帽子类部件后相机自动拉远，
     头顶仍不被裁切；
   - 在角色区域拖动仍能转动角色，在抽屉区域滑动只滚动列表、不转动角色；
   - 切到压测场景后 HUD 不压住状态栏/刘海，数量滑条能正常拖动。
```

- [ ] **Step 4: 更新 `README.md` 目录结构**

在 `modules/avatar/` 段之后、`assets/avatar/` 之前插入：

```
modules/ui/                移动端 UI 基建（与 avatar 模块无耦合）
  ui_metrics.gd              纯计算：安全区换算、取景距离/偏移（无节点依赖，全覆盖单测）
  safe_area_margin.gd        SafeAreaMargin：按系统安全区设四边内缩，含最小边距兜底
```

并在「## 跑测试」小节后补一句：

```markdown
UI 相关用例在 `tests/ui`（纯函数与容器）与 `tests/scenes`（场景布局回归），
两者都不依赖转换产物之外的资源，可单独跑：`tools/run_tests.sh res://tests/ui`。
```

- [ ] **Step 5: 提交**

```bash
git add docs/mobile_export.md README.md
git commit -m "docs: UI 缩放改动的真机走查项与 modules/ui 目录说明"
```

- [ ] **Step 6: 真机验收（人工，需用户执行）**

按 `docs/mobile_export.md` 导出 APK 装机，逐条走查 Step 3 中新增的 5 项。此步骤无法自动化，
完成后把结果反馈给用户；若某项不通过，优先怀疑：安全区上报值（打印 `DisplayServer.get_display_safe_area()`）、
蒙皮网格 AABB 是否为绑定姿势（spec 第 5 节风险备忘，退回用 `Skeleton3D` 骨骼位置求并集）。

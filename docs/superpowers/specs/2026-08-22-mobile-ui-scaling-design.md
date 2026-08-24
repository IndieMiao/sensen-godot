# 移动端 UI 缩放、安全区与换装取景

日期：2026-08-22 · 已获用户批准

## 问题

Android 真机上 UI 极小、按钮贴屏幕边缘几乎点不到（用户实测截图）。

根因：`project.godot` 缺 `display/window/stretch/*`，Godot 4 默认 `disabled`，视口即屏幕物理像素。1080×2400 机型上 UI 按 1:1 物理像素绘制、字体仍是默认 16px。`viewport_width=720` 只作用于桌面窗口，对真机无效。

叠加三个次因：

1. 无 theme、无安全区处理（全项目未调用过 `DisplayServer.get_display_safe_area()`）；
2. 换装面板 `anchor_left=0.6` 仅 40% 宽（720 基准下 288px），而 3 列 × 96px 缩略图需 296px，必然溢出；槽位标签用裸 `HBoxContainer`，不换行不滚动，`glass` 溢出屏幕；
3. 换装房间底部按钮行与压测 HUD 的 `offset 12,12` 均为零边距贴边，落在手势条/状态栏区域。

用户追加要求：换装房间相机透视不要太大，需要看到角色全身。现状 FOV 75°（默认）、距离 2.2m，头顶已被裁切。

## 方案

### 1. 缩放层

`[display]` 段：

```ini
window/size/viewport_width=360
window/size/viewport_height=640
window/size/window_width_override=720
window/size/window_height_override=1280
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

基准 360×640 使 1 基准单位 ≈ 1dp（1080 宽屏缩放 3.0×），尺寸数值可直接对照 Android 规范书写。`expand` 下 20:9 屏视口为 **360×800**，多出高度补在下方不裁剪。`canvas_items` 只缩放 2D，3D 仍按屏幕原生分辨率渲染，无画质损失。`window_*_override` 保持桌面窗口 720×1280 不变。

否决：保持 720 基准靠 theme 写大（尺寸数值失去 dp 含义，易写错）；运行时按 DPI 算 `content_scale_factor`（部分安卓机 DPI 上报不准，需额外限幅兜底）。

### 2. 主题

新建 `assets/ui/app_theme.tres`，`[gui] theme/custom` 注册。基准单位即 dp：

| 项 | 值 | 1080 宽屏实际 |
|---|---|---|
| 默认字号 | 16 | 48px |
| Button StyleBox 上下内容边距 | 14 | — |
| → 由此得到的 Button 高 | ≈48 | ≈144px（达 Android 48dp 触摸标准） |
| 槽位标签按钮左右内容边距 | 16 | 48px |
| 缩略图按钮 | 72 × 72 | 216px |
| 容器间距 | 8 | 24px |

注意 theme 无「最小尺寸」属性，控件高度由字号 + StyleBox 内容边距推导（16 号字约 19 高 + 上下各 14 ≈ 48）。需要精确 48 的控件（如滑条）另设 `custom_minimum_size`。

`parts_panel.gd` 中硬编码的 `Vector2(96, 96)` 改为 `72`：96 是旧 720 基准值（真机 144px），72 是新基准值（真机 216px），实际增大 50%。

### 3. 安全区

新建 `modules/ui/safe_area_margin.gd`（`MarginContainer` 子类），两场景共用：

- 读 `DisplayServer.get_display_safe_area()`（物理像素）；
- 换算系数 = 视口尺寸 / `DisplayServer.window_get_size()`；
- 四边内缩 = 安全区插入值 × 换算系数，与最小值 16 取大，经 `add_theme_constant_override` 写入 `margin_*`；
- 监听 `get_tree().root.size_changed` 重新应用。

系统上报 0（桌面、老机型）时退回固定 16 单位边距，任何情况下不贴边。

### 4. 换装房间布局（底部抽屉）

```
UI (CanvasLayer)
└── SafeArea (MarginContainer + safe_area_margin.gd, 满屏)
    └── VBox
        ├── Spacer (Control, size_flags_vertical=3, mouse_filter=IGNORE)
        └── Drawer (PanelContainer, custom_minimum_size.y=312)
            └── VBox (parts_panel.gd)
                ├── TabsScroll (ScrollContainer, 仅横向) → SlotTabs (HBoxContainer)
                ├── PartsScroll (ScrollContainer, 竖向) → PartsGrid (columns=4)
                └── Buttons (HBoxContainer, 三按钮 size_flags_horizontal=3 均分)
```

- Spacer 设 `mouse_filter=IGNORE`，现有 `_unhandled_input` 拖拽转身在角色区照常生效；Drawer 保持默认 `STOP`，抽屉内滑动选部件不会误触发转身。**Spacer 本身是 IGNORE 还不够**——`SafeArea` 和它直属的 `VBox` 这两层祖先容器也必须显式设成 `mouse_filter=IGNORE`，否则默认 `STOP` 会在事件传到 Spacer 之前就把整个全屏容器的触摸事件吞掉，导致角色区完全无法拖拽转身（此前一版实现踩过这个坑，且当时的测试只断言了 Spacer 自己，对此完全失明）。
- 标签栏套横向 `ScrollContainer`，解决槽位标签溢出（如 `glass` 一类靠后的槽位滑不到）。
- **`Drawer` 必须用自有 StyleBoxFlat 覆盖全局主题的 `PanelContainer` 内容边距**：横向 `content_margin = 0`（安全区已经提供了离屏边 16，不需要 Drawer 再加一层），纵向 `content_margin = 12`（上下各 12）。若不这样做，`Drawer` 会继承全局主题的默认内边距，把 4×72+3×8=312 的网格挤出可用内宽（见下方宽度账）。
- 高度账（视口 360×800，安全区上下各按 24 估，实测数值）：`Drawer/VBox` 内三个子项纵向堆叠——标签栏 `TabsScroll` 实测高 **59**（非主题默认的 48，`ScrollContainer` 按内部 `SlotTabs` 按钮的实际内容撑高）+ 容器间距 8 + 缩略图区 `PartsScroll`（`size_flags_vertical=3` 撑满剩余空间）+ 容器间距 8 + 按钮行 `Buttons` 实测高 **51**（非 48）；`VBox` 内容合计 **288**，加上 `Drawer` 自身 StyleBox 的纵向内边距 12+12=**24**，抽屉总高 = 288 + 24 = **312**（原推导 296 是按主题名义高度 48/48 估算标签栏与按钮行、且内边距笼统假设 32 算出的，两处都偏离实测值）。抽屉连同下安全区占 312+24=336（视口的 42%）；角色可用区 = 800 − 24 − 312 − 24 = **440**（≈55%），即第 5 节 `ratio` 的典型值。安全区插入值随机型变化，故取景按实际值计算而非写死。
- 宽度账：360 − 左右安全区 16×2 = 328。**原推导到此止步、直接断言 `328 ≥ 312` 可以容纳 4×72+3×8=312 的网格，但漏算了 `Drawer` 自身的内边距**：`PanelContainer` 默认继承全局主题的 `SB_panel` 样式，其 `content_margin_left/right` 均为 16（见第 2 节主题表），会再吃掉 328 − 32 = **296** 的可用内宽——296 < 312，网格放不下，`PartsScroll` 又不能横向滚动，于是把整个 `Drawer` 顶宽、挤没右侧安全边距，这正是本任务修的原始 Critical 缺陷。修复方式是给 `Drawer` 挂一个自有 `StyleBoxFlat`（横向 `content_margin=0`、纵向 `content_margin=12`，见上一条约束），使其可用内宽恢复到 328 ≥ 312，网格才放得下。

否决：可收起抽屉（多一层状态 + Tween + 相机插值，换装场景需要边点边看，收起价值低）；半透明浮层（换鞋/裤子时下半身被面板遮挡）。

### 5. 相机自适应取景

`fov = 35°`、`rotation = 0`。距离与垂直偏移在 `config_applied` 后按角色包围盒计算：

**必须同时监听 `config_applied` 和 `slot_applied` 两个信号。** `config_applied` 只在进场首次装配完成时发出一次（`avatar_rig.gd:124-126`，`_initial_loading` 为真的那个分支）；之后任何一次换装——包括点击缩略图触发的 `equip()`/`unequip()`——都只发 `slot_applied`，不再发 `config_applied`。若只连前者，进场取景一次之后相机就再也不会重新取景，戴上更高的帽子会直接切头顶，直接违反"能看到角色全身"这条验收项。

可用区不写死 0.6，而是由实际布局反推——上边界是安全区上插入值（避开刘海），下边界是抽屉顶边：

```
subject      = 角色全局 AABB × 1.12 余量
free_top     = 安全区上插入值                     # 单位，避开刘海/状态栏
free_bottom  = 视口高 - 安全区下插入值 - 抽屉高    # 抽屉顶边
free_h       = free_bottom - free_top
ratio        = free_h / 视口高                    # 360×800 典型值 ≈ 0.55（抽屉 312 时）
center_ratio = (free_top + free_h * 0.5) / 视口高

visible_h = subject.y / ratio
dist_h    = visible_h * 0.5 / tan(fov/2)
dist_w    = subject.x * 0.5 / (tan(fov/2) * 视口宽高比)
dist      = max(dist_h, dist_w)
v_offset  = -visible_h * (0.5 - center_ratio)     # 角色中心由画面 50% 移到 center_ratio
```

`ratio`/`center_ratio` 与安全区、抽屉高度同源，任一变化取景自动跟随，不会出现头顶压在刘海下的情况。`fov` 为竖直视角（Godot 默认 `keep_aspect = KEEP_HEIGHT`），故 `dist_w` 需再除以视口宽高比（宽/高）。

1.6m 角色算得 dist ≈ 6.1m，前后 0.3m 深度尺寸差约 5%（现状 2.2m 距离为 14%），满足"透视不要太大"。`dist_w` 分支保证宽挂件（如压测场景那顶路障帽）不被左右裁切。

**`v_offset` 语义**：Godot 的 `Camera3D.v_offset` 沿相机局部 Y 轴**平移相机**（见 `get_camera_transform()`），不是平移视锥。因此不产生俯仰造成的梯形畸变，代价是约 13° 的轻微仰视——对全身立绘属可接受且显腿长，故采用；不使用旋转俯角，那会让头大脚小。

**风险**：Godot 蒙皮网格 `MeshInstance3D.get_aabb()` 可能返回绑定姿势而非当前姿势的包围盒。若实测取景不准，退回用 `Skeleton3D` 各骨骼全局位置求并集 + 固定余量。

否决：固定参数写死（为容纳高帽子需预留大余量，普通发型时角色显小）；正交投影（角色扁平无立体感，且与压测场景透视相机观感不一致）。

### 6. 压测 HUD

本次范围为「缩放 + 安全区 + 换装底部抽屉」，压测 HUD 只做最小适配，不重排布局：

- `HUD/VBox` 套同一 SafeArea，移除 `offset_left/top = 12` 贴边；
- 尺寸由主题自动带上；
- `CountSlider.custom_minimum_size` 由 `(220, 0)` 改为 `(0, 48)` 并横向撑满——否则滑条高度仍是默认值，依旧难拖。

## 验证口径

- 现有 gdUnit4 全量测试无回归；
- **新增单测**：取景计算与安全区换算均为纯函数（输入包围盒/视口尺寸/抽屉占比 → 输出距离、偏移、边距），覆盖边界：零高度包围盒（应跳过取景而非除零）、安全区为 0（退回 16 边距，`ratio` 相应变大）、超宽包围盒触发 `dist_w` 分支、极端宽高比、抽屉高度接近视口高时 `ratio` 趋近 0 的下限保护。与既有 spec「不为一行胶水加单测」不冲突——那条针对 `change_scene_to_file` 一类无逻辑胶水，本节是有分支的数值计算；
- 两场景 headless 冒烟；
- 真机走查：三个底部按钮均可一次点中、槽位标签可横滑至 `glass`、戴高帽子自动拉远且不切头顶、切至压测场景 HUD 不压状态栏、滑条可正常拖动。

## 改动清单

| 文件 | 改动 |
|---|---|
| `project.godot` | `[display]` 缩放配置 + `[gui] theme/custom` |
| `assets/ui/app_theme.tres` | 新建 |
| `modules/ui/safe_area_margin.gd` | 新建 |
| `scenes/dressing_room/dressing_room.tscn` | UI 子树重排为底部抽屉 + 相机 fov |
| `scenes/dressing_room/dressing_room.gd` | 自适应取景 + 节点路径更新 |
| `scenes/dressing_room/parts_panel.gd` | 4 列 + 标签横滚 + 尺寸常量 |
| `scenes/stress_test/stress_test.tscn` | HUD 套安全区 + 滑条尺寸 |
| `tests/` | 取景与安全区换算单测 |

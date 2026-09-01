# UI 优化交接（2026-09-01）

写给接手 UI 工作的人/agent。假设你没有先前的会话上下文。
配套：`2026-09-01-internal-demo-handoff.md`（整体验收）、`2026-09-01-internal-demo-avatar-map-design.md`（设计）。

---

## 1. UI 目前长什么样、由什么决定

三个场景：`scenes/map_poc/`（地图）、`scenes/dressing_room/`（换装房）、`scenes/stress_test/`（压测）。

| 文件 | 作用 |
|---|---|
| `modules/ui/design_tokens.gd` | 色板 / 4dp 间距栅格 / 圆角三档 / 字阶五档 / 触摸内边距的**唯一取值来源** |
| `assets/ui/app_theme.tres` | 工程级主题，取值引用上面的 token 语义 |
| `modules/ui/safe_area_margin.gd` | 安全区（刘海/挖孔）内边距，支持注入式测试入口 |
| `modules/ui/ui_metrics.gd` | 取景距离等度量换算 |

方向是决策者在三选一里选定的 **B「薄荷绿体系化」**：主色 `#34D399`、按下 `#059669`、圆角 22（抽屉）/14（卡片）/21（胶囊）。

**注意 `design_tokens.gd` 的 docstring 写了准确边界**：阴影、表面 alpha、滚动条颜色、chip/pill 的内边距**没有** token，仍散在主题里。改风格时"只改这两个文件就够"成立，但"每个值都有名字"不成立。

---

## 2. 不能碰的东西（都有测试守着，破了会红）

### 2.1 48dp 触摸目标 — `tests/ui/test_app_theme.gd`
`Button` stylebox 的 `content_margin_top/bottom = 14`、`left/right = 16`，`default_font_size = 16`。
这是真机上"按钮点得到"的下限，历史上踩过。

**副作用值得知道**：这个 16 的内边距会包在图标外面。一个 64px 图标的按钮最小宽会变成 96 而不是你设的 72 —— 4 列网格因此撑破安全区（见 §3.3）。

### 2.2 五个类型变体必须存在
`AccentButton`、`AccentPillButton`、`PillButton`、`RoundButton`、`ChipPanel`。
删任意一个，对应场景会**静默**回退成默认灰按钮（不报错）。

### 2.3 缩放基准
`canvas_items` + `expand`，viewport 360x640，桌面 override 720x1280。1 单位 ≈ 1dp。

### 2.4 移动端列表滚动：PASS 冒泡 + 全局死区 24
换装房的部件列表能滑动，靠的是 ScrollContainer 里的 Button 设 `mouse_filter = MOUSE_FILTER_PASS`。
默认的 `STOP` 会把按压截断在按钮上，ScrollContainer 收不到就永远不开始拖拽跟踪
（引擎 `NOTIFICATION_SCROLL_BEGIN` 机制：按压起跟踪、越死区后广播通知取消子按钮按压）。
短按=点击、划动=滚动，由全局滚动死区 24 仲裁。

**这套是踩过坑定下来的，不要"顺手改成 STOP 更规范"。** `parts_panel.gd` 里每处 `mouse_filter` 都有注释。

### 2.5 颜色必须写 6 位小数 — `tests/ui/test_design_tokens.gd`
主题里的颜色是 hex/255 的精确展开。3 位小数的误差（7.8e-5 ~ 4.5e-4）超过 Godot
`is_equal_approx` 对 ≤1 数值的 `CMP_EPSILON ≈ 1e-5`，token 与主题的比对断言会失败。
例：`#34d399` → `Color(0.203922, 0.827451, 0.6, 1)`。

### 2.6 地图 Environment 的 `background_mode` 必须是 0 — `tests/scenes/test_character_lighting_parity.gd`
`0` = CLEAR_COLOR。用 `1`（COLOR）会画一层实色**盖掉底下的 Mapbox 地图**，
G1/G3 那套透明合成（`viewport.transparent_bg` + 插件的 `setZOrderMediaOverlay`）就废了。

### 2.7 两个场景的角色打光必须一致 — 同上测试
`ambient_light_source = 2`（COLOR，显式颜色）、`ambient_light_color`、`ambient_light_energy`、
平行光 `light_energy`、`shadow_enabled` 五项在地图与换装房之间必须相同。

**为什么用显式颜色而不是默认的 BG**：Godot 默认 `ambient_light_source = BG`，
即环境光取自背景色 —— 那样"改背景颜色会连带改角色打光"，两件事本不该耦合。
历史现场：地图场景**根本没有 WorldEnvironment**（环境光=0，角色背光面纯黑），
换装房则是 0.9 白背景 × 0.6 叠平行光 1.2（过曝）。

---

## 3. 已知待优化项（按价值排序）

### 3.1 marker 图钉和 HUD 圆钮长得一样
两者都用 `RoundButton` 变体、都是白色圆形 —— **地图内容与操作控件视觉上分不开**。
`scenes/map_poc/marker_layer.gd` 的 `_build()` 里设的 `theme_type_variation = &"RoundButton"`。
建议给 marker 单独一个变体（比如带小尖角的气泡钉），与控件明确区分。

### 3.2 marker 全挤在上半屏、被状态芯片压住
`scenes/map_poc/demo_markers.json` 的偏移量 north 最大只有 +80m，在 `pitch = 45°` 下
全落在上半屏，而定位芯片正在那儿 —— 气泡会被屏幕上边缘切掉。
两条路：改偏移分布（要保持"相对锚点的米偏移"这个约束，别写死经纬度，见 §4.2），
或把芯片挪走。这项要看着屏幕调。

### 3.3 部件按钮暂时不显示缩略图
`scenes/dressing_room/parts_panel.gd` 的 `SHOW_THUMBNAILS = false`。
原因：`assets/avatar/thumbs/` 下 25 张缩略图是**同一张** 64×64 / 168 字节占位图
（管线缺口，`tools/pipeline/extract_parts.gd` 的 `_write_thumb` 对所有部件都没解析到真实图），
信息量为零；而 §2.1 那个 16 内边距会把每格最小宽顶到 96，4 列撑破安全区。
现在改为只显示 part id 文案。

管线能产出真实缩略图后：把常量改 `true`、同步放宽格子尺寸、**重跑
`tests/scenes/test_dressing_room_layout.gd` 的 `test_drawer_does_not_overflow_safe_area_on_four_part_slot`**
（它就是守这条的，会告诉你有没有撑破）。

### 3.4 换装房背板是占位
`dressing_room.tscn` 的 `Backdrop`：30×30 无光照四边形 @ z=-6，纯 0.9 灰。
参考版（森森正式版）是个真实房间：粉色墙 + 沙发。相机固定沿 -Z 看、`reframe` 只改距离，
所以静态背板足够，可直接替换成美术资产。

### 3.5 尚未纳入 token 的取值
阴影（色/尺寸/偏移）、表面 alpha（0.94/0.96/0.97）、`SB_round_pressed`/`SB_pill_pressed`
的独立灰、滚动条 grabber 色、`SB_chip`/`SB_pill*` 的内边距。

---

## 4. 会让你白花时间的坑

### 4.1 Activity 级窗口透明 —— GDScript 管不到
`project.godot` 里 `window/per_pixel_transparency/allowed=true`，Godot 导出时因此给 Android
Activity 套了 translucent 主题（logcat 可见 `isTopActivityTransparent=true`）。地图需要它
（Mapbox 从插件的 FrameLayout 透上来），但它是**窗口属性**：

- `Viewport.transparent_bg = false` **不能**撤销它（实测：真机日志确认标志确实是 false，画面照样透）
- `DisplayServer.window_set_flag(WINDOW_FLAG_TRANSPARENT, false)` **也不能**（实测：代码执行了，背景像素毫无变化）

**结论：除地图之外的任何场景，想要不透底就得自己有实体背板**（见 §3.4）。
不要再去和引擎较劲，这条已经花过两轮验证。

### 4.2 演示内容坐标必须相对锚点，不能写死经纬度
角色和 marker 都相对 `map_poc.gd` 的 `home_lat/home_lng` 存储（marker 存米偏移）。
写死经纬度的后果：用户定位到任何非上海人民广场的位置，内容全部落在
`CULL_FACTOR = 4.0 × 相机距离` 之外被剔除 —— 地图上空无一人。
`tests/map/test_map_home_anchoring.gd` 会抓这条（锚在东京断言内容仍在可见范围）。

洛杉矶那 10 个角色是**跨洋剔除/浮动原点的压测夹具**，保持绝对坐标，别改。

### 4.3 切换场景瞬间的截图不可信
`change_scene_to_file` 过程中截屏会拍到首帧之前的状态：桌面透上来、HUD 重复出现、
HUD 读数全 0。**重拍一张再下结论**，本轮为此误判过两次。

### 4.4 Godot 4.7.2 的类型推断
`var x := <动态成员访问>` 解析失败。测试里读 `n.center_lng`、`n._spawn_queue.size()`
这类要显式标类型：`var lng0: float = n.center_lng`。本轮三个任务先后踩过。

### 4.5 `.uid` 文件受版本控制
仓库里有 527 个。新增任何 `.gd` 都要把伴生 `.uid` 一起提交，否则 Godot 会重新生成造成漂移。

---

## 5. 怎么快速验证 UI 改动

**本地渲帧（最快，不需要设备、不需要构建、不需要 macOS 录屏权限）：**

```bash
godot --path . --write-movie /tmp/shot.png --resolution 540x1170 \
      res://scenes/dressing_room/dressing_room.tscn --quit-after 90
# 看最后一帧 /tmp/shot00000089.png
```

`--quit-after` 别设太短，异步加载没落地会有退出竞态的假报错。

**真机（需要 USB 调试授权）：**

```bash
godot --headless --path . --export-debug "Android" build/x.apk
adb install -r build/x.apk
adb shell am force-stop com.sensen.avatarphase1
adb shell am start -n com.sensen.avatarphase1/com.godot.game.GodotAppLauncher
adb exec-out screencap -p > /tmp/dev.png      # 设备侧截图，不受 macOS 权限限制
adb shell input tap <x> <y>                    # 坐标按 1080x2344 原图算
```

地图的调试读数：点"我的位置"那个芯片会展开一行工程数据（相机同步、可见角色数、
惯性峰值/当前值、Mapbox 回读）。

**测试：**

```bash
tools/run_tests.sh                              # Godot，175 用例
tools/run_tests.sh res://tests/ui               # 只跑 UI
cd tools/unity_export && .venv/bin/python -m pytest tests -q   # 必须在这个目录跑
```

Python 那 5 个既有测试依赖 cwd 在 `tools/unity_export/`（靠同级目录导入），
从仓库根跑会报 `ModuleNotFoundError`，不是回归。

---

## 6. 一句话状态

已合入 `main`（merge `3a8937e`），Godot 175/175、Python 18/18，Android 真机验过阻断链。
UI 层面「不统一」的硬问题（场景里残留的旧配色、两种绿）已经修完；剩下的是 §3 那批
需要审美判断的优化，以及 §3.3 依赖管线补齐缩略图。

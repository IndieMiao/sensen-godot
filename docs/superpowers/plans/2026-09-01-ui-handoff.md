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

---

# 追加：2026-09-02 视觉整改（侧栏统一 + 编辑页瘦身）

全程**无真机**完成，靠 §7.1 的本地预览宿主取景验证。Godot 220/220。

## 7. 无真机怎么看 UI —— `tools/dev/ui_preview.tscn`

§5 那条直接渲场景的命令有个坑：`SafeAreaMargin` 读的是
`DisplayServer.get_display_safe_area()`，在桌面上拿到的是**宿主显示器**的可用区
（MacBook 自己的摄像头缺口），再按窗口/视口比例换算，得到的边距既不对称也远大于
真机——截图右侧会被切掉，和真机对不上。`test_dressing_room_layout.gd:310` 那段注释
说的是同一件事。

预览宿主用 `SafeAreaMargin.apply_margins()` 这个注入口把安全区按帧压成确定值：

```bash
godot --path . --write-movie /tmp/s.png tools/dev/ui_preview.tscn \
      --quit-after 200 -- res://scenes/dressing_room/dressing_room.tscn notch shoes
# 看最后一帧 /tmp/s00000199.png
```

- 参数 2：`notch`（默认，上 44 下 28 左右 16）/ `flat`（四边 16 = 可用宽度最坏情况）
- 参数 3：仅换装房，直接预览指定槽位（`shoes` 这种部件多的槽最容易暴露文案截断）
- `--quit-after` 给够帧数；换装房挑槽位要 ≥200（首次装配等 `config_applied`）

**注意：`godot --headless --import` 会卡在 adb 探测上不退出**（logcat 里是
`cannot connect to daemon at tcp:5037`）。要么后台跑再 kill，要么直接忽略——
`tools/run_tests.sh` 里那句有 `|| true` 兜底。

## 8. 改了什么

### 8.1 地图侧栏：四种控件 → 一种方块

改之前是 `CheckButton`（自带拨杆）+ 胶囊 `RoundButton` + 圆角矩形 `SecondaryButton`
+ 正圆 `RoundButton`，三种宽度（72/72/72/48），右边缘参差不齐——地图上并排看是四个
互不相干的东西。

现在统一成 `RailButton`：56×56 同款方块、图标在上 + 12 号文案在下、同一套
表面/圆角 16/阴影。侧栏宽度 72 → 56（marker 可用横向空间 +16），顺序改成
`3D / Rotate / LA / Edit`（两个相机控件相邻）。

- `3D/2D` 从 `CheckButton` 换成 `toggle_mode = true` 的普通 `Button`：保留
  `button_pressed` 语义，去掉那根拨杆。选中态直接用 variation 的 `pressed` 样式
  （薄荷底 + 主色描边），不需要在代码里换 variation。
- 双态按钮（3D/2D、LA/Nearby）**图标和文案一起换**——小字号下只换文案几乎看不出来。

### 8.2 换装房：顶栏卡片拆掉，Done 移到右上角

- 顶栏原本是整条 `TopPanel` 白卡片 + 两个 80 宽文字按钮 + 18 号标题。现在是浮在
  3D 场景上的透明 `HBoxContainer`：左边返回圆形图标钮，右边 Done（96×48）。
  标题去掉（进来就看得见角色，不需要再说一遍）。
- `TopBar` 与其中的 `Spacer` 必须是 `MOUSE_FILTER_IGNORE`，否则这条 48 单位高的
  空白会吞掉转身拖拽。父容器 IGNORE 时子按钮仍参与命中测试是引擎行为，
  `test_top_bar_actions_are_really_tappable_not_just_present` 用真实 rect 中心
  派发一次触摸把这条钉住（做过变异验证：把 Done 自己设成 IGNORE 该用例即红）。
- `Reset` 从顶栏挪到抽屉页脚，与 `Selected: …` 同一行：它作用于选择结果，放在
  提交按钮旁边既容易误触，也让顶栏退回三个控件。用 `SecondaryButton` 而不是
  `GhostButton`——旁边就是灰色说明文字，透明按钮会被读成一段文案而不是控件。
- 抽屉 `custom_minimum_size.y` **312 → 268**，角色可视高度约 +20%。
  部件列表现在是「2 行 + 露出第 3 行一角」，露出的半行就是可滚动的提示。

### 8.3 主题新增（`app_theme.tres`）

| 新增 | 说明 |
|---|---|
| `RailButton` | 侧栏方块。`normal`/`hover` 同一张；`pressed` = 薄荷底激活态 |
| `RailButton/styles/hover_pressed` | **不能省**：Android 抬手后保留 hover，toggle 按住态没显式定义会回落到引擎默认灰 |
| `Button/colors/icon_*_color` | 全套设成墨色。**图标 SVG 是白色描边**，靠这几项乘法调制；删掉就回落成引擎默认的纯白 = 在白色 rail 上完全看不见，且不报错 |
| `Button/constants/icon_max_width = 22` | 图标按 4x 栅格化（96px 纹理）保清晰，用这个收口到 22 单位 |

`tests/ui/test_app_theme.gd` 新增两条守这些：图标色不能是白、`hover_pressed` 必须存在。

### 8.4 图标：`assets/ui/icons/*.svg`

7 个 24×24 白色描边图标（`view_3d` `view_2d` `travel` `pin` `avatar` `rotate` `back`）。

- **必须是白色**：Godot 的 `icon_*_color` 是乘法调制，黑色图标乘任何颜色还是黑色，
  没法按状态染色。
- `.import` 里 `svg/scale=4.0` + `mipmaps/generate=true`：纹理 96px，缩到 22 单位
  不糊也不摩尔纹。新增图标记得一起改这两项，并把 `.import` 一起提交。

### 8.5 顺带修的

`parts_panel.gd` 的 `PART_LABELS`：两列格子每格内宽约 132 单位，14 号字约 18 字符
就被 `clip_text` 截断（真机上是 `Black Teal Runne`）。已把两条超长的改短，
**新增文案控制在 16 字符内**。

## 8.6 第二轮（同日，真机反馈后）

### marker 不再是「红色感叹号」
`demo_markers.json` 里是别人留下的**留言**（"今天云不错"、"楼下新出桂花拿铁"），
而珊瑚底 + 近黑 `!` 在地图上读起来是警告徽标，语义正好反了。
换成白色留言气泡字形（`assets/ui/icons/note.svg`）。

珊瑚色**没动**——`test_marker_uses_non_accent_signal_color` 守着"marker 不能是薄荷绿"，
为的是地图内容和界面控件视觉可分。换字形之后同样的珊瑚就从"警报"变成了"有人留言"。
`test_marker_layer.gd` 加了一条断言禁止它退回 `Label`。

### 侧栏：Edit 置顶、去掉 Rotate、文案移到按钮外
- 每项从"图标+文字都在按钮里"改成 `VBoxContainer{ 纯图标方块 52×52 , 文案 }`，
  文案压在地图上，靠 `RailCaption` 变体的 4px 白描边保证可读（实测压在角色身上仍清晰）。
- ⚠️ **纯图标按钮必须显式写 `icon_alignment = 1`**：`Button.icon_alignment` 的默认值是
  `LEFT`，有 text 时被文字撑着看不出来，去掉文案后三个图标会一起贴到左内边距上
  （真机上肉眼可见地偏左）。`vertical_icon_alignment` 同理要回到 `CENTER`——之前为了
  "图标在上文字在下"设成了 `TOP`。这两条现在由
  `test_side_rail_is_uniform_tiles_with_captions_outside_the_button` 守着。
- 顺序：`Edit / 3D / LA`，Edit 置顶。
- Rotate 移除。**`bearing` 变量保留**——它仍要参与相机推导并喂给 Mapbox（spec §5.3），
  只是恒为 0；`_set_bearing` 已删（无调用方）。
  `test_rotate_control_is_gone_and_bearing_has_no_mutator` 防止有人加回 setter 却不接 UI。

### 换装房相机：固定参考盒，比例恒定
原来每次 `slot_applied` 都按 `merged_aabb(rig)` 重算距离，于是**换个发型角色就忽大忽小**
（实测 `hairhat0` 1.721m → `hairhat101` 1.971m，差 14%），转身时包围盒宽度变化还会让画面左右呼吸。

现在对着 `DressingCamera.reference_box()` 这个与装扮无关的固定盒取景：

| 常量 | 值 | 说明 |
|---|---|---|
| `REF_HEIGHT` | 1.80 | 按**身体**定，不含高发型余量 |
| `HEAD_OVERFLOW` | 0.25 | 高发型允许向上溢出的量，落在顶栏那条透明带子里 |
| `PADDING` | 1.02 | 参考盒固定了，不再需要给动态包围盒兜底（原 1.12） |
| `EYE_LIFT` | 0.04 | 机位上抬占可用区比例，视线从腰腹抬到胸口 |

**为什么 REF_HEIGHT 不取最高的 1.971**：那样短发角色要连带缩小 15%，头顶空出一大块死区
（试过，很难看）。改成按身体取景、让超出的发型向上溢出到顶栏——顶栏是透明的、只在左右
两端有控件，中间正好留给头发。

⚠️ `position.y` 与 `v_offset` 是**同一个自由度**（`v_offset` 平移的是相机本身），
所以"抬机位"只能通过 `EYE_LIFT` 表达；改 `position.y` 会被 `v_offset` 原样抵消，画面纹丝不动。

`dressing_room.gd` 不再把 `slot_applied` 连到 `_reframe()`（布局变化仍会重新取景）。
测试相应反转：`test_equip_taller_part_keeps_the_character_the_same_size`、
`test_reframe_scale_is_identical_regardless_of_equipment` / `..._body_rotation`。

### 顺带发现：APK 被打进了 12MB 无关图片

改完图标居中重新导出，APK 从 124.8MB 涨到 136.6MB。查下来与 UI 改动无关：

仓库根有个 `output/`（15MB 的概念图/审计图，没有任何代码引用）。导出预设是
`export_filter="all_resources"`——**只要 Godot 导入过的资源就会被打包**，而
`exclude_filter` 当时没有 `output/*`。本轮为了导入 SVG 图标跑了几次
`godot --headless --import`（`tools/run_tests.sh` 里也有一句），把这些 PNG 一并
导入成 `.ctex`，于是全进了包。

已在两个预设（Android/iOS）的 `exclude_filter` 里补上 `output/*` 与 `.playwright-mcp/*`。

**教训**：`all_resources` + 仓库里随手放的图片目录 = 悄悄变大的包。新增任何生成物
目录都要同步加进 `exclude_filter`；`.gitignore` 拦不住它，Godot 看的是文件系统。
（`output/`、`.playwright-mcp/`、`artifacts/` 目前都未被 git 跟踪也未被 ignore，
要不要一起 gitignore 由仓库主人定。）

## 8.7 第三轮：分区取景 + 编辑页瘦身

### 切分类推近对应部位（zoom in / 何时 zoom out）

`DressingCamera` 增加 `Region { FULL, HEAD, TORSO, FEET }`，`region_for_slot()` 把
分类映射过去，切标签时补间推近（`FOCUS_TWEEN_S = 0.35`，CUBIC/EASE_OUT）。

**每个分区都是固定盒**，和 FULL 一样与所装部件无关——所以"换发型不改变比例"在
每一档里依然成立，变的只有档位本身。`test_region_zoom_keeps_scale_constant_within_a_level`
对四个档位逐一守这条。

**zoom out 的三个入口**（这是设计上真正要想清楚的部分）：

| 时机 | 行为 | 理由 |
|---|---|---|
| 进场 | 恒为 FULL | 先建立"这是我的角色"，不能一进来就是个大头 |
| 点角色 | FULL ↔ 当前分区 来回切 | 选完想看整体效果的显式手势 |
| 再点一次 | 回到该分类的分区 | 对称，不需要重新切标签 |

**刻意没做"停顿 N 秒自动缩回"**：用户逐个试发型时，镜头会在每次选择之间来回抽动。
显式手势可预期得多。要做也应该是"选定后长时间无操作"，而不是"每次选择后"。

点角色的判定：`_track_drag` 累计**路径长度**（不是首尾直线距离——转出去再转回来
首尾重合但显然是拖拽），松手时 ≤ `TAP_SLOP = 12` 才算点击。

⚠️ **分区盒必须保持"高瘦"**：`UIMetrics.frame_distance` 取 max(高约束, 宽约束)，
而 `frame_v_offset` 是按被摄体正好填满 ratio 推的。一旦宽度成为约束项（矮而宽的盒子
在 0.46 的竖屏视口下很容易触发），被摄体填不满 ratio，v_offset 就会把它整体推偏上。
TORSO/FEET 的宽度就是为此收窄的。要改宽先把 `frame_v_offset` 一起改对。

### 编辑页继续瘦身

- 删掉 `Selected: X` 整行（48 单位）。它说的三件事都已有更直接的表达：选中项有薄荷
  描边、角色身上已经穿着、忙碌态 Done 显示 "Trying on..."。
- `Reset` 回到顶栏，做成与返回同款的图标圆钮——它作用于**整套装扮**，本来就不属于
  某个分类，放在分类面板里是错的。顶栏成了「圆·圆 … 胶囊」，两端各自形状统一。
- Done 从 `AccentButton`（radius 8 矩形）改成 `AccentPillButton`（radius 24 胶囊，
  字号 15）。顺带把 `AccentPillButton` 修成名副其实的胶囊——它此前叫 Pill 但用的是
  radius 8 的方角样式，且全项目无人使用。
- 抽屉 **268 → 208** = 32 内边距 + 48 标签行 + 8 间距 + 120 列表区。120 是权衡出来的：
  4 件的槽位（2 行 = 104）只剩 16 余量，6 件的槽位（3 行 = 160）正好露出 16 当作
  "可滚动"提示。

### 两条建议实施时被我否掉了

- **选中态改白底**（原 P3）：本意是让"当前选中"和"提交"不再同色。但真做出来发现
  薄荷浅底在一堆灰底芯片里是主要的可辨识信号，改成白底反而更难扫。改用**形状**
  区分：Done 是胶囊，选中项是圆角矩形。
- **抽屉贴底**（原 P4）：单看抽屉确实该贴底，但整页是"浮在 3D 场景上的悬浮元素"
  这一套语言（顶栏也是浮的）。只把抽屉锚死会破坏一致性，而底部那 21 单位是手势条
  安全区，本来就该让开。

## 8.8 第四轮：部件缩略图（运行时渲）

`modules/avatar/thumbs/part_thumbnailer.gd`：离屏 `SubViewport` 逐个渲部件、按
part_id 缓存。选项格子从 2 列纯文字改成 **3 列 图＋文案**。

**为什么不用 `assets/avatar/thumbs/`**：那 25 张是同一张 64×64 / 168 字节占位图
（§3.3），信息量为零；等管线补齐要排期，而"不试穿就知道长什么样"是这页最缺的一环。

### 几个关键点

- **材质不用额外处理**：管线在 `extract_parts` 阶段就把 `AvatarMaterialFactory`
  造好的材质烘进了 `.res`，单独实例化一个部件就带着正确外观。
- **必须 `own_world_3d = true`**：否则会把宿主场景（角色、背板、地图）一起拍进来。
- **光照与换装房刻意一致**（环境光显式取色 0.3 白 + 平行光 1.0 + filmic）：
  缩略图和穿在身上的颜色对不上就失去参考意义，同 §2.7 的道理。
- **串行渲染 + `_slot_generation` 代际号**：共用一个 SubViewport，且快速连点分类时
  要丢弃上一批的异步结果，否则会把上个分类的图贴到新按钮上。
- **`free()` 不能写成 `queue_free()`**：渲完立刻回收是安全的，而延迟回收会在用例
  结束时被 gdUnit 记成 orphan node，跑测直接非零退出（踩过）。
- **socket 类部件**是 PackedScene（带 manifest 偏移），**mesh 类**是裸 Mesh，没有
  Skeleton3D 会以绑定姿势渲出来——所以 `Amethyst Set` 这类蒙皮衣服的袖子会略微张开。
  做缩略图够用，要更好看得在渲染时挂一个临时骨架摆姿势。

### ⚠️ 格子高度是量出来的，不是算出来的

`THUMB_CELL_HEIGHT = 98`。**Button 的最小尺寸参考纹理原始尺寸**
（`RENDER_SIZE = 160`），主题的 `icon_max_width = 52` 只约束绘制宽度、不参与最小
尺寸计算。所以"52 图 + 文案 + 内边距 = 80"这个推算是错的，实测 98。

于是抽屉 **208 → 292** = 32 内边距 + 48 标签行 + 8 间距 + 204（2 行 × 98 + 8）。
3 列 × 2 行 = 6 格，正好装下部件最多的槽位（shoes 6 件、glass 5+无 = 6），
**所有分类都不需要滚动**。

> 2026-09-02 追记：部件池换代后 hairHat / cloth / shoes **三个槽位都恰好是 6 件**，
> glass 仍是 5+无 = 6。也就是说 6 格已经用满，**再往 `samples.json` 加任何一件都会
> 让那个分类开始滚动**。要扩池就得先重新权衡抽屉高度或列数。

保留 160px 高分辨率纹理是有意的：真机 3x 密度下 52 单位需要 156px，降采样到 104
会发虚。代价就是抽屉高了 84 单位。
`test_thumbnail_cell_height_matches_the_drawer_budget` 会在有人改
`RENDER_SIZE` / 字号 / `icon_max_width` 时报红，提示重新量并同步调抽屉。

### 顺带修的文案错误

缩略图一上就暴露了两个名字对不上实物的：
`glass4` "Peach Square" 其实是**星形**墨镜 → "Star Shades"；
`shoes3` "Teal Runners" 其实是**黑色**靴子 → "Black Runners"。

## 9. 这轮没做的

- §3.2（marker 全挤在上半屏）没动：需要对着真地图调偏移分布，本地预览没有 Mapbox 底图。
- §3.3 缩略图仍等管线；§3.4 背板仍是占位灰。
- §3.5 那批未纳入 token 的取值只多不少——`SB_rail`/`SB_rail_active` 的内边距、
  阴影同样是散值。要收敛就一起收。

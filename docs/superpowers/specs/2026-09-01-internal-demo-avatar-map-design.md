# 内部 Demo（2026-09-04 周五）范围设计：avatar + 地图端到端

日期：2026-09-01（周二）
状态：已与决策者逐节确认，待实施
上游背景：[3D 地图方案A](2026-08-25-3dmap-mapbox-research.md)、[avatar 一期](2026-08-21-avatar-godot-design.md)、[海外版重构调研](2026-08-30-overseas-refactor-research.md)

---

## 1. 背景与优先级变更

与合伙人对齐后短期目标收敛：**avatar 模块与地图模块优先**，作为本周五（2026-09-04）的内部目标；
原 PoC 路线里的 **G3 收尾（iOS 桥正式化 / 导出链正规化）与 G4（性能矩阵）优先级下调**，本周不做。

这条变更的直接后果是：Plane 上 SGODOT-3 下几条 high 优先级的"正式化/量化"任务本周让位给"能演示的功能"。
优先级同步见 §8。

## 2. 交付物与验收口径

**交付物**：一个可装机的 Android APK，外加一个 iOS 包（**除定位外**跑通同一条链，iOS 用默认位置）。
决策者拿到 Android 包能自己点完这条链，无需讲解：

> 打开 App → 落在自己真实位置 → 周围有别人的角色和几条留言气泡 →
> 拖拽/双击地图，手感带惯性 → 点进换装房换一身 → 回地图，自己的角色已经变了

不接受"分模块各自截图"或"演示视频代替装机"——验收口径是**端到端可上手**。

## 3. 预算

可用：周二剩余 + 周三 + 周四 + 周五上午 ≈ **3.5 个工作日**（单人）。

| # | 工作项 | 估时（天） |
|---|---|---|
| ① | 换装闭环回写地图 | 0.4 |
| ② | avatar 部件池整理 | 0.25 |
| ③ | Android 定位 | 0.6 |
| ④ | Marker/气泡 | 0.5 |
| ⑤ | 手势惯性 + 双击缩放 | 0.25 |
| ⑥ | UI design token 重铸 | 0.5 |
| — | iOS 重建 + 双端装机验收 | 0.5 |
| | **合计 3.0，缓冲 0.5** | |

## 4. 明确不做（防止实施期临时加回）

- ❌ 搜索地名 / Mapbox Geocoding —— 现有"飞洛杉矶"按钮已能演示飞行动画，投入产出最低
- ❌ 水晶族专用 shader、材质对齐 Unity 的全量对比矩阵（Plane SGODOT-1 / SGODOT-2 / 水晶 shader 子任务）
- ❌ Marker 热度分级、相机聚焦编排、他人角色实时数据（全部假数据）
- ❌ iOS 桥迁 GDExtension、iOS/Android 导出链正规化、G4 性能矩阵、G2 撕裂量化
- ❌ 后台定位、GCJ-02 坐标系（仅海外发行前提未变）

## 5. 实施期已确认的事实（省去重查）

实施前查证过、与直觉相反的三条，写在这里避免重踩：

1. **`tier` 字段不是付费等级**。它是手工在 `tools/unity_export/samples.json` 标注的复杂度标记；
   `tools/pipeline/extract_parts.gd:172` 里 `tier == 1` 的语义是"保留 AnimationPlayer"。
   **不能用 tier 筛选"付费高级部件"。**
2. **转换管线不记录 Unity 侧材质族名**。`tools/unity_export/parts.py:88` 只抽 albedo / ao / floats，
   没有 shader 或材质名字段。所以无法用元数据自动识别"水晶族"，只能目视筛 + 白名单。
3. **场景切换是整场景重建**（`scenes/map_poc/map_poc.gd:261` 用 `change_scene_to_file`），
   回地图必然重跑 `_ready → _spawn_pawns`。所以"换装后返回要刷新"**不需要额外机制**。

当前部件目录只迁移了 **15 个**：hairHat 4、cloth 4、shoes 2、glass 2、body / eyes / messengerBag 各 1。

## 6. 各工作项设计

### ① 换装闭环回写地图（0.4 天）

**问题**：`scenes/map_poc/map_poc.gd:333` 里"我"这个 pawn 写死 `Avatar.slot_table.default_config()`，
不读换装房存的档，闭环是断的。

**改法**：
- 改读 `Avatar.load_outfit()`，**null 时回落 `default_config()`**
  （`modules/avatar/persistence/outfit_store.gd` 无存档返回 null，`tests/persistence/test_outfit_store.gd:25` 已覆盖该行为）
- 区分"自己"（`_pawns[0]`）与另外 22 个随机配置的路人 pawn
- 不做刷新机制（见 §5.3）

**验收**：换装房换上装 → 保存 → 返回地图，`_pawns[0]` 外观已更新。

### ② avatar 部件池整理（0.25 天）

**背景**：效果差的是原 App 里的付费高级部件（材质复杂，统一 toon shader 下呈平面色）。
本周不做专用 shader，改为**从 demo 可选集合里剔除，用普通部件替代**。

**改法**：
- 先出一个基线 APK，**逐部件截图后由决策者确认剔除名单**——无法用元数据自动识别（见 §5.2），
  也不由实施者单方面判定"难看"
- 数据驱动过滤：`assets/avatar/parts_manifest.json` 每条加可选 `hidden` 布尔字段
  → `modules/avatar/catalog/part_catalog.gd` 的 `AvatarPartMeta` 加同名字段
  → `parts_for_slot()` 过滤。约 15 行，不碰 shader、不碰管线逻辑
- 补池：`tools/unity_export/samples.json` 加 8-10 个普通部件，跑 `convert.py` + `extract_parts.gd`

**风险**：补部件可能撞上美术命名漂移（`T_xxx_D 1.png` 副本尾巴、`bag ≠ messengerBag`），
需要 `tools/unity_export/overrides.json` 定点兜底。这是本项唯一的不确定性。

### ③ Android 定位（0.6 天）

**现状**：地图起点钉死上海人民广场（`map_poc.gd` 的 `START_LAT` / `START_LNG`）；Godot 无内置定位 API。

**改法**：
- 插件骨架现成——`tools/android/overlay/GodotMapPlugin.kt` 已有 `getPluginSignals()` /
  `@UsedByGodot` / `emitSignal` 全套，照现有 `map_ready` 信号加 `SignalInfo("location_update", ...)`
- **优先路径**：订阅 Mapbox v11 自带的 location provider（`mapView.location`），省掉 Play Services 依赖
  —— 先花 30 分钟验证能否回传经纬度
- **退路**：AOSP `LocationManager`，零额外依赖
- 运行时权限用 Godot 内置 `OS.request_permission("android.permission.ACCESS_FINE_LOCATION")`，
  不写 Kotlin 权限流；`ACCESS_FINE_LOCATION` 加进 overlay 的 `AndroidManifest.xml`
- `scenes/map_poc/map_bridge.gd` 加 `signal location_update(lat, lng, accuracy)` + `start_location()`；
  **iOS 实现空转返回默认位置**，保持接口一致（不破坏 MapBridge 抽象层）
- 拿到首个定位 → `_teleport()` + 把自己的 pawn 钉过去；拿不到就留在上海默认点

**保留约束**：插件信号必须 `CONNECT_DEFERRED`；`MapboxMap` 是 `@MainThread` API，读状态走 UI 线程缓存。

### ④ Marker / 气泡（0.5 天）

**数据**：`scenes/map_poc/demo_markers.json` 假数据（lat / lng / text / author），
接口形状对齐 Unity 的 `QueryNewMapMarkerReponse`。

**渲染**：Godot Control 层。`MapGeoMath.geo_to_world` → `Camera3D.unproject_position` 投屏，
跟 pawn 同一个 `_reposition_pawns` 节奏更新，出屏隐藏。

**交互**：点图钉展开气泡，再点收起。不做聚焦动画、不做热度分级。

### ⑤ 手势惯性 + 双击缩放（0.25 天）

**问题**：`map_poc.gd` 的 `_unhandled_input` 里 `InputEventScreenDrag` 直接 `_apply_world_delta`，
**抬手即停**，没有惯性，手感不丝滑。

**改法**：
- 拖拽时用 EMA 记录 world delta 速度；`InputEventScreenTouch` 松手进入 fling 态；
  `_process` 里指数衰减继续 `_apply_world_delta`，低于阈值停止；任何新触摸立即打断
- 双击检测（300ms 内两次）→ `_set_zoom(zoom + 1)` 走 Tween 平滑变焦，不瞬变

**⚠️ 硬约束**：现有"PASS 冒泡 + 全局死区 24"的移动端列表滚动机制是踩过坑定下来的（引擎
`NOTIFICATION_SCROLL_BEGIN` 机制），fling 实现**不得回退或破坏它**。靠现有 110 用例回归兜底。

### ⑥ UI design token 重铸（0.5 天）

**方向**：延续现有薄荷绿，但把散落取值收成体系（三选一中选定的方向 B）。

- 新增 `modules/ui/design_tokens.gd` 常量表：色板 / 4dp 间距栅格 / 圆角三档 / 字阶五档 / 阴影
- 重写 `assets/ui/app_theme.tres`，全部 StyleBox 与字体引用语义 token
- 取值：主色 `#34D399`、深色 `#059669`、圆角 22（抽屉）/ 14（卡片）/ 胶囊（按钮）
- 应用面：map_poc 的 HUD 与定位芯片、dressing_room 的抽屉与部件格、④ 新增的 marker 气泡
- **下周设计会要推翻，只需改 `design_tokens.gd` + `app_theme.tres` 两个文件**

排期上放在 ④ 之前，让气泡直接用 token，避免返工。

### iOS 重建（0.5 天）

重跑 `tools/ios/setup_ios_g3.sh` + xcodebuild + 装机。定位空转用默认位置，其余功能一致。
免费个人团队证书（53LT77CV6R）**7 天有效期** → 必须周五当天装机。

构建四坑速查见 `docs/superpowers/plans/2026-08-31-3dmap-g3-ios-transparency.md` 追记：
钥匙串授权挂死、SPM 需显式 `https_proxy`、pbxproj 引号锚点两制式、macOS 无 `timeout` 命令。

## 7. 排期

| 时段 | 内容 | 理由 |
|---|---|---|
| 周二剩余 | ① 换装闭环 + 出基线 APK 目视筛部件清单 | 最小改动立刻验证两模块连上；筛部件是 ② 的输入 |
| 周三上午 | ③ Android 定位（含 30 分钟验证分支） | 不确定性最高，早暴露 |
| 周三下午 | ⑥ UI token 重铸 | 早做，让 ④ 的气泡直接用 token |
| 周四上午 | ② 部件池 + ⑤ 惯性/双击 | 两项独立且小 |
| 周四下午 | ④ Marker/气泡 | 最可砍的一项放最后 |
| 周五上午 | 缓冲 / 收尾 / 双端构建 | |
| 周五下午 | iOS 装机 + 双端验收 + 录屏留证 | 证书 7 天期，必须当天装 |

## 8. 风险与降级预案

| 风险 | 降级 |
|---|---|
| 补部件撞上命名漂移 | 不补新部件，只剔除难看的，接受池子偏小 |
| Mapbox 自带 location provider 回传不通 | 退 AOSP `LocationManager`（+0.3 天，吃周五上午缓冲）；再不行退成"定位按钮"跳到一个真实地点 |
| iOS 构建链翻车（四坑之一） | 只交 Android，iOS 用录屏证明能跑 |
| UI token 铺不完 | 只覆盖 map_poc + dressing_room 主路径，stress_test 场景不管 |
| 惯性破坏现有滚动机制 | 110 用例回归兜底，发现即回退该项 |

## 9. 验收清单

- [ ] Android 真机：开 App → 权限弹窗 → 落到真实位置，自己的角色在脚下
- [ ] 快速甩动地图有惯性衰减；双击平滑放大
- [ ] 至少 3 个 marker 可点，气泡中文显示正常
- [ ] 进换装房换上装/发型 → 保存 → 返回地图，自己的角色已更新
- [ ] 全程 UI 视觉统一（薄荷绿 token 体系）
- [ ] iOS 真机跑通同一条链（定位除外，用默认位置）
- [ ] `tools/run_tests.sh` 全绿

## 10. Plane 优先级同步

本 spec 定案后，Plane 项目 Sensen Godot（SGODOT）需做如下调整：

**升为 high（本周做）**
- SGODOT-7 定位插件 —— 缩范围为"仅 Android + 首帧定位"，iOS 空转
- SGODOT-8 Marker/气泡 —— 缩范围为"单类型 + 点击气泡，无聚焦编排"
- SGODOT-9 搜索 + 手势 —— **拆开**：手势惯性/双击本周做，搜索地名本周不做
- 新建：换装闭环回写地图
- 新建：avatar 部件池整理（demo 白名单 + 补普通部件）
- 新建：UI design token 重铸

**降为 low（本周之后）**
- SGODOT-4 G4 双端性能矩阵
- SGODOT-5 G2 撕裂量化
- SGODOT-6 iOS 桥迁 GDExtension
- SGODOT-10 Android 插件迁 AAR
- SGODOT-11 iOS 导出链正规化

**保持不变**：SGODOT-1 / SGODOT-2（材质对齐、特殊材质）、SGODOT-12（G0 前提冻结）、
SGODOT-13（水晶 shader）、SGODOT-14（token 独立化）。

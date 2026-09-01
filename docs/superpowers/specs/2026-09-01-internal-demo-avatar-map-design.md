# 内部 Demo（2026-09-04 周五）范围设计：avatar + 地图端到端

日期：2026-09-01（周二）
状态：已与决策者逐节确认，待实施
上游背景：[3D 地图方案A](2026-08-25-3dmap-mapbox-research.md)、[avatar 一期](2026-08-21-avatar-godot-design.md)、[海外版重构调研](2026-08-30-overseas-refactor-research.md)

---

## 1. 背景与优先级变更

与合伙人对齐后短期目标收敛：**avatar 模块与地图模块优先**，作为本周五（2026-09-04）的内部目标；
原 PoC 路线里的 **G3 收尾（iOS 桥正式化 / 导出链正规化）与 G4（性能矩阵）优先级下调**，本周不做。

这条变更的直接后果是：Plane 上 SGODOT-3 下几条 high 优先级的"正式化/量化"任务本周让位给"能演示的功能"。
优先级同步见 §10。

## 2. 交付物与验收口径

**阻断交付物**：一个可装机的 Android APK。决策者拿到手能自己点完这条链，无需讲解：

> 打开 App → 落在自己真实位置 → 周围有别人的角色和几条留言气泡 →
> 拖拽/双击地图，手感带惯性 → 点进换装房换一身 → 回地图，自己的角色已经变了

Android 这条链不接受"分模块各自截图"或"演示视频代替装机"——验收口径是**端到端可上手**。

**非阻断交付物**：一个 iOS 包（除定位外跑通同一条链，iOS 用默认位置）。
按已定的"Android 为主，iOS 能跑就行"，**iOS 不参与阻断判定**：iOS 构建链翻车时
允许降级为录屏留证（§8），不影响本周目标达成。这条降级**只适用于 iOS**，
不适用于上面的 Android 阻断链。

## 3. 预算

可用：周二剩余 + 周三 + 周四 + 周五上午 ≈ **3.5 个工作日**（单人）。

| # | 工作项 | 估时（天） |
|---|---|---|
| ① | 换装闭环回写地图 | 0.4 |
| ② | avatar 部件池整理 | 0.25 |
| ③ | Android 定位（含权限三态 + 内容重锚） | 0.7 |
| ④ | Marker/气泡（相对锚点） | 0.6 |
| ⑤ | 手势惯性 + 双击缩放 | 0.25 |
| ⑥ | UI design token 重铸 | 0.5 |
| — | iOS 重建 + 双端装机验收 | 0.5 |
| | **合计 3.2，缓冲 0.3** | |

③④ 各上调 0.1，来自对抗评审发现的两条：Android 12+ 权限必须 FINE+COARSE 同请求、
定位后演示内容必须跟着重锚（详见 §6③）。缓冲因此从 0.5 收窄到 0.3——
若周四结束时进度落后，**先砍 ④ Marker/气泡**（§8 已列为最可砍项）。

## 4. 明确不做（防止实施期临时加回）

- ❌ 搜索地名 / Mapbox Geocoding —— 现有"飞洛杉矶"按钮已能演示飞行动画，投入产出最低
- ❌ 水晶族专用 shader、材质对齐 Unity 的全量对比矩阵（Plane SGODOT-1 / SGODOT-2 / 水晶 shader 子任务）
- ❌ Marker 热度分级、相机聚焦编排、他人角色实时数据（全部假数据）
- ❌ iOS 桥迁 GDExtension、iOS/Android 导出链正规化、G4 性能矩阵、G2 撕裂量化
- ❌ 后台定位、GCJ-02 坐标系（仅海外发行前提未变）

## 5. 实施期已确认的事实（省去重查）

实施前查证过、与直觉相反的六条，写在这里避免重踩：

1. **`tier` 字段不是付费等级**。它是手工在 `tools/unity_export/samples.json` 标注的复杂度标记；
   `tools/pipeline/extract_parts.gd:172` 里 `tier == 1` 的语义是"保留 AnimationPlayer"。
   **不能用 tier 筛选"付费高级部件"。**
2. **转换管线不记录 Unity 侧材质族名**。`tools/unity_export/parts.py:88` 只抽 albedo / ao / floats，
   没有 shader 或材质名字段。所以无法用元数据自动识别"水晶族"，只能目视筛 + 剔除名单。
3. **场景切换是整场景重建**（`scenes/map_poc/map_poc.gd:261` 用 `change_scene_to_file`），
   回地图必然重跑 `_ready → _spawn_pawns`。所以"换装后返回要刷新"**不需要额外机制**。
4. **pawn 存的是绝对经纬度，`_teleport()` 不会带着它们走**（`map_poc.gd:335-341` 生成、
   `:222 _reposition_pawns()` 只重投影）。定位到别处 = 近处 pawn 全被 `CULL_FACTOR = 4.0` 剔除。
   演示内容必须相对锚点存储，见 §6③。
5. **`parts_manifest.json` 是管线产物，每次转换全量覆写**
   （`tools/pipeline/extract_parts.gd:25-32`）。任何手工加进去的字段都会被静默擦除。
6. **Android targetSdk 取 Godot 默认 36**（`export_presets.cfg:31` 的 `gradle_build/target_sdk`
   为空 → `godot-src/platform/android/java/app/config.gradle:9`）。targetSdk ≥ 31 触发
   Android 12+ 的定位权限规则，见 §6③。

当前部件目录只迁移了 **15 个**：hairHat 4、cloth 4、shoes 2、glass 2、body / eyes / messengerBag 各 1。

以上 4-6 条由 2026-09-01 的 Codex 对抗性评审发现，均已回代码核实。

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
- 过滤名单放**独立文件** `assets/avatar/demo_denylist.json`（一个 part id 数组），
  在 `modules/avatar/catalog/part_catalog.gd` 的 `load_from_file()` 之后套一层过滤，
  `parts_for_slot()` 与随机路人配置池都走过滤后的集合。约 20 行，不碰 shader、不碰管线
- **⚠️ 不要把 `hidden` 写进 `assets/avatar/parts_manifest.json`**：该文件是管线产物，
  `tools/pipeline/extract_parts.gd:25-32` 每次全量重建 `manifest_parts` 后 `store_string` 覆写，
  entry 构造里不含该字段 —— 手工加的标记会在下次转换时被**静默擦除**，隐藏部件重新出现在
  换装列表和随机路人池里。独立 denylist 同时避开这个坑，且改名单不需要重跑转换
- 回归测试：denylist 里的 id 不出现在 `parts_for_slot()` 结果中；重跑转换后 denylist 仍生效
- 补池：`tools/unity_export/samples.json` 加 8-10 个普通部件，跑 `convert.py` + `extract_parts.gd`

**风险**：补部件可能撞上美术命名漂移（`T_xxx_D 1.png` 副本尾巴、`bag ≠ messengerBag`），
需要 `tools/unity_export/overrides.json` 定点兜底。这是本项唯一的不确定性。

### ③ Android 定位（0.7 天）

**现状**：地图起点钉死上海人民广场（`map_poc.gd` 的 `START_LAT` / `START_LNG`）；Godot 无内置定位 API。

**改法**：
- 插件骨架现成——`tools/android/overlay/GodotMapPlugin.kt` 已有 `getPluginSignals()` /
  `@UsedByGodot` / `emitSignal` 全套，照现有 `map_ready` 信号加 `SignalInfo("location_update", ...)`
- **优先路径**：订阅 Mapbox v11 自带的 location provider（`mapView.location`），省掉 Play Services 依赖
  —— 先花 30 分钟验证能否回传经纬度
- **退路**：AOSP `LocationManager`，零额外依赖
- **权限（⚠️ 关键）**：`AndroidManifest.xml` 必须**同时**声明 `ACCESS_FINE_LOCATION` 与
  `ACCESS_COARSE_LOCATION`，且两者**在同一次运行时请求中提交**。本工程 `export_presets.cfg:31` 的
  `gradle_build/target_sdk` 为空 → 取 Godot 默认 `targetSdk 36`
  （`godot-src/platform/android/java/app/config.gradle:9`），而 targetSdk ≥ 31 时
  **单独请求 FINE 会被系统直接忽略**（无弹窗、无回调）。
  因此用 `OS.request_permissions()`（复数，一次提交 manifest 里全部危险权限），
  **不是** `OS.request_permission("...FINE_LOCATION")`（单数，Godot 两个方法都存在，
  见 `godot-src/core/core_bind.h:309-310`，用错这个是本项最容易翻车的点）
- 必须处理三态并各有行为：**精确授权** → 正常流程；**仅粗略授权**（用户选 approximate）→ 照常用，
  精度降级不阻断；**拒绝或超时**（3 秒无有效定位）→ 回落上海默认点，且演示内容照常可见（见下条）
- `scenes/map_poc/map_bridge.gd` 加 `signal location_update(lat, lng, accuracy)` + `start_location()`；
  **iOS 实现空转返回默认位置**，保持接口一致（不破坏 MapBridge 抽象层）
- **定位后的内容重锚（⚠️ 一票否决项）**：`map_poc.gd:335-341` 现在把 12 个近处 pawn 生成在
  `START_LAT + off`、10 个在 `LA_LAT + off`，存的是**绝对经纬度**；`_reposition_pawns()`（:222）
  只按 `p.lat/p.lng` 重投影，`_teleport()` 只改 anchor/center，**都不会改 pawn 的地理坐标**。
  照原样实现的话，定位到任何非上海人民广场的位置，近处 pawn 全落到 `CULL_FACTOR = 4.0` 之外被剔除，
  地图上空无一人 —— §9 阻断项里"远离上海实测仍有路人和 marker"那条直接失败。
  正确做法：
  - 近处 12 个 pawn 与全部 demo marker 改为**相对锚点的偏移量**存储，不写绝对经纬度
  - **等首个有效定位（或 3 秒超时回落上海）确定锚点之后再 spawn 近处队列**，
    避免"先按上海 spawn、后重定位"的中间态（现有 spawn 是分帧 2/帧，中途改坐标会有可见跳变）
  - **LA 那 10 个保持绝对坐标不动** —— 它们是跨洋剔除 + 浮动原点的压测夹具
    （`map_poc.gd:339` 注释写明），不是演示内容
  - 加一条集成测试：把锚点设在远离上海/洛杉矶的坐标，断言近处 pawn 与 marker 仍在可见范围内

**保留约束**：插件信号必须 `CONNECT_DEFERRED`；`MapboxMap` 是 `@MainThread` API，读状态走 UI 线程缓存。

### ④ Marker / 气泡（0.6 天）

**数据**：`scenes/map_poc/demo_markers.json` 假数据，接口形状对齐 Unity 的 `QueryNewMapMarkerReponse`。
坐标存**相对锚点的偏移量（米）而非绝对经纬度**——理由同 §6③ 的重锚条款：
写死经纬度会让 marker 在用户真实位置全部出屏。至少 3 个 marker 落在首屏可见范围内。

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

| 时段 | 内容 | 天 | 理由 |
|---|---|---|---|
| 周二剩余 | ① 换装闭环 + 出基线 APK 交决策者筛部件 | 0.5 | 最小改动立刻验证两模块连上；筛部件清单是 ② 的输入，越早给决策者越好 |
| 周三 | ③ Android 定位（含 30 分钟 provider 验证 + 权限三态 + 内容重锚）→ ⑥ UI token 起 | 1.0 | ③ 不确定性最高且是一票否决项，早暴露 |
| 周四 | ⑥ 收尾 → ② 部件池 → ⑤ 惯性/双击 → ④ Marker 起 | 1.0 | ⑥ 必须早于 ④，让气泡直接用 token 不返工 |
| 周五上午 | ④ Marker 收尾 + 缓冲 0.2 | 0.5 | 最可砍的一项排最后，进度落后时直接砍 |
| 周五下午 | iOS 装机 + 双端验收 + 录屏留证 | 0.5 | 免费证书 7 天期，必须当天装 |

工作量 3.2 / 预算 3.5，缓冲 0.3 集中在周五上午。

## 8. 风险与降级预案

| 风险 | 降级 |
|---|---|
| 补部件撞上命名漂移 | 不补新部件，只剔除难看的，接受池子偏小 |
| Mapbox 自带 location provider 回传不通 | 退 AOSP `LocationManager`（+0.3 天，**恰好吃光全部缓冲**——同时触发时必须砍 ④）；再不行退成"定位按钮"跳到一个真实地点 |
| iOS 构建链翻车（四坑之一） | 只交 Android，iOS 用录屏证明能跑。**仅限 iOS**——iOS 是非阻断项（§2），此降级不适用于 Android 主链 |
| Android 12+ 权限请求被系统忽略（只请求了 FINE） | 已在 §6③ 写死"FINE+COARSE 同请求 + `OS.request_permissions()`"；仍失败则退成手动"定位"按钮跳到一个真实地点 |
| 定位成功但周边空无一人（pawn/marker 未重锚） | 已在 §6③ 列为一票否决项并给出相对锚定方案；集成测试覆盖 |
| UI token 铺不完 | 只覆盖 map_poc + dressing_room 主路径，stress_test 场景不管 |
| 惯性破坏现有滚动机制 | 110 用例回归兜底，发现即回退该项 |

## 9. 验收清单

**阻断项**（任一不过 = 本周目标未达成）
- [ ] Android 真机：开 App → **权限弹窗出现**（未出现即 §6③ 的权限坑复现）→ 落到真实位置，自己的角色在脚下
- [ ] **在一个远离上海人民广场的地点实测**：周围仍有路人角色和 ≥3 个可点 marker（重锚生效）
- [ ] 拒绝权限 / 选"大致位置" / 3 秒超时 三种路径都不崩，且回落后演示内容照常可见
- [ ] 快速甩动地图有惯性衰减；双击平滑放大
- [ ] 气泡中文显示正常
- [ ] 进换装房换上装/发型 → 保存 → 返回地图，自己的角色已更新
- [ ] 全程 UI 视觉统一（薄荷绿 token 体系）
- [ ] `tools/run_tests.sh` 全绿（含新增的远距离重锚集成测试、denylist 回归测试）

**非阻断项**
- [ ] iOS 真机跑通同一条链（定位除外，用默认位置）；构建链翻车则录屏留证

## 10. Plane 优先级同步

本 spec 定案后，Plane 项目 Sensen Godot（SGODOT）需做如下调整：

**升为 high（本周做）**
- SGODOT-7 定位插件 —— 缩范围为"仅 Android + 首帧定位"，iOS 空转
- SGODOT-8 Marker/气泡 —— 缩范围为"单类型 + 点击气泡，无聚焦编排"
- SGODOT-9 搜索 + 手势 —— **拆开**：手势惯性/双击本周做，搜索地名本周不做
- 新建：换装闭环回写地图
- 新建：avatar 部件池整理（demo denylist + 补普通部件）
- 新建：UI design token 重铸

**降为 low（本周之后）**
- SGODOT-4 G4 双端性能矩阵
- SGODOT-5 G2 撕裂量化
- SGODOT-6 iOS 桥迁 GDExtension
- SGODOT-10 Android 插件迁 AAR
- SGODOT-11 iOS 导出链正规化

**保持不变**：SGODOT-1 / SGODOT-2（材质对齐、特殊材质）、SGODOT-12（G0 前提冻结）、
SGODOT-13（水晶 shader）、SGODOT-14（token 独立化）。

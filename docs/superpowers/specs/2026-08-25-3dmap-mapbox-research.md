# 3D 地图（Mapbox × Godot 角色）技术调研与方案

日期：2026-08-25
状态：调研完成，方案待评审（PoC 前不落任何实现）
调研方法：7 维度并行网络调研 + 6 项关键结论对抗验证（全部一手来源：官方文档 / GitHub 源码与 issue / changelog / 本机大陆网络实测）+ 本地 Unity/Godot 工程侦察
调研全文底稿（全部发现/证据链/验证裁决/完整性审查/评审问答）：[`2026-08-25-3dmap-mapbox-research-appendix.md`](2026-08-25-3dmap-mapbox-research-appendix.md)

---

## 1. 背景与问题定义

Unity 旧版 3D 地图主页使用**已停滞多年后于 2026 年才复活的 Mapbox Unity SDK**（`AbstractMap`）：栅格瓦片下载后贴到 quad mesh 上由 Unity 渲染。性能差的根因是"引擎内瓦片重建 + 栅格贴图"路线本身：瓦片加载/纹理上传抖动、内存高、样式不可控。该路线已判死刑。

### Unity 侧功能基线（新方案需对齐的交互范围）

来自 `_Gensen/Scripts/{NewMapHome,MapHomePage,MapTrace}`：

- 设备定位 + 首帧定位动画；搜索定位（`LocateToLocation`）
- 手势：拖拽平移（惯性阻尼）、双指缩放、双击缩放
- 自己的 Avatar Pawn：走 Emoji3d/AvatarIO 换装系统，站在定位点
- 他人 Marker（USER_NOTE / Scenic 两类）：气泡 UI、热度分级、相机聚焦/solo、刷新
- 足迹页（MapTrace）：同一套地图 + 相机聚焦
- 页面跳转：个人空间 / 换装房

### Godot 侧现状

角色系统已完整迁移（`modules/avatar`：FBX 部件 + Skeleton3D + AnimationPlayer + 自定义 toon shader + socket 三层机制 + 换装抽屉 UI），Android 真机 20 角色 merged 顶满 120Hz 已验证。**角色渲染不是问题，问题只在地图。**

## 2. 硬性需求

1. 不允许再走"栅格瓦片当纹理在引擎里贴图渲染"；
2. 优先让 Mapbox 自己的渲染器出图（GL JS 或原生 Maps SDK）；
3. 打包 Android + iOS，中端机流畅（目标 60fps，**当前无任何路线有实测数据，禁止在 PoC 前做承诺**）；
4. 角色保留现有 Godot 材质/动画/换装能力。

### 2.1 动工前必须冻结的需求前提（影响选型权重）

| 问题 | 默认假设（待确认） | 若相反 |
|---|---|---|
| 发行区域 | **仅海外发行** | 若国内上架：Mapbox 整套作废（外商禁入测绘负面清单），须换持证图商 + GCJ-02 + ICP/审图号 |
| 角色是否需被 3D 建筑/地形真遮挡 | 不需要（Pokémon GO 式风格化底图也没有） | 需要 → 只剩 custom layer 路线（= 放弃 Godot 渲染角色） |
| 地图上多角色（好友 3D 形象）规模 | 少量 3D pawn + 大量 2D marker | 大量 3D 角色会加重叠加层负担，但仍是 Godot 强项（已验证 20 角色 120Hz） |
| 离线地图 | 需要基本缓存能力 | 仅原生 SDK 有官方离线（GL JS 无） |

## 3. 调研关键结论（已对抗验证）

### 3.1 决定性事实：Mapbox 不能替我们播角色动画

- **Mapbox model layer / LocationPuck3D 三端（GL JS/iOS/Android）均不支持任何 glTF 内置动画**——关键帧、骨骼蒙皮、morph target 全部排除，style spec 源码属性枚举级证实；节点覆盖只有旋转（连节点位移都没有，四肢摆动类动画无路可走）。官方 2023-10 答复"计划支持"，至 2026-08 三年未兑现、无 roadmap；2026 年新增的 ModelSource 交互 API 仍是"车门/螺旋桨"级刚体旋转。【[style spec 指南](https://docs.mapbox.com/style-spec/guides/using-3d-models/)、[v8.json 属性枚举](https://github.com/mapbox/mapbox-gl-js/blob/main/src/style-spec/reference/v8.json)、[iOS #2025](https://github.com/mapbox/mapbox-maps-ios/issues/2025)、[iOS #2338](https://github.com/mapbox/mapbox-maps-ios/issues/2338)】
- 官方给带动画角色指的唯一出路：**custom layer 里自己渲染**（GL JS 配 three.js；iOS Metal/SceneKit；Android 自研 GL 渲染器）——即在别的渲染器里重建整套角色管线。

**推论：要满足需求 4（角色继承材质/动画/换装），角色只能继续由 Godot（或等价重写的第二渲染器）渲染。"把角色直接交给 Mapbox"不存在。**

### 3.2 原生 Maps SDK v11（推荐的地图出图方式）

- 版本 11.28.4（2026-08-20），双端同步、2-4 周一发；iOS Metal，Android 默认 GLES、Vulkan 公测预览（**Vulkan 预览不支持 custom layer**）。iOS 2026-12 起停止 CocoaPods 分发，需 SPM。
- 相机每帧可读：`cameraState`（center/zoom/bearing/pitch）+ `CameraChanged` 事件 + `FreeCameraOptions`（墨卡托位置 + 四元数）；精确投影矩阵仅 custom layer 回调参数提供（可拿来校准）。
- 呈现载体：Android MapView 默认 SurfaceView、可切 TextureView（透明/alpha 合成，有额外开销）；iOS 为内嵌 CAMetalLayer 的 UIView，有 `presentsWithTransaction` 同步选项（官方注明用于"UIKit 元素钉在经纬度上"场景——正是叠加层防抖需要的）。**两端都可与其他 View 叠加。**
- 离线：官方 offline region/tile pack（唯一有官方离线的产品线）。
- 计费：**MAU 制，25,000 MAU/月免费**，超出 $4.00/千起阶梯递减，含无限瓦片请求。
- 风险记录：Android 特定机型 ANR 史（三星/小米/vivo + v11.9-11.12），需锁新补丁版 + 机型灰度。

### 3.3 GL JS + WebView 路线（降级为备选）

- GL JS v3.29（强制 WebGL2 → iOS 15+）；model layer 同样无动画；带动画角色须 three.js custom layer——官方示例实际**不含任何动画播放**（three@0.126，无 AnimationMixer），"官方认可"仅是一句文字指路。
- threebox 停更（2022-06 起，兼容声明停在 GL JS v2；社区在 v3 跑通但需自打崩溃补丁，与 terrain 组合有未修复渲染缺陷）；活维护替代是 deck.gl ScenegraphLayer（`_animations` 为实验前缀，换装式"共享骨架+运行时增删部件"支持度未验证）。
- 性能证据结构性偏负：custom layer 持续动画迫使整图每帧全量重绘（#7591/#7629，原作者实测约 20 个动画对象即卡顿、CPU 显著高于独立 context）；**iOS 低电量模式 WKWebView rAF 硬限 30fps（WebKit bug 168837）——"稳定 60fps"对相当比例会话物理不可达**；GL JS 月更在中端移动 GPU 上出过崩溃级回归（Pixel 8a Mali-G715，v3.21/3.22）。零正面移动端基准。
- 计费按 map load（50k/月免费，超出 $5/千起）：高频打开的主页地图，成本可能数十倍于 MAU 口径；且"GL JS 嵌原生 App WebView"的计费归类新旧文档口径并存，**未获 Mapbox 书面确认前不得选此路线**。
- 无官方离线。Godot 移动端 WebView 插件生态：商业 godot-webview 仅桌面、godot_wry 移动端 Planned、零散 Android 插件质量参差、iOS 空白——还得自研双端 WebView 插件。

### 3.4 Godot 混合叠加的平台事实（本方案成败所在）

**Android（可行性链条完整，无公开端到端案例）：**
- "Godot as Android library"（AAR）是官方文档化路线；单实例、须锁方向（本 App 竖屏，无碍）。
- 透明背景：4.5 修复（PR #106709，4.7.2 已含）；**Android 唯一开关是 `display/window/per_pixel_transparency/allowed`**（`size/transparent` 官方明示 Android 无效；`should_render_transparent_background` 这个 API 名不存在，勿再引用）。
- 原生 View 垫底是插件一等能力：`GodotPlugin.onMainCreate` 返回的 View + `shouldBeOnTop()=false`，javadoc 明写"配合透明让 Godot 处理输入"；3.x 时代同构场景（相机预览垫底）是官方特性。
- z-order 无官方 API：需 host/插件侧拿到 Godot 的 SurfaceView 手动设置。**三层结构（地图底 / Godot 中 / 原生 UI 顶）应使用 `setZOrderMediaOverlay(true)` 而非 issue #22 示例的 `setZOrderOnTop(true)`**，且须在 surface attach 前调用；与 Mapbox MapView（默认也是 SurfaceView）构成双 SurfaceView，相对次序未定义行为，PoC 首要验证项。地图切 TextureView 不是更稳的备选（会反过来要求 Godot setZOrderOnTop，牺牲原生 UI 叠顶）。
- 反例边界：Flutter 嵌 Godot 叠 UI 失败案例经过 Flutter PlatformView 合成器，不能外推到纯原生/Godot 为壳场景。

**iOS（全方案最脆弱一环）：**
- 原生 UIView 垫到 Godot 视图下方本身是官方 API 可达的（`DisplayServer.window_get_native_handle` 返回 UIViewController/godotView）；**但 Godot iOS 不支持窗口透明**：4.7.2 中 `FEATURE_WINDOW_TRANSPARENCY` 被注释禁用、GL 层硬编码 `opaque=YES`、Metal 层无透明处理、`per_pixel_transparency` 在 iOS 代码路径零引用。2023 年社区同思路尝试失败无解。
- 官方 LibGodot：core 已合入 4.6（4.7.2 自带 `libgodot.h`），但**仅桌面三平台、无 UI 嵌入**；Apple UI Embedding 停在 Migeran 私有 4.6 分支"PR Ready for Upstreaming"（GodotCon 2026-04 口径），官方仓库无对应 PR。
- 第三方 fork 路线：SwiftGodotKit（4.6 基 fork，iOS 真机可用、无模拟器、单实例、无 4.7 分支）；react-native-godot（4.5 基，**百万用户量产实证**，支持模拟器）。fork = 引擎版本分裂（Android 4.7 / iOS 4.5-4.6）+ 跟版风险。
- 低成本探索项（无先例，只能当 spike）：运行时取 godotView 把 `layer.opaque = NO` + viewport transparent_bg；或自 patch 引擎（改 display_layer + 上报 FEATURE_WINDOW_TRANSPARENCY）自建导出模板。

### 3.5 行业先例（模式与教训）

- **绑大厂"游戏引擎地图 SDK"的产品全部被迫迁移过**：Google gaming solution 2022 关停（DQ Walk 被迫换栈）；Niantic Lightship Maps 2025-10 全面日落，官方退路点名 Mapbox/Esri；Mapbox Unity SDK 停摆 3 年后 2026 复活（仅 Unity、仍是引擎内重建）。稳定的是 Mapbox 数据/渲染器产品线本体，不稳定的是"引擎壳"。**方案应绑定前者。**
- 主流模式收敛为两条：①引擎内矢量瓦片→mesh（Pokémon GO/Lightship，Godot 无任何现成实现，自研=Zenly 子集）；②**原生地图渲染器出图 + 应用层叠角色**（Zenly 后继产品 Jagat/Snap Map 事实主流；Snap Map = Mapbox 数据 + 自研 GL + 应用层 Bitmoji）。注意：模式②的公开案例角色多为 2D/轻 3D 贴片，"全屏透明第二 3D 引擎"无公开先例——这是我们要用 PoC 回答的增量问题。
- Zenly 教训：自研全套地图引擎 ≈ 10 人 × 3 年，且救不了商业模式。不作为迁移首选。

### 3.6 引擎内替代路线（对照组，全部不达标）

- Godot 生态无生产级 MVT→mesh 方案（最高星 godot-openstreetmap 停更且自述不稳定；全部缺文字标注链路——SDF 字形/碰撞消隐/CJK 是隐藏大头）。
- "Cesium for Godot"实为社区插件 3D Tiles for Godot（Battle Road Labs），**仅桌面**；Android issue 挂 15 个月，Quest 3 真机导出实测失败；iOS 无计划。cesium-native 本体能跑移动端（Unity 下游已证），缺口在 Godot 插件层，无人排期。
- MapLibre Native 嵌 Godot 唯一先例（yuiseki/maplibre-native-godot）是桌面实验（2 stars，每帧 GPU→CPU→GPU 回读）；MapLibre 官方也有 Slint 嵌入参考实现（同样仅桌面、自述非成品）。MapLibre 移动渲染本体成熟（iOS Metal 自 v6；**Android v13.0.0 起 Vulkan 为默认后端**，2026-03）。零拷贝进 Godot 需 Vulkan external memory/Metal shared texture 级自研，数月级、无先例。
- 自渲染若继续用 Mapbox 瓦片按 tile request 计费（劣于 MAU/map load 含无限瓦片），实践中要换 MapTiler/OpenMapTiles 系数据源。

### 3.7 角色资产管线（若有朝一日转向"地图侧渲染角色"的代价）

- Godot→glTF：**ShaderMaterial 不可导出（toon shader 100% 丢失）**；骨骼动画导出有仍 open 的根关节运动 bug（#114110）；更稳链路是 Unity 原始 FBX→Blender→glb（Blender FBX 导入有骨骼朝向猜测 + 动画逐帧烘焙两个损耗点）。
- three.js 换装（共享骨架）官方支持但坑密（坐标系/bind matrix/包围球/骨骼顺序）；SM_/SK_ 坐标系 + socket 三层机制要按 three.js 约定**第三次重推**。
- toon：内置 MeshToonMaterial 太简陋（无描边）；最完整现成实现是 @pixiv/three-vrm 的 MToon（活跃维护）；忠实复刻自研 shader 约 1-3 周。
- 定性：换装 + socket 校正 + toon 三子系统在第二渲染器重写（一次性 3-6 周）**+ 此后每次资产更新双端回归的持续成本**。高成本选项，仅当"真遮挡"成为硬需求时才值得。

### 3.8 中国区与商务（前提：仅海外发行）

- 仅海外发行：中国测绘/ICP/审图/GCJ-02 义务**全部不适用**（《地图管理条例》属地适用，972 号通知只约束境内 App）；海外场景 GPS 与 Mapbox 底图同为 WGS-84 自洽。一旦国内上架，义务全部回归且 Mapbox 无合规通道（外商禁入测绘负面清单，mapbox.cn 已停运、DNS 无解析、官方中国帮助页已 404）。
- 大陆直连：**"时通时断、无 SLA"**——2026-08-25 上海移动实测 api.mapbox.com（CloudFront）直连正常（0.13-0.6s），但主站（Fastly）严重劣化；2024-12~2025-04 有多个大陆用户报告完全不可用。生产不得依赖大陆直连；团队调试须长期备代理。
- token：移动端只能内置 pk token，**无包名/bundle ID 绑定、URL 限制对原生 SDK 无效**；防盗用靠每 App 独立 token + Tokens API 轮换 + 用量告警。
- 归属合规：Mapbox wordmark 与 attribution 必须始终可见（可移位不可隐藏）、保留 Telemetry 退出入口——**Godot 全屏层与换装抽屉 UI 不得遮挡，布局需预留**。
- 备胎：MapLibre（零 MAU 费用、活跃、样式基本兼容）是最直接逃生通道；Google Maps 移动 SDK 2025-03 起免费不限量但定制弱；高德仅国内发行才有意义。**架构必须保留地图供应商抽象层（硬要求，非可选）。**

## 4. 候选方案对比

| | A. 原生 SDK 垫底 + Godot 透明叠加 | B. WebView + GL JS + three.js | C. 原生 custom layer 内重建角色 | D. 引擎内自渲染（MVT/MapLibre 嵌入） |
|---|---|---|---|---|
| 需求1 不贴瓦片 | ✅ | ✅ | ✅ | ✅（矢量 mesh）/自研 |
| 需求2 Mapbox 出图 | ✅ 原生渲染器 | ✅ GL JS | ✅ | ❌（第三方/自渲染） |
| 需求3 流畅上限 | 高（双上下文合成开销待测） | 低-中（全图重绘 + WebView + 低电量 30fps 硬限） | 高（单渲染器） | 中-低（回读瓶颈/自研质量） |
| 需求4 角色继承 | ✅ **100% 复用 Godot 资产** | ❌ three.js 等价重写 | ❌ 每平台重建渲染器 | ✅ |
| 真遮挡（角色被建筑挡） | ❌ 只能近似 | 部分（同 context 深度） | ✅ | ✅ |
| 离线 | ✅ 官方 | ❌ | ✅ | 自研 |
| 计费 | MAU 25k 免费 | map load（口径存疑，或数十倍贵） | MAU | tile request/换数据源 |
| 工程量（到功能对齐 MVP，粗估） | ~2-3 人月 | ~2-3 人月 + 持续双维护 | ≥4-6 人月 + 持续双维护 | ≥4-6 人月，高不确定 |
| 主风险 | Android z-order 未定义行为；**iOS 透明无先例**；相机同步撕裂 | 性能结构性负面；计费口径；插件自研 | 放弃 Godot 角色；Vulkan 预览断供 custom layer | 无先例、标注链路、公交车系数 |

## 5. 推荐方案：A（原生 Mapbox SDK v11 垫底 + Godot 透明层渲染角色）

四条硬性需求里它是唯一同时满足 1/2/4、且 3 的上限最高的路线。与行业主流"模式②"同构，增量赌注只有一个：**"第二个 3D 引擎作为全屏透明层"能否稳帧且不撕裂**——这正是 PoC 要最先回答的问题。

### 5.1 分层与壳形态

```
┌──────────────────────────────┐
│  Godot UI 层（换装抽屉/气泡/按钮，已有） │  ← Godot 场景内
│  Godot 3D 层（角色/他人 pawn/emoji）  │  ← 透明 viewport
├──────────────────────────────┤
│  Mapbox MapView（原生，地图+POI标注）  │  ← 插件垫底 View
└──────────────────────────────┘
      宿主：Godot 导出工程（双端一致，首选）
```

- **Android**：Godot 4.7 导出工程为壳 + v2 Android 插件：`onMainCreate` 创建 MapView、`shouldBeOnTop()=false` 垫底；插件内拿 Godot SurfaceView 设 `setZOrderMediaOverlay(true)` + TRANSLUCENT（attach 前）；`per_pixel_transparency/allowed=true`。
- **iOS 首选**：Godot 导出工程 + iOS 插件经 `window_get_native_handle` 垫 MapView + 透明 spike（运行时 `layer.opaque=NO`）→ 不成则**自 patch 引擎构建导出模板**（改 display_layer_ios + 上报 FEATURE_WINDOW_TRANSPARENCY，改动面小但无先例）。
- **iOS 备选**：SwiftGodotKit/libgodot fork 原生壳嵌 Godot——代价是引擎版本分裂（4.5/4.6 vs 4.7）与资产双导出，除非首选路线死掉不启用。react-native-godot 的原生封装层可作参考实现。
- 双端各需一个薄**定位插件**（Godot 无内置 GPS/罗盘；现有社区插件均小型个人项目，建议自研 thin plugin：权限、单点订阅、经纬度+精度+朝向回传）。

### 5.2 输入路由（解决触摸分层）

Godot 全屏在上、**消费全部触摸**，地图 View 永远不收原生手势（禁用 Mapbox gesture plugin）。拖拽/双指缩放/双击/惯性全部在 Godot 侧实现（把 Unity `NewMapCameraMovement` 的手感参数移植过来），换装抽屉等 Godot UI 天然优先命中。手势产出统一走"相机控制器"，不存在"透传给地图"的需求。

### 5.3 相机同步协议（本方案技术核心）

**原则：单一权威相机位姿，两个渲染器同帧消费同一份位姿，杜绝往返延迟。**

- 常态（用户操作）：Godot 手势 → 相机控制器算出 `(center, zoom, bearing, pitch)` → 每帧经 JNI/ObjC 桥 `setCamera`（jumpTo，无动画）喂给地图；Godot 侧用**同一份位姿**推导 Camera3D。桥上每帧 6 个 double，开销可忽略；残余偏差 = 两个 surface 的出帧相位差（SurfaceView 合成不保证同帧，iOS 可用 `presentsWithTransaction=true` 收敛）。
- 地图主导段（flyTo/聚焦 marker 动画）：反向——订阅 `CameraChanged` 每帧读 `cameraState` 更新 Godot 相机；或干脆把 fly-to 动画也在 Godot 侧插值（推荐，权威不换手）。
- 位姿→Godot Camera3D 数学（PoC 期间用 custom layer 的 `projectionMatrix` 参数做校准基准）：
  - `worldSize = 512 × 2^zoom`（px）；`mpp = cos(lat) × 2πR / worldSize`（R=6378137）
  - 相机到注视点距离 `d_px = (H/2) / tan(fovY/2)`（fovY 取 CustomLayerRenderParameters.fieldOfView，GL JS 系默认 ≈36.87°），`d_m = d_px × mpp`
  - Godot：注视点 = 屏幕中心地理点的本地米制坐标，相机按 bearing（方位角）/pitch（俯仰）球坐标偏移 `d_m`，同 fovY。
  - **浮动原点**：以角色/地图中心为原点、周边小范围用等距近似展开成米制平面，中心移动超阈值即重锚——规避 float32 高 zoom 抖动。
- 角色/气泡锚定：geo→本地米制（3D pawn 直接放场景）；2D 气泡用同一相机投影到屏幕坐标钉 Control。

### 5.4 内容归属

- 地图侧：底图、道路/地名标注、POI、（可选）Scenic 类静态 marker 走 Mapbox annotation。
- Godot 侧：自己的角色、他人 3D pawn/emoji、气泡 UI、聚焦 solo 展示、一切动画。
- 样式：Mapbox Studio 定制卡通化底图（Standard 的 3D 地标建筑建议关闭——既贴产品风格又回避"角色无法被建筑遮挡"的穿帮；样式复杂度是 PoC 帧率变量之一）。
- 供应商抽象层：地图操作全部走 `MapBridge` 接口（setCamera/annotation/offline/style），MapLibre 实现作为逃生通道（相机模型同源，成本可控）。

### 5.5 版本与依赖策略

- 锁版本：Mapbox SDK 锁最新 stable 补丁版（ANR 史）+ 机型灰度；Godot 4.7.2；两侧升级都要跑"透明+z-order"回归（依赖非官方 workaround，任一方升级可能破坏）。
- 不依赖的东西：model layer 的动画支持（三年未兑现，不可等待）；Android Vulkan 预览（不支持 custom layer，且我们不用 custom layer）；threebox（停更）。

## 6. 必须写明的风险（评审重点）

1. **一票否决项：相机同步撕裂**。快速拖拽/捏合时角色相对地图漂移的量化上限，全行业无先例数据（Snap/Jagat 的叠加角色是 2D 贴片）。PoC 第一项验证，不达标则方案 A 作废，退路只有 B/C——两者都意味着放弃 Godot 渲染角色。
2. **iOS 结构性风险**：Godot iOS 无透明支持（引擎源码级挡死），首选路线依赖无先例的 spike/自 patch；备选 fork 路线带引擎版本分裂。iOS 单独设 PoC 关卡，且要接受"iOS 晚于 Android 交付"的排期现实。
3. **Android z-order 未定义行为**：双 SurfaceView 相对次序靠 `setZOrderMediaOverlay` workaround（非官方 API），时序敏感（attach 前设置），嵌入形态下 `per_pixel_transparency` 是否开箱即用未验证。
4. **性能零实测**：双 GPU 上下文 + 全屏 TRANSLUCENT 合成的代价（官方文档明示 per-pixel transparency 影响性能）只能真机定量；文档/对外沟通禁用"可达 60fps"表述，直到 G4 出数据。
5. **遮挡上限**：Godot 层拿不到地图深度，角色永远不被建筑/地形真遮挡。需求冻结时确认可接受（配合关 3D 建筑）。
6. **平台依赖**：地图 SDK 行业死亡率高（Google/Lightship 前车之鉴）→ 供应商抽象层是硬要求；Mapbox attribution 不得被遮挡；大陆调试须代理、生产不依赖大陆直连。
7. **生命周期/内存**：双引擎同进程的 pause/resume 协同、低内存 kill 恢复、内存峰值（3-4GB 机型余量）无数据，进 G4 指标。

## 7. PoC 验证计划（按序执行，每关带否决条件）

**机型矩阵**：骁龙 7 系（如 Redmi Note 13 Pro 级）、天玑/Mali 中端各一台、iPhone 13 或 SE3；已有的 120Hz 验收机作对照。

| 关卡 | 内容 | 时长 | 通过判据 | 否决后动作 |
|---|---|---|---|---|
| G0 | 冻结 2.1 需求前提（发行区域/遮挡/多角色/离线） | 半天 | 决策记录 | — |
| G1 | Android 合成：Godot 导出工程 + 插件垫 MapView + 透明 + `setZOrderMediaOverlay` | 3-5 天 | 地图可见、Godot 角色叠加无黑屏、原生 UI 可叠顶 | 换 AAR 嵌入形态再试；仍败 → A 废弃 |
| G2 | 相机同步：手势→桥→jumpTo + Godot 同位姿推导（含校准 against projectionMatrix） | 1-2 周 | 录屏逐帧量化：快速拖拽下角色锚点漂移 ≤2 帧等效；手感与原生地图 Demo 对照无明显差 | 尝试 presentsWithTransaction/帧对齐优化；仍败 → 上会决策 B/C |
| G3 | iOS 透明：runtime opaque spike（3-5 天）→ 引擎 patch 模板（+1-2 周） | 1-3 周 | 同 G1 判据 | 评估 SwiftGodotKit fork（1 周）；全败 → iOS 架构单独决策（custom layer 或 B） |
| G4 | 性能矩阵：Standard/定制样式 × 昼夜 × 拖拽/缩放/静置，采 p95 frametime、内存峰值、20min 发热与电流、双引擎生命周期切换 | 1 周 | p95 ≤16.7ms；内存峰值有余量；无 ANR | 降级预案：限帧/简化样式/关 3D 元素/降分辨率缩放 |
| G5 | 功能对齐 spike：定位插件、marker+气泡、聚焦动画、足迹页复用 | 1-2 周 | Unity 基线逐项打勾 | — |

**并行商务动作（低成本高价值，指派责任人）**：①向 Mapbox 提工单确认 glTF 动画 roadmap（只做风险输入）；②若保留 B 备选，书面确认 WebView 内 GL JS 计费口径；③按预期 DAU 算 MAU 成本曲线（25k 免费额度覆盖期）。

## 8. 结论

- **地图由 Mapbox 原生 Maps SDK v11 渲染（Metal/GLES、MAU 计费、官方离线），角色由 Godot 透明层渲染（资产零迁移）**——唯一同时满足四条硬性需求的架构，与 Zenly 后继产品的主流模式同构。
- 三个赌注按序用 PoC 拆雷：Android 合成（G1）→ 相机同步（G2）→ iOS 透明（G3）。任何一关失败都有明确退路与决策点，不存在"做到一半才发现死路"的敞口。
- WebView+GL JS 仅作功能性退路（体验不等价：低电量 30fps 硬限、全图重绘、计费口径未确认）；custom layer 路线仅当"真遮挡"成为硬需求才考虑（= 放弃 Godot 渲染角色 + 双端重建角色管线）。

## 附：关键参考

- Mapbox 3D 模型限制（三端统一）：https://docs.mapbox.com/style-spec/guides/using-3d-models/
- iOS ModelLayer 无动画（官方答复）：https://github.com/mapbox/mapbox-maps-ios/issues/2025 、https://github.com/mapbox/mapbox-maps-ios/issues/2338
- Android SDK changelog（版本/Vulkan 预览限制）：https://github.com/mapbox/mapbox-maps-android/blob/main/CHANGELOG.md
- 透明背景示例（Android TextureView）：https://docs.mapbox.com/android/maps/examples/transparent-background/
- SceneKit custom layer 示例（深度融合参照）：https://docs.mapbox.com/ios/maps/examples/sceneKit/
- Godot Android library 官方文档：https://docs.godotengine.org/en/stable/tutorials/platform/android/android_library.html
- Godot Android 透明修复（4.5）：https://github.com/godotengine/godot/pull/106709
- z-order workaround（维护者）：https://github.com/m4gr3d/Godot-Android-Samples/issues/22
- GodotPlugin 垫底 View API：https://github.com/godotengine/godot/blob/master/platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPlugin.java
- iOS 透明挡死证据：https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/apple_embedded/display_server_apple_embedded.mm
- LibGodot core（4.6 合入）：https://github.com/godotengine/godot/pull/110863 ；伞形 PR：https://github.com/godotengine/godot/pull/90510
- SwiftGodotKit：https://github.com/migueldeicaza/SwiftGodotKit ；react-native-godot（量产实证）：https://github.com/borndotcom/react-native-godot
- GL JS custom layer 性能问题：https://github.com/mapbox/mapbox-gl-js/issues/7591 、https://github.com/mapbox/mapbox-gl-js/issues/7629
- iOS 低电量 rAF 30fps：https://bugs.webkit.org/show_bug.cgi?id=168837
- Lightship Maps 日落公告（退路点名 Mapbox/Esri）：https://www.nianticspatial.com/en/products/maps-sdk-notice
- Google gaming 关停：https://developers.google.com/maps/deprecations
- Zenly 自研地图（TechCrunch）：https://techcrunch.com/2022/05/18/social-maps-app-zenly-rolls-out-its-own-maps/
- 3D Tiles for Godot（无移动端）：https://github.com/Battle-Road-Labs/3D-Tiles-For-Godot/issues/77
- MapLibre Android Vulkan 默认化：https://github.com/maplibre/maplibre-native/blob/main/platform/android/CHANGELOG.md
- Godot glTF 导出限制（ShaderMaterial）：https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/exporting_3d_scenes.html ；根动画 bug：https://github.com/godotengine/godot/issues/114110
- Mapbox 定价：https://www.mapbox.com/pricing ；token 安全：https://docs.mapbox.com/help/dive-deeper/how-to-use-mapbox-securely/
- 地图管理条例（属地适用）：https://www.gov.cn/zhengce/content/2015-12/14/content_10403.htm ；972 号通知：https://www.gov.cn/zhengce/zhengceku/202405/content_6950568.htm
- Mapbox attribution 要求：https://docs.mapbox.com/help/dive-deeper/attribution/

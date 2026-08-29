# 3D 地图调研全文附录（Mapbox × Godot）

调研日期：2026-08-25 ｜ 整理日期：2026-08-29

> 本文是调研的**完整底稿**：7 个并行调研维度的全部发现（含一手来源与置信度）、6 项关键结论的对抗验证裁决、完整性审查，以及评审阶段的深入问答沉淀。
> **决策与推荐方案**见同目录 [`2026-08-25-3dmap-mapbox-research.md`](2026-08-25-3dmap-mapbox-research.md)，本文不重复给结论，只保全证据。
> 调研方法：Workflow 并行 14 个子代理（7 扫描 + 6 对抗验证 + 1 完整性审查），441 次工具调用；验证一律只认一手来源（官方文档 / GitHub 源码与 issue / changelog / 本机大陆网络实测）。

## 目录

1. Mapbox GL JS + WebView 路线
2. Mapbox 原生 Maps SDK v11+（Android/iOS）
3. Godot 4 与原生视图/WebView 的混合集成
4. 行业先例与教训
5. 引擎内自渲染替代路线（对照组）
6. 角色资产管线（迁移代价）
7. 中国区可用性与商务/合规
8. 完整性审查（Critic）
9. 深入解读（评审问答沉淀）


## 1. Mapbox GL JS + WebView 路线

### 结论摘要

Mapbox GL JS 当前最新为 v3.29.0（2026-08-20 发布），v3 强制 WebGL2，自带 Standard 样式、3D 光照、地标建筑与 terrain，且已有正式的 model layer/addModel API 可直接放 glTF 模型——但官方明确声明 model layer 不支持任何 glTF 动画（关键帧、蒙皮、morph 全不支持），只能做节点旋转与材质覆盖级别的"部件动画"；官方给出的带完整动画的路线是 Custom Layer + three.js。该路线技术上成熟（官方示例、three.js AnimationMixer 播蒙皮动画无障碍），但生态有隐患：threebox 自 2022-06 起停更（仅 dependabot 提交、声明兼容 GL JS v2.x），更可靠的替代是 deck.gl ScenegraphLayer（支持 glTF 动画、经 MapboxOverlay interleaved 集成）或自己手写 custom layer。移动端 WebView 是本路线最大风险区：iOS Safari/WKWebView 有长期存在的内存增长与 WebGL 崩溃 issue（v3 时代仍有 #12906），角色持续动画要求每帧 triggerRepaint 导致整图 60fps 全量重绘，中端机 60fps 无官方证据背书，且官方从未发布 GL JS vs 原生 SDK 的性能对比；离线方面 GL JS 无官方支持（仅原生 SDK 有 offline region）。计费上 WebView 内跑 GL JS 按 map load 计（每次 Map 初始化一次，5 万次/月免费，超出 $5/千次起），对高频打开的移动 App 主页面可能显著贵于原生 SDK 的 MAU 口径。总体判断：该路线功能上可行、有官方背书的集成方式，但性能与离线两项硬指标均无正面证据，需真机 PoC 验证后才能采纳。

### 关键发现

- **GL JS 最新稳定版为 v3.29.0，发布于 2026-08-20，仍在高频迭代（约每月一个 minor）**（置信度：高）
  - GitHub Releases 显示 v3.29.0（2026-08-20）、v3.28.1（2026-08-07）、v3.28.0（2026-08-05）、v3.27.0、v3.26.0 等。v3.29 新增更细粒度手势控制 API（map.keyboard/dragRotate/touchZoomRotate 的 enable/disable 细分）。v3 系列自 3.0 起从 Flow 迁 TypeScript、废弃 WebGL1、强制 WebGL2（意味着 iOS 侧需 Safari/WKWebView 15+）
  - 来源：<https://github.com/mapbox/mapbox-gl-js/releases>
- **GL JS v3 的 3D 能力完整：Standard 样式（默认启用）、3D 光照/lightPreset、地标 3D 建筑、建筑与地形阴影、terrain**（置信度：高）
  - migrate-to-v3 官方指南原文：v3 enables the Mapbox Standard Style、realistic 3D lighting system、3D models for landmarks、building and terrain shadows；Standard（mapbox://styles/mapbox/standard）在不传 style 时为默认样式，经 map.setConfigProperty('basemap','lightPreset','dusk') 等配置。terrain/setTerrain 自 v2 起持续可用
  - 来源：<https://docs.mapbox.com/mapbox-gl-js/guides/migrate-to-v3/>
- **GL JS v3 有正式的 model layer 与 Map#addModel/hasModel/removeModel/listModels API，可用 model source 直接放 glTF/glb 模型**（置信度：高）
  - Map API 文档 Models 分组含 addModel()/hasModel()/removeModel()/listModels()；style 里可用 type:'model' 的 source + type:'model' 的 layer，支持 .gltf/.glb、Draco 与 Meshopt 压缩（v3.28 加了 Meshopt v1）、PBR metallic-roughness 材质。限制：单 mesh 最多 65,536 顶点（16 位索引）、不支持 EXT_texture_webp、仅 globe/Mercator 投影
  - 来源：<https://docs.mapbox.com/mapbox-gl-js/api/map/>
- **决定性限制：model layer 明确不支持 glTF 动画——关键帧动画、蒙皮（skinning）、morph target 全部不支持，本项目的骨骼动画角色不能走 model layer**（置信度：高）
  - 官方 Using 3D Models 指南 Limitations 原文：'No support for glTF animations (key frame animations, skinning, or morph targets)'。仅支持通过 nodeOverrides（节点 orientation）和 materialOverrides/model-color/model-emissive-strength/model-rotation 等 paint 属性做刚体部件级动画（如开车门、螺旋桨），官方 animate-along-route 示例即此类。指南同页明确指路：'For full glTF support including animations, use custom layers with Three.js'
  - 来源：<https://docs.mapbox.com/style-spec/guides/using-3d-models/>
- **Custom Layer + three.js 有官方维护的一手示例，且示例已随版本更新到 v3.29.0，是官方认可的带动画 glTF 路线**（置信度：高）
  - 官方示例 'Add a 3D model with three.js'：CustomLayerInterface + three.js（示例用 three@0.126 + GLTFLoader）+ MercatorCoordinate.fromLngLat 做地理定位，Map 构造时开 antialias:true 使自定义层有 MSAA；渲染循环需 map.triggerRepaint()。页面同时链到 threebox 版示例。注意共享 GL context 需 renderer.autoClear=false/resetState() 管理状态
  - 来源：<https://docs.mapbox.com/mapbox-gl-js/example/add-3d-model/>
- **在 three.js custom layer 中播骨骼蒙皮 glTF 动画技术上成熟，但代价是每帧 triggerRepaint 强迫整张地图 60fps 持续全量重绘**（置信度：高）
  - three.js 的 SkinnedMesh+AnimationMixer 是核心能力，与渲染到哪个 context 无关；官方文档明确此路线是'完整 glTF 支持（含动画）'的推荐方案；threebox 自带 11-animation.html 蒙皮动画示例。风险点不在动画本身，而在 GL JS 默认按需渲染，角色常驻动画后地图失去 idle 省电优势，中端机 DPR 高时 fill-rate 与电耗压力大（无官方缓解方案，只能自行降 DPR/限帧）
  - 来源：<https://docs.mapbox.com/style-spec/guides/using-3d-models/>
- **threebox 处于停更状态：最后一个 release v2.2.7 是 2022-06-03，此后仅 dependabot 依赖升级提交，官方声明兼容线停在 GL JS v2.x，未声明 v3 兼容**（置信度：高）
  - GitHub API：jscastro76/threebox 最新 release v2.2.7（2022-06-03），npm threebox-plugin@2.2.7 同日发布后再无版本；2026-06 的最近提交全是 dependabot（tape/picomatch 等 devDependency bump），无功能维护。原 peterqliu/threebox 2021-04 已归档。文档声明兼容 mapbox-gl-js v2.2.0/three.js r132 时代。用于 v3 需自行验证（v3 保持 CustomLayerInterface 向后兼容，社区有人在 v3 上跑通，但无官方保证）
  - 来源：<https://github.com/jscastro76/threebox>
- **threebox 的活维护替代：deck.gl ScenegraphLayer 支持带动画的 glTF（含骨骼动画），经 MapboxOverlay（interleaved:true）与 GL JS v3 同 context 渲染**（置信度：高）
  - ScenegraphLayer 用 scenegraph 指向 glb，_animations:{'*':{speed:N}} 播放 glTF 动画（属性带下划线为实验前缀），_lighting:'pbr'；@deck.gl/mapbox 的 MapboxOverlay 实现 IControl，interleaved 模式可插入 Mapbox 图层栈并配 beforeId 排序（旧 MapboxLayer 已移除）。deck.gl 由 vis.gl/OpenJS 基金会持续维护。已知小坑：interleaved 下后加的 Mapbox 图层排序问题 issue #9222
  - 来源：<https://deck.gl/docs/api-reference/mesh-layers/scenegraph-layer>
- **iOS 前提条件满足但有历史包袱：WKWebView 自 Safari 15（iOS 15，2021-09）起 WebGL2 GA 且 WebGL 跑在 Metal(ANGLE) 上，GL JS v3 的 WebGL2 硬要求可满足**（置信度：高）
  - WebKit 官方博客宣布 Safari 15 支持 WebGL2、WebGL 实现基于 Metal（ANGLE 后端）。即 App 最低 iOS 15。注意 iOS 15 初期有 'GPU Process: Canvas Rendering' 引发的 WebGL 性能回退投诉（apache/cordova-ios#1246、WebKit bug 230749），后续版本修复；Android System WebView 为 Chromium 内核，WebGL2 无障碍
  - 来源：<https://webkit.org/blog/11989/new-webkit-features-in-safari-15/>
- **移动端 WebView 性能证据整体偏负面且缺乏正面基准：iOS Safari/WKWebView 存在 v3 时代仍未关闭的内存增长 issue，官方从未发布 GL JS vs 原生 SDK 性能对比**（置信度：高）
  - 关键 issue：#12906 'Safari on macOS and iOS memory overuse from user movement'（v3 时代，缩放/平移导致内存持续增长）；changelog v3.1.1 修复 'WebGL 在部分移动设备（iOS Safari）随机崩溃至不可恢复状态'，v3.1.0 修复多纹理样式内存过高；历史上 #8771/#8282/#4052 等 iOS 内存崩溃反复出现；Android WebView 大量 marker 卡顿 #6212。#12953 用户索要官方 GL JS vs 原生 SDK 对比，无官方数据。没有任何一手来源证明中端机 WebView 内 60fps 可达，需 PoC 实测
  - 来源：<https://github.com/mapbox/mapbox-gl-js/issues/12906>
- **离线地图：GL JS 无官方离线支持，官方离线能力（offline region/tile pack，上限 750 tile pack）只存在于原生 Maps SDK for Android/iOS；GL JS 只能靠第三方 Service Worker/IndexedDB 方案，且受 ToS 缓存条款约束**（置信度：高）
  - 官方 Offline maps 帮助页适用产品仅列 Maps SDK for Android/iOS 与 Raster/Vector Tiles API，无 GL JS；原生 SDK 可按 bbox+zoom+style 下载全量资源入库。社区方案如 map-gl-offline（IndexedDB 存 tile/style/font/sprite，因 GL JS v3 移除 addProtocol 改用 Service Worker 拦截请求）为非官方，商用需自查 Mapbox ToS 缓存限制
  - 来源：<https://docs.mapbox.com/help/troubleshooting/mobile-offline/>
- **计费：GL JS 按 map load 计费——每次 Map 对象初始化计一次，含无限次矢量/栅格瓦片请求；免费 5 万 loads/月，超出后 $5.00/千次起阶梯递减**（置信度：高）
  - 官方 pricing 页原文：'A map load is counted every time Mapbox GL JS initializes on a webpage or in a web app'，含 unlimited Vector/Raster Tiles API 请求。阶梯：≤50,000 免费；50,001–100,000 $5.00/千；100,001–200,000 $4.00/千；200,001–1M $3.00/千；1M–5M $2.50/千。对移动 App 的含义：主页面每次冷启动/重建 WebView 重新 new Map 都计一次 load；对比原生 Maps SDK 按 MAU 计（月活 ≤25,000 免费），高频日活场景下 map loads 口径可能明显更贵（一个日活用户每月可产生几十次 load）
  - 来源：<https://www.mapbox.com/pricing>
- **手势交互：GL JS 自带完整移动端手势集（默认开启拖拽平移、双指捏合缩放+旋转、双指拖拽俯仰、双击缩放），v3.29 又补了细粒度开关，但触控手感与原生 SDK 的差距无量化证据，低帧率下惯性滑动会失真**（置信度：中）
  - Map options：touchZoomRotate（pinch 缩放+旋转，默认 true）、touchPitch（双指拖拽俯仰，默认 true）、cooperativeGestures（嵌入页防误触模式，App 全屏地图应保持关闭）；示例页均带 viewport meta user-scalable=no 防页面级缩放冲突。v3.29.0 新增 touchZoomRotate.isRotationEnabled/isTapDragZoomEnabled 等细分 API。已知负面证据：#1844 指出移动端触控感知性能差于原生（fling 在主线程 GC/卡顿时会异常大幅漂移，sub-30fps 下显著）——该 issue 年代久远，v2 重写手势系统后有改善，但'WebView 手感 == 原生 SDK'同样无一手证据；WKWebView 内触摸事件走 WebKit 主线程，重渲染帧率下降时手势跟手性同步劣化
  - 来源：<https://docs.mapbox.com/mapbox-gl-js/api/map/>
- **对本项目的路线含义：WebView 路线下角色渲染只能选 custom layer 系（three.js 手写 / deck.gl ScenegraphLayer / 赌 threebox 在 v3 上能跑），且现有 Godot 资产（Skeleton3D+AnimationPlayer+toon shader+换装）必须整体重写为 three.js 生态实现，Godot 引擎在此路线中被完全绕开**（置信度：高）
  - 换装系统需用 three.js 重做（GLTFLoader 加载部件 + SkinnedMesh.bind 共享骨架或 attach 到 Bone），toon shader 需从 Godot shading language 移植为 GLSL/ShaderMaterial 或 three.js MeshToonMaterial，动画重定向到 three.js AnimationMixer。这是资产管线级重写而非移植；'角色保留现有材质/动画/换装能力'这条硬性需求在此路线下实际变成'等价重实现'。此为基于官方 API 能力边界的推论，非单一来源可引
  - 来源：<https://docs.mapbox.com/mapbox-gl-js/example/add-3d-model/>

### 遗留问题（该维度未决）

- 中端 Android（如骁龙 7 系 + System WebView）与 iPhone SE/13 级别设备上，GL JS v3 Standard 样式 + custom layer 蒙皮角色持续动画的实测 fps/内存/发热——无任何一手来源，必须真机 PoC（建议直接量：DPR 钳制到 2 与不钳制两组、lightPreset 昼夜两组）
- threebox v2.2.7 在 GL JS v3.29 上是否实际可跑（CustomLayerInterface 向后兼容理论上可行，但无官方/仓库声明）；若不可跑，deck.gl ScenegraphLayer 的 _animations 对多部件换装角色（共享骨架、运行时增删 SkinnedMesh）支持度如何，还是必须手写 three.js custom layer
- Mapbox ToS 对'在原生移动 App 内嵌 WebView 跑 GL JS'的许可与计费归类是否有专门条款（是否强制要求用原生 SDK / map loads 口径是否适用于 App 内 WebView），需查 Mapbox Product Terms 或问商务
- WebView 与 Godot 的混合架构问题（本维度未覆盖）：Godot 4.7 内嵌 WebView（Android WebView/WKWebView 叠在 Godot 视图上或反向）是否有成熟插件，还是整个 App 壳放弃 Godot 改原生壳+WebView，角色也进 WebView——该架构决策影响本路线可行性权重
- GL JS 每帧 triggerRepaint 常驻重绘的电耗数据（对标 Pokémon GO 类常亮主页面），无公开测量，PoC 需加电流计或电池 API 采样

### 对抗验证

#### 验证 1.1：裁决 ⚠️ 部分成立/需修正

"GL JS + three.js custom layer 播放骨骼动画 glTF"这条技术路线本身成立（官方文档明确指路、threebox 有蒙皮动画示例、社区在 v3 上实跑过），但"中端手机 WebView 里稳定接近 60fps"这半句不可信：找不到任何一手正面证据（无官方基准、无第三方移动端实测报告、官方 three.js 示例甚至不播动画且用的是 2021 年的 three@0.126.0），而结构性反证充分——custom layer 持续动画迫使整张地图每帧全量重绘（官方 issue 实测 CPU 显著高于独立 context 方案，2018 年桌面 Chrome 上 >20 个动画对象即卡顿）、iOS WKWebView 在低电量模式下 rAF 被硬性节流到 30fps（"稳定 60fps"对相当比例会话在物理上不可达）、GL JS v3 在中端 Android GPU 上 2026 年仍出过崩溃级回归（v3.21/3.22 Pixel 8a Mali-G715 UBO 崩溃，3.23.1 才修复）。该断言必须降级为"技术可行、性能未验证，采用前必须在目标中端真机 WebView 上做 PoC 实测（单角色蒙皮 + Standard 样式 + 持续 triggerRepaint + 高 DPR），并准备降 DPR/限帧/降样式复杂度的退路"。threebox 停更结论确认：最新 release v.2.2.7（2022-06-03），此后至 2026-06 全部提交为 dependabot 依赖升级，README 官方兼容声明停留在 mapbox-gl-js v1.11.1/v2.0.1 + three r132（无任何 v3 兼容声明）；社区确有项目以 threebox-plugin@2.2.7 + mapbox-gl>=3.0.0 + three@0.170 组合运行，但需自行打崩溃遏制补丁，2024–2026 年的功能性 issue 基本无维护者响应——生产采用 threebox 等于自担 fork 维护责任。

证据：

- 【无官方动画示例】官方 'Add a 3D model with three.js' 示例页当前实际引用 mapbox-gl-js v3.29.0 + three@0.126.0（2021 年 2 月的 three 版本），代码含 GLTFLoader 与 triggerRepaint，但全页无 AnimationMixer——官方示例加载的是静态模型，从未演示过骨骼动画播放，更无移动端性能数据（页面源码 grep 实证：three@0.126.0 出现 8 次、mapbox-gl-js/v3.29.0 出现 8 次、triggerRepaint 出现 6 次、AnimationMixer 0 次）
  - <https://docs.mapbox.com/mapbox-gl-js/example/add-3d-model/>
- 【官方指路属实】Using 3D Models 指南 Limitations 原文确认 model layer 'No support for glTF animations (key frame animations, skinning, or morph targets)'，且明确写 'For full glTF support including animations, use custom layers with Three.js'——上游此条结论无误；但注意这只是文字指路，官方没有配套的动画示例代码，更没有性能承诺
  - <https://docs.mapbox.com/style-spec/guides/using-3d-models/>
- 【结构性反证一】issue #7591（threebox 原作者 peterqliu 本人提交）：three.js 场景走 custom layer 相比独立 GL context 有'significant perf loss'，约 20 个动画对象以上即明显卡顿（fairly major choppiness），而独立 canvas 方案 200 个对象仍流畅——这还是桌面 Chrome；持续动画场景下 scene rerender 与 map repaint '*constantly*' 同时发生是架构性成因
  - <https://github.com/mapbox/mapbox-gl-js/issues/7591>
- 【结构性反证二】issue #7629：报告者实测同一动画层，Mapbox custom layer 实现的 CPU 占用显著高于 deck.gl 独立 context 实现，根因是 render() 里 triggerRepaint 使'the whole map needs to be redrawn every time'；社区给出的缓解方案恰恰是放弃 custom layer、自建独立 GL overlay 只同步相机矩阵。issue 以 performance 标签存在 3 年后关闭，无官方修复
  - <https://github.com/mapbox/mapbox-gl-js/issues/7629>
- 【'稳定60fps'的硬性证伪条件】WebKit 官方 bug 168837：iOS 在低电量模式下将 requestAnimationFrame 硬性节流至 30fps，WKWebView 同样受影响（另见 bug 215745 确认 iOS 14+ 行为）。任何用户开省电模式时角色动画与地图渲染即被腰斩到 30fps，这使'稳定接近 60fps'对全体用户在物理上不可保证——原生 Metal 渲染不受此 Web 层节流约束
  - <https://bugs.webkit.org/show_bug.cgi?id=168837>
- 【中端移动 GPU 是 v3 回归多发面】issue #13662（2026-04-22）：GL JS v3.21/v3.22 的 symbol 层 UBO 优化在 Pixel 8a（Mali-G715，典型中端 Android GPU）上 2 秒内 WebGL context 崩溃（'Aw, Snap!'），streets-v12 标准样式即触发，降级 3.19.1 可绕过，v3.23.1 确认修复。说明 GL JS 快速迭代（月更）下中端移动 GPU 兼容性会反复出险，WebView 路线需持续回归测试锁版本
  - <https://github.com/mapbox/mapbox-gl-js/issues/13662>
- 【无官方性能对比数据】issue #12953 'Compare Performance: Mapbox GL JS vs. Native iOS/Android SDKs'（2023-11 提出）至今仍 open，官方从未发布 GL JS 与原生 SDK 的性能对比或任何移动端帧率基准——上游此条属实
  - <https://github.com/mapbox/mapbox-gl-js/issues/12953>
- 【修正上游一处错误】#12906（Safari/iOS 内存过量增长导致 WKWebView 崩溃）并非'v3 时代仍未关闭'——它已于 2023-12-04 以 completed 关闭（报告者定位为显存过量分配，产出 PR #12924）。但'iOS 内存问题反复出现'的大方向仍成立：2026-06 仍有新的内存累积 issue open（#13685/#13688，raster-array 时间轴场景）
  - <https://github.com/mapbox/mapbox-gl-js/issues/12906>
- 【threebox 停更确认，GitHub API 实证】repo 未 archived 但：最新 release v.2.2.7 发布于 2022-06-03；2026 年 2–6 月全部提交为 dependabot devDependency 升级（tape/picomatch/shell-quote/minimatch），维护者仅合并机器人 PR；master README Compatibility 节原文声明 'Mapbox-gl-js v1.11.1. or v.2.0.1' + 'Three.js 132 (already bundled)'，无一字提及 GL JS v3；67 个 open issue，2024–2026 年的功能 issue（#428/#429/#435/#437/#441/#445/#446）持续无维护者解决
  - <https://github.com/jscastro76/threebox>
- 【threebox 蒙皮动画示例属实但基于 v2】examples/11-animation.html 确实加载 soldier.glb 并 playAnimation()（骨骼蒙皮动画），但示例页引用的是 api.mapbox.com/mapbox-gl-js/v2.2.0——threebox 全部示例（含 15-performance.html 性能测试页）均锁在 GL JS v2.2.0，不构成 v3 兼容或移动端性能证据
  - <https://github.com/jscastro76/threebox/blob/master/examples/11-animation.html>
- 【threebox 在 v3 上'能跑但带伤'的社区个例】2026 年活跃项目 prieston/klorad 的 packages/engine-mapbox/package.json 实际组合为 threebox-plugin@2.2.7 + mapbox-gl>=3.0.0 + three@0.170.0，证明 v2.2.7 在 GL JS v3 上可运行；但同仓库 2026-05 有 PR #138 'fix(engine-mapbox): contain Threebox render crashes (flyTo)'——需要自行写崩溃遏制代码才能生产使用，无任何官方兼容保证
  - <https://github.com/prieston/klorad>
- 【threebox 与 GL JS 新特性组合的现存缺陷】threebox issue #445（2025-08-29，open 无回应）：threebox 模型与 Mapbox DEM terrain 组合时出现面片随机消失（hidden faces）渲染缺陷，官方示例即可复现——本项目若用 terrain/Standard 样式叠 threebox，此类深度冲突问题无上游修复渠道
  - <https://github.com/jscastro76/threebox/issues/445>
- 【WebView 历史负面证据】#6212：Android WebView 内大量自定义 marker 性能显著低于桌面（2018）；同期 #6879 报告 Cordova iOS 下 GL JS 低性能。年代久远仅作背景，但至今没有任何反向的正面移动端基准来推翻它们
  - <https://github.com/mapbox/mapbox-gl-js/issues/6212>

<details><summary>验证方法与裁决口径（展开）</summary>

验证方法：全部走一手来源——GitHub REST API 拉取 threebox 仓库元数据/releases/commits/issues 原文与 mapbox-gl-js issue 原文及评论、curl 抓取 docs.mapbox.com 官方页面源码逐词 grep、raw.githubusercontent.com 抓取 threebox README/package.json/示例源码、WebKit bugzilla。判 PARTIALLY 的理由：断言由两半构成——(1)'custom layer 能播骨骼动画 glTF'为 CONFIRMED（官方指南明文指路+threebox 示例+社区实跑）；(2)'中端手机 WebView 稳定接近 60fps'为 UNCLEAR 偏 REFUTED：零正面一手证据（搜索多轮未找到任何移动端 fps 实测/demo 报告），且'稳定'一词被 iOS 低电量 30fps 硬节流直接证伪、被全图重绘架构（#7591/#7629）和中端 GPU 崩溃回归（#13662）严重削弱。对上游的修正与补充：(a) #12906 已于 2023-12-04 关闭，上游'仍未关闭'表述过时，但 2026 年另有内存 issue open（#13685/#13688）；(b) 上游称官方示例'是官方认可的带动画 glTF 路线'需打折——示例本身不播任何动画且 three 版本停在 0.126.0（约 5 年未升），官方对'动画'仅有一句文字指路，无示例无基准无性能承诺；(c) threebox 停更结论确认无误，另补充两条上游没有的关键事实：社区存在 threebox@2.2.7+GL JS v3+three 0.170 的实跑组合（需自行打崩溃补丁），以及 threebox 与 DEM/terrain 组合有未修复渲染缺陷；(d) #7629 的社区结论提示：若最终仍走 WebView 路线，'独立 GL context 叠加+相机矩阵同步'（deck.gl 模式）比 custom layer 更省 CPU，这与上游推荐 deck.gl ScenegraphLayer 的方向一致，但 interleaved 模式同样共享 context，需实测对比 interleaved 与 overlaid 两种模式。对决策的含义：任何'GL JS WebView 出图'方案立项前，必须先做最小 PoC（目标中端真机、WebView 容器、Standard 样式、单蒙皮角色持续动画、开 antialias、原生 DPR）实测帧率/发热/内存，否则性能风险不可控；threebox 不应作为生产依赖引入，若用需按 fork 自维护对待。

</details>


## 2. Mapbox 原生 Maps SDK v11+（Android/iOS）

### 结论摘要

Mapbox 原生 Maps SDK v11 系（2026-08 最新稳定 11.28.4，Android/iOS 版本号同步）是活跃维护的成熟路线：iOS 全程 Metal 渲染，Android 默认 OpenGL ES、自 11.24.1 起提供 Vulkan 公测预览（但该预览尚不支持 Custom Layer API）。对本项目最关键的结论是：model layer / addStyleModel / LocationPuck3D 虽支持 glTF 2.0 静态模型，但官方 style spec 明确**不支持任何 glTF 内置动画（关键帧、骨骼蒙皮 skinning、morph targets 全部不支持）**，只能通过 node/material overrides 做刚体部件旋转与材质动画——即"角色骨骼动画+换装"无法走 model layer 原生路线。要在地图渲染管线内画完整蒙皮角色，唯一出路是 Custom Layer API（iOS 每帧给 MTLRenderCommandEncoder + 投影矩阵，共享深度缓冲，官方有 SceneKit 完整场景示例，深度可与地图/地形融合；Android 每帧给 GL 上下文 + projectionMatrix），技术上可行但等于放弃 Godot 渲染器、在 SceneKit/Filament/自研层重建整套角色渲染（toon shader、换装、动画状态机），迁移成本极高。相机状态（center/zoom/bearing/pitch、FreeCameraOptions 四元数朝向）每帧可读，投影矩阵仅在 custom layer 回调内提供。计费为 Maps SDKs for Mobile MAU：免费 25,000 MAU/月，超出 $4.00/千起阶梯递减。呈现载体上 Android MapView 默认 SurfaceView（可切 TextureView 获得透明背景/alpha 合成），iOS MapView 是内嵌 CAMetalLayer 的 UIView 且支持 presentsWithTransaction 同步，两端都可作为普通平台 View 与其他视图（如透明 Godot 层）叠加——这为"原生地图打底 + Godot 透明覆盖渲染角色"的混合架构留了门。

### 关键发现

- **Android/iOS Maps SDK v11 版本号同步且高频维护，2026-08 最新稳定版为 11.28.4，最新预发布为 11.30.0-rc.1**（置信度：高）
  - Android changelog：11.28.4（2026-08-20）、11.30.0-rc.1（2026-08-24）、11.29.0-rc.1（2026-08-10）；iOS changelog 完全同步：11.28.4（2026-08-20）、11.30.0-rc.1（2026-08-24）。发版节奏约每 2-4 周一个 minor。注意：Mapbox 计划 2026-12 停止通过 CocoaPods 分发 iOS SDK，需用 Swift Package Manager。
  - 来源：<https://github.com/mapbox/mapbox-maps-android/blob/main/CHANGELOG.md>
- **iOS 渲染后端是 Metal；Android 默认 OpenGL ES，自 v11.24.1 起提供 Vulkan 公测预览（独立 artifact），且 Vulkan 预览明确不支持 Custom Layer API**（置信度：高）
  - iOS 官方仓库描述即 'powered by vector tiles and Metal'。Android v11.24.1（2026-05-18 后发布）changelog：新增 Vulkan 后端 Public Preview，独立 artifact android-core-vulkan / android-core-vulkan-ndk27 替换默认 OpenGL 的 android-core；已知限制：建议 Android 12 (API 31)+（后续版本已把最低要求提到 API 31）、仅 arm64-v8a、无 OpenGL 自动回退、不支持 MapWidget (Android Auto)、**Custom layer API 不支持**、不支持 MapView.snapshot()。若走自定义层画角色路线，Android 端被锁死在 OpenGL ES 后端。
  - 来源：<https://github.com/mapbox/mapbox-maps-android/blob/main/CHANGELOG.md>
- **model layer 的 glTF 2.0 支持明确排除一切内置动画：关键帧动画、骨骼蒙皮（skinning）、morph targets 均不支持——蒙皮角色动画无法走 model layer**（置信度：高）
  - 官方 Style Spec 'Using 3D Models' 指南（适用 GL JS + iOS + Android SDK，2026-08 现行版）Limitations 原文：'Animation: No support for glTF animations (key frame animations, skinning, or morph targets)'，并写明 'For full glTF support including animations, use custom layers'。可替代能力仅限：nodeOverrides 对命名节点做整体朝向旋转（车门/螺旋桨式刚体动画）、materialOverrides 改 model-color/model-emissive-strength/model-opacity，可配 feature-state 表达式驱动。其他硬限制：每 mesh 顶点上限 65,536（16 位索引）、不支持 glTF 相机/灯光/多场景、纹理不支持 WebP（EXT_texture_webp）、仅 metallic-roughness PBR、官方建议单个动画模型 <25,000 顶点。Android 端 ModelLayer 至 v11.13+ 仍标注 @MapboxExperimental。
  - 来源：<https://docs.mapbox.com/style-spec/guides/using-3d-models/>
- **Mapbox 官方 2023-10 即答复 ModelLayer 不支持 glTF 内置动画、'计划未来实现'，至 2026-08 仍未落地——不能指望短期补上**（置信度：高）
  - mapbox-maps-ios issue #2025（'gltf/glb animations in ModelLayer'，2023-09-27 提出，针对 v11.0.0-beta.4）：Mapbox 成员 evil159 于 2023-10-05 答复 'At the moment ModelLayer doesn't support animations within gltf/glb files. We are planning to implement the support for this in the future'，随即关闭。此后近 3 年的 changelog 与 style spec 均无骨骼/关键帧动画支持落地记录（2026-08 现行 style spec 仍列为不支持）。
  - 来源：<https://github.com/mapbox/mapbox-maps-ios/issues/2025>
- **LocationPuck3D 支持 glTF/glb 自定义 3D 定位 puck，但同样无 glTF 动画播放；动画能力上限是实验性的节点 TRS/材质属性动画（AnimatableModel），非骨骼蒙皮**（置信度：高）
  - Android LocationPuck3D（v11.13 API 文档）字段：modelUri、modelScale/modelRotation/modelTranslation 及各自 expression 版、modelOpacity、modelColor、modelEmissiveStrength、modelCastShadows/ReceiveShadows、modelScaleMode(VIEWPORT/MAP)、materialOverrides/nodeOverrides（@MapboxExperimental）、modelElevationReference。无任何播放 glTF 内置动画的 API。Android changelog 早期引入实验性 AnimatableModel / ModelNodePart / ModelMaterialPart API，可对 puck 模型的命名部件做属性动画（本质是 node override 的 TRS 插值）。iOS 有官方 custom-3D-puck 示例（Puck3DConfiguration 同能力）。角色走路/待机等蒙皮动画不可能用 puck 实现。
  - 来源：<https://docs.mapbox.com/android/maps/api/11.13.0/mapbox-maps-android/com.mapbox.maps.plugin/-location-puck3-d/>
- **Custom Layer API 每帧提供完整相机参数与投影矩阵，可在地图渲染管线内共享深度缓冲绘制任意 3D 内容；官方 SceneKit 示例证明画完整 3D 场景并与地图/地形深度融合可行**（置信度：高）
  - Android：CustomLayerHost.render(CustomLayerRenderParameters) 每帧调用，参数含 width/height/latitude/longitude/zoom/bearing/pitch/fieldOfView/projectionMatrix(List<Double>)/elevationData/renderToTilesIDs；在地图 GL 上下文内直接发 GL 命令，可自行管理 depth/stencil state。iOS：CustomLayerHost 协议，renderingWillStart(metalDevice, colorPixelFormat, depthStencilPixelFormat) 初始化，render 每帧拿 CustomLayerRenderParameters + 地图同一 render pass 的 MTLRenderCommandEncoder。官方 SceneKit 示例在自定义层内用 SCNRenderer 渲染完整 SCNScene（模型+灯光+地形深度遮挡），关键对齐点 renderer.usesReverseZ = false（gl-native 不用 reverse-Z）。结论：画完整蒙皮角色技术可行、深度可与地图融合，但必须在 SceneKit（iOS）/自研 GL 渲染器（Android）里重建骨骼动画、toon shader、换装系统——Godot 的 Skeleton3D/AnimationPlayer/shader 资产无法复用，等于为两个平台各写一个迷你角色渲染引擎；且 Android Vulkan 后端不支持该 API。
  - 来源：<https://docs.mapbox.com/ios/maps/examples/sceneKit/>
- **相机状态每帧可读：cameraState（center/zoom/bearing/pitch）+ CameraChanged 事件 + FreeCameraOptions（位置/海拔/四元数朝向）；但投影矩阵在公共 API 层不直接暴露，只在 custom layer 回调参数里给**（置信度：高）
  - 两端 MapboxMap.cameraState 随时可读；CameraChanged 事件逐帧回调。FreeCameraOptions 提供 position（墨卡托坐标）、orientation（单位四元数 [x,y,z,w]）、setLocation/setAltitude（v11 新增拆分方法，Android migrate-to-v11 文档记载），与 CameraOptions 完全互换，可用 getFreeCameraOptions()/setCamera(FreeCameraOptions) 读写。若在地图渲染管线外（如叠加的 Godot 层）复现地图相机，需用这些参数自行重建投影矩阵（Mapbox 相机模型：以屏幕中心为 pivot 的 fov/pitch/bearing/zoom，fieldOfView 在 custom layer 参数中给出）；精确矩阵仅 CustomLayerRenderParameters.projectionMatrix 提供。
  - 来源：<https://docs.mapbox.com/android/maps/api/10.8.0/mapbox-maps-android/com.mapbox.maps/-free-camera-options/>
- **v11 性能总体口碑良好（原生 Metal/GL 渲染、持续性能优化），但 Android 端有真实的 ANR/崩溃记录史，需锁定较新的补丁版本**（置信度：中）
  - 正面：v11 与 GL JS v3 同代渲染引擎（官方博客 'Explore GL JS v3 & Mobile Maps v11'），changelog 持续有性能项（异步 tile 上传、landmark LOD、zoom-out 动画优化、Vulkan 路线）。负面记录：#2639 ANR（v11.12.0，native 库初始化 mutex，三星/小米/vivo + Android 11-13）、#2573 ANR（v11.9.2，Android 14 / S23 Ultra）、#2240 ViewAnnotations 崩溃（v11.0.0）、近期 changelog 仍在修 use-after-free / ConcurrentModificationException / VRR 帧同步等问题。对'中端机 60fps 只渲染地图+puck'的诉求，原生 SDK 是几条路线里性能上限最高的；风险主要在特定机型 ANR 与新版本回归，建议跟随最新 stable 并做机型灰度。
  - 来源：<https://github.com/mapbox/mapbox-maps-android/issues/2639>
- **计费口径：Maps SDKs for Mobile 按 MAU 计费，免费额度 25,000 MAU/月，超出后每千 MAU $4.00 起阶梯递减；MAU 内含 Vector/Raster Tiles API 无限请求**（置信度：高）
  - pricing 页（2026-08-25 抓取）：Up to 25,000 免费；25,001–125,000 $4.00/1000；125,001–250,000 $3.20/1000；250,001+ $2.40/1000；1,250,000+ 联系销售。MAU 定义（docs pricing guide）：billing period（随账单周期非自然月）内调用过 SDK 功能（如显示地图）的独立用户计 1 MAU，卸载重装会多计（SDK 不存个人标识）；覆盖 Vector Tiles API 与 Raster Tiles API 的全部请求，无预付/年约要求。对照：GL JS 走 Web 端则按 Map Loads 计费（50k 免费，$5.00/千起），移动 App 内嵌 WebView 用 GL JS 的计费口径需另行确认，原生 SDK 的 MAU 口径对移动 App 通常更划算。
  - 来源：<https://www.mapbox.com/pricing>
- **呈现载体：Android MapView 默认 SurfaceView、可切 TextureView 获得透明背景与 alpha 合成；iOS MapView 是内嵌 CAMetalLayer 的 UIView；两端均可与其他平台 View 自由叠加——支持'地图打底 + 透明 Godot 层画角色'的混合架构**（置信度：高）
  - Android：MapInitOptions.textureView: Boolean（默认 false = SurfaceView；true = TextureView）。官方 transparent-background 示例明确：透明背景需 textureView 渲染（TextureView 支持 alpha 合成，SurfaceView 不支持通用 alpha 叠加但 Z-order 上可被其他 View 覆盖）；TextureView 有额外合成开销。iOS：MapView(UIView) 底层为 CAMetalLayer，提供 presentsWithTransaction 属性（默认 false 异步出帧；设 true 用 CoreAnimation 事务同步，官方注明用于'UIKit 元素钉在经纬度上'的场景，减少叠加层抖动——对 Godot/UIKit 叠加角色跟随地图点位直接相关）；地图自身背景透明通过 style 里省略或透明化 background layer 实现。
  - 来源：<https://docs.mapbox.com/android/maps/examples/transparent-background/>

### 遗留问题（该维度未决）

- glTF 内置动画支持虽在 2023 年被官方称'计划实现'，但至今没有 roadmap 时间点——是否值得直接向 Mapbox 提工单/销售渠道确认，作为长期路线风险输入？
- 若采用'原生 MapView 打底 + Godot 透明层画角色'混合架构：Godot 4.7 在 Android（作为子 View/透明 GLSurfaceView）与 iOS（透明 MTKView 叠加）嵌入原生 App 的透明背景、触摸事件穿透/转发、双渲染器并存的功耗表现，需要单独维度验证（本维度未查）。
- 叠加架构下角色与地图的遮挡关系只能近似（Godot 层拿不到地图深度缓冲）：角色被建筑/地形遮挡的需求是否存在？若存在，只有 custom layer 路线能做真深度融合。
- Android Vulkan 后端何时 GA、何时补上 Custom Layer API 支持——若两年内 Mapbox 把默认后端切到 Vulkan 而 custom layer 断供，自定义层路线有长期维护风险。
- 每帧用 cameraState/FreeCameraOptions 在地图渲染管线外重建与 Mapbox 完全一致的投影矩阵（含 fov、近远平面、padding、地形海拔）是否有官方公式/参考实现？GL JS 有社区资料，原生端需按 CustomLayerRenderParameters.projectionMatrix 逆向校验。
- 中国大陆的瓦片访问延迟、合规（测绘资质/GCJ-02 偏移）未在本维度调查，若 App 面向国内用户需另行评估。
- iOS SceneKit 已被 Apple 标记为 soft-deprecated（WWDC24 起建议迁 RealityKit）：custom layer 路线若选 SceneKit 承载角色，需评估其长期可用性。

### 对抗验证

#### 验证 2.1：裁决 ✅ 证实

截至 2026-08-25，Mapbox model layer 与 LocationPuck3D 在 GL JS / iOS / Android 三端均完全不能播放 glTF 文件自带的任何动画（关键帧 node/TRS 动画、骨骼蒙皮 skinning、morph targets 全部不支持），只能渲染静态模型；动画能力上限为：整模型级 model-rotation/model-translation/model-scale 等 paint 属性逐帧驱动 + 命名节点级 nodeOverrides（仅 orientation 三轴欧拉角旋转，无节点级平移/缩放）+ materialOverrides 材质属性（color/emissive-strength/opacity 等），可用 feature-state 表达式或客户端动画器（Android 实验性 AnimatableModel/ModelNodePart，ModelNodePart 仅暴露 rotation）驱动——即"车轮/螺旋桨/车门"式刚体部件旋转，绝非蒙皮角色动画。带蒙皮动画的卡通角色不可能直接交给 Mapbox model layer 或 3D puck 渲染，官方指定的唯一出路是 custom layer 自行渲染（GL JS 配 Three.js；iOS Metal/SceneKit；Android 自研 GL 渲染器）。对上游结论的两处修正：(1) Android ModelLayer 已于 v11.17.0（2025-12-04）promote 到 stable，不再是类级 @MapboxExperimental（仅个别新属性如 modelAllowDensityReduction/modelColorUseTheme 仍为实验性），"至 v11.13+ 仍标注实验性"的说法已过时；(2) 节点覆盖不是"TRS 插值"而是仅 R（旋转/orientation），style spec 的 modelNodeOverride 结构只有 orientation 一个字段，节点级 paint 属性也只有 model-rotation。另补充：2026-01/02 两端新增的 ModelSource/ModelNodeOverride/ModelMaterialOverride 交互式模型 API（Android 11.18.1、iOS 11.19.0-rc.1）仍只是上述覆盖机制的封装，未引入任何 glTF 动画播放能力。

证据：

- 2026-08-25 抓取的现行官方指南，开篇明言'This guide details feature support for static 3D model rendering in Mapbox GL JS and the Mapbox Maps SDK for iOS and Android'（三端统一）；Limitations 原文逐字：'Animation: No support for glTF animations (key frame animations, skinning, or morph targets)'、'Model parts and materials can be animated using model node and material overrides'、'For full glTF support including animations, use custom layers with Three.js'；节点覆盖的 paint 属性仅列 model-rotation；其余限制同步确认：每 mesh 65,536 顶点上限（16 位索引）、不支持 glTF 相机/灯光/多场景、不支持 EXT_texture_webp、仅 metallic-roughness PBR；Use-case specific 段明确'Individual animated models (such as the main navigation puck or an ego vehicle)…Geometric complexity should stay below 25.000 vertices'（此处 animated 指部件覆盖式动画），实例化场景建议 <15,000 顶点
  - <https://docs.mapbox.com/style-spec/guides/using-3d-models/>
- style spec 源码（main 分支，GL JS 3.29 世代）机器可验证枚举：model 层 paint 属性全集为 model-ambient-occlusion-intensity/model-cast-shadows/model-color/model-color-mix-intensity/model-cutoff-fade-range/model-elevation-reference/model-emissive-strength/model-front-cutoff/model-height-based-emissive-strength-multiplier/model-line-cutout-mode/model-opacity/model-receive-shadows/model-rotation/model-roughness/model-scale/model-translation/model-type，layout 仅 model-allow-density-reduction/model-id/visibility——不存在任何动画播放属性；modelNodeOverride 结构定义仅含 orientation 一个字段（3 欧拉角，度），证实节点覆盖只有旋转、无节点级平移/缩放；全文件 grep 'anim' 仅命中 raster-particle 等无关条目
  - <https://github.com/mapbox/mapbox-gl-js/blob/main/src/style-spec/reference/v8.json>
- issue 全文与评论经 GitHub API 原文核验：2023-09-27 提出（v11.0.0-beta.4），Mapbox 成员 evil159 于 2023-10-05 答复原文'At the moment ModelLayer doesn't support animations within gltf/glb files. We are planning to implement the support for this in the future. Currently…the only way to animate 3D models is by animating properties of a model layer (e.g. modelRotate/modelTranslation/modelScale/etc.)'，当日关闭；上游引用准确无误
  - <https://github.com/mapbox/mapbox-maps-ios/issues/2025>
- 更新的决定性反证检验：2025-06-13 用户报告'was able to render the models using ModelLayer but I can't play the animations included in the GLB file'（tRex.glb），Mapbox 成员 pjleonard37 于 2025-06-21 关闭并转支持渠道，未宣称已支持或将支持——证明至 2025-06 该能力仍不存在，且官方未再承诺路线图
  - <https://github.com/mapbox/mapbox-maps-ios/issues/2338>
- 全量 changelog（至 11.30.0-rc.1，2026-08-24）逐条 grep 'animat/gltf/skinning'：零条目涉及 glTF 内置动画播放落地。关键时间线：11.9.0（2024-12-18）引入实验性 AnimatableModel/ModelMaterialPart/ModelNodePart（仅限 puck 可覆盖部件）；11.17.0（2025-12-04）'Promote ModelLayer to stable'；11.18.1（2026-01-29）新增 ModelSource/ModelSourceModel/ModelNodeOverride/ModelMaterialOverride 交互式模型 API，官方描述用例仍是'rotating doors, landing gear, or propellers'——刚体部件旋转，非蒙皮
  - <https://github.com/mapbox/mapbox-maps-android/blob/main/CHANGELOG.md>
- iOS 全量 changelog（至 11.30.0-rc.1，2026-08-24）同样零条 glTF 动画支持条目；对应的 ModelSource/ModelNodeOverride API 于 11.19.0-rc.1（2026-02-12）落地，能力描述与 Android 完全一致（doors/landing gear/propellers）
  - <https://github.com/mapbox/mapbox-maps-ios/blob/main/CHANGELOG.md>
- 2026-08 现行稳定版（11.28.0）LocationPuck3D API 文档字段全集核验：modelUri、modelScale/Rotation/Translation（及 Expression 版）、modelOpacity、modelColor（+ColorMixIntensity/ColorUseTheme）、modelEmissiveStrength、modelCastShadows/ReceiveShadows、modelScaleMode、modelElevationReference、nodeOverrides/materialOverrides——页面上'animat'零匹配，不存在任何播放 glTF 动画的 API
  - <https://docs.mapbox.com/android/maps/api/11.28.0/mapbox-maps-android/com.mapbox.maps.plugin/-location-puck3-d/index.html>
- ModelNodePart（@MapboxExperimental）唯一可变属性是 rotation: List<Double>（3 欧拉角）——所谓 AnimatableModel 动画本质是'节点旋转 + 材质属性'插值，不是完整 TRS，更不是蒙皮；上游'TRS 插值'措辞需收窄为仅旋转
  - <https://docs.mapbox.com/android/maps/api/11.28.0/mapbox-maps-android/com.mapbox.maps.plugin.locationcomponent.model/-model-node-part/index.html>
- 官方'动画 3D 模型'示例源码核验：飞机模型动画全部通过 DisplayLink 逐帧写 feature-state，再由 modelRotation 表达式 match 命名部件（front_gear/propeller_left_outer 等）实现刚体旋转，外加整模型 modelTranslation——通篇无任何 glTF 动画播放调用，证实官方展示的'动画'上限就是部件覆盖
  - <https://github.com/mapbox/mapbox-maps-ios/blob/main/Sources/Examples/SwiftUI%20Examples/Animated3DModelSourceExample.swift>
- GL JS 侧对照：changelog（3.17.0 起'Remove experimental flag from model layer'，最新 3.29.0）所有 model 相关条目为 Meshopt v1 支持、lightOverrides、LOD、性能优化等，无 glTF 动画播放；GL JS 官方 3D 模型动画示例（add-3d-model、add-3d-model-and-animate-along-route）均走 Three.js custom layer 路线，与 style spec 指南的官方建议一致
  - <https://github.com/mapbox/mapbox-gl-js/blob/main/CHANGELOG.md>

<details><summary>验证方法与裁决口径（展开）</summary>

对抗验证方法：直接抓取现行 style spec 指南 HTML 与 v8.json 源码做属性全集枚举（机器可验证，排除文档摘录偏差）、GitHub API 原文核验两个 issue（2023 与 2025 各一）、grep 三端全量 changelog 至 2026-08-24 最新 rc、抽查 11.28.0 稳定版 API 文档与官方示例源码。核心结论无法推翻：三端一致不支持 glTF 内置动画（关键帧/蒙皮/morph 全排除），近 3 年官方仅承诺过一次'未来支持'（2023-10）且至今无落地、无路线图更新，2026 年新增的 ModelSource 交互 API 反而坐实了官方在'部件覆盖'方向而非动画播放方向投入。对上游的两处小修正：(1) Android ModelLayer 自 11.17.0（2025-12-04）起已 stable，'仍实验性'说法过时（不影响结论，反而说明 API 定型后仍无动画）；(2) 节点覆盖仅支持旋转（orientation/model-rotation），无节点级平移缩放，'TRS 插值'为过度表述——这对'能否用覆盖机制伪造走路动画'的判断有实际意义：连节点位移都做不到，四肢摆动类动画完全无路可走。架构推论（供上游汇总）：带蒙皮动画+换装的卡通角色只有两条路——A) Mapbox custom layer 内自建渲染（iOS Metal/SceneKit、Android 自写 GL ES 渲染器且与 Vulkan 预览后端互斥、需重造骨骼动画/toon shader/换装，Godot 资产不可复用）；B) 地图 View 打底 + 透明 Godot 视图叠加渲染角色（保留全部 Godot 资产，需用相机参数对齐两层投影）。本次会话未重新验证的上游子项：Vulkan 预览不支持 custom layer、计费口径、TextureView/CAMetalLayer 叠加细节（不属于本核心问题，未发现矛盾信号）。置信度：核心结论 high（多源交叉、含机器可验证的属性枚举）；两处修正 high（直接源码/文档签名核验）。

</details>


## 3. Godot 4 与原生视图/WebView 的混合集成

### 结论摘要

Android 侧混合集成已是 Godot 官方一等公民：官方 AAR（org.godotengine:godot）+ GodotHost/GodotFragment 可把 Godot 嵌进既有 App，渲染表面固定为 SurfaceView（官方明确拒绝 TextureView），透明背景 bug 已在 4.5 修复（per_pixel_transparency → PixelFormat.TRANSLUCENT），配合 setZOrderOnTop(true) workaround 与 GodotPlugin.onMainCreate/shouldBeOnTop() 可实现"原生地图垫底 + 透明 Godot 在上"，4.7 均可用。iOS 侧没有官方 library 目标：上游 LibGodot PR #90510 至 2026-08 仍未合并，社区可用路线是基于引擎 fork 的 SwiftGodotKit（真机可用、SwiftUI GodotAppView、单实例）或量产验证过的 react-native-godot；而反向路线（Godot 导出 iOS 工程里把 Mapbox UIView 垫底）被 iOS 平台层挡死——display_server_ios 未实现窗口透明、GL 层硬编码 opaque=YES，不 patch 引擎无法透明。WebView 插件生态桌面端成熟（商业 godot-webview 仅桌面、godot_wry 的 Android/iOS 仍是 Planned），移动端只有零散 Android 原生 WebView 叠加插件、iOS 几乎空白，作为地图渲染载体不如原生 Maps SDK 路线可靠。触摸路由无官方透传 API，可行模式是原生手势层直接吃触摸（有插件实证）或 Godot 收手势后经 @UsedByGodot/JNI 桥调地图 camera。公开的 Godot+原生地图完整叠加案例未找到，最接近的实证是 Godot 3.x 时代的 google-maps 插件与 Born 的 react-native-godot 百万用户量产。

### 关键发现

- **Godot 4.x 官方支持以 Android library（AAR）形态嵌入既有 Android App，属官方文档化路线**（置信度：高）
  - AAR 发布在 MavenCentral（org.godotengine:godot:<version>）；host Activity 实现 GodotHost 接口，用 GodotFragment/GodotActivity 托管引擎；双向通信经 runtime GodotPlugin 的 emitSignal/@UsedByGodot。硬限制：每进程仅一个 Godot 实例（可用 android:process 隔离）；不支持自动 resize/横竖屏配置变更（需 android:screenOrientation 锁方向或 android:configChanges 自行处理，否则可能崩溃）；官方示例为 GLTF Viewer（RecyclerView + Godot 渲染 3D 模型）。
  - 来源：<https://docs.godotengine.org/en/stable/tutorials/platform/android/android_library.html>
- **Godot Android 渲染表面是 SurfaceView（GL 用 GLSurfaceView、Vulkan 用自研 VkSurfaceView），官方明确不打算支持 TextureView**（置信度：高）
  - proposal #12630（2025-06 提出，Flutter 集成者请求 TextureView 选项）被维护者 m4gr3d 以"SurfaceView 集成复杂 + 性能考虑"关闭为 not_planned。这决定了 Godot 视图与其他 View 层叠必须走 SurfaceView 的 z-order 机制，无法像普通 View 一样任意裁剪/半透明/动画。
  - 来源：<https://github.com/godotengine/godot-proposals/issues/12630>
- **Android 透明背景在 Godot 4.5 起官方可用（4.7 自然包含）：GodotFragment 此前无法透明是 bug，已修复**（置信度：高）
  - issue #106703（GodotFragment 背景恒为黑）→ PR #106709 于 2025-06-12 合并、milestone 4.5：按 display/window/per_pixel_transparency/allowed（配合 display/window/size/transparent、rendering/viewport/transparent_background）给 GodotGLRenderView/GodotVulkanRenderView 设 PixelFormat.TRANSLUCENT 并更新 app theme。注意：theme 部分只对 gradle build 导出生效；GL 与 Vulkan 渲染后端均已覆盖。
  - 来源：<https://github.com/godotengine/godot/pull/106709>
- **z-order 控制无官方 API，但官方维护者给出了可用 workaround：host 侧找到 Godot 的 SurfaceView 手动 setZOrderOnTop(true) + setFormat(TRANSLUCENT)，即可让下层原生 View 透出**（置信度：高）
  - m4gr3d 在 Godot-Android-Samples issue #22 给出代码：遍历 godotFragment.view.allViews 找 SurfaceView，调 view.setZOrderOnTop(true) 和 view.holder.setFormat(PixelFormat.TRANSLUCENT)。风险点：setZOrderOnTop(true) 后 Godot surface 在整个窗口最上层，同窗口普通 View 无法再叠到 Godot 之上（需改用 setZOrderMediaOverlay 或把 UI 放进 Godot）；若下层地图（Mapbox Android SDK 默认也用 SurfaceView）同为 Surface，双 Surface 合成顺序需实测，必要时把地图切 TextureView 模式。
  - 来源：<https://github.com/m4gr3d/Godot-Android-Samples/issues/22>
- **把原生 View（如地图）垫在 Godot 渲染视图下方是 Godot Android 插件体系的一等能力：GodotPlugin.onMainCreate 返回的 View 可选择加在 Godot 主视图之上或之下**（置信度：高）
  - master 分支 GodotPlugin.java javadoc 明确：onMainCreate(Activity) 返回的 View 会加入 Godot 视图层级，并"Use GodotPlugin#shouldBeOnTop() to specify whether the plugin's View should be added on top or behind the main Godot view"。适用于 Godot 导出 App 内嵌地图 SDK 的路线（v2 插件架构同样保留此 API）。
  - 来源：<https://github.com/godotengine/godot/blob/master/platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPlugin.java>
- **iOS 侧不存在官方 "Godot as library" 目标；上游 LibGodot PR（#90510，Migeran）截至 2026-08-15 仍 open、milestone 4.x**（置信度：高）
  - PR 功能：把 Godot 编成静态/动态库，经 GDExtension API 由宿主进程控制启动/迭代/关闭，Apple 平台上 Godot 窗口可渲染进宿主提供的 surface。未合并意味着 iOS 嵌入必须依赖第三方 fork（migueldeicaza/godot 或 migeran/libgodot），存在版本跟进风险（当前 fork 基于 4.6，目标引擎 4.7 需确认 fork 进度）。
  - 来源：<https://github.com/godotengine/godot/pull/90510>
- **SwiftGodotKit 是 iOS 嵌入 Godot 的最成熟社区路线：新版基于 libgodot（4.6 fork）支持 iOS 真机，Godot 内容映射为 UIView/NSView 并提供 SwiftUI 封装**（置信度：高）
  - README（当前 main 分支）：基于 migueldeicaza/godot 的 swiftgodotkit-4.6 分支 libgodot patch；SwiftUI 用法 GodotApp(packFile:"game.pck") + GodotAppView()；限制：不支持 iOS 模拟器（"there is no support for the iOS simulator"）、每 App 仅一个 GodotApp 实例、SwiftGodot 与 godot fork 分支必须 API 匹配否则运行时报 null method bind。Pixel Pals 作者 2025-05 博客实测称集成"easy"、包体约 +30MB。
  - 来源：<https://github.com/migueldeicaza/SwiftGodotKit>
- **反向路线（Godot 导出 iOS 工程 + 原生 UIView 垫底 + Godot 透明）当前被引擎挡死：iOS 平台未实现窗口/层透明**（置信度：高）
  - master 源码证据：platform/ios/display_server_ios.mm 无任何 transparent 处理；display_layer_ios.mm 的 GDTOpenGLLayer 硬编码 self.opaque = YES，GDTMetalLayer 也未接 per_pixel_transparency 设置；ProjectSettings 文档只给 Android 写了透明支持注记。2023 年论坛案例：开发者把 UIView insertSubview 到 Godot 渲染视图后面并开 per_pixel_transparency + set_transparent_background(true)，macOS 生效、iPhone 失败，无解答。要走此路必须自行 patch 引擎（设 CAMetalLayer opaque=NO 等），无公开成功先例。
  - 来源：<https://github.com/godotengine/godot/blob/master/platform/ios/display_layer_ios.mm>
- **商业插件 godot-webview（Kroket Ltd）仅支持桌面三平台，不能用于 Android/iOS，可直接排除**（置信度：高）
  - 官网明示 Supported platforms: Windows, MacOS, Linux（Vulkan/Metal）；Qt6/Chromium 内核，离屏渲染成 RGBA8 纹理贴到 TextureRect/任意 mesh，支持透明（经 CSS）、JS↔Godot 互操作、键鼠事件转发；版本 0.1.4 beta（2025-08-11），要求 Godot 4.5-dev4+。移动端完全不在支持列表。
  - 来源：<https://godotwebview.com/>
- **godot_wry（开源 GDExtension、系统原生 webview）移动端仍未落地：Android/iOS 状态为 Planned**（置信度：高）
  - README（2026-08 抓取 main 分支）：Windows(WebView2)/macOS(WebKit) 支持、Linux X11 部分支持且无透明（issue #17）；Android/iOS 标注 ⏳ Planned，"Contributions welcome"。已知 caveat：webview 是原生叠加、恒在 Godot 之上渲染（非离屏纹理），有 JS⇔GDScript 通信与输入转发。若想用它承载 Mapbox GL JS，移动端需自己实现平台层。
  - 来源：<https://github.com/doceazedo/godot_wry>
- **移动端 WebView 只有零散 Android 插件（原生 View 叠加式，无离屏纹理），iOS 侧几乎空白**（置信度：中）
  - 可查到：office-bsmx/godot-webview（Android 简单集成）、brown5lc/Godot-4-Android-WebView（Godot 4.x、面向 Quest 3 但通用 Android）、Sam2much96/GodotChrome（暴露 Android WebView API，声称可控层叠顺序）；均为把 WebView 作为原生 View 盖在 Godot 上，透明背景/JS bridge 能力参差且维护度低。iOS 仅有 Godot 3 时代的 vini-guerrero/Godot-Webview custom module，Godot 4 不可直接用。结论："WebView 承载 Mapbox GL JS" 路线在 Godot 移动端没有现成可靠插件，需自研双端插件。
  - 来源：<https://github.com/brown5lc/Godot-4-Android-WebView>
- **触摸路由无官方透传 API；"原生地图 View 直接吃触摸 + camera 变化经 signal 回传 Godot" 已有插件实证**（置信度：高）
  - MauriceButler/godot-google-maps-plugin-android：MapView 经 onMainCreate 的 FrameLayout 加入视图层级（默认在 Godot 之上），用户手势由 MapView 原生处理；googleMap.setOnCameraMoveListener 把 camera target 打包成 Dictionary 经 emitSignal("onLocationUpdateResponse") 回传 GDScript；Godot 侧经 Engine.get_singleton("MapPlugin") 调 @UsedByGodot 方法（createMap/setLocation/zoom）。注意该插件是 Godot 3.x/.gdap 一代插件架构，Godot 4.2+ 需按 v2 架构重写，但模式可复制。
  - 来源：<https://github.com/MauriceButler/godot-google-maps-plugin-android/blob/main/app/src/main/java/com/oddsockgames/mapPlugin/MapPlugin.java>
- **若 Godot 透明层全屏在上，则手势需二选一：Godot 收手势后经插件桥调地图 camera API，或 host 层自行拦截分发；Godot 侧有现成的 Android 多指手势开关**（置信度：中）
  - Godot 的 SurfaceView（GodotVulkanRenderView 设 setFocusableInTouchMode(true)）会消费其区域内触摸且不提供 pass-through；ProjectSettings 有 input_devices/pointing/android/enable_pan_and_scale_gestures（默认 false，开启后 Android 多指 pan/scale 转成 InputEventPanGesture/MagnifyGesture），便于在 GDScript 里统一收拖拽/双指缩放再经 @UsedByGodot JNI 调 Mapbox camera（animateCamera/easeTo）。此模式是架构推断（官方双向通信机制 + 输入事件均有文档），无完整公开范例。
  - 来源：<https://docs.godotengine.org/en/stable/classes/class_projectsettings.html>
- **量产级混合集成实证存在：Born 的 react-native-godot（Born + Migeran 开发）基于 LibGodot 双端嵌入 Godot，服务百万级用户**（置信度：高）
  - npm @borndotcom/react-native-godot 1.0.1（2025-11-04）；README："Supports Android and iOS, built on LibGodot"、"Stable implementation serving millions of users in Born's applications"；Godot 跑独立线程不阻塞 RN JS 线程，TS/JS 可访问全部 Godot API（react-native-worklets-core）；支持启/停/重启/暂停引擎、可换载不同 Godot 项目；示例支持 iOS 模拟器（其 libgodot 预编译包含模拟器 slice）。证明 "原生 App 壳 + Godot 渲染层" 双端量产可行。
  - 来源：<https://github.com/borndotcom/react-native-godot>
- **负面案例：Flutter 内嵌 Godot 想在 Godot 之上叠 UI/做页面导航失败——SurfaceView 恒在最上，setZOrderOnTop(false) 与 Flutter 渲染成 texture 均无效**（置信度：高）
  - proposal #12630 作者 2025-08-03 最终更新："I was able to render Flutter as a texture but this has no effect. The root problem is still that Godot is rendered above anything else as a surface"。教训：跨框架（Flutter/RN/Capacitor）叠加时 Godot surface z-order 很难驯服；纯原生 host（本项目场景）可控性更好，因为可以直接拿到 SurfaceView 调 z-order API，但"地图在下、Godot 透明在上、原生 UI 再叠最上"三层结构在 Android 上需要用 setZOrderMediaOverlay 而非 setZOrderOnTop，需真机验证。
  - 来源：<https://github.com/godotengine/godot-proposals/issues/12630>
- **未找到任何公开的 "Godot + Mapbox/Google Maps 原生底图 + 透明 3D 角色层" 完整项目或成败复盘**（置信度：中）
  - 检索到的最接近产物：MauriceButler 的 google maps 插件（2022-2023，Godot 3.x，地图在上层区域而非垫底）、官方 GLTF Viewer 示例（Godot 视图与 RecyclerView 组合）、Godot-Android-Samples issue #22（透明叠加诉求）。Pokemon GO/Zenly 式 "地图垫底" 结构在 Godot 生态属无人走通的公开空白，方案需按上面各原语自行拼装并预留真机验证周期。
  - 来源：<https://github.com/MauriceButler/godot-google-maps-plugin-android>

### 遗留问题（该维度未决）

- Godot 4.7 嵌入库场景（host App 自带 theme，非 gradle 导出）下 per_pixel_transparency 是否开箱即用，还是仍需 issue #22 的 setZOrderOnTop workaround——需真机 demo 验证（PR #106709 的 theme 改动只覆盖 gradle 导出路径）
- Mapbox Android SDK v11 的 MapView（默认 SurfaceView，可选 TextureView 模式）与 Godot SurfaceView 双渲染器同窗时的合成 z-order（setZOrderMediaOverlay 组合）、帧率与功耗表现无公开数据，中端机 60fps 目标需 PoC 实测
- iOS 若走 SwiftGodotKit/libgodot 路线：fork 何时跟进 Godot 4.7、现有 FBX+Skeleton3D+toon shader 资产在 libgodot 运行时是否行为一致、GodotAppView 能否透明背景叠在原生 Mapbox MapView 之上（均未找到文档或案例）
- iOS 反向路线所需的引擎 patch（CAMetalLayer opaque=NO + 接通 per_pixel_transparency）工作量与副作用（合成功耗、ProMotion）无公开先例，需自行验证或放弃该路线
- Godot 收手势→JNI/Swift 桥→地图 camera 的每帧调用延迟（手势跟手性）是否达标，特别是双指缩放+旋转连续手势场景
- react-native-godot 是否可只取其 Android/iOS 原生封装层（不引入 React Native）作为参考实现，其 LibGodot 预编译产物的引擎版本与 4.7 的差距

### 对抗验证

#### 验证 3.1：裁决 ⚠️ 部分成立/需修正

「Android 上把 Godot 4 渲染表面设为透明并叠在原生 Mapbox MapView 之上」在机制层面成立且有官方背书，但上游结论需四处修正：(1) 透明开关的真实判定条件：Godot 4.5+（4.7.2-stable 源码复核）仅读取 display/window/per_pixel_transparency/allowed 一个设置来决定给 SurfaceView 设 PixelFormat.TRANSLUCENT（Vulkan：GodotVulkanRenderView 构造函数 holder.setFormat；GL：EGL 8888 config + TRANSLUCENT）；display/window/size/transparent 在 Android 官方文档明示无效，rendering/viewport/transparent_background 只管根 viewport 是否输出 alpha。上游把三个设置并列为触发条件不准确。(2) 任务提示中的 API 名 should_render_transparent_background 在 godot 仓库不存在（code search 零命中），系误记。(3) 关键遗漏：4.5 的修复只设 TRANSLUCENT 格式，从不调用任何 z-order API——而 Mapbox Maps Android SDK v11 的 MapView 默认同样用 SurfaceView（MapInitOptions.textureView 默认 false）。两个默认 z-order 的兄弟 SurfaceView 相对合成次序未定义，因此 host 必须手动遍历 Godot 视图树拿到其 SurfaceView 并设 z-order（维护者 m4gr3d 认可的 workaround，非官方 API）。且对本项目"地图在下 / 透明 Godot 居中 / 原生 UI 叠顶"三层结构，应改用 setZOrderMediaOverlay(true) 而非 issue #22 示例里的 setZOrderOnTop(true)（后者会把 Godot 压在整个 window 之上，原生 UI 无法再叠顶）；该调用须在 surface 附加到 window 前完成，时序需真机验证。上游"必要时把地图切 TextureView"的备选方向存疑：地图切 TextureView 后进入 window 图层，反而要求 Godot setZOrderOnTop(true)，牺牲原生 UI 叠顶，不是更稳的组合。(4) 「透明 + 原生 View 垫底 + Godot 收输入」是官方文档化模式：GodotPlugin.shouldBeOnTop() javadoc 明写 returning false 用于配合透明让 Godot 处理输入；其能力源头是 3.x PR #51935（milestone 3.4，2021-09 合并），作者动机就是相机预览垫底 + 透明 Godot 叠加——同构场景的官方先例。但截至 2026-08-25 查不到任何"Godot 4.5+ 透明叠原生地图/相机"的端到端公开成功案例（4.5 修复 PR 自带 before/after 验证视频，Godot-Android-Samples issue #22/#16 均无回帖确认；唯一详细失败案例是 Flutter 集成，其失败混入 Flutter platform-view 合成器因素，不能外推到纯原生 host）。「保持流畅（中端机 60fps）」无任何一手基准数据：官方 ProjectSettings 文档对 per_pixel_transparency 明示"This affects performance"，双 GPU 上下文（Mapbox 渲染 + Godot 渲染）+ 全屏 TRANSLUCENT 图层合成的叠加开销只能靠真机 PoC 定量，此点判 UNCLEAR。

证据：

- 官方修复 PR「Fix transparency background issue on Android」：2025-06-12 合并，milestone 4.5，修复 issue #106703（GodotFragment 背景恒黑）；改动覆盖 GodotGLRenderView.java、GodotVulkanRenderView.java、Godot.kt、display_server_android.cpp（FEATURE_WINDOW_TRANSPARENCY 打开、is_window_transparency_available 读 per_pixel_transparency/allowed）与导出 theme（windowIsTranslucent，仅 gradle 导出生效，AAR 嵌入场景 theme 由 host 自控不受此限）；PR 自带 before/after 视频。置信度：高（一手 diff 逐行核对）
  - <https://github.com/godotengine/godot/pull/106709>
- 4.7.2-stable 源码复核（经 GitHub API ref=4.7.2-stable 取原文）：shouldBeTranslucent 为真时仅执行 getHolder().setFormat(PixelFormat.TRANSLUCENT)（第 69-70 行）；GL 路径同为 TRANSLUCENT + RegularConfigChooser(8,8,8,8,16,0)；全文无任何 setZOrderOnTop/setZOrderMediaOverlay 调用；另 setFocusableInTouchMode(true)（第 66 行）证实 Godot 视图会消费其区域内触摸、无 pass-through。Godot.kt 中判定条件为 !editorHint && GodotLib.getGlobal("display/window/per_pixel_transparency/allowed")，读取自 .pck 内项目设置，AAR 嵌入模式同样生效。置信度：高
  - <https://github.com/godotengine/godot/blob/4.7.2-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/GodotVulkanRenderView.java>
- 官方文档两条限定：per_pixel_transparency/allowed 注明 "This affects performance, so leave it on false unless you need it"；display/window/size/transparent 注明 "This setting has no effect on Android as transparency is controlled only via per_pixel_transparency/allowed"——纠正上游把三个设置并列为 Android 触发条件的说法。另 input_devices/pointing/android/enable_pan_and_scale_gestures 设置确实存在（默认 false），支撑「Godot 收手势→桥接调地图 camera」路线。置信度：高
  - <https://github.com/godotengine/godot/blob/master/doc/classes/ProjectSettings.xml>
- Godot Android 维护者 m4gr3d 2025-05-22 给出的 host 侧 workaround 原文核实：遍历 godotFragment.view.allViews 找 SurfaceView，setZOrderOnTop(true) + holder.setFormat(TRANSLUCENT)，并确认原透明失效是引擎 bug（即 #106703）。注意：该 issue 至今 open、无提问者成功回帖；且 setZOrderOnTop(true) 会把 Godot surface 置于整个 window 之上，三层结构应改 setZOrderMediaOverlay(true)（Android SurfaceView 文档：媒体覆盖层位于其他常规 SurfaceView 之上、window 之下，且须在 window attach 前设置，见 https://developer.android.com/reference/android/view/SurfaceView#setZOrderMediaOverlay(boolean)）。置信度：workaround 存在=高；media overlay 三层方案=中（机制有 Android 官方文档，无 Godot 场景实测）
  - <https://github.com/m4gr3d/Godot-Android-Samples/issues/22>
- master 源码 javadoc（第 346-355 行）逐字核实：shouldBeOnTop() 返回 false 时插件 View 垫在 Godot 主视图之后，"which can be useful when used with transparency in order to let the Godot view handle inputs"——「地图垫底+透明 Godot 收输入」是官方注释明确设想的用法，上游 claim 成立。置信度：高
  - <https://github.com/godotengine/godot/blob/master/platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPlugin.java>
- 历史先例核实：3.x 时代 PR「[3.x] Window transparency support on Android」（milestone 3.4，2021-09-15 合并）作者自述动机 "Allows plugins to do specific rendering and render godot UI on top (useful for camera support with drawing on top)"——与本项目同构（原生渲染垫底+透明 Godot 叠加）的能力在 Godot 3.x 是官方特性，4.x 曾回归为 bug 直到 4.5 修复。置信度：高
  - <https://github.com/godotengine/godot/pull/51935>
- 负面案例边界核实：TextureView 提案 2025-06-18 被 m4gr3d 以 not_planned 关闭（SurfaceView 集成复杂+性能考虑）；Flutter 作者 2025-08-03 最终更新称 setZOrderOnTop(true/false) 与 Flutter 渲染成 texture 均无效、Godot 恒在最上。但该失败链路经过 Flutter PlatformView 合成器，m4gr3d 索要 APK 复查未获后续；纯原生 host 可直接持有 SurfaceView 与完整 window，故此案例不能证伪原生方案，仅证明跨框架（Flutter/RN/Capacitor 的 platform-view 路线）风险高。置信度：高（对案例事实）
  - <https://github.com/godotengine/godot-proposals/issues/12630>
- 直接同场景案例核实：2024-01 有人在 Godot 4.2.1 用 shouldBeOnTop=false 把 Google Map 垫在 Godot 下，开满所有透明设置仍黑屏——这正是 4.5 修复前 bug 的表现，不代表 4.5+ 现状；该 issue 至今 open、无 4.5+ 复测回帖。结论：至今没有任何公开的『Godot 4.5+/4.7 透明叠原生地图』端到端成功实证，可行性推断只建立在源码+维护者 workaround+3.x 先例上。置信度：高（对『查无实证』这一点）
  - <https://github.com/m4gr3d/Godot-Android-Samples/issues/16>
- Mapbox Maps Android SDK v11 源码核实：MapView 按 MapInitOptions.textureView（默认 false，MapInitOptions.kt 第 33 行）在 SurfaceView 与 TextureView 间二选一（MapView.kt 第 160-163 行），默认 SurfaceView + MapboxSurfaceHolderRenderer，且 SDK 自身不调 z-order API。推论：默认配置下与 Godot 构成双 SurfaceView，相对次序未定义，必须 host 侧给 Godot surface 设 setZOrderMediaOverlay(true)；若把地图切 textureView=true 则地图进 window 图层，Godot（window 后）会被地图盖住，只能再 setZOrderOnTop(true) 牺牲原生 UI 叠顶——上游『必要时地图切 TextureView』不是更稳解。置信度：源码事实=高；层叠推论=中（待真机）
  - <https://github.com/mapbox/mapbox-maps-android/blob/main/maps-sdk/src/main/java/com/mapbox/maps/MapView.kt>
- 官方 Android library 文档核实：AAR 发布于 MavenCentral，GodotHost/GodotFragment/GodotActivity 托管；硬限制原文确认——每进程仅一个 Godot 实例（可 android:process 隔离）、"Automatic resizing / orientation configuration events are not supported and may cause a crash"（须 android:screenOrientation 锁方向）；本项目为竖屏应用，锁竖屏即可规避。文档通篇未提透明/z-order/与原生 View 层叠——层叠属于无官方文档的灰色地带。置信度：高
  - <https://docs.godotengine.org/en/stable/tutorials/platform/android/android_library.html>
- 版本事实：4.7-stable 2026-06-18、4.7.1 2026-07-14、4.7.2-stable 2026-08-18 发布，目标版本 4.7 真实存在且必然包含 4.5 的透明修复（已在 4.7.2 tag 源码直接验证）。另：should_render_transparent_background 在 godotengine/godot 全库 code search 零命中，该 API 名不存在。置信度：高
  - <https://github.com/godotengine/godot/releases>

<details><summary>验证方法与裁决口径（展开）</summary>

裁决口径：判 PARTIALLY 而非 CONFIRMED 的原因有三。(a) 可行性链条完整但全部环节没有一个端到端公开成功案例（4.5+ 透明叠原生地图/相机），最接近的同场景案例（samples issue #16，Google Map 垫底）停留在修复前的失败状态无人复测；(b) z-order 是决定性环节却无官方 API，依赖遍历私有视图树的 workaround（维护者认可但可能随版本变化），且三层结构所需的 setZOrderMediaOverlay 用法连 workaround 级别的先例都没有，只有 Android 平台文档背书；(c) 『中端机 60fps』完全无实证，且官方文档明示 per-pixel transparency 影响性能，Mapbox 与 Godot 双渲染上下文叠加的功耗/带宽只能真机定量。上游各 claim 的具体修正：claim3（透明触发条件三设置并列）→ 实际 Android 端唯一开关是 per_pixel_transparency/allowed（size/transparent 官方明示无效）；claim4 → workaround 属实但 setZOrderOnTop 与三层结构冲突、'地图切 TextureView' 方向可能反向错误；其余核心 claim（AAR 官方路线+单实例+方向锁、TextureView not_planned、shouldBeOnTop 一等能力、Flutter 负面案例边界）逐条核实无误。建议的最小 PoC（1-2 天）：Kotlin host + Mapbox v11 默认 MapView + Godot 4.7.2 AAR（.pck 开 per_pixel_transparency/allowed + viewport transparent_background），host 在 fragment attach 前后对 Godot SurfaceView 试 setZOrderMediaOverlay(true)/setZOrderOnTop(true) 两档，用 Perfetto 量中端机（如骁龙 7 系）合成帧率与 GPU 占用；PoC 通过前不应把该路线定为唯一方案。检索局限：WebFetch 对 github.com/docs.godotengine.org 域被环境拦截，全部 GitHub 证据改经本地 gh CLI（已认证）直取 API/源码原文，文档经 curl 取 HTML，一手性不受影响；Godot 论坛/Reddit 只做了抽样检索，不排除存在未公开索引的成功案例，但至少说明『无广为人知的成功先例』成立。

</details>

#### 验证 3.2：裁决 ⚠️ 部分成立/需修正

iOS 上「Mapbox 原生 MapView 在下 + Godot 4 透明渲染层在上」的验证结论：路径(1)（Godot 导出 iOS 工程里垫 UIView + Godot 层透明）在目标版本 Godot 4.7.2-stable 仍被引擎挡死，上游结论成立且证据可加强——DisplayServerAppleEmbedded::has_feature 中 FEATURE_WINDOW_TRANSPARENCY 被注释禁用（返回 false），display/window/per_pixel_transparency/allowed 在 iOS/apple_embedded 代码路径中零引用（全仓库只有 android/macos 等平台处理它），GLES 层 GDTOpenGLLayer 硬编码 self.opaque=YES、GDTMetalLayer 的 initializeDisplayLayer 无任何透明处理，无公开成功先例；但须修正一点：拿 view controller / 垫 UIView 本身是官方一等 API——DisplayServer.window_get_native_handle 在 iOS 上 WINDOW_HANDLE 返回 UIViewController 指针、WINDOW_VIEW 返回 Godot 的 UIView（4.7.2 源码 542-553 行），因此「把地图 UIView 插到 Godot 视图下层」机械上完全可行，唯一堵点是 Godot 侧透明合成需自行 patch 引擎（无先例）。路径(2)（Godot as library 嵌入原生 App）上游表述过时需修正：LibGodot Core（PR #110863，Migeran 提交）已于 2025-10-08 合入官方 milestone 4.6，4.7.2-stable 已含 core/extension/libgodot.h（libgodot_create_godot_instance / libgodot_destroy_godot_instance 入口），故「官方完全没有 as-library 目标」不再准确；但该官方合入仅支持 Linux/Windows/macOS，不含 iOS，且不含 UI 嵌入（渲染进宿主 view）——按 Migeran 在 GodotCon 2026（2026-04-23）公布的状态表，Apple UI Embedding 仍停在其 4.6 私有分支、状态「PR Ready for Upstreaming」，截至 2026-08-25 官方仓库无对应 open PR（唯一 open 的是伞形 PR #90510，milestone 4.x）。因此 iOS 嵌入实践上仍必须走第三方 fork：SwiftGodotKit（基于 migueldeicaza/godot 的 swiftgodotkit-4.6 分支，iOS 真机可用、明确不支持 iOS 模拟器、每 App 仅一个 GodotApp、SwiftGodot 与 godot fork 分支必须 API 匹配；无 4.7 分支）或 react-native-godot（基于 migeran/libgodot 的 libgodot_migeran_45 分支即 Godot 4.5 基，README 明确支持 iOS 模拟器，量产实证但版本锁在 4.5、仓库最近推送 2025-11-07）。总体判断：核心问题答案是「路径(1) 不可行（除非自 patch 引擎），路径(2) 可行但必须接受 fork 引擎（4.5/4.6 基）与目标 4.7 的版本落差（.pck 与场景资产需按 fork 版本导出）」。

证据：

- 4.7.2-stable 一手源码：has_feature 中 `// case DisplayServerEnums::FEATURE_WINDOW_TRANSPARENCY:` 被注释（约 377 行），即 iOS/visionOS 显示服务器明确不上报窗口透明能力；这是比上游引用更精确的挡死证据。置信度 high（直接读 tag 源码）。注意上游引用的 platform/ios/display_server_ios.mm 自 4.5 起已变薄壳，逻辑移至 drivers/apple_embedded，引用位置过时但结论不变。
  - <https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/apple_embedded/display_server_apple_embedded.mm>
- 同文件 542-553 行：window_get_native_handle 官方实现——WINDOW_HANDLE 返回 (int64_t)GDTAppDelegateService.viewController（UIViewController*），WINDOW_VIEW 返回 viewController.godotView（UIView*）。回答了「插件能拿到 view controller 吗」：能，且是官方 API，GDExtension/iOS 插件可据此把地图 UIView insertSubview 到 Godot 视图下层。置信度 high。
  - <https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/apple_embedded/display_server_apple_embedded.mm>
- 4.7.2-stable：GDTOpenGLLayer initializeDisplayLayer 硬编码 self.opaque = YES（87 行）；GDTMetalLayer 的 initializeDisplayLayer 除模拟器 Metal 版本检查外为空，无 opaque/透明处理、不读任何透明相关项目设置。置信度 high。
  - <https://github.com/godotengine/godot/blob/4.7.2-stable/platform/ios/display_layer_ios.mm>
- 全仓库代码搜索：per_pixel_transparency 仅出现在 platform/android、platform/macos、main/main.cpp、editor、doc 与 popup 相关文件，platform/ios 与 drivers/apple_embedded 零引用——iOS 渲染路径完全没接这个设置。另 doc/classes/ProjectSettings.xml 对 display/window/size/transparent 只写了 Android 特别注记，无 iOS 支持说明。置信度 high。
  - <https://github.com/search?q=repo%3Agodotengine%2Fgodot+per_pixel_transparency&type=code>
- 上游需修正的关键事实：『LibGodot: Core - Build Godot Engine as a Library』（作者 kisg/Migeran）已 merged（2025-10-08，milestone 4.6），是 PR #90510 拆分的 Part 1，提供 GodotInstance GDCLASS 与 libgodot_create_godot_instance/libgodot_destroy_godot_instance 入口；PR 正文明确『Supports: Linux, Windows and MacOS』——官方 as-library 已存在但不含 iOS。置信度 high。
  - <https://github.com/godotengine/godot/pull/110863>
- 4.7.2-stable tag 下该文件存在（HTTP 200），内容即上述两个 LIBGODOT_API 入口——目标版本 4.7 官方自带 LibGodot core。置信度 high。
  - <https://github.com/godotengine/godot/blob/4.7.2-stable/core/extension/libgodot.h>
- 伞形 PR #90510 截至 2026-08-15 更新仍 state=open、merged=false、milestone 4.x（gh api 实测）。评论区 2026-06-19 引用的 GodotCon 2026（2026-04-23）Migeran 状态表：Core LibGodot=『Merged in Godot 4.6』；Reinitialization、UI Embedding Infrastructure、Apple UI Embedding=『Stable in Migeran 4.6 Branch / PR Ready for Upstreaming』；Android/Windows UI Embedding=『PR In Progress』。另经 gh search 确认官方仓库当前没有独立的 UI Embedding open PR。即 iOS 渲染进宿主 view 的能力仍未上游化。置信度 high（PR 状态为 API 实测；状态表为 Migeran 方自述，high-medium）。
  - <https://github.com/godotengine/godot/pull/90510>
- README（main，实测抓取）确认上游描述：基于 4.6 版 libgodot patches（『the new 4.6-based libgodot patches』）；iOS 需真机（『there is no support for the iOS simulator, as Godot does not run on those』）；『There can only be one GodotApp in your application』；要求 SwiftGodot 分支 swiftgodotkit 与 godot fork 分支 swiftgodotkit-4.6 严格配套，否则运行时 null method bind。fork 分支列表实测最高 swiftgodotkit-4.6，无 4.7；SwiftGodotKit 活跃（最近提交 2026-08-04，release v4.6.0 于 2026-02-22）。置信度 high。
  - <https://github.com/migueldeicaza/SwiftGodotKit>
- README 实测：『Supports Android and iOS, built on LibGodot』且有『Run on the iOS Simulator』章节（与 SwiftGodotKit 的无模拟器限制并存，因二者 libgodot 构建不同）；但自定义构建指引明确要求 migeran/libgodot 分支 libgodot_migeran_45（Godot 4.5 基）；仓库最近推送 2025-11-07、2667 stars。上游把它当 4.6 级量产证据需降级为『4.5 基、版本滞后于目标 4.7 两个小版本』。置信度 high。
  - <https://github.com/borndotcom/react-native-godot>
- migeran/libgodot 公开仓库 default branch 为 libgodot_migeran_45（最近推送 2025-11-11），无公开 4.6 分支——GodotCon 表中的『Migeran 4.6 Branch』要么私有要么即 migueldeicaza fork 的 swiftgodotkit-4.6。跟版风险实证。置信度 high。
  - <https://github.com/migeran/libgodot>
- 2023 年论坛案例（上游同源）：开发者做 iOS 插件把 UIView 加到 rootViewController 并置底，开 per_pixel_transparency + set_transparent_background，macOS 生效、iOS 失败无解。本次仅经搜索摘要复核（页面直抓被限，返回 167 字节），未发现任何后续公开成功案例或引擎 patch 教程。置信度 medium（作为『无先例』的佐证；挡死结论以引擎源码为准）。
  - <https://ask.godotengine.org/147089/transparent-background-on-ios>

<details><summary>验证方法与裁决口径（展开）</summary>

对上游各条 iOS 相关 claim 的裁定：(1)「反向路线被引擎挡死」CONFIRMED，但证据升级为 4.7.2-stable 的 FEATURE_WINDOW_TRANSPARENCY 注释禁用 + per_pixel_transparency 全仓库搜索，且需补充 window_get_native_handle 官方能拿 UIViewController/UIView（垫 View 这半步不是堵点）；上游引用的文件路径（platform/ios/display_server_ios.mm）在 4.5+ 已重构到 drivers/apple_embedded，引用需更新。(2)「iOS 侧不存在官方 Godot as library 目标；PR #90510 仍 open」PARTIALLY——伞形 PR 确实 open，但 LibGodot Core 已拆分合入官方 4.6（PR #110863），4.7 自带 libgodot.h；准确说法是『官方 as-library 已有但仅桌面三平台、无 UI 嵌入，iOS 嵌入未上游化』。(3) SwiftGodotKit 条 CONFIRMED（4.6 fork、无模拟器、单实例、分支配套），并补充：无 swiftgodotkit-4.7 分支，目标 4.7 项目必须把资产按 4.6 导出或等 fork 跟进。(4) react-native-godot 条 PARTIALLY——iOS 支持与量产表述属实，但其 libgodot 是 4.5 基（libgodot_migeran_45）且支持 iOS 模拟器，上游未写明版本锁定。可行性总裁定：路径(1) 需自行 patch 引擎（把 Metal layer 设非 opaque + 让 DisplayServer 上报/处理透明），无公开成功先例，风险高；存在一个未被验证的低成本实验——用 window_get_native_handle 拿到 godotView 后在运行时把 layer.opaque 置 NO 并开 viewport transparent_bg（无需重编引擎），但 2023 案例同思路失败、引擎不保证最终 blit 的 alpha 语义，只能当探索性 spike 不能当方案基线。路径(2) 是当前唯一有量产实证的 iOS 混合路线，代价是引擎退到 fork 的 4.5/4.6 与单实例限制。未能查证项：Migeran『Apple UI Embedding』PR 的具体提交时间表（截至 2026-08-25 未出现在官方仓库）；本机 WebFetch 对 github.com/docs.godotengine.org 被网络策略拦截，全部证据改经 curl/gh CLI 直取一手源码与 API，不影响置信度。

</details>


## 4. 行业先例与教训

### 结论摘要

行业先例调研结论：三大"游戏引擎地图 SDK"中，Google 的 gaming solution 已于 2021 年宣布弃用、2022 年底关停；Niantic Lightship Maps SDK 已于 2025 年 10 月随 Niantic 拆分（游戏部门卖给 Scopely、Niantic Spatial 转向企业空间智能）而彻底关停端点；唯一例外是 Mapbox Unity SDK——用户"已归档"的前提已过时，该仓库 2025-2026 年复活并发布了 v3.1.x（但仅支持 Unity，仍是引擎内重建路线，对 Godot 无直接可用性）。产品侧分两条路：Pokémon GO 一族（含 Lightship Maps、Mapbox Unity SDK v3）走"矢量瓦片→引擎内生成 mesh"，角色与地图同场景渲染；Zenly 后继的社交定位类产品（Jagat、Snap Map）走"原生地图渲染器出图 + 应用层叠加角色"，其中 Zenly 自己则花三年自研了完整地图引擎、最终仍因商业原因被 Snap 关停。核心教训：把地图能力绑在大厂"引擎内地图 SDK"上的产品全部被迫迁移过至少一次，而完全自研地图引擎成本极高；对 Godot 项目而言，业界从未有现成的"Godot 地图 SDK"，主流可行模式收敛为"原生 Mapbox SDK / GL JS 出图 + 引擎透明层合成角色"或"自建矢量瓦片→mesh 管线"两条，前者与本项目"让 Mapbox 自己的渲染器出图"的硬性需求方向一致。

### 关键发现

- **用户前提'Mapbox Unity SDK 已归档'与 2026 年事实不符：仓库未被 archive，且已复活并持续发布 v3.x**（置信度：高）
  - GitHub API 实测（2026-08-25）archived=false、disabled=false、pushed_at=2026-08-17；提交记录显示 v3.1.0 于 2026-05-18 合入、v3.1.1 于 2026-06-09 发布、2026-07-20 仍有 input 修复合入 main。README：包名 com.mapbox.sdk、当前版本 3.1.x、最低 Unity 2022.3 LTS、构建目标仅 iOS/Android、强制 URP。但该 SDK 仅面向 Unity，对 Godot 无直接可用性。
  - 来源：<https://github.com/mapbox/mapbox-unity-sdk>
- **Mapbox 官方文档对 Unity SDK 的口径：v2 停止开发、v3 '即将发布'，文档已缩减到只剩安装指南——官方态度是低调重启而非归档**（置信度：高）
  - docs.mapbox.com/unity/maps/guides/ 实测（2026-08）：'Current version: v2.1.1'、'Version 2 is no longer in active development. Version 3 is in development and will be released soon'、'This documentation has been reduced to include only an installation guide'，并引导去 Mapbox Discord #unity 频道。文档状态明显滞后于仓库（main 分支已是 3.1.1），说明 v3 处于'仓库先行、文档未跟上'的半正式状态，生态成熟度风险仍高。
  - 来源：<https://docs.mapbox.com/unity/maps/guides/>
- **Mapbox Unity SDK v3 的技术路线仍是'瓦片数据→引擎内生成地形/建筑 mesh'的引擎内重建，不是嵌入 Mapbox 原生渲染器**（置信度：高）
  - README 依赖表：URP shader graph 提供 terrain/building 着色器、com.unity.burst 1.8.12 用于'Burst-compiled terrain decode and collider job'、Newtonsoft JSON 解析 tile metadata，iOS 侧带 XCFrameworks、Android 侧带 sqlite 原生库（原生部分用于瓦片存取而非渲染）。即 Mapbox 自己在 Unity 上也没有走'原生渲染器出图'路线，引擎内重建仍是其游戏引擎产品线的选择。
  - 来源：<https://github.com/mapbox/mapbox-unity-sdk/blob/main/README.md>
- **该仓库在 2020-2023 年间确实事实性停滞过（社区多次公开质疑'项目已死'），历史教训是其维护承诺曾中断多年**（置信度：中）
  - issue #1912 'This project is dead?'、#1887 'Future of the Unity SDK?'、#1774 'Is the Mapbox Unity SDK still being worked on?' 等；搜索结果称仓库活跃度在约 2020 年 5 月后基本停滞、issue/PR 长期积压，直到 2025 年底-2026 年才恢复密集提交（sdk3/gaVersion 分支合并）。选型时应把'曾停摆 3 年以上'计入供应商风险。
  - 来源：<https://github.com/mapbox/mapbox-unity-sdk/issues/1912>
- **Google Maps Platform gaming solution（含 Maps SDK for Unity、Playable Locations API）2021-10-18 宣布弃用，2022-12-31 彻底关停，官方原因是采用率有限（limited adoption）**（置信度：高）
  - 弃用公告 2021-10-18 发布，既有客户可用至 2022-12-31；受影响产品包括 Square Enix/COLOPL 的 Dragon Quest Walk（被迫迁移到其他地图服务）。Google 官方 deprecations 页将关停原因表述为 limited adoption。该 SDK 与 Lightship Maps 同为'矢量数据→Unity 内生成 GameObject/mesh'路线，说明大厂做'游戏引擎内真实地图'两次商业化尝试均告失败。
  - 来源：<https://developers.google.com/maps/deprecations>
- **Dragon Quest Walk 等在营 LBS 游戏因 Google gaming services 关停被迫整体迁移地图技术栈——绑定大厂引擎内地图 SDK 的平台风险已被验证过一次**（置信度：高）
  - Automaton 2021-10-19 报道：Google 于 10 月 18 日弃用 gaming services，DQ Walk 在游戏内公告确认受影响并宣布将切换其他服务以维持运营；文中明确该服务包含 Maps SDK for Unity（Unity 内实现 LBS 功能）与 Playable Locations API（游戏对象放置候选点）。
  - 来源：<https://automaton-media.com/en/news/20211019-4449/>
- **Niantic Lightship Maps SDK for Unity 已完整日落：2025-07 停止支持、2025-08 下线文档与 GitHub 仓库、2025-10 关闭服务端点；官方建议迁移到 Mapbox 或 Esri**（置信度：高）
  - 官方 Sunset Notice 原文（2026-08 实测仍在线）：'No further updates'、'Support ends on July 2025'、'Docs & samples removed on August 2025'、'GitHub repo decommissioned on August 2025'、'SDK deactivation on October 2025 (Niantic Labs endpoints will be shut down)'；原因是 Niantic 游戏部门作为独立公司并入 Scopely、Niantic Spatial 转向企业/开发者空间智能业务；'Recommended Next Steps' 点名 Mapbox 与 Esri（'These platforms offer rich Unity support'）。实测 lightship.dev/docs/maps/ 已 404，印证文档下线。
  - 来源：<https://www.nianticspatial.com/en/products/maps-sdk-notice>
- **Lightship Maps SDK 的技术路线是'矢量地图几何+语义→Unity 内由 feature builder 生成瓦片 mesh（maps as GameObjects）'，即引擎内矢量瓦片重建的代表实现**（置信度：中）
  - 其（已下线的）Unity 开发文档描述：Lightship Maps prefab 携带可配置 feature builders 用于'generating and rendering meshes for map tiles features'；开发者可获得'full access to vectorized map geometry and semantics'并据此程序化生成内容；map layer 是与地图关联的一组 GameObject。该 SDK 曾长期停留在 public beta（v0.x），从未 GA。
  - 来源：<https://lightship.dev/docs/maps/unity/>
- **Pokémon GO 的地图是 Unity 引擎内渲染的风格化地图，数据源 2017-12 起从 Google Maps 全面切换为 OpenStreetMap；Niantic 后来把这套地图技术产品化为 Lightship 平台开放**（置信度：高）
  - OSM Wiki 与多家媒体记录：2017 年 11-12 月 Niantic 分批把 in-game 底图从 Google 数据切到 OSM（2017-08 快照），此前 OSM 仅用于 spawn point 逻辑；地图为游戏内自渲染（非嵌入地图 SDK 视图）。Time（2022-05）报道 Niantic 通过 Lightship 把'powers Pokémon GO'的地图/空间技术开放给开发者。注意：2025 年游戏部门售予 Scopely 后其内部管线不再对外。
  - 来源：<https://wiki.openstreetmap.org/wiki/Pok%C3%A9mon_Go>
- **Zenly 是'完全自研地图引擎'路线的代表：早期用 MapKit/Google Maps SDK（也用过 Mapbox），2019 年起代号 Wonka 自研三年，2022-05 上线自有数据+自研 3D 渲染引擎，明确自述用'video game technology'榨取设备性能**（置信度：高）
  - TechCrunch 2022-05-18 采访地图负责人 Charly Delaroche：初期'working with MapKit and Google Maps SDK'、因无法控制画布而自研；项目始于 2019、按'当时的新机型'定性能基线（iOS 12 为下限）；'We wanted to do something that was more 3D and used video game technology to use the maximum performance of the device'；含 fog of war、动画等游戏化表现。另有 Mapbox 官方博客 'Clear the fog with Zenly' 佐证其中期用过 Mapbox。
  - 来源：<https://techcrunch.com/2022/05/18/social-maps-app-zenly-rolls-out-its-own-maps/>
- **Zenly 的教训：顶级自研地图引擎救不了商业模式——2022-08 Snap 宣布裁撤、2023-02-03 关停，理由是'不太可能产生有意义的利润'**（置信度：高）
  - TechCrunch 2022-12-05：Zenly（约 4000 万用户）随 Snap 裁员 20% 的成本削减被关停，2023-02-03 下线；Snap 称决策依据是 app 盈利可能性低、流行市场变现困难。对本项目的含义：自研全套地图渲染（Zenly 约 10 人地图团队做了 3 年+）是重资产路线，不适合作为迁移方案首选。
  - 来源：<https://techcrunch.com/2022/12/05/zenly-was-the-best-social-app-and-it-will-sadly-shut-down-on-february-3rd/>
- **Snap Map 的架构是'Mapbox 数据/服务 + Snap 自研定制 GL 渲染'，Bitmoji 角色由应用层绘制在地图上，而非游戏引擎场景**（置信度：中）
  - Mapbox 官方博客 'Mapbox helps power Snap Map'：Snap Map 使用 Mapbox（含 Geocoding 等服务），Snapchat 团队'built custom GL rendering with OpenGL-based innovations to render complex layers in a fast, performant way'。Bitmoji 3D 头像在移动端可 30-40 FPS 渲染（Snap 开发者文档/AWS 案例）。即：地图渲染器与角色渲染同属应用自绘层，属'地图渲染器体系内叠加角色'而非引擎内重建。注意该合作文章较早（约 2017），2024-2026 现状未复核。
  - 来源：<https://medium.com/mapbox/mapbox-helps-power-snap-map-4ced4fb3176a>
- **Jagat（Zenly 停服后最大的继任社交地图 App 之一）走的是'原生地图 SDK 出图'路线：iOS 上默认 Apple Maps（MapKit），可切换 Mapbox 风格视图，角色/emoji 由应用层叠加**（置信度：低）
  - NamuWiki 词条记录其地图使用 Apple Maps、可切换 Mapbox（圆形地图视图）；产品于 2023 年爆发（3 天 50 万下载、首月 1M+ DAU，TechCrunch 2023-12 报道破 1000 万用户）。无任何证据表明其使用游戏引擎渲染地图。二手来源，置信度中低。
  - 来源：<https://en.namu.wiki/w/Jagat>
- **业界模式一（引擎内矢量瓦片→mesh 重建）：代表 Pokémon GO/Lightship Maps/Google Maps SDK for Unity/Mapbox Unity SDK v3/第三方 GO Map 插件；优点是角色与地图同场景（光照/阴影/遮挡/相机完全一致、风格自由），缺点是 SDK 生态死亡率极高且 Godot 无任何现成实现**（置信度：高）
  - 该模式四个商业实现中：Google 已关停（2022）、Niantic 已日落（2025）、Mapbox Unity 版曾停摆 3 年后于 2026 复活但仅限 Unity、Unity Asset Store 的 GO Map 等第三方插件仅覆盖 Unity。对 Godot 意味着必须自研矢量瓦片解析+mesh 生成+样式系统（Zenly 级投入的子集），与'不再引擎内贴瓦片'的诉求兼容但工程量最大。
  - 来源：<https://www.nianticspatial.com/en/products/maps-sdk-notice>
- **业界模式二（原生地图 SDK 渲染底图 + 上层合成角色）：Zenly 停服后的社交地图产品（Jagat、Snap Map、whoo 等）事实上的主流路线；映射到本项目即'Mapbox 原生 Maps SDK v11+ 出图 + Godot 透明层渲染角色'**（置信度：中）
  - 该模式地图渲染性能由 Mapbox/Apple 原生渲染器保证（Metal/Vulkan-backed），角色层保留引擎全部材质/动画/换装能力；技术难点集中在两点：(1) 引擎视图与原生地图视图的合成方式（透明 SurfaceView/UIView 层叠 vs 纹理共享）及其对 60fps 的影响，(2) 地图相机与引擎相机的逐帧同步（手势输入归属、投影矩阵对齐）。社交地图产品中角色多为 2D/轻 3D 贴片，'重蒙皮动画角色+透明引擎层'的公开先例未检索到，需原型验证。
  - 来源：<https://medium.com/mapbox/mapbox-helps-power-snap-map-4ced4fb3176a>
- **业界模式三（WebView + Mapbox GL JS）与模式四（地图渲染器内直接渲染角色，如 GL JS custom layer + three.js 加载 glTF）在移动 App 中均无可查证的知名'3D 角色站地图'先例**（置信度：中）
  - 模式三：GL JS 渲染质量成熟，但移动端 WebView 与引擎双向相机/手势同步、合成帧率、离线能力均是风险点，检索不到走此路线的头部移动产品。模式四：Mapbox GL JS 的 custom layer 配 three.js 渲染 3D 模型是 Web 端成熟做法（中文社区大量实践文章），原生 Maps SDK v11 亦有 custom layer 接口，但在地图渲染器内实现蒙皮骨骼动画+运行时换装+自定义 toon shader 等于重写整套角色管线，与'保留现有 Godot 资产'的硬性需求冲突。
  - 来源：<https://zhuanlan.zhihu.com/p/65980510>
- **横向教训：所有把'真实地图进游戏引擎'押注在大厂 SDK 上的产品都经历过至少一次被迫迁移；Niantic 官方给自家 SDK 用户的退路就是 Mapbox/Esri，印证 Mapbox 是当前该领域存活的默认选项**（置信度：高）
  - 时间线：Google gaming services（2018 推出→2021 弃用→2022 关停）→受影响者迁移；Lightship Maps（2022 beta→2025 关停）→官方建议 Mapbox/Esri；Mapbox Unity SDK（2017 推出→2020 停滞→2026 v3 复活）。稳定的是 Mapbox 的数据/瓦片/原生渲染器产品线本体（GL JS、Mobile Maps SDK、MTS），不稳定的是各家'游戏引擎壳'。结论：方案应绑定 Mapbox 渲染器/数据这一稳定层，而非任何引擎专用 SDK 层。
  - 来源：<https://www.nianticspatial.com/en/products/maps-sdk-notice>

### 遗留问题（该维度未决）

- 'Whee' 具体指哪款产品未能确证（可能是日本的 whoo location app 或其他 Zenly 继任 App）；whoo 的地图技术栈也未检索到一手资料，建议上游澄清产品名后再查。
- Snap Map 2024-2026 年现状是否仍基于 Mapbox 未复核（引用的合作文章约为 2017 年）；Snap 收购 Zenly 后其自研引擎技术是否被并入 Snap Map 亦无公开资料。
- Mapbox Maps SDK v11+（Android/iOS 原生）与 Godot 的具体合成方式（透明 GLSurfaceView/UIView 层叠、外接纹理、Metal/Vulkan 互操作）的可行性与帧率数据属于其他调研维度，本维度只确认了'原生 SDK+上层角色'是业界主流模式，未验证 Godot 侧实现。
- Mapbox Unity SDK v3 的原生库（iOS XCFrameworks / Android sqlite libs）具体承担多少职责（仅瓦片存取还是含部分渲染核心）未深挖；若其复用了 mapbox native core 的瓦片管线，对评估'Mapbox 对游戏引擎的长期承诺'有参考价值。
- Esri ArcGIS Maps SDK for game engines（Niantic 官方推荐的另一家）的现状、许可与移动端表现本次未调研。
- Pokémon GO 在 Scopely 时代（2025 至今）的客户端地图管线是否有架构变化无公开资料；被迫离开 Lightship Maps 的第三方开发者实际迁移去向（Mapbox Unity v3？自研？）也缺乏公开案例。

## 5. 引擎内自渲染替代路线（对照组）

### 结论摘要

引擎内自渲染路线在 Godot 生态里没有一条能直接满足"Android/iOS 移动端 + 60fps + 生产质量地图"的现成方案。MVT→mesh 方向只有废弃或桌面向的项目（最高星的 godot-openstreetmap 已两年停更且自述不稳定，活跃的 geodot-plugin 仅支持桌面三平台），且全部缺失文字标注渲染链路。Cesium 方向的"3D Tiles for Godot"是 Battle Road Labs 受 Cesium Ecosystem Grant 资助的社区插件（非 Cesium 官方产品），2025 年发布后仍活跃，但平台仅限 Windows/Linux/macOS，Android 只是"未来计划"、iOS 无计划，因此 Google Photorealistic 3D Tiles 在 Godot 移动端也不可用（且 photoreal 风格与卡通角色 App 不匹配、按 root tileset 计费）。MapLibre Native 嵌入 Godot 有唯一先例 yuiseki/maplibre-native-godot（实验性，2 stars，仅桌面），其每帧 readStillImage CPU 回读机制在移动端跑 60fps 是硬伤；MapLibre Native 本体的移动端渲染（iOS Metal、Android Vulkan/GLES）倒是成熟，但把它以零拷贝方式塞进 Godot 移动端需要数月级自研。计费上，自渲染路线若继续用 Mapbox 托管瓦片会退化为按 tile request 计费（不如官方 SDK 的 MAU/map load 含无限瓦片），实践中只能换 MapTiler/OpenMapTiles 系数据源并放弃 Mapbox Studio 样式生态。结论：这些对照路线全部劣于"Mapbox/MapLibre 官方渲染器出图"主路线，其中唯一理论可行但代价极高的是自研 MapLibre Native GDExtension 移动端集成。

### 关键发现

- **Godot 生态不存在生产级的 MVT→mesh 矢量瓦片渲染插件，最高星项目已停更且自述不稳定**（置信度：高）
  - GitHub 全量检索（godot+openstreetmap / vector tile / mvt / mapbox 等关键词）最高星为 RodZill4/godot-openstreetmap（232 stars），从 OSM 数据生成 3D 建筑/道路场景，最后 push 2024-06-23，README 自述 Godot 4 迁移中'simple demo working although unstable'，无标注/文字渲染；其余 Toshiwoz/GodotMapLoader（51 stars，2019 停更）、fcazalet/godot-osm-tilemap（18 stars，2021 停更，且是栅格 tilemap）；2026 年新出现的若干 OSM 小项目（openstreetmap-racer 等）均为 0-4 stars 玩具级。没有任何项目实现 MVT 解码→样式化 mesh→文字标注的完整链路
  - 来源：<https://github.com/RodZill4/godot-openstreetmap>
- **活跃的 Godot 地理插件 geodot-plugin 面向桌面 GIS 可视化，不支持移动端**（置信度：高）
  - boku-ilen/geodot-plugin（186 stars，2026-07-13 仍有提交）是 GDAL 的 GDExtension 封装，用于本地地理数据加载；README 构建说明仅覆盖 Linux/Windows/macOS 三平台，无 Android/iOS 构建路径；其宿主项目 LandscapeLab 是桌面/VR 景观可视化工具，定位与移动地图 App 完全不同
  - 来源：<https://github.com/boku-ilen/geodot-plugin>
- **'Cesium for Godot' 实为社区插件 '3D Tiles for Godot'（Battle Road Labs 开发、Cesium Ecosystem Grant 资助），并非 Cesium 官方维护产品**（置信度：高）
  - 2025-05-01 Cesium 官方博客宣布，插件由 Battle Road 通过 Cesium Ecosystem Grant 构建，基于 GDExtension 集成 cesium-native，支持 Cesium ion、WGS84 高精度地球、physics/collision，要求 Godot 4.1+/Forward+；与 Cesium for Unity/Unreal 的官方一方支持地位不同
  - 来源：<https://cesium.com/blog/2025/05/01/introducing-3d-tiles-for-godot-by-battle-road/>
- **3D Tiles for Godot 目前仅支持桌面三平台，Android 是'未来计划'（issue 挂起一年余无进展），iOS 完全无计划，移动端直接不可用**（置信度：高）
  - README 明确'available for Windows, Linux, and macOS (Apple Silicon)... with support for Web and Android coming in the future'，iOS 未被提及；issue #77（Android version，2025-05-02 建）至今 open；release 仅 v1.0.0（2025-04-28）和 v1.0.1（2025-08-31）两版；仓库仍活跃（161 stars，最后 push 2026-08-05，24 open issues），另需注意双精度模式要自编译 Godot（precision=double）
  - 来源：<https://github.com/Battle-Road-Labs/3D-Tiles-For-Godot>
- **Google Photorealistic 3D Tiles 在 Godot 只能经 3D Tiles for Godot/cesium-native 接入，因此移动端同样不可用；且计费按 root tileset 请求收费、视觉风格与卡通 App 不匹配**（置信度：高）
  - 计费：Map Tiles API 的 Photorealistic 3D Tiles 每月 1000 次免费 root tileset 请求，超出后 $6.00/1000 次（CPM），一次 root tileset 请求覆盖约 3 小时 session 内的瓦片请求，每日上限 10000 次 root tileset 查询；photogrammetry 实景网格的流式带宽/内存开销面向桌面级场景设计，对'卡通角色站在地图上'的产品形态既过重又风格冲突
  - 来源：<https://developers.google.com/maps/documentation/tile/usage-and-billing>
- **MapLibre Native 嵌入 Godot 存在唯一直接先例 yuiseki/maplibre-native-godot，但属个人实验项目且仅支持桌面**（置信度：高）
  - GDExtension 暴露 MapLibreMap 节点（继承 TextureRect），用 maplibre-native 的 WebGPU headless 后端（wgpu-native），MapMode::Continuous + 每帧 renderOnce() + readStillImage() 回读像素 → ImageTexture::update()；GDScript API 覆盖 set_style_url/fly_to/jump_to/set_pitch/set_bearing/geo_to_screen/screen_to_geo 等；README 声明'Working on Linux, Windows, and macOS'，无移动端；基于 godot-cpp 4.3-stable，有 open issue 'Support for Godot 4.7?'；仓库 2026-04-14 创建、2026-06-23 最后 push，仅 2 stars/0 forks，公交车系数为 1
  - 来源：<https://github.com/yuiseki/maplibre-native-godot>
- **该先例的每帧 GPU→CPU→GPU 像素回读架构（readStillImage → ImageTexture::update）在中端手机上稳 60fps 风险极大，走通移动端需换零拷贝共享纹理方案且无现成实现**（置信度：中）
  - README 架构表明确 'wgpu-native and Godot's Vulkan/Metal renderer use independent contexts'（两套独立 GPU 上下文，靠 CPU 拷贝桥接）；移动端零拷贝需要 Vulkan external memory / Metal shared texture / GLES external texture 级别的引擎侧打通，Godot 与 maplibre-native 两边都无现成接口，属自研范畴；估算工作量为数月级（含 Android/iOS 交叉编译 maplibre-native + GDExtension 移动构建 + 手势/标注交互桥接）
  - 来源：<https://github.com/yuiseki/maplibre-native-godot/blob/main/README.md>
- **MapLibre Native 本体的移动端渲染成熟：iOS 自 v6.0.0 起用 Metal，Android 已正式发布 Vulkan 后端（并保留 OpenGL ES 版本），这是自研集成路线唯一的正面基础**（置信度：高）
  - 渲染器 2023 年完成模块化后陆续落地 Metal（iOS v6.0.0）、Vulkan（Android，发行版分 org.maplibre.gl:android-sdk 与 android-sdk-opengl）、WebGPU（最新，桌面实验）；即若自研 Godot 集成，移动端应直接用 Metal/Vulkan 原生后端而非先例所用的 WebGPU headless 后端
  - 来源：<https://maplibre.org/maplibre-native/docs/book/platforms/index.html>
- **包体代价：MapLibre Native 的 .so/.dylib 为每 ABI 约 10-30MB 量级的原生库；MVT-DIY 路线包体最小；cesium-native + 3D Tiles 路线居中但叠加流式数据的内存/带宽开销**（置信度：低）
  - 直接证据较弱：Android 优化文章称从 APK 移除 MapLibre 单一 ABI 的 .so 可省 10-30MB；MapLibre 官方未发布精确 per-ABI 体积数据；cesium-native 路线的运行时内存主要消耗在瓦片缓存与 photogrammetry mesh，插件未提供移动端实测数据（因为根本没有移动端构建）
  - 来源：<https://medium.com/android-news/controlling-apk-size-when-using-native-libraries-45c6c0e5b70a>
- **计费差距：第三方/自研渲染器使用 Mapbox 托管矢量瓦片将按 tile request 计费，显著劣于官方 SDK 的计费模型（web map load / 移动端 MAU 均含无限瓦片请求）**（置信度：高）
  - Mapbox 定价文档明确：非 Mapbox GL JS/官方 SDK 渲染的地图按 Vector Tiles API tile request 计费；官方移动 Maps SDK 按 MAU 计费（阶梯断点 25k/125k/250k/1.25M MAU），一次 map load/MAU 内瓦片请求不限量。因此自渲染路线实践中会改用 MapTiler/OpenMapTiles/Protomaps/OpenFreeMap 等数据源，但即放弃 Mapbox 数据
  - 来源：<https://docs.mapbox.com/accounts/guides/pricing/>
- **样式与标注质量差距：MVT-DIY 路线需从零自建文字标注渲染（SDF 字形、标注碰撞消隐、CJK/多语言、道路沿线文字），现有 Godot OSM 项目无一实现；MapLibre Native 路线自带完整样式+标注渲染但样式生态弱于 Mapbox 官方**（置信度：中）
  - MapLibre Style Spec 从 Mapbox Style Spec v8 分叉，兼容大部分经典样式语法，可用 Maputnik/MapTiler 编辑器，但 Mapbox Studio、Mapbox Standard（v11+ 的 3D 光照/dynamic 样式）等专有生态不可用；MVT-DIY 连底线的标注能力都要自研，这是该路线最大的隐藏工作量
  - 来源：<https://maplibre.org/projects/native/>

### 遗留问题（该维度未决）

- maplibre-native 的 WebGPU 后端（wgpu-native）在 Android/iOS 上的可用性与成熟度未查证——若自研移动集成，是复用 WebGPU headless 还是必须切到 Metal/Vulkan 原生后端并自建 headless 渲染目标，直接决定工作量下限
- Godot 4.7 是否已提供官方外部纹理导入 API（Vulkan external memory / Metal shared texture / GLES external_oes）可让 MapLibre 离屏纹理零拷贝进 Godot 渲染管线——本维度未查 Godot 渲染 API 文档，这是 CPU 回读瓶颈能否根除的关键
- 3D Tiles for Godot 的 Android 支持有无路线图或时间表（issue #77 无维护者承诺）；以及其是否计划支持矢量底图（目前只做 3D Tiles/影像地形，本就不覆盖'街道地图'形态）
- Mapbox TOS 对'下载 MVT 瓦片后在完全第三方引擎内渲染'的许可条款细节（计费规则已确认按 tile request，但许可合规性未逐条核实）
- yuiseki/maplibre-native-godot 的每帧回读在桌面端的实测帧耗（README 提到 get_last_render_ms API 和 FPS benchmark demo，但未公布数据），可作为评估移动端可行性的基线

### 对抗验证

#### 验证 5.1：裁决 ⚠️ 部分成立/需修正

说法(1)"Cesium for Godot 已可用于生产移动端"被推翻：该插件实为 Battle Road Labs 经 Cesium Ecosystem Grant 开发的社区插件"3D Tiles for Godot"（非 Cesium 官方维护），截至 2026-08-25 仅支持 Windows/Linux/macOS 桌面端，README 明示 Android 属"未来计划"、iOS 从未被提及；Android issue #77 挂起 15 个月，维护者自认"我们自己从未验证过 Android"，且有两位用户（2025-07 与 2026-06）在 Meta Quest 3 真机导出实测失败（无 Android 二进制，每个 Cesium 节点报错）；发版仅 v1.0.0/v1.0.1 两版，2026 年提交全为桌面向（macOS 支持、metadata）。底层 cesium-native 本身可跑移动端（下游 Cesium for Unity 有 iOS/Android 正式构建），故障碍在 Godot 插件层，但自行移植属无人排期的自研工作。说法(2)"MapLibre Native 可作为库嵌入游戏引擎做离屏渲染到纹理"部分成立：桌面端已有可运行先例——个人项目 yuiseki/maplibre-native-godot（WebGPU headless 后端 + 每帧 renderOnce()/readStillImage() CPU 回读，仅 Linux/Windows/macOS，2 stars/0 forks，基于 godot-cpp 4.3，2026-06-23 后无提交，"支持 Godot 4.7?"issue 无人回应），以及上游遗漏的 MapLibre 官方 org 嵌入参考实现 maplibre/maplibre-native-slint（活跃至 2026-08-22，但自述"尚非成品 SDK"且同样仅桌面三平台）；核心库确有 HeadlessFrontend 离屏渲染能力（含 Vulkan headless），且本体移动渲染后端成熟（iOS 自 ios-v6.0.0/2024-01-16 起 Metal；Android 自 android-v13.0.0/2026-03-03 起 Vulkan 为 org.maplibre.gl:android-sdk 默认后端，OpenGL ES 保留于 android-sdk-opengl，最新 android-v13.5.1/2026-08-21）。但"嵌入游戏引擎"无任何官方支持承诺（Unity 移动端嵌入询问 issue #1257 被关闭且无解决方案），无任何移动端嵌入先例，现有先例均为桌面级 PoC 且依赖每帧 GPU→CPU→GPU 拷贝——该说法作为"技术可行性已被桌面验证"成立，作为"成熟可用路线"不成立，移动端属数月级自研。上游 11 条初步结论经对抗复核全部关键事实成立，未发现错误，仅需上述三处精化补强。

证据：

- 3D Tiles for Godot 当前 master README「Supported Platforms」原文：available for Windows, Linux, and macOS (Apple Silicon)... with support for Web and Android coming in the future；iOS 全文未提及；另要求 Godot 4.1+、Forward+ 渲染器、双精度需自编译 Godot（precision=double）。置信度：高（仓库原文直取）
  - <https://github.com/Battle-Road-Labs/3D-Tiles-For-Godot>
- issue #77（Android version）2025-05-02 建、至今 open；维护者 Kyn21kx 2025-05-02 回复承认 We haven't verified this ourselves yet；用户 CoffeeAt0900（2025-07-23）与 AaronTaube（2026-06-18）先后报告 Meta Quest 3 部署失败、编辑器对每个 Cesium 节点报错——比上游「挂起无进展」更决定性：真机实测不可用。置信度：高
  - <https://github.com/Battle-Road-Labs/3D-Tiles-For-Godot/issues/77>
- GitHub API 实测（2026-08-25）：该仓库 161 stars、最后 push 2026-08-05、24 open issues、仅 v1.0.0（2025-04-28）与 v1.0.1（2025-08-31）两个 release；近 30 条提交全为桌面向（macOS ARM64 支持、KHR 材质扩展、metadata），零 Android/iOS 移植迹象。置信度：高
  - <https://github.com/Battle-Road-Labs/3D-Tiles-For-Godot/releases>
- Cesium 官方博客（2025-05-01）确认：插件由 Battle Road 经 Cesium Ecosystem Grant 构建，「The Battle Road team is committed to maintaining and updating the plugin」——维护主体是 Battle Road 而非 Cesium，与 Cesium for Unity/Unreal 的一方产品地位不同。上游此条成立。置信度：高
  - <https://cesium.com/blog/2025/05/01/introducing-3d-tiles-for-godot-by-battle-road/>
- 反向论点验证：cesium-native 底层可跑移动端——下游 Cesium for Unity 的 CHANGES.md 记录「Added support for building to iOS」「Added support for building to Android」及后续 iOS/Android 修复（含 Android 15 十六 KB 页对齐）。即 Godot 移动端缺口在 GDExtension 插件层（构建/HTTP/CI），非 cesium-native 本体，但该移植无人排期。置信度：高
  - <https://github.com/CesiumGS/cesium-unity/blob/main/CHANGES.md>
- yuiseki/maplibre-native-godot README 原文「Status: Working on Linux, Windows, and macOS」；架构为 MapMode::Continuous + 每帧 renderOnce() + readStillImage() 回读像素（WebGPU headless/wgpu-native 后端）；GitHub API 实测：2 stars/0 forks、2026-04-14 创建、2026-06-23 最后 push、基于 godot-cpp 4.3-stable、issue #12「Support for Godot 4.7?」（2026-07-02 建）open 无回复。上游此条全部属实。置信度：高
  - <https://github.com/yuiseki/maplibre-native-godot>
- 上游遗漏的重要正面证据：MapLibre 官方 org 下存在嵌入参考实现 maplibre/maplibre-native-slint（23 stars，最后 push 2026-08-22，活跃），README 自述「Not yet a polished end-user SDK」「works on Linux, Windows, and macOS」——证明「把 MapLibre Native 当库嵌入宿主 UI 框架渲到纹理」的模式被官方社区认可并持续维护，但同样明确非生产级、仅桌面三平台、无移动端。置信度：高
  - <https://github.com/maplibre/maplibre-native-slint>
- iOS Metal 后端时间点确证：ios-v6.0.0 release（2024-01-16 发布）原文「This is the first release that uses Metal for rendering. This is a graphics API from Apple that replaces OpenGL ES on Apple platforms」。上游此条成立。置信度：高
  - <https://github.com/maplibre/maplibre-native/releases/tag/ios-v6.0.0>
- Android Vulkan 后端精确版本（上游缺失）：CHANGELOG 13.0.0 条目「Breaking: Use Vulkan as rendering backend for the org.maplibre.gl:android-sdk package. You can still use OpenGL ES with the org.maplibre.gl:android-sdk-opengl package」；GitHub API 实测 android-v13.0.0 发布于 2026-03-03，最新 android-v13.5.1 发布于 2026-08-21，13.5.x 另增 multiBackend flavor 运行时 GL/Vulkan 切换（PR #4288）——发版节奏密集，移动渲染本体成熟且活跃。置信度：高
  - <https://github.com/maplibre/maplibre-native/blob/main/platform/android/CHANGELOG.md>
- 官方无游戏引擎嵌入支持承诺：issue #1257「maplibre - Unity support」（2023-06 提问「能否用于 Android/iOS 跨平台 Unity 应用」）已 closed 且无任何解决方案回复；仓库内无 Unity/Unreal/Godot 官方集成或路线图。离屏能力本身存在于核心（platform/default/include/mln/gfx/headless_frontend.hpp 的 HeadlessFrontend，changelog 有 Vulkan headless 快照修复记录），但「能力存在」不等于「嵌入引擎受官方支持」。置信度：高（负面证据基于仓库检索，存在漏检的小概率）
  - <https://github.com/maplibre/maplibre-native/issues/1257>

<details><summary>验证方法与裁决口径（展开）</summary>

对抗复核范围与结果：上游 11 条初步结论的关键事实（仓库星数/时间线/README 原文/release 记录/博客表述）逐条经 GitHub API 与官方页面一手核验，未发现任何需推翻的错误结论，上游整体质量高。三处精化：(1) 3D Tiles for Godot 的 Android 不可用有真机失败报告佐证（Quest 3 导出报错），比「issue 挂起」更硬；同时补充反向 nuance——cesium-native 本体在下游 Unity 插件已跑通 iOS/Android，Godot 缺口纯在插件层；(2) Android Vulkan 默认化的精确版本与日期为 android-v13.0.0 / 2026-03-03（上游未给版本号），且上游所列 android-v11.x 已是旧系列，当前为 v13.5.1；(3) 上游遗漏 maplibre/maplibre-native-slint——官方 org 维护的嵌入参考实现，对「嵌入可行性」是比 yuiseki 个人项目更权威的正面证据，但其自述与平台限定同样支持「桌面 PoC、非生产、无移动端」的总判断。未复核项：上游关于包体大小的条目（其自标 low，无官方 per-ABI 数据，维持存疑）与 Mapbox/Google 计费条目（非本次两个核心问题，未做对抗验证，不代表背书）。核查方法局限：cesium.com 与 maplibre.org 域名被网络策略拦截 WebFetch，分别改用 curl 直取博客正文与 GitHub 仓库内文档源文件，内容均为一手。对上游架构风险判断（每帧 GPU→CPU→GPU 回读难稳中端机 60fps）：其 README 依据属实，但无任何一方发布过移动端实测帧率数据，该性能结论本身仍是推断而非实测，维持 medium 置信。

</details>


## 6. 角色资产管线（迁移代价）

### 结论摘要

若选择"地图侧（three.js/原生）渲染角色"，现有 Godot 角色资产迁移在几何/蒙皮/动画层面可行但保真度有硬伤，材质层面则是完全重写。Godot 4 编辑器与运行时（GLTFDocument）都能导出 glTF 2.0，蒙皮与骨骼动画轨道基本保留，但官方文档明确 ShaderMaterial 不可导出（自定义 toon shader 100% 丢失），且骨骼动画导出存在仍 open 的根关节运动错误 bug；更稳的转换链是绕开 Godot、从 Unity 原始 FBX 经 Blender 转 glTF，但 Blender FBX 导入本身有骨骼朝向猜测与动画逐帧烘焙两个保真度损耗点。three.js 侧多蒙皮部件共享骨架换装是官方支持（DetachedBindMode/SkinnedMesh.bind）且社区大量实践，但坑密度高（坐标系、bind matrix、包围球、骨骼命名一致性）；本项目 SM_/SK_ 两族 FBX 坐标系差异和 socket 三层机制刚在 Godot 侧对齐完，换到 three.js 要按其左右手系/Y-up 约定全部重推一遍。toon 渲染在 three.js 生态里 MeshToonMaterial 过于简陋（无描边），完整移植需基于 @pixiv/three-vrm 的 MToon 或手写 GLSL。总体定性：这是"三大子系统（换装、socket 校正、toon shader）在第二个渲染器里重写 + 每次资产更新双端回归"的持续性双维护成本，属于高成本选项，仅当地图侧渲染在其他维度收益压倒性时才值得。

### 关键发现

- **Godot 4 编辑器可将场景导出为 glTF 2.0，但官方文档明确列出 ShaderMaterial 不可导出——自定义 toon shader 在任何 Godot→glTF 路线上必然丢失**（置信度：高）
  - 编辑器入口 Scene > Export As... > glTF 2.0 Scene...，支持 .glb 与 .gltf+.bin+纹理。官方 Limitations 原文："ShaderMaterials cannot be exported"，另外粒子与 2D 场景也不导出。含 ShaderMaterial 的网格导出时材质落回默认/无材质，几何与蒙皮仍在。适用 Godot 4.x stable 文档（2026-08 抓取 master 分支 exporting_3d_scenes.rst 原文核实）。
  - 来源：<https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/exporting_3d_scenes.html>
- **Godot 运行时导出 glTF 的官方 API 存在且在打包后的工程里可用：GLTFDocument.append_from_scene → generate_buffer / write_to_filesystem**（置信度：高）
  - 官方 Runtime file loading and saving 文档："Godot has first-class support for glTF 2.0, both in the editor and exported projects. Using GLTFDocument and GLTFState together, Godot can load and save glTF files in exported projects"。API 名已在 master 分支 modules/gltf/doc_classes/GLTFDocument.xml 核实：append_from_scene(node, state)、generate_buffer(state) 返回 PackedByteArray、write_to_filesystem(state, path)。可用于写自动化脚本批量把现有 Skeleton3D+AnimationPlayer 场景转 glb。
  - 来源：<https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html>
- **历史上 ShaderMaterial 曾导致 glTF 导出直接崩溃（#70159），已于 4.0 stable 修复；修复方式是不崩溃地跳过，材质仍不转换**（置信度：高）
  - issue #70159（4.0 beta7/8 崩溃）2022-12-17 关闭，milestone 4.0，修复 commit b14c87cb 标题 "glTF: Fix export crash with a ShaderMaterial (fixes #70159)"，只改 modules/gltf/gltf_document.cpp。含义：4.0+ 用 ShaderMaterial 导出不再崩，但不要期待任何 shader 参数被翻译成 glTF PBR。
  - 来源：<https://github.com/godotengine/godot/issues/70159>
- **Godot glTF 导出骨骼动画存在仍 open 的保真度 bug：根关节运动写出错误（#114110），影响 4.4.1 与 4.5.1**（置信度：高）
  - issue #114110（2025-12-17 提报，2026-08 仍 open、无 milestone）：Scene > Export As 导出的 glTF 在 Blender / Khronos glTF Sample Viewer / Babylon sandbox 中根骨骼动画键值错误（有 key 但值不对）。对'角色贴地移动'类动画（根位移）是直接命中。另有 #78028（open）：纯骨架无网格的动画场景无法导出——本项目角色带网格，影响较小但说明导出器边角未打磨。迁移前必须用真实角色资产实测目标 Godot 版本。
  - 来源：<https://github.com/godotengine/godot/issues/114110>
- **three.js 多蒙皮部件共享一套骨架做换装是官方支持的一等能力：SkinnedMesh.bindMode 的 DetachedBindMode 文档明言用于跨多个 SkinnedMesh 共享 skeleton**（置信度：高）
  - 官方 SkinnedMesh 文档原文："DetachedBindMode ... is useful when sharing a skeleton across multiple skinned meshes"。配套 API：SkinnedMesh.bind(skeleton, bindMatrix)、Skeleton、SkeletonUtils.clone。前提约束：各部件必须以同一骨架（相同骨骼命名与层级）绑定导出。
  - 来源：<https://threejs.org/docs/#api/en/objects/SkinnedMesh>
- **three.js 换装的社区实践量大但坑密度高：Y-up/Z-up 坐标系错位、bind matrix、包围球剔除、骨骼顺序是四类反复出现的坑；最被推荐的省事路线是所有部件+骨架合进单个 glTF 用可见性开关**（置信度：中）
  - 论坛多线程佐证（18536/61189/46226/34733）：直接替换 skeleton 常出 "freaky monster" 变形，根因多为 glTF 导出时 Z-up→Y-up 变换使外部骨骼数据失效；需 bone.matrixWorldNeedsUpdate、computeBoundingSphere 处理剔除。资深回答（Oxyn）建议：单文件包含全部部件蒙皮到同一骨架 + AnimationUtils.subclip，隐藏/显示做换装，避免运行时 rebind；readyplayerme 式大部件库才需要运行时 bind。结论：技术成熟、无框架级封装，需自研 200~500 行装配层并逐部件回归。
  - 来源：<https://discourse.threejs.org/t/sharing-a-skeleton-between-different-skinned-meshes/61189>
- **FBX→glTF 转换链现状：FBX2glTF（facebookincubator）未归档但处维护模式；Godot 官方口径是历史 FBX 导入'骨架与动画问题多到常见做法是先进 Blender 再导出 glTF 2.0'，4.3+ 已内置 ufbx 导入器**（置信度：高）
  - GitHub API 核实 facebookincubator/FBX2glTF archived=false、最后 push 2026-03-27。Godot 4.3 博文原文："Past users of .fbx encountered a plethora of issues when importing skeletons and animations, to the extent that it became common practice to import such animation files in Blender and re-export as glTF 2.0"。可行链有三条：(1) Unity 原始 FBX → Blender → glTF（社区首选）；(2) FBX2glTF 命令行（老但可批量）；(3) Godot(ufbx 导入) → GLTFDocument 导出（会叠加 Godot 导出器自身 bug）。
  - 来源：<https://godotengine.org/article/introducing-the-improved-ufbx-importer-in-godot-4-3/>
- **Blender FBX 导入本身有两个固有保真度损耗：骨骼朝向靠猜（FBX 骨骼 -X 对齐 vs Blender Y 对齐，需 automatic bone orientation）、动画一律按 baked 曲线读入（逐帧关键帧线性插值）**（置信度：高）
  - Blender 官方手册 FBX 章节明言 bones' orientation 导入复杂需调设置；动画 "reads all curves as if they were 'baked' ones"。后果：转出的 glTF 动画文件体积膨胀（每骨每帧 key）、曲线不可再编辑；骨骼视觉朝向错不影响蒙皮结果但影响在 Blender 内二次编辑。对本项目：Unity 美术源 FBX 经此链转 three.js 用 glb，蒙皮结果通常正确，但需逐动画目检。
  - 来源：<https://docs.blender.org/manual/en/2.81/addons/import_export/io_scene_fbx.html>
- **three.js 内置 toon 能力仅 MeshToonMaterial（gradientMap 阶梯光照的 Lambert 变体，无描边、无边缘光），复刻 Unity/Godot 级卡通渲染必须外接方案**（置信度：高）
  - 官方文档：MeshToonMaterial 仅比 MeshLambertMaterial 多 gradientMap 阶梯化，gradientMap 需 NearestFilter + NoColorSpace。描边需 examples/jsm/effects/OutlineEffect.js（反转外壳法，GitHub contents API 核实存在）或后处理 OutlinePass，论坛有 MeshToonMaterial+OutlineEffect 组合失效的报告（thread 40961）。若现有 Godot toon shader 含 ramp 贴图/描边/边缘光/脸部阴影修正等特性，需 onBeforeCompile 注入或整段手写 GLSL ShaderMaterial 重写，Godot shading language 无法机器翻译到 GLSL/TSL。
  - 来源：<https://threejs.org/docs/pages/MeshToonMaterial.html>
- **three.js 生态最完整的现成 toon 实现是 @pixiv/three-vrm 的 MToonMaterial，仍在活跃维护，可作移植参照或直接采用（需接受 VRM 工作流约束）**（置信度：高）
  - GitHub API 核实 pixiv/three-vrm archived=false、最后 push 2026-08-10、约 2.1k star；npm @pixiv/three-vrm 最新 3.5.5。MToon 含阴影 ramp、描边、边缘光、matcap 等完整卡通特性，但按 VRM 规范组织（材质参数挂在 VRM 扩展上）；把现有 FBX 部件资产转成 VRM 或单独实例化 MToonMaterial 均需额外胶水。工作量定性：直接用 MToon 约数天调参；忠实复刻自研 Godot toon shader 约 1-3 周（取决于特性数与双端目检验收）。
  - 来源：<https://github.com/pixiv/three-vrm>
- **本项目特有迁移成本：SM_/SK_ 两族部件 FBX 坐标系不同 + socket 三层变换机制刚在 Godot 侧按右手系重新推导对齐，换 three.js 渲染需按其约定第三次重推，不可照搬任何一侧的四元数**（置信度：高）
  - 本地已验证事实（非网络来源）：SM_* 静态网格顶点建模在骨骼系（FBX 内全局变换 (0,90,90.65)），SK_* 蒙皮网格建模在根坐标系（单位阵）；Unity 左手系、Godot 右手系，逐字迁移必错——three.js 右手系 Y-up 但 glTF 导出链会再叠一层 Z-up→Y-up 变换。socket 挂点（hairHat/glass/mask/headset/backpack）的骨骼轴向归一化逻辑（assembler.gd 的 socket_frame()）需在 three.js 里以 bone.matrixWorld 逆推重写。
  - 来源：<~/.claude/projects/-Volumes-ACASIS-projects-sensen-godot/memory/socket-part-frames.md>
- **结论（e）：'Godot 角色 + web/地图侧角色'双实现属于高且持续的双维护成本，非一次性迁移；仅当地图侧渲染角色在遮挡/性能维度有压倒性收益时才应接受**（置信度：中）
  - 成本构成：(1) 一次性——换装装配层、socket 坐标系校正、toon shader 三个子系统在 three.js 重写（合计粗估 3-6 周级）；(2) 持续性——每新增部件/动画都要走 FBX→glTF 转换链并在两个渲染器各自目检（材质无法共享定义，toon 参数改动要双端手动同步）；(3) 风险——Godot→glTF 导出链有 open 的根动画 bug（#114110），Blender 链有骨骼朝向/烘焙损耗，均需建立自动化对比验收。对照方案（角色仍由 Godot 渲染、地图以纹理/外部视图合成进 Godot）则完全复用现有资产管线，角色侧零迁移成本。
  - 来源：<https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/exporting_3d_scenes.html>

### 遗留问题（该维度未决）

- 目标 Godot 版本（用户称 4.7）的 glTF 导出器是否已修复 #114110 根关节运动 bug——需用本项目真实角色（含位移动画）实测导出后在 Khronos glTF Sample Viewer 目检
- 现有自研 toon shader 的特性清单（ramp/描边/边缘光/阴影色等）尚未逐条对照 three.js 可行性，1-3 周的移植估算需拿真 shader 拆解后修正
- 两条转换链（Unity 原始 FBX→Blender→glb vs Godot ufbx 导入→GLTFDocument 导出）对 SK_ 族蒙皮部件的保真度对比未实测，尤其 tier1 飘动动画
- 若采用'所有部件合进单一 glb + 可见性开关'的 three.js 换装方案，全部件集合的单文件体积与首屏加载耗时（移动端 WebView 内）未评估
- MToonMaterial 脱离 VRM 文件单独实例化用于非 VRM glb 的官方支持程度（API 是否稳定公开）未逐版本核实
- 地图侧渲染角色时 three.js 骨骼动画 + Mapbox GL 地图渲染叠加在中端安卓机 WebView 里能否稳 60fps——属性能维度，本维度未验证

## 7. 中国区可用性与商务/合规

### 结论摘要

Mapbox 主线在"仅海外发行"前提下商务与合规上完全可行：中国的测绘资质/ICP/地图审核/GCJ-02 义务只约束在中国境内提供地图服务或在境内应用商店上架的 App，海外发行可整体忽略（仅剩大陆开发调试需代理的工程问题）。但 Mapbox 在大陆直连已死：api.mapbox.com 从大陆 IP 连接被拒（VPN 可用），Mapbox China/mapbox.cn 已停运且域名不再解析，也不接受中国区注册。定价上两条路线差异巨大：原生 Mobile Maps SDK 按 MAU 计费（免费 25,000 MAU/月，超出 $4.00/千 MAU 起阶梯递减），GL JS 按 map load 计费（免费 50,000 次/月，超出 $5.00/千起；每次 Map 初始化计一次、会话上限 12 小时）——对高频打开的主页地图，WebView+GL JS 的月成本可能是原生 SDK 的数十倍，且 GL JS 嵌 WebView 的计费归类存在口径模糊，建议向 Mapbox 书面确认。token 方面移动端只能内置 public token，URL 限制仅对浏览器请求生效、不适用于 Android/iOS SDK，Mapbox 无包名/bundle ID 绑定，防盗用只能靠每 App 独立 token + Tokens API 轮换 + 用量监控。备胎排序：MapLibre Native（活跃维护、Metal/Vulkan 后端、零 MAU 费用）是最直接的降级路径；Google Maps 移动 SDK 2025-03 起免费不限量但难嵌入 Godot 渲染管线；若未来国内发行则必须切换高德等持证厂商并引入 GCJ-02，架构上应预留地图供应商抽象层。

### 关键发现

- **api.mapbox.com 从中国大陆直连基本不可用，须经代理/VPN**（置信度：高）
  - GitHub issue mapbox/mapbox-gl-js#13374（2024-12-27 建，至今 open）：大陆 IP 请求 https://api.mapbox.com/styles/v1/... 返回 net::ERR_CONNECTION_REFUSED，开 VPN 后同一请求成功；api.mapbox.cn 同样失败。第三方（Chinafy）亦称 Mapbox 瓦片/样式/API 在大陆被阻断、极慢或加载不全，且 Mapbox 不支持中国区注册。封锁方向（GFW 还是 Mapbox 封 IP）无官方定论，但'直连不可用'的结论不受影响。影响：仅海外发行的 App 不受影响；大陆团队开发调试需全程代理。
  - 来源：<https://github.com/mapbox/mapbox-gl-js/issues/13374>
- **Mapbox China（mapbox.cn）已停止运营，无国内合规通道**（置信度：高）
  - 2022 年起公众号注销、官网无法访问（知乎报道）；本次实测（2026-08-25）www.mapbox.cn DNS 已无解析记录，api.mapbox.cn 请求失败（issue #13374 中大陆用户实测同样失败）。Chinafy 确认该中国特供版已 discontinued，且外资企业无法取得测绘资质、无法在华合规运营。结论：不存在'切到中国节点'的选项。
  - 来源：<https://www.chinafy.com/blog/does-mapbox-work-in-china>
- **在中国境内提供地图服务需地图审核+ICP 备案+测绘资质，外商不予受理**（置信度：高）
  - 一手来源：自然资源部办公厅/工信部办公厅《关于规范移动互联网应用程序中登载使用地图行为的通知》（自然资办函〔2024〕972号，2024-04-24）：从事互联网地图服务的 APP 主办者须按《测绘法》《地图管理条例》等履行地图审核程序、ICP 备案手续，登载地图须标注审图号，地图内容更新须重新送审；违规将被处置。另据行业来源：互联网地图服务资质不受理外商投资企业申请，地图数据服务器必须设在境内，且持证单位禁止链接境外互联网地图服务（这条直接堵死'国内壳+境外 Mapbox 数据'的混合方案）。
  - 来源：<https://www.gov.cn/zhengce/zhengceku/202405/content_6950568.htm>
- **GCJ-02 坐标偏移只在'地图数据或发行地涉及中国'时构成问题，海外场景 WGS-84 全链路自洽**（置信度：中）
  - 中国法规要求境内公开发布的地图使用加密偏移坐标系 GCJ-02（偏移约几十至数百米），高德/腾讯等国内 SDK 全部输出 GCJ-02；而 GPS 定位输出 WGS-84，Mapbox 全球底图（OSM 数据）也是 WGS-84。因此：仅海外发行 + Mapbox 底图 → 定位与底图同为 WGS-84，无需任何纠偏；若未来切高德底图或国内发行 → 必须做 WGS-84→GCJ-02 转换。已知残留问题：Mapbox 底图上中国区域路网（OSM 中国数据）质量较差，海外用户若在中国境内使用会看到粗糙地图，但这不属于合规问题。
  - 来源：<https://en.wikipedia.org/wiki/Restrictions_on_geographic_data_in_China>
- **App 仅面向海外发行时，中国测绘/ICP/审图义务可以完全忽略**（置信度：中）
  - 《测绘法》《地图管理条例》及 972 号通知的适用范围是在中国境内从事互联网地图服务/在境内应用分发平台上架的 App（通知发文对象为境内主管部门与 App 主办者，配套的 App 备案制度也只覆盖境内分发）。App 不在大陆商店上架、不面向大陆用户提供服务，则无 ICP 备案、无审图号、无测绘资质要求，GCJ-02 也无需处理。边界条件：(1) 未来若上架苹果中国区/国内安卓商店，需境内主体 + ICP/App 备案 + 更换持证地图供应商，义务立即全部回来；(2) 大陆开发调试访问 api.mapbox.com 需代理（工程问题，非合规问题）。建议架构上保留地图供应商抽象层以备国内化。
  - 来源：<https://www.gov.cn/zhengce/zhengceku/202405/content_6950568.htm>
- **Mobile Maps SDK（v10/v11+）按 MAU 计费：免费 25,000 MAU/月，超出 $4.00/千 MAU 起**（置信度：高）
  - 实抓 mapbox.com/pricing（2026-08-25）'Maps SDKs for Mobile'：Up to 25,000 MAU 免费；25,001–125,000 为 $4.00/1,000 MAU；125,001–250,000 为 $3.20/1,000；250,001+ 为 $2.40/1,000；1,250,000+ 联系销售。MAU 定义：计费月内在你的 App 里访问过 Mapbox 服务的用户，一个用户一个计费月只计一次（跨版本升级不重复计，卸载重装除外）。docs.mapbox.com/accounts/guides/pricing/ 确认移动端按 MAU 或 tile requests 计费、取决于产品与版本。第三方（woosmap）称激活免费层需绑信用卡，此点需自行注册验证。
  - 来源：<https://www.mapbox.com/pricing>
- **Mapbox GL JS 按 map load 计费：免费 50,000 次/月，超出 $5.00/千起**（置信度：高）
  - 实抓 mapbox.com/pricing 及 docs.mapbox.com/mapbox-gl-js/guides/pricing/（现行 v3 口径）：map load = 每次 GL JS Map 对象初始化计一次，单次会话上限 12 小时，会话内 Vector/Raster Tiles API 请求不限量、交互（缩放/平移/切样式）不另计费。阶梯：≤50,000 免费；50,001–100,000 $5.00/1,000；100,001–200,000 $4.00/1,000；200,001–1,000,000 $3.00/1,000；1M–5M $2.50/1,000；5M+ 联系销售。v1/v2 为旧计费口径，官方建议升 v3。
  - 来源：<https://docs.mapbox.com/mapbox-gl-js/guides/pricing/>
- **对本项目（常驻主页地图），原生 SDK 的 MAU 计费远优于 WebView+GL JS 的 map load 计费，且后者计费归类有口径风险**（置信度：中）
  - 量级对比：10,000 MAU 时原生 SDK 完全免费（<25k）；同样用户走 WebView+GL JS，按每用户每天 3 次冷启动初始化 Map 计，月 map loads ≈ 900k，费用约 $2,700+/月。另有口径风险：docs.mapbox.com/accounts/guides/pricing/ 的 Hybrid frameworks 一节将 'Mapbox GL JS-based hybrid SDKs'、'Cordova/Phonegap + Mapbox GL JS' 归入按 tile requests 计费（旧版口径），现行 GL JS v3 官方口径是 Map Loads for Web，但'嵌入移动 WebView'没有单独条款；同时 TOS/LICENSE 明确禁止修改或拦截 SDK 的计费与遥测代码。若走 WebView 路线，建议向 Mapbox support 书面确认计费归类，避免被按 tile requests 口径追溯。
  - 来源：<https://docs.mapbox.com/accounts/guides/pricing/>
- **移动端 token 无法用 URL 限制防盗用，Mapbox 也没有包名/bundle ID 绑定，只能靠隔离+轮换+监控**（置信度：高）
  - 官方 docs（accounts/guides/tokens/ 与 help/dive-deeper/how-to-use-mapbox-securely/）：客户端只应内置 public scope token（pk.*，对样式只读）；secret token 绝不能进客户端；URL restrictions 仅对浏览器发起的请求有效，明确不适用于 Android/iOS/Navigation SDK；官方未提供任何基于应用包名/bundle ID 的限制机制（与 Google Maps 的 app restriction 不同），故 pk token 被反编译提取后可被冒用。官方推荐的缓解手段：每个 App 单独建 token（便于按 token 追踪用量、定位异常）；用 Tokens API（POST /tokens/v2/{username}）定期轮换（建新→发版→删旧，未缓存请求立即失效）；token 不入仓库（iOS 用 Xcode 配置、Android 用 Gradle 脚本注入）；在 console 按 token 监控用量异常。下载 SDK 用的 downloads:read scope token 与运行时 token 必须分开。
  - 来源：<https://docs.mapbox.com/help/dive-deeper/how-to-use-mapbox-securely/>
- **备胎一：MapLibre 是 Mapbox 最直接的降级路径，2025-2026 活跃且生产可用，零 MAU 费用**（置信度：高）
  - MapLibre Native（BSD 开源，Mapbox GL Native 分叉）：iOS v6.0.0 起 Metal 渲染后端；Android Vulkan 后端 2024-12-12 正式发布（官方称 2026 起新设备 OpenGL ES 仅走翻译层，Vulkan 具战略意义）；2025 年持续发版（Android 11.8.0 / iOS 6.10.0，新增 PMTiles 支持），月度 newsletter 持续到 2025-10+。配 MapTiler/Stadia/Protomaps 第三方瓦片或自托管（OpenFreeMap/Planetiler），SDK 本身无按 MAU 收费，成本转为瓦片服务订阅或自托管运维。风格/瓦片格式与 Mapbox GL 基本兼容（Mapbox v2+ 专有特性除外），从 Mapbox 迁移成本低。对'嵌入 Godot'路线还有独有优势：开源 C++ 核心可做纹理级集成。
  - 来源：<https://maplibre.org/news/2024-12-12-maplibre-android-vulkan/>
- **备胎二：Google Maps 移动 SDK 免费不限量但与 Godot 集成差、大陆同样不可用**（置信度：高）
  - 2025-03-01 Google Maps Platform 定价改革后，Maps SDK for Android/iOS 的移动动态地图保持免费且不限量（官方 march-2025 页面明确 'Maps SDK for mobile remain free with no limits'），费用上是最优备胎。但它只提供原生 View（MapView/GMSMapView），无法嵌入 Godot 渲染管线，只能做平台层 View 叠加/挖洞，3D 角色与地图的深度合成受限；矢量样式定制弱于 Mapbox；中国大陆同样被墙。适合作为'彻底放弃引擎内合成'时的保底。
  - 来源：<https://developers.google.com/maps/billing-and-pricing/march-2025>
- **备胎三：高德/AMap 仅在国内发行场景有意义，商用需付费许可**（置信度：中）
  - 高德开放平台是国内发行时的合规路线（持测绘资质、GCJ-02、有审图号），但商用（任何直接/间接获益，含免费 App 引流）需事先取得商用授权——2025-11-01 起更名为'技术服务许可书'，第三方对比称基础版约 5 万元/年（此价格来自 CSDN 非官方，需商务确认）；免费配额仅限个人认证或经评估的非商业企业开发者，且 2025-05-20 起执行新定价。海外发行场景高德无优势（海外数据弱），不必考虑；仅当未来国内上架时启用，且需同步引入 GCJ-02 转换与境内主体。
  - 来源：<https://lbs.amap.com/commercial>

### 遗留问题（该维度未决）

- GL JS v3 嵌入移动 WebView 的计费归类（Map Loads for Web 还是 tile requests / Legacy hybrid 口径）官方文档存在新旧口径并存，若最终选 WebView 路线必须向 Mapbox support 书面确认，并确认 TOS 对'GL JS 用于原生 App 内嵌'是否有未公开限制。
- Mapbox 新账号注册的地区限制与免费层是否强制绑信用卡（woosmap 第三方说法）需实际注册验证；大陆团队用海外主体注册是否会触发风控也未验证。
- 大陆对 api.mapbox.com 的封锁属 GFW 还是 Mapbox 主动封 IP 无官方结论；若是后者，Mapbox 未来政策变化（放开或收紧）无法预期，海外发行不受影响但大陆调试代理方案需长期维持。
- 本项目预期 MAU/日均地图会话数尚未量化——25,000 MAU 免费额度够不够、超出后月账单多少，需要拿真实增长预期算一遍两条路线的成本曲线。
- 高德'技术服务许可'2025-05-20 新定价的确切配额与价格（基础版 5 万/年为第三方口径）如未来考虑国内发行需直接询价；同时需评估腾讯位置服务作为国内备选的对比。

### 对抗验证

#### 验证 7.1：裁决 ⚠️ 部分成立/需修正

三段核心结论两成立一过强，修正如下。(1)【大陆直连——上游"基本不可用、须经代理"过强，应改为"不稳定、不可靠、不可作生产依赖"】2026-08-25 本机一手实测（上海移动家宽 AS24400，出口 183.195.39.144，已用 ifconfig/路由表/traceroute 排除 TUN 代理，traceroute 确认走中国移动 CMNET 骨干直达）：api.mapbox.com（CloudFront 13.33.183.x）直连完全正常——根路径返回 200 {"api":"mapbox"}，styles/v1 与 a.tiles.mapbox.com 均返回 Mapbox 业务层 JSON（401 Invalid Token / 403 Forbidden，均为应用层响应而非 CDN 地域封锁页），整请求仅 0.13–0.6 秒；但 www.mapbox.com（Fastly 146.75.40.143）确实严重劣化（15 秒仅收到 609KB 中的 440KB 超时）。而 2024-12 至 2025-04 有多个大陆用户一手报告不可用（gl-js#13374、#13388、running_page#812），全部无 Mapbox 官方回应。综合：大陆直连呈"时通时断、站点(Fastly)与 API(CloudFront)分化、无任何官方 SLA/公告"状态，不存在"恒定被墙"或"恒定可用"的稳态；生产架构不得依赖大陆直连、大陆团队调试须备代理的工程结论仍然成立，但"基本不可用"作为 2026 年现状陈述已被实测证伪。(2)【mapbox.cn 停运——证实】www.mapbox.cn / api.mapbox.cn 经 223.5.5.5、8.8.8.8、114DNS 交叉验证均无 A 记录（域名 zone 仍托管在阿里万网 hichina，SOA serial 2026011209，即域名保留但服务下线）；Mapbox 官方 docs 原"Mapbox in China"帮助页已 404 撤下；叠加 2024 版外商投资准入负面清单明令禁止外商投资地面移动测量、导航电子地图编制等测绘活动，"无国内合规通道、不存在切中国节点选项"成立。(3)【仅海外发行则中国地图合规不适用——证实，带边界条件】《地图管理条例》第二条明文限定适用于"在中华人民共和国境内从事……互联网地图服务"（第三十三条测绘资质、第三十四条地图数据服务器设境内均只约束境内服务单位）；自然资办函〔2024〕972 号（2024-04-24，原文已核）发文对象为各省主管部门与境内 App 主办者，要求的地图审核/ICP 备案/审图号均系境内制度。App 不在大陆商店上架、不面向大陆用户，则无 ICP/审图号/测绘资质义务，GCJ-02 亦无需处理（海外场景 GPS 与 Mapbox 底图同为 WGS-84 自洽）。边界条件：一旦上架苹果中国区或国内安卓商店、或面向大陆用户提供服务，全部义务立即回归且须换持证国内图商；另海外用户携 App 入境时在境内采集高精度位置数据属理论灰区（测绘法属地管辖），但对纯地图显示类场景不构成现实合规负担。

证据：

- 一手实测（2026-08-25，上海移动直连、无代理，traceroute 证实走 CMNET 骨干）：根路径 HTTP 200 {"api":"mapbox"}；styles/v1 无效 token 返回 401 {"message":"Not Authorized - Invalid Token"} 与 403 {"message":"Forbidden"}（均为 Mapbox 应用层 JSON，非 CloudFront 地域封锁页）；a.tiles.mapbox.com 返回 401；三连测 0.13–0.6s——直接证伪'api.mapbox.com 大陆直连基本不可用'作为当前事实
  - <https://api.mapbox.com/>
- 一手实测同日同网：主站（Fastly 146.75.40.143）15 秒超时仅收 440050/609148 字节——大陆访问'站点劣化、API 正常'的分化状态，与 issue #13388 报告的 www.mapbox.com/maps 不可访问互相印证
  - <https://www.mapbox.com/>
- 经 gh api 核实：2024-12-27 创建、至今 open、标题'Does mapbox server block the ip from China'，报告 styles 请求 ERR_CONNECTION_REFUSED、开 VPN 恢复、api.mapbox.cn 同败；唯一一条评论是玩笑话，零 Mapbox 官方回应——是单用户报告而非官方定论，不足以支撑'基本不可用'的 high 置信度
  - <https://github.com/mapbox/mapbox-gl-js/issues/13374>
- 经 gh api 核实：2025-01-19 创建、open、'IPs from China cannot access mapbox'，但其截图证据是 www.mapbox.com/maps 与 geojson.io（营销站/工具站，Fastly 侧）不可访问，并非 api.mapbox.com 瓦片/样式接口
  - <https://github.com/mapbox/mapbox-gl-js/issues/13388>
- 经 gh api 核实：2025-04-18 大陆用户报告'Mapbox is not available in mainland China'，2025-06-17 通过 PR #877 引入替代方案后关闭——2025 上半年大陆社区仍普遍视 Mapbox 为不可用，与 2026-08 实测可用并存，证明可用性随时间波动
  - <https://github.com/yihong0618/running_page/issues/812>
- 一手 DNS 实测：www.mapbox.cn/api.mapbox.cn 经 223.5.5.5、8.8.8.8、114.114.114.114 交叉查询均无 A 记录；zone 仍在阿里万网（NS dns9/dns10.hichina.com，SOA serial 2026011209）——域名保留、服务已下线，证实 mapbox.cn 停运
  - <https://www.mapbox.cn/>
- 一手实测 HTTP 404：Mapbox 官方文档原'Mapbox in China'指引页已撤下（docs 站大陆可正常访问，404 为真实状态非网络故障），官方已不再提供任何中国区接入指引
  - <https://docs.mapbox.com/help/troubleshooting/mapbox-in-china/>
- 原文全文核实：《自然资源部办公厅 工业和信息化部办公厅关于规范移动互联网应用程序中登载使用地图行为的通知》自然资办函〔2024〕972号，成文 2024-04-24；发文对象为'各省……自然资源主管部门、电信主管部门，移动互联网应用程序主办者'；要求履行地图审核程序、ICP 备案手续、标注审图号、内容更新重新送审——上游引用准确，且其境内属性支撑海外豁免结论
  - <https://www.gov.cn/zhengce/zhengceku/202405/content_6950568.htm>
- 《地图管理条例》原文核实：第二条'在中华人民共和国境内从事向社会公开的地图的编制、审核、出版和互联网地图服务……应当遵守本条例'（属地适用）；第三十三条互联网地图服务需测绘资质；第三十四条'互联网地图服务单位应当将存放地图数据的服务器设在中华人民共和国境内'——义务主体均为境内服务单位，仅海外发行不在射程内
  - <https://www.gov.cn/zhengce/content/2015-12/14/content_10403.htm>
- 《外商投资准入特别管理措施（负面清单）（2024年版）》（发改委/商务部令第23号，2024-09-08 公布、2024-11-01 施行）：禁止外商投资地面移动测量、导航电子地图编制、各类政区地图/真三维地图编制等——从法源上封死 Mapbox 在华持证合规运营的可能，支撑'无国内合规通道'
  - <https://www.gov.cn/zhengce/202409/content_6973047.htm>
- 第三方佐证（降级为辅助证据）：称 Mapbox China 特供版已 discontinued、大陆访问劣化——与本次 DNS/连通性一手实测方向一致，但其'被阻断'表述同样未区分 Fastly 主站与 CloudFront API 的分化
  - <https://www.chinafy.com/blog/does-mapbox-work-in-china>

<details><summary>验证方法与裁决口径（展开）</summary>

方法论与局限：(1) 连通性实测仅单一出口（上海移动家宽）、单日（2026-08-25），已通过 env/ifconfig/路由表/traceroute/ipinfo 排除代理与 TUN 劫持（机器上有 Tailscale utun6 但默认路由走 en1，traceroute 逐跳显示 CMNET 骨干），但不能外推到电信/联通/其他省份或高峰时段；GFW 与 CloudFront IP 轮换都可能造成区域性、间歇性差异——这正是把结论从'基本不可用'改写为'不可靠'的原因。(2) 重要新发现（上游未提，防后续误判）：events.mapbox.com 在 Mapbox 自家权威 NS（ns-1742.awsdns-25.co.uk）上即解析为 0.0.0.0，属 Mapbox 全球性下线该遥测域名，与中国封锁无关——任何把'遥测域名解析失败'当作大陆被墙证据的说法都是错的；这也提示原生 SDK 遥测端点已迁移，评估'SDK 遥测大陆可靠性'需针对新端点实测。(3) WebFetch 在本环境被域名安全校验拦截（claude.ai 不可达），全部一手来源改经本地 curl 与 gh api 获取，反而使连通性数据成为真·大陆视角。(4) 对本项目的工程含义不变：仅海外发行则 Mapbox 方案无合规障碍；大陆团队开发调试仍应全程备代理（可用性无保证）；建议保留地图供应商抽象层（MapLibre 兜底/未来国内化），若未来国内上架需境内主体+ICP/App 备案+持证图商+GCJ-02 全套切换。(5) 上游其余计费/token/备胎类 claim 不在本次核心问题范围，未逐条复核。

</details>


## 8. 完整性审查（Critic）

> 独立审查代理对全部调研+验证结果的批判性复盘：未覆盖的缺口、仍未验证的假设、方案文档必须写明的风险。方案文档已据此补齐相机同步/触摸路由/PoC 判据等章节。

### 8.1 调研缺口

- 【最大技术缺口】地图↔Godot 相机同步管线完全未调研：叠加架构下每帧需把 Mapbox cameraState（center/zoom/bearing/pitch/FreeCameraOptions）换算为 Godot Camera3D 投影，涉及 Mercator 投影数学、地理锚点→场景坐标换算、Godot 官方模板单精度浮点在高 zoom 下的抖动（需 floating origin 方案）、以及两个独立渲染器（Mapbox 渲染线程 vs Godot 渲染循环）之间的帧相位差——快速拖拽时角色相对地图'滑动/漂移'的量化上限没有任何维度测过，而这正是 Zenly/Snap 选择同渲染器画角色的原因。各维度只把'投影矩阵重建'列为 open question，没人调研跨 View 帧同步机制（SurfaceView 合成不保证两 surface 内容同帧）。
- 定位与传感器链路整个维度缺失：Godot 无内置 GPS/罗盘 API，现状只有零散社区插件（WolfBearGames Android/iOS、KarimIbrahim、Lunatik Games，均小型个人项目，https://github.com/WolfBearGames/Godot-GeolocationPlugin-Android ）；若走原生宿主架构则定位可放宿主侧，但'定位数据→角色移动插值→与地图 puck 一致性'的归属未设计；Android 运行时权限/iOS Info.plist/后台定位/罗盘朝向均未调研，且这些插件与 iOS fork 引擎（SwiftGodotKit 4.6 基）的兼容性完全未知。
- 触摸分层路由只讨论到'二选一'，未覆盖真实混合场景：本 App 现有大量 Godot UI（换装抽屉、安全区适配已在 Godot 侧实现），叠加架构下需要'Godot UI 区域消费触摸、地图区域手势穿透或桥接'的命中测试方案；Android View 层级中最上层 View 先收触摸，Godot 默认吃掉全部输入——选择性透传的具体机制（onTouchEvent 返回值控制/宿主拦截分发）无人验证。
- App 壳归属与平台不对称架构未作为独立决策调研：Android 可双向（Godot host 或原生 host），iOS 被迫原生 host + fork 引擎，结果可能是两端两套集成架构；'非纯游戏'App 通常还需推送、深链、登录、支付、统计等原生 SDK，这些能力在'Godot 导出工程为壳'与'原生工程为壳'两种形态下的接入成本差异完全未评估。
- 混合架构生命周期与内存管理未调研：后台/前台切换时 Godot 嵌入实例与 MapView 的 pause/resume 协同、低内存 kill 与状态恢复、双引擎（Mapbox + Godot）同进程内存峰值在 3-4GB 中端机上的余量，均无数据；react-native-godot 是唯一可参考的生命周期实现。
- 地图视觉风格维度缺失：产品要的是卡通角色配套的风格化底图（Pokémon GO/Zenly 观感），但没人调研 Mapbox Studio 自定义样式能否达成卡通化效果、Standard 样式（3D 光照/地标）与 Classic 样式在原生 SDK 上的能力与性能差异、3D 建筑开关对观感与遮挡需求的联动影响——样式复杂度直接影响中端机帧率，是 PoC 变量却未被定义。
- 选型的需求前置输入未定义：单角色还是多角色（好友头像上图、Zenly 式）、POI/标注量级、角色是否需要被 3D 建筑真遮挡、相机模式（跟随/俯仰/飞行动画）——这些直接改变各路线权重（如多角色会加重叠加层与地图标注 API 的分工问题），应在方案文档开头作为'需求假设'显式冻结。
- 零拷贝外部纹理第三路线（地图离屏渲染→纹理进 Godot）未判生死：Godot 官方 CameraFeed/外部纹理链路在 Android 未实现（CameraTexture 文档明示仅 Linux/macOS/iOS，https://docs.godotengine.org/en/4.4/classes/class_cameratexture.html ），Godot 4.7 是否有 Vulkan external memory / Metal shared texture / GL_TEXTURE_EXTERNAL_OES 导入 API 决定 MapLibre headless 路线能否根除 CPU 回读瓶颈——in-engine-alt 把它列为 open question 后无人跟进，应查 RenderingDevice/texture_create_from_extension API 后给出明确结论。
- Godot 4.7 移动端渲染器选型（Forward+/Mobile/Compatibility）在'透明叠加 + 自定义 toon shader'场景下的约束未调研：透明 framebuffer 在三种渲染器上的支持差异、Android Vulkan（Godot 默认）与 Mapbox GLES 双上下文并存的驱动层风险、toon shader 在 Mobile 渲染器的兼容性，均无结论。
- 包体与内存预算横向对比未汇总：Mapbox 原生 SDK（每 ABI 体积）+ Godot 引擎库 + 角色资产的总包体 vs WebView 路线，对移动分发的影响没有任何维度给出数字。
- MapLibre Native 作为'主选而非备胎'的同架构验证缺失：其 Android/iOS MapView 与 Godot 透明层叠加的等价可行性（SurfaceView/TextureView 行为、相机 API 与 Mapbox 的差异）、MapTiler 等数据源的成本与样式质量，未认真评估——'供应商抽象层'的实际工程成本因此无法估计。
- 各路线工程量/工期对比估算完全缺失：没有任何维度给出人月级成本（叠加架构的相机同步+桥接层、custom layer 路线的角色渲染器重写、WebView 路线的 three.js 全家桶重写），选型文档不能只比可行性不比成本。
- 统一 PoC 计划本身是缺口：所有维度都以'需真机 PoC'收尾，但没有汇总出机型矩阵（骁龙 7 系 + 中端 Mali GPU + iPhone SE/13 级）、指标阈值（fps/内存/发热/电流）、每条路线的一票否决条件清单——这应是最终文档的必备附件。
- 对 Mapbox 官方渠道的确认动作全部停留在'建议去问'：WebView 内 GL JS 计费口径、glTF 动画 roadmap、GL JS 嵌原生 App 的 ToS 许可、（若需要）商务折扣——这些是低成本高价值的动作，方案文档应把'发工单/联系商务'列为带责任人的行动项而非 open question。

### 8.2 有风险的假设

- 主推的'原生地图垫底 + 透明 Godot 叠加'架构默认能交付'角色视觉上钉在地图坐标上'的效果——这建立在跨渲染器逐帧相机同步延迟足够小的假设上，全部调研中没有任何先例、测量或理论上界支撑；业界模式二的实证（Snap Map/Jagat）角色都是 2D 应用层贴图，没有一个是'第二个 3D 引擎全屏透明叠加'。
- Android 端到端可行性由机制层证据（4.5 透明修复 + 维护者认可的 setZOrderMediaOverlay workaround）推断而来，公开世界零个完整成功案例；'z-order 调用须在 surface attach 前完成'的时序、嵌入库场景（host 自带 theme）下 per_pixel_transparency 开箱即用，均未真机验证。
- iOS 路线的全部可行性押在第三方 fork 上且含双重未验证假设：SwiftGodotKit/libgodot fork 的 GodotAppView 能透明背景叠加原生 MapView（无任何文档或案例）、现有 FBX+Skeleton3D+toon shader 资产在 fork 运行时行为一致——同时隐含'团队接受引擎从 4.7 回退到 4.5/4.6 或双端版本分裂'这一未与决策者确认的前提。
- '中端手机 60fps'在所有候选路线上都是纯假设：叠加路线（双 GPU 上下文 + 全屏 TRANSLUCENT 合成，官方文档明示 per_pixel_transparency 影响性能）、WebView 路线（结构性反证充分）、custom layer 路线，全部零实测数据。
- china-ops 维度的全部结论以'App 仅海外发行'为前提，该前提是调研中自设的，未经产品/决策者确认；团队身处大陆这一事实使该假设更需要显式确认而非默认。
- 计费结论假设 WebView 内 GL JS 按 map load 口径、原生 SDK 按 MAU 口径且现行价格/免费额度长期稳定——WebView 口径存在新旧文档并存的模糊且未获 Mapbox 书面确认；两条路线的成本对比也未按真实预期 DAU/会话模型算过成本曲线，'数十倍差距'只是量级推演。
- GL JS 备选路线中'角色实现可行'实际悬空：deck.gl ScenegraphLayer 对'共享骨架 + 运行时增删 SkinnedMesh 部件换装'的支持未验证，threebox 需自担 fork 维护，手写 three.js custom layer 的换装/socket/toon 三子系统工作量只是估算——该路线的角色端可行性并没有被任何实验证实。
- 'Godot 收手势→JNI/Swift 桥→地图 camera API'的跟手性可接受是假设，双指捏合+旋转连续手势的每帧桥接延迟无任何数据；反向方案（地图直接吃触摸）与 Godot UI 并存的分发方案也未验证。
- 'MapLibre 是 Mapbox 的直接降级路径'假设切换成本低：两家 SDK 的相机 API、样式生态、View 层行为差异未做对照验证，'零 MAU 费用'的对价（数据源另行付费、样式质量）未量化。
- 假设嵌入库/fork 形态的 Godot 运行时与标准编辑器导出行为一致（资产加载、GDExtension/插件、渲染设置）——嵌入路线的所有资产兼容性结论都由标准导出经验外推而来。
- Mapbox 'model layer 未来不会支持 glTF 动画（不可等待）'与'custom layer API 会长期存在'两个方向相反的平台假设同时被采用：前者有三年未兑现的证据支撑，后者却被 Android Vulkan 预览不支持 custom layer 的事实直接威胁——依赖 custom layer 的任何路线都建立在'Mapbox 不会在切换默认后端时断供该 API'的赌注上。

### 8.3 必须写明的风险

- 架构一票否决风险：叠加架构的角色-地图同步撕裂（快速拖拽/缩放时角色相对地图漂移）与手势跟手性是本方案成败的第一验证项，必须写明'PoC 首先验证此项，不达标则整个主推架构作废'，并写明失败后的两条退路（custom layer 原生重写角色 / WebView+three.js 全家桶）各自意味着放弃 Godot 渲染角色。
- 性能承诺风险：截至定稿日没有任何路线在目标中端机型上有一手帧率/内存/发热数据，文档不得写'可达 60fps'类承诺性语言；须附 PoC 机型矩阵、指标阈值与降级预案（降 DPR/限帧/简化地图样式/关 3D 建筑）。
- iOS 结构性风险：官方 Godot 无 iOS UI 嵌入（LibGodot iOS 部分无合并时间表），生产只能依赖第三方 fork（版本锁 4.5/4.6、不支持模拟器、单实例、无透明叠加先例）；fork 停更或不跟进新版本即断路；反向路线需自 patch 引擎透明合成且无先例。iOS 是全方案最脆弱的一环，必须单独成节。
- Android 集成脆弱性：透明层 z-order 依赖非官方 workaround（遍历视图树 setZOrderMediaOverlay），Godot 或 Mapbox SDK 任一升级都可能破坏；双 SurfaceView 相对合成次序属未定义行为；须写明版本锁定与升级回归策略。
- 引擎版本分裂风险：Android（官方 4.7）与 iOS（fork 4.5/4.6）并存将导致资产导出管线（.pck 按 fork 版本导出）、特性集与测试矩阵翻倍；要么全项目降级迁就 iOS fork，要么承担双版本维护——二选一必须在文档中显式决策。
- Mapbox 平台依赖风险：model layer 的 glTF 动画'计划中'三年未兑现，不可作为等待项；Android Vulkan 预览不支持 Custom Layer API，若默认后端迁移则 custom layer 路线有断供风险；行业先例（Google gaming、Lightship Maps 全部关停）证明地图 SDK 死亡率高——文档必须要求代码层保留地图供应商抽象层与 MapLibre 逃生通道。
- 商务与计费风险：WebView 内 GL JS 的计费归类未获 Mapbox 书面确认（map load 口径下高频主页 App 成本可能数十倍于原生 MAU 口径）；移动端 public token 无包名/bundle ID 绑定，防盗用只能靠 token 隔离+轮换+用量告警；免费额度（25,000 MAU / 50,000 loads）是否够用需按增长预期出成本曲线后再定稿。
- 中国前提风险：全部合规与商务结论以'仅海外发行'为前提，一旦计划在大陆上架，Mapbox 整套方案作废（需持证国内图商 + GCJ-02 + 资质/审图），架构上的供应商抽象层因此是硬要求而非可选项；大陆开发调试对 api.mapbox.com 的直连呈时通时断、无 SLA 状态，团队须长期维持代理且不得在生产链路依赖大陆直连。
- 遮挡能力上限：叠加架构下角色永远无法被 3D 建筑/地形真遮挡（Godot 层拿不到地图深度缓冲），只能近似（关 3D 建筑或接受穿模）；若产品确认需要真遮挡，唯一路线是 custom layer（= 放弃 Godot 渲染角色、在 SceneKit/自研层重建 toon+换装+动画）。此需求必须在动工前冻结。
- 角色资产双实现风险：任何时点转向'地图侧渲染角色'（three.js 或原生 custom layer）都意味着 toon shader 100% 重写（glTF 不携带 ShaderMaterial）、SM_/SK_ 坐标系与 socket 三层机制按新渲染器第三次重推、以及此后每次资产更新的双端回归——这是持续性成本而非一次性迁移，文档须按'高成本选项'标注。
- Mapbox 归属合规风险（现有调研完全未提）：Mapbox wordmark 与 attribution 必须在地图上始终可见（可移位不可隐藏），且 App 须保留 Telemetry 退出入口（通常由 attribution 控件提供）——全屏透明 Godot 层及其 UI（抽屉等）不得遮挡这些元素，UI 布局需预留位置（https://docs.mapbox.com/help/dive-deeper/attribution/ ，Product Terms 2025-10）。
- WebView 备选路线的物理上限：若保留该路线作退路，须写明 iOS 低电量模式下 WKWebView rAF 被硬限 30fps（相当比例会话 60fps 物理不可达）、WKWebView 长期内存增长问题、以及 GL JS 无官方离线支持——它只能作为功能性退路，不是体验等价的退路。

## 9. 深入解读（评审问答沉淀）

> 以下三节来自方案评审阶段的问答（2026-08-29），是对调研结论的展开解释，随附录归档。

### 9.1 custom layer 路线详解（方案 C 的本质）

**定义**：custom layer 是 Mapbox 在自己渲染管线里留的钩子——每帧渲染到该图层位置时把画笔交给你的代码，用底层图形 API（WebGL/Metal/OpenGL ES）直接往**地图同一块画布**上画，共享深度缓冲。

三条路线的本质区别：

| | 谁渲染角色 | 角色画在哪 |
|---|---|---|
| model layer | Mapbox（但不支持动画，已排除） | 地图管线内 |
| custom layer（方案 C） | 你自己写渲染代码 | 地图管线内（共享画布/深度） |
| 方案 A（推荐） | Godot | 地图管线外，透明 surface 叠加 |

**三端形态**：
- GL JS：`CustomLayerInterface` 的 `render(gl, matrix)`，共享 WebGL2 context + 墨卡托→裁剪空间投影矩阵；官方示例接 three.js。持续动画需每帧 `triggerRepaint()` → 整图放弃按需渲染、每帧全量重绘（#7591/#7629 的性能问题根源）。
- iOS：`CustomLayerHost` 协议，`render` 每帧给 `CustomLayerRenderParameters`（宽高/经纬度/zoom/bearing/pitch/fieldOfView/投影矩阵）+ 地图同一 render pass 的 `MTLRenderCommandEncoder`。官方 SceneKit 示例证明可画完整 3D 场景并与地形深度遮挡（坑：`usesReverseZ = false`）。
- Android：`CustomLayerHost.render(CustomLayerRenderParameters)`，在地图 GL 上下文直接发 GLES 命令。**硬约束：Vulkan 预览后端不支持 custom layer**——走此路 Android 锁死 GLES 后端，且有未来断供风险。

**为什么是"最贵的正确"**：在裸画笔之上要把 Godot 正在做的事每个平台重写一遍——骨骼蒙皮求值与调色板上传、动画采样/混合/状态机、toon shader 用 MSL 和 GLSL ES 各一份、换装+socket 三层机制按新渲染器第三次重推、FBX→glTF 资产管线（Godot 导出丢 ShaderMaterial、有根动画 bug #114110）。iOS 可借 SceneKit 少写一层但其已被 Apple soft-deprecate（WWDC24 起建议迁 RealityKit）；Android 连借都没有。粗估 ≥4-6 人月起步 + 此后每次美术更新在三处（Godot 换装房 + 双平台地图角色渲染器）回归的持续成本。

**换来的独有好处**：①真·深度融合（角色被 3D 建筑/地形正确遮挡——方案 A 永远做不到）；②单渲染器、零相机同步问题（G2 一票否决项天然不存在）；③单 GPU 上下文。

**决策树位置**：主动选它的唯一理由 = G0 冻结时"角色必须被建筑真遮挡"成为硬需求；被动落到它 = 方案 A 的 G2 撕裂不可接受且无法优化。只要确认不需要真遮挡（配合关 3D 建筑的卡通底图），不应碰这条路线。

### 9.2 "30fps 上限"的归属澄清

**30fps 硬限属于方案 B（WebView 路线），与方案 A 无关。**出处是 WebKit 行为：iOS 低电量模式下网页 `requestAnimationFrame` 被硬性节流到 30fps（WebKit bug 168837），WKWebView 同样受影响——只影响"地图和角色跑在 WebView 里"的方案 B。

方案 A 两层都是原生渲染，无结构性上限：地图层是 Mapbox 原生 SDK（Metal/GLES，60fps 是常规工作状态）；角色层 Godot 已有实测（Android 真机 20 merged 角色顶满 120Hz、帧时 <10ms）。

方案 A 真正的性能未知项（待测，非已知上限）：①全屏 TRANSLUCENT surface 的系统合成成本（Godot 官方文档标注 per_pixel_transparency 影响性能）；②双 GPU 上下文并存的调度；③iOS `presentsWithTransaction=true` 的同步提交开销。这三项即 G4 要量的内容；实测不达标另有降级手段（限帧/简化样式/关 3D 元素/降分辨率缩放），不像 WebView 被系统一刀切。

### 9.3 方案 A 的镜头同步（含倾角 pitch）

**支持，且是设计内能力**——pitch/bearing/zoom/center 四自由度全部同步。核心不是"两个相机互相追"（必然滞后漂移），而是**"一份权威位姿、两个消费者"**：手势归全屏在上的 Godot，相机控制器每帧算出 `(center, zoom, bearing, pitch)`，同一帧内经桥调 Mapbox `setCamera`（jumpTo，原生支持 pitch，v11 上限 85°），Godot 用同一份数值摆 Camera3D。残余误差只剩两 surface 出帧相位差（G2 量化）。

**倾角映射数学**：Mapbox 相机 = 绕屏幕中心地面点的轨道相机，`d_px = (H/2)/tan(fovY/2)`，`d_m = d_px × mpp(lat, zoom)`；Godot 镜像 = 注视点放屏幕中心地理点（本地米制、浮动原点），相机按球坐标（方位=bearing，仰角=90°−pitch，距离=d_m）偏移，同 fovY。fovY 不硬编码，从 custom layer 回调参数读；PoC 期间挂一个**不画东西的 custom layer 专门 dump `projectionMatrix`** 逐元素校准自建矩阵，校准完摘掉。

**三种镜头运动的权威归属**：用户手势 → Godot 权威（主路径）；程序动画（聚焦 marker/flyTo/定位动画，对应 Unity 的 `FocusToMarker`/`LocateToLocation` 等）→ 仍在 Godot 侧做插值，权威不换手（推荐）；万一用地图自带动画 → 订阅 `CameraChanged` 反向驱动（一帧滞后，仅兜底）。

**边界条件**：①camera padding 会偏移投影中心——偏移逻辑放 Godot 权威位姿里，不用 Mapbox padding（或用 Camera3D frustum offset 复现）；②3D terrain 让注视点带海拔——一期关 terrain；③Standard 样式低 zoom 默认 globe 投影破坏平面近似——钉死 mercator 或限最小 zoom；④高 pitch 见地平线——Godot 层只画角色，天空/雾由地图管。

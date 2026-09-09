# SensenAvatar

当前产品首要目标是做成更好玩的基于地图的游戏。下一轮玩法方向、首日节奏、3D 交互与验收以
[`以好玩为先的改造方案`](docs/product/fun-first-rework-2026-09-07.md) 为准，优先于历史策划中的冲突约束。
首个旅程切片已接入分钟级种植、采集制作、料理、庭院布置和地图地点交互；G3 存档保留兼容路径。
实现范围、验证证据与待试玩问题见 [旅程切片记录](docs/qa/journey-slice-2026-09-07.md)。
资源路线、持续设施和场景操作见 [第二轮记录](docs/qa/journey-expansion-2026-09-07.md)。手工作品修复地点、每轮补给选择和持久目标追踪见 [场景发现记录](docs/qa/journey-discoveries-2026-09-08.md)。本轮接入实物陈列操作、可行走侧径、来访居民交互与紧凑工作台，最新验证见 [场景操作记录](docs/qa/journey-spatial-2026-09-08.md)。

本地试玩：`node tools/dev/run_journey.mjs`。需要 Godot、Node、已安装的服务端依赖，以及
`server/.env` 中可访问的测试数据库配置。启动器创建独立的旅程试玩数据库与客户端存档，使用自然时间。
下文保留 Avatar 模块的开发说明。

Godot 4.7（Mobile 渲染管线）实现的角色换装（avatar）模块一期：从 Unity 项目迁移部件资产，
在 Godot 侧完成装配、换装、存档与轻量压测。目标是把 Unity 侧已经生产的角色/部件资产
（FBX + 材质）转换为 Godot 原生资源，并提供一套可换装、可存档、可压测的角色系统，供后续
原生嵌入或独立运行。

一期范围：换装（列表选择 + 异步切换 + 存档）、两套装配策略（逐部件直挂 / 合并成单网格）、
活动度节流（按距离/可见性降级动画与粒子播放）、压测场景与移动端导出走查文档。不包含：
UGC 上传、云端资产分发（PCK 下载）、Unity 侧特效（GPUParticles）自动迁移。

## 目录结构

```
modules/avatar/            avatar 模块本体（GDScript，无场景状态）
  avatar_service.gd          Autoload "Avatar"：门面，唯一对外入口
  assembly/                  AvatarRig 状态机 + 两种装配策略 + 活动度控制(RigActivity)
  catalog/                   PartCatalog：manifest 加载与查询
  content/                   ContentRepo：资产可用性检查
  data/                       AvatarConfig / AvatarSlotTable / AvatarSlotDef
  loading/                   PartLoader（异步加载+去重+取消）/ PartCache（LRU）
  persistence/                LocalOutfitStore：本地存档
  shaders/                    统一 toon shader + 材质工厂（Unity 参数映射）

modules/ui/                移动端 UI 基建（与 avatar 模块无耦合）
  ui_metrics.gd              纯计算：安全区换算、取景距离/偏移（无节点依赖，全覆盖单测）
  safe_area_margin.gd        SafeAreaMargin：按系统安全区设四边内缩，含最小边距兜底

assets/avatar/
  base/                       base_rig.tscn（骨架+AnimationPlayer）、animations.res（idle/walk/run）
  parts/                      转换产出的 AvatarPartDef .res（每个部件一份）
  thumbs/                     部件缩略图
  parts_manifest.json         部件清单（转换管线产出，PartCatalog 的数据源）
  source/                     从 Unity 工程搬运的原始 FBX/PNG（转换管线中间产物）

scenes/
  dressing_room/              换装场景（项目 main scene）
  stress_test/                批量角色压测场景（数量滑条 + direct/merged 切换 + HUD）

tools/
  unity_export/               Python 阶段：解析 Unity YAML/GUID，产出 recipes.json + 搬运源资产
  pipeline/                   Godot headless 阶段：recipes.json → .res/.tscn/thumbs/manifest；
                              以及 base_rig.tscn 生成脚本

tests/                        gdUnit4 测试，目录结构与 modules/ 对齐，外加 pipeline/ integration/
addons/gdUnit4/               测试框架（第三方插件）
docs/mobile_export.md         移动端导出与真机验收指引
docs/superpowers/             设计过程文档（spec / plan，历史记录，非运行时依赖）
```

## 跑测试

```bash
tools/run_tests.sh                       # 全量
tools/run_tests.sh res://tests/assembly  # 只跑某个子目录
```

脚本会先做一次 `--headless --import`（保证 .uid/导入缓存是最新的），再调用
`addons/gdUnit4/runtest.sh`。退出码 0 且报告里 `orphans` 为 0 才算通过——gdUnit4 会把节点
泄漏也计入失败。

UI 相关用例在 `tests/ui`（纯函数与容器）与 `tests/scenes`（场景布局回归），
两者都不依赖转换产物之外的资源，可单独跑：`tools/run_tests.sh res://tests/ui`。

## 跑转换管线（Unity → Godot）

一期转换管线分两段，示例样例集（15 个部件 + 基础角色）已经跑过一次，产出物已入库；
如果需要重新生成（改了 `samples.json`/`overrides.json`，或换了 Unity 工程路径）：

```bash
# 1. Python 阶段：解析 Unity 工程，搬运 FBX/PNG 到 assets/avatar/source/，写 out/recipes.json
cd tools/unity_export
.venv/bin/python convert.py --unity-root ../../../sensen-unity --godot-root ../.. --out out
cd ../..

# 2. Godot 阶段：先跑一次 import，确保第 1 步搬进来的新 FBX/PNG 已生成 .import 缓存
#    ——漏了这步，第 3 步读到的是未导入/过期的资源，本分支为此丢过一个小时。
godot --headless --path . --import

# 3. Godot 阶段：recipes.json → assets/avatar/parts/*.res + parts_manifest.json + thumbs
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- tools/unity_export/out/recipes.json

# 4. Godot 阶段：生成基础角色骨架 + idle/walk/run 动画库
#    （若存在 assets/avatar/source/mixamo/clips.json，会顺带把 Mixamo 劳作/表情 clip 重定向进同一个库）
godot --headless --path . --script res://tools/pipeline/gen_base_rig.gd

# 5.（可选，快）只刷新 Mixamo clip：下载好的 Y Bot 版 FBX 放进 assets/avatar/source/mixamo/，
#    写 clips.json，先 --import 再跑。细节见 assets/avatar/source/mixamo/README.md
godot --headless --path . --script res://tools/pipeline/gen_mixamo_clips.gd
```

第 1 步的报告（`tools/unity_export/out/report.txt`）里出现 ERROR 时命令会以非 0 退出；
按报告修 `overrides.json` 或 `samples.json` 直到干净退出。第 2/3/4 步是幂等的，可重复跑。

管线只**增改**不删：从 `samples.json` 拿掉一个部件后，它在 `assets/avatar/`
`source/` `parts/` `thumbs/` 下的产物不会自动消失（manifest 里没有了，但文件还在、
照样进包）。拿掉部件后按 manifest 对一遍这三个目录，手工删干净。

第 2 步如果长时间不动（`imported` 数不涨、进程 CPU 时间不涨），多半是**另有一个
Godot 进程占着本工程的锁**——`ps aux | grep godot` 看有没有残留的 headless 实例，
杀掉再跑。踩过一次，白等了二十多分钟。

### 怎么挑要加哪些部件

Unity 侧共 949 个 `ap_*.asset`，但**只有用标准 toon shader（`DonutAvatar`，
GUID `090d4a3e…`）的那些能直接用**。其余是水晶/火焰/透明镜片这类特效材质，依赖
cubemap 反射、菲涅尔、alpha 等我们不消费的通道，搬过来会渲成一坨平色
（`cloth87`/`hairhat101`/`hairhat37`/`glass4` 就是这么下架的）。

判据是 `.mat` 里的 `m_Shader` GUID——注意 `.meta` 的 GUID 被 Tuanjie 混淆成 base64，
**不能反查路径**，但 `.mat` 内部的引用仍是明文 hex，直接 grep 即可。挑的时候还应
要求「该槽位下只有一个 `.mat` + 一张 `_D` 贴图」，否则贴图靠 token 匹配容易配错。

选完先用 `tools/dev/render_part_previews.gd` 渲出来看一眼再定（见下）。

## 两个场景怎么开

- **换装场景** `res://scenes/dressing_room/dressing_room.tscn` —— 项目 main scene，直接
  `godot --path .` 或编辑器里 F5 即可。右侧面板按槽位分类，点部件缩略图切换（异步加载，
  切换过程原地不闪烁），底部“保存/重置”对应 `Avatar.save_outfit` / 默认配置。拖拽左键
  旋转视角。
- **压测场景** `res://scenes/stress_test/stress_test.tscn` —— 需要显式指定打开：
  `godot --path . res://scenes/stress_test/stress_test.tscn`。左上角 HUD：
  数量滑条（1–20，默认 10）现场重建角色阵列；按钮切换 `direct`/`merged` 装配策略并立即
  重建，用于对比两种策略的开销差异。

## 压测数据怎么读

HUD 四行含义：

| 行 | 含义 |
|---|---|
| `角色: N  策略: merged/direct` | 当前场上角色数与装配策略 |
| `FPS: x  帧时: y ms` | `Performance.TIME_FPS` / `TIME_PROCESS*1000`，帧时越低越好 |
| `DrawCalls: n` | 本帧绘制调用数（`RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`） |
| `显存: m MB` | 显存占用（`RENDERING_INFO_VIDEO_MEM_USED`） |

预期结论：同样角色数下，`merged` 策略的 DrawCalls 应显著低于 `direct`（合并策略把同材质
的部件网格拼接进一个 `MeshInstance3D`，direct 策略每个部件各占一个绘制调用）。如果没有
观察到这个差异，先看角色是否都装了同材质部件（默认随机换装大多数槷位都会命中不同材质，
个体差异属正常）。

`headless` 模式下渲染服务器是空实现，DrawCalls/显存两行恒为 0，仅用来做“脚本跑得通”的
冒烟检查；真实读数需要在有头环境（桌面或真机）里看。真机走查步骤见
[`docs/mobile_export.md`](docs/mobile_export.md)。

## 部件预览（挑件不用装机）

`assets/avatar/thumbs/` 里那批是占位图，看不出谁是谁。要肉眼过一遍部件，用离屏渲染：

```bash
# 渲 manifest 里的全部部件；也可在末尾追加 part_id 只渲其中几个
godot --path . --script res://tools/dev/render_part_previews.gd -- /tmp/previews
```

复用换装页那个 `PartThumbnailer`，所以颜色/打光与真实换装页一致。**必须带窗口跑**——
`--headless` 的 dummy 渲染驱动下 SubViewport 取不到图像，存出来全是透明的。

## 已知限制（一期）

- 移动端仅验证过安装包内置资产，不含 PCK 远程下载/热更新。
- socket 部件的 Unity 粒子系统（tier=2）未自动迁移，manifest 里 `tier` 字段仍会写入，供
  活动度控制预留；实际特效二期在 Godot 内重做。

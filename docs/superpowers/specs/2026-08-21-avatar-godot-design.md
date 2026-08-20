# Avatar 模块 Godot 重构设计（一期）

日期：2026-08-21
状态：已与需求方逐节评审通过
范围：avatar 部件 加载 / 切换 / 保存 基础框架（一期），含 Unity 现状评估与 Godot 目标架构

---

## 1. 背景与目标

将 Unity 工程（`../sensen-unity`，Tuanjie 分支）中的 avatar 模块重构为 Godot 版本。

**保留的产品能力**：部件自由组合、异步加载、iOS/Android 双端、多角色同屏、合理的装扮内存管理、与原生客户端低耦合（3D 与其 UI/交互后续尽量放 Godot）、效果接近 Unity（一期性能优先，效果可适当降低）。

**已确认的决策**：

| 决策点 | 结论 |
|---|---|
| 一期交付形态 | 独立 Godot App（不做原生嵌入；接口按可嵌入设计） |
| 引擎/语言 | Godot 4.7.2 stable + GDScript（热点后续可用 C++ GDExtension） |
| 资产迁移 | 自动化转换工具（Python），一期迁样例集，工具支持全量 |
| 部件 ID | 全新语义化 ID 体系，不做老数据兼容；avatar 服务器 API 将重写 |
| 存档 | 一期本地 JSON；存储层留接口，二期接服务器 |
| 性能目标 | 中端机（骁龙 7 系 / iPhone 12 级）10–15 角色 60fps |
| 装配策略 | 方案 B：换装即合并（bake-on-dress），详见 §5 |

---

## 2. Unity 现状评估

### 2.1 现有机制（核心源码在 `com.sensen.modules` 包，已从备份取得）

- **骨架**：一套共享骨架 `SK_DtBase.fbx`（62 骨、无 BlendShape、Generic 非 Humanoid），基础 prefab `DT_AvatarBase` 预置 14 个槽位，每槽位一个常驻 `SkinnedMeshRenderer` + 一个挂点 Transform（`AvatarStructureConfig` 两个平行数组按枚举序号索引）。
- **两种部件**（全库 955 个）：
  - `attachType=SK`（约 45%）：换 mesh —— 把部件 FBX 中按槽位命名的子网格赋给对应 SMR（`sharedMesh` + `materials`），骨骼绑定靠美术侧统一骨架（40/40 抽样 FBX 骨骼名与顺序一致）；
  - `attachType=SOCKET`（约 55%）：挂点下 `Instantiate(socketPrefab)` + 局部 TRS。
- **部件数据**：`AvatarPartScriptableObject`（guid/attachType/partName/partType/mesh/materials/socketPrefab/TRS/thumbnail），**部件 ID = Unity 资产 GUID**，同一字符串身兼资产 GUID、Addressables key、服务器 partId、用户存档内容四职。
- **加载**：每部件一次 `Addressables.LoadAssetAsync`（远端 bundle，PackSeparately —— 全库 1000+ 个 bundle）；`AvatarIO` 按 PartType 追踪句柄并在换装时释放旧句柄；用手写"加载会话号"丢弃过期回调。
- **存档**：配置 = 有序 GUID 列表。生产路径：配置 + 3 张截图（6 次相机渲染、3 次 ReadPixels、3 次阻塞写盘）经 UaaL JSON 消息发给原生客户端持久化；另有一条 `HttpAvatarStorage` 直连服务器的路径并存。
- **对客户端暴露**：`DressingManager` 7 个方法（载装扮/换单件/重置单件/保存/读配置等），真正的换装 UI 在原生客户端；Unity 内的 `DressingRoomUI`/`RecommmendSuitUI` 是开发调试壳。

### 2.2 值得保留的设计

共享骨架 + 按槽位换 mesh（系统基石；Godot 按骨骼名绑定比 Unity 按索引更稳）；两种挂载类型；槽位模型；配置 = 槽位→部件 ID 映射（改进其列表形态）。

### 2.3 主要问题（重构要消灭的）

| 类别 | 问题 |
|---|---|
| 性能 | 每角色最多 14 SMR + 挂件；516 材质几乎零共享、56 种 shader；无合并/图集/GPU 实例化/LOD；全部件投影（draw call 翻倍）；Animator 全部 AlwaysAnimate 且 62 骨为真实 Transform 节点；237 个"静态"挂件各带独立 Animator 播摆动；个别挂件为 28 根空骨骼的蒙皮渲染器 + 6 个粒子系统 |
| 内存 | 632/1921 张贴图无移动端压缩覆盖（最高 2048²/3072²，无 mip streaming）；`AllAvatarParts` 单 SO 硬引用全部 955 部件（加载即全库进内存）；多处 Addressables 句柄泄漏、RenderTexture 泄漏、事件订阅泄漏 |
| 架构 | 14 槽位在枚举/预制体/两处 UI 共 4 处硬编码；部件 ID 深耦合 Unity 资产库；换装无防抖/去重/取消，竞态靠散落 5+ 处的代数计数补丁；保存被截图流程绑架；双保存路径并存；启动时同一接口重复请求两次 |
| 分发 | 一部件一 bundle（1000+），依赖资源在包间重复；`m_RetryCount: 0` 一次网络抖动即永久缺件；实测加载慢到需要 10s 超时 + 遮罩特效兜底 |
| 耦合 | 部件 ID/存档格式/消息桥均与 Unity 资产库或 UaaL 绑定 |

---

## 3. 目标架构（Godot）

核心原则：**avatar 模块自包含、零业务依赖** —— 不认识 UI、服务器、原生客户端。

```
res://
├── modules/avatar/                 # 核心模块（只依赖 Godot 引擎）
│   ├── data/
│   │   ├── slot_table.tres/.gd     # 槽位表：数据驱动（名称/挂点骨骼/必选/默认部件）
│   │   ├── part_def.gd             # 部件定义 Resource
│   │   └── avatar_config.gd        # 装扮配置：{槽位: 部件id} + 序列化/diff
│   ├── catalog/part_catalog.gd     # 部件目录：只读 manifest 元数据（不引用资源本体）
│   ├── content/content_repo.gd     # 分发接缝：ensure_available(part_id)；一期空实现，二期 PCK 下载/挂载
│   ├── loading/
│   │   ├── part_loader.gd          # 异步加载：线程加载 + 代数计数防竞态 + 同资源请求合并
│   │   └── part_cache.gd           # LRU 缓存（按估算字节数上限，默认 64MB 可配）
│   ├── assembly/
│   │   ├── avatar_rig.gd           # 装配根：Skeleton3D + 动画 + 槽位状态机 + 活动度控制
│   │   ├── assembler.gd            # 装配策略接口
│   │   ├── assembler_direct.gd     # 策略1：直挂（调试/对比基线）
│   │   └── assembler_merged.gd     # 策略2：合并（默认）
│   ├── persistence/outfit_store.gd # 存档接口 + LocalJsonStore
│   └── avatar_service.gd           # 模块门面（外部唯一入口，形态可被消息桥驱动）
├── assets/avatar/                  # 转换工具产出（base 骨架场景/parts/thumbs/shaders/manifest）
├── scenes/
│   ├── dressing_room/              # 换装场景 + Godot UI
│   └── stress_test/                # 压测场景（帧率/内存 HUD）
└── tools/unity_export/             # Python 转换工具
```

依赖方向：`scenes → modules/avatar → Godot`。`AvatarService` 对外接口对应 Unity 侧被客户端调用的方法集（载入装扮/换单件/重置单件/保存/读当前配置），为二期嵌入留接缝，一期不实现桥。

---

## 4. 数据模型与 ID 体系

### 4.1 三层解耦（取代 Unity GUID 一身四职）

| 层 | 承担者 | 说明 |
|---|---|---|
| 逻辑 ID | 语义 slug（`cloth1`、`hairhat20`） | 服务器/存档/API 只认它，引擎无关；由 partName 派生，小写、全库唯一（工具校验） |
| 引擎寻址 | `res://` 路径 | 只存在于 manifest 的 id→res 映射 |
| 分发单元 | PCK 资源包 | `load_resource_pack()` 挂载后按原路径加载；打包粒度按套装/类别；下载包只放纯资产不放脚本（iOS 审核） |

Unity GUID 仅作 `unity_guid` 字段留档溯源。

### 4.2 槽位表 slot_table.tres

每槽位一条：`{ name, attach_bone, required, default_part }`。一期沿用 14 槽位；新增槽位 = 加一行数据。必选槽位卸下时回落默认部件。

### 4.3 部件清单 parts_manifest.json

目录元数据与资源本体分离（UI 列表只读 manifest + 缩略图）：

```json
{ "version": 1, "parts": [
  { "id": "cloth1", "slot": "cloth", "attach": "mesh", "tier": 0,
    "pack": "builtin",
    "res": "res://assets/avatar/parts/skin01/cloth1.tres",
    "thumb": "res://assets/avatar/thumbs/cloth1.png",
    "unity_guid": "604181a9..." },
  { "id": "hairhat20", "slot": "hairHat", "attach": "socket", "tier": 1,
    "pack": "builtin",
    "res": "res://assets/avatar/parts/hairhat/hairhat20.tscn",
    "offset": { "pos": [0,0,0], "rot": [0,0,0], "scale": [1,1,1] },
    "thumb": "...", "unity_guid": "..." }
]}
```

### 4.4 socket 部件能力分级（tier，转换工具自动判定）

- **T0 静态**：单 `MeshInstance3D`，默认档；
- **T1 循环动画**：`MeshInstance3D + AnimationPlayer`（对应 Unity 237 个 idle 摆动件），播放权归 AvatarRig 活动度控制；后续可选把轻摆烘成 shader 顶点动画；
- **T2 特效**：含 `GPUParticles3D` 等，转换工具校验预算（单件粒子数上限、每角色 T2 件数上限），超标不通过。

转换时降级：空骨骼蒙皮挂件一律烘成静态 mesh；真·蒙皮挂载件现库不存在，不支持。

### 4.5 存档格式（本地 JSON）

```json
{ "version": 1, "slots": { "body": "body00", "cloth": "cloth1", "glass": "" } }
```

存 `user://avatar/outfit_<user_id>.json`。按槽位键值（自描述、可局部缺省、可版本迁移），取代 Unity 的有序 GUID 列表。`OutfitStore` 接口：`save(user_id, config)` / `load(user_id)`。

### 4.6 转换工具（tools/unity_export/，Python，幂等）

输入 Unity 工程路径 + 部件筛选列表：

1. **解析**：扫 `ap_*.asset` YAML → guid/attachType/partType/mesh 引用/材质/TRS/缩略图；经 `.meta` 反查 FBX/贴图路径；套装 FBX 子网格按"子网格名 = 槽位名"约定定位。
2. **搬运**：拷贝 FBX/贴图，生成 Godot `.import` 预设（ASTC、上限 512²、mipmap 开）。
3. **材质**：读 `.mat` YAML 提取 `_BaseColor`/`_AO`/标量参数 → 统一 toon ShaderMaterial `.tres`；56 种 shader 收敛为 1 个参数化 toon（特殊 shader 皮肤一期落普通 toon）。
4. **生成**：PartDef `.tres` / socket `.tscn`、`parts_manifest.json`、guid→新 id 映射 CSV。
5. **校验**：id 唯一、引用存在、骨骼名与基础骨架一致、tier 预算；出报告。

一期样例集：基础角色（SK_DtBase + 默认 5 件）+ 2 套换装（skin01、skin88 一类带多材质/特效的）+ 3–4 个挂载件，覆盖换 mesh/多 surface/socket 三种形态。

---

## 5. 运行时设计

### 5.1 异步加载 PartLoader

```
equip(slot, part_id)
  → ContentRepo.ensure_available(part_id)   # 一期 no-op
  → PartCache 命中？→ 直接交付
  → ResourceLoader.load_threaded_request()  # 引擎线程加载，依赖自动带出
  → 完成回调 → 校验代数 → 交付 AvatarRig
```

- 竞态治理收敛到一处：每（角色×槽位）一个代数计数器，过期回调丢弃（资源仍进缓存）。
- 请求合并：多角色同时请求同一部件合并为一次实际加载。

### 5.2 内存管理 PartCache

- Godot Resource 引用计数；装着的部件由 AvatarRig 持有，卸下无人引用即释放（无句柄泄漏类别）。
- LRU 只解决换装 UI 来回切换抖动：按估算字节上限（默认 64MB 可配），场景退出主动 clear。
- 材质跨角色共享同一实例；将来 per-角色参数用 instance uniform。
- 缩略图独立小缓存。

### 5.3 装配 AvatarRig + AssemblerMerged（方案 B：换装即合并）

- 槽位状态 `{current, desired, generation}`；`apply_config()` diff 后只加载变化槽位；全部到货后调一次 `assembler.rebuild()`。
- 合并：收集 mesh 类部件 surfaces → 骨骼索引按骨骼名重映射到共享 Skeleton3D 统一 Skin → 拼单个 `ArrayMesh`（同材质 surface 合并，异材质各留 surface）→ 单 `MeshInstance3D`。约 7k 顶点，先主线程实现（预期毫秒级），压测不过关再挪 WorkerThreadPool。
- socket 部件不合并：`BoneAttachment3D` + 实例化场景，按 tier 受活动度控制。
- 显示原子性：整配置加载期间隐藏/占位，`config_applied` 后一帧显示；单件切换旧件保持到新件到货（无闪烁、无裸体帧）。
- 阴影：角色 mesh `cast_shadow = OFF` + 脚下假影（面片/贴花）。
- `assembler_direct`（每部件一个 MeshInstance3D 直挂）保留作调试与性能对比基线。

### 5.4 动画

- `base_rig.tscn`：Skeleton3D（62 骨，Godot 骨骼非节点）+ AnimationPlayer + 共享 AnimationLibrary（idle/walk/run 由 `dt@*.fbx` 转换）。
- 一期 AnimationPlayer 直接播；AnimationTree 待真需混合再引入。
- 活动度三档（活跃/降频/休眠，按屏幕可见性+相机距离）作用于 AnimationPlayer 与 T1/T2 挂件。

### 5.5 信号与错误处理

- 信号：`slot_applied(slot, part_id)`、`config_applied(config)`、`part_load_failed(slot, part_id, err)`。
- 单件失败：槽位保持原样 + 信号（UI 提示）；必选槽位初始加载失败回落默认部件。
- 存档损坏/版本不识别：备份坏文件、回落默认装扮，不崩。
- 本地资源无超时；二期下载超时/重试归 ContentRepo。

---

## 6. 场景与 UI

### 6.1 换装场景 dressing_room

简单背景 + 角色台（单指拖旋转）+ 固定相机。UI：槽位标签页（slot_table 动态生成）、部件网格（PartCatalog + 缩略图，当前穿着高亮，非必选槽位有"卸下"）、保存/重置。进入 `load()→apply_config()` 原子显示；点选即时预览；保存才落盘。

### 6.2 压测场景 stress_test

可调数量（5/10/15/20）AvatarRig 随机装扮，播 idle/walk。HUD：FPS / frame time / draw call / 内存 / direct↔merged 策略切换。验收基准：中端真机 15 角色 60fps。

---

## 7. 测试策略

- 单测（gdUnit4）：AvatarConfig diff/序列化、SlotTable、manifest 解析、OutfitStore 读写与损坏回退、PartLoader 竞态（快速连续换装出正确终态）。
- 转换工具（pytest）：YAML 解析、ID 生成唯一性、tier 判定、校验器。
- 集成：换装场景手动走查；压测数据留档（策略×角色数×机型帧率表）。

---

## 8. 一期边界

**不做**：服务器 API 对接、原生客户端嵌入、PCK 热更下载（只留 ContentRepo 接缝）、贴图 atlas、AIGC/截图流程、pose/Emoji3d 系统、dressing set 换背景、特殊 shader 逐个还原。

**验收清单**：
1. 转换工具跑通样例集，校验报告干净；
2. 换装场景：列表→点选切换（异步无闪烁）→保存→杀进程重进恢复；
3. 压测场景：真机 iOS/Android 各出一份帧率数据，15 角色 merged 达 60fps（不达标须有明确归因与下一步）；
4. 单测全绿。

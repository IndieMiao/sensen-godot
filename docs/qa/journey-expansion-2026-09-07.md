# 旅程第二轮：地图资源、持续设施与场景操作

日期：2026-09-07。工作区实现，未部署或发布。验收目标仍为 60–90 分钟主动游玩；本记录不将研发、加载和等待时间计为游戏内容，也不代表新玩家留存已改善。

最新验证已切换到用户连接的 vivo 真机；独立更新包已安装，详见[第二轮真机记录](journey-physical-v4-2026-09-07.md)。下文保留模拟器启动方式，不能把较早的模拟器 APK 当作最新包。

## 玩法变化

首个切片之后，完成花箱和第一顿饭不再只剩重复交付：玩家可以建设三个有持续用途的设施，选择下一轮资源倾向，并把奖励用在种植、料理或布置中。

| 设施 | 两阶段投入 | 建成后的用途 |
| --- | --- | --- |
| 苗圃育苗床 | 2 木料 + 2 石料；2 芦苇 + 1 生菜 | 每轮探索选 2 生菜种子、2 胡萝卜种子或 1 株鲜洋甘菊；后两项需要作物已解锁 |
| 小馆茶台 | 3 木料 + 2 芦苇；1 沙拉 + 1 茶 | 持续供餐，沙拉获得 30 金币，茶获得 24 金币；建成后居民到访 |
| 庭院补给站 | 3 石料 + 2 木料；2 芦苇 + 1 洋甘菊 | 2 木料兑换 2 石料或 2 芦苇；直接沿捷径到苗圃 |

庭院资源点附带石料，小馆资源点附带芦苇。新探索可选择苗圃木料、庭院石料、小馆芦苇路线，对应地点每个节点分别增加 1 木料、2 石料、2 芦苇。选择在本轮冻结，重新进场或重试不能换奖励。所有当前可达采集点取完后才可开始下一轮；育苗床奖励是可选项，不阻塞下一轮。

未改作物时钟，仍为 3/6/12/18 分钟。育苗床给鲜花是建设后的主动获取路径，不会直接加速田里作物。

## 交互与 3D

- 每个设施都有未建、在建、完成三个原生模型状态；点击设施后人物走近，再投入材料或使用功能。
- 直接点庭院地面放置和拖动摆件，固定旋转、撤销、保存等工具。一次拖动记为一次撤销，取消手势恢复原位置。
- 已安排好料理材料、仍有空地时，主操作可以推荐田外目标；逐格手动播种继续可用。
- 三处地点补上连续地面、街道、路口和出口路标。路标能让角色走到出口并返回地图；周边街景是场景背景，不代表开放了整张可行走街区或继承了真实街道几何。
- 世界标识显示为 28 像素圆形图标，触区保留 44×44。标识避让人物，必要时用引线指向物件。
- 普通活动面板打开时，明确的地图/农场按钮一次点击即可到达；操作结算与未保存布置继续拦截离开。系统返回仍先关闭面板。
- 真机修复了未保存布置确认后丢失跳转目的地的问题：保存或放弃后继续原跳转，取消确认留在编辑中。
- 种花、修复、制作和料理成功后收起面板，展示世界变化；备餐台显示已制成的食物。
- 采集路线前置，移除重复材料统计和零资源地点行；料理显示成品、材料和图标操作。三条路线、两道配方的操作入口在已验收的小屏中无须滚动。
- 采集或木料数量变化时保留静态建筑与居民对象，避免重装居民外观。布置和新增居民仍按实际变化更新。

## 版本与运行

服务端 domain 为 `4`，schema 为 `1`，`journey.version` 仍为 `1`。内容哈希为 `3caf4b3fae85197c`。新增材料、设施使用记录、路线字段均有旧值兼容默认值。

迁移工具支持 domain 1/2/3 到 4。只接受当前或指定的确切旧内容哈希，保存原状态及历史命令结果；迁移不会强制切换旧 G3 玩法。domain 3 本轮之前的内容哈希为 `8492f383f6f939b9`，可通过 `--previous-content-version` 指定。默认仅报告。真机验收将原试玩库复制为 `sensen_farm_journey_physical_v4`，只迁移副本，核对状态与历史一致；原库及业务库未迁移。

桌面入口：

```sh
node tools/dev/run_journey.mjs
```

默认使用新库 `sensen_farm_journey_playtest_v4` 和用户目录 `sensen-journey-playtest-v4`。旧库与旧本地目录保留。依赖 Godot 4.7、Node、已安装的 server 依赖和 `server/.env` 中的测试数据库配置。

本轮模拟器为独立的 `Sensen_Journey_QA`、`emulator-5560`，Android API 36，画面为 720×1560；Godot 逻辑视口约 360×780。未操作其他模拟器或原应用包。

模拟器服务，在 `server/` 下运行：

```sh
JOURNEY_PORT=3117 JOURNEY_DEVICE_INSPECT=1 JOURNEY_DATABASE=sensen_farm_journey_emulator_v4 node --import tsx tools/journey_playtest_server.ts
```

模拟器包位于 `output/journey-emulator/sensen-journey-qa.apk`，独立包名 `com.sensen.journeyqa`，通过模拟器宿主别名 `10.0.2.2` 访问本机服务，无须 ADB 端口转发。准备及运行：

```sh
godot --headless --path . --script res://tools/dev/prepare_journey_device.gd -- --journey-emulator
godot --headless --path output/journey-device/project --export-debug 'Android Journey QA' "$PWD/output/journey-emulator/sensen-journey-qa.apk"
adb -s emulator-5560 install -r output/journey-emulator/sensen-journey-qa.apk
adb -s emulator-5560 shell am start -n com.sensen.journeyqa/com.godot.game.GodotAppLauncher
JOURNEY_SERIAL=emulator-5560 JOURNEY_EVIDENCE_DIR=output/journey-emulator/evidence node tools/dev/journey_device_control.mjs status
```

物理手机仍使用不带 `--journey-emulator` 的准备命令以及 `adb reverse`。宿主别名只被显式带有 `journey_device_qa` 的调试检查入口接受，普通游戏入口未修改。

触控位置来自实时 Godot 控件树或已渲染场景的投影，经过真实 ADB 输入，不通过观察器下发玩法命令。工具检查前台应用和快照活跃状态，等待移动/结算，记录接收的触控；缺失回执时失败且不自动重发。

## 验证记录

规则扩展的服务端类型检查和包含 PostgreSQL 的 368 项测试通过；农场回归 173 项、旅程 7 项、地点 71 项通过。最新原生图形检查 27 组、81 张截图通过，覆盖场景像素、人物移动、标记重叠、导航恢复与配方/路线可见性。最新真机记录 145 次触控，145 次均有回执；完整状态通过更新与重启核对。

已通过自然时钟触控完成：开局种植和收获、三个地点采集、居民初见、修工作台、花箱制作与地面拖动保存、沙拉和共同用餐、侧径、育苗床两阶段、领取鲜花并种进花箱、全部六个基础里程碑、木料路线与下一轮石料路线选择。更新前后第一次存档核对完整状态一致，见 `output/journey-emulator/update-check.json`。

后续真机追加完成：补给站与茶台两阶段、两种材料兑换、捷径、三条资源路线、洋甘菊自然收获、种花、制茶和两次供茶结算。最新包的茶配方与第三条路线均经实际点击验证，无须先滚动；不是只验证控件树中存在。

逐步截图、触摸回执、前后状态在 `output/journey-emulator/evidence/`。汇总工具：

```sh
node tools/dev/journey_evidence_report.mjs output/journey-emulator/evidence
```

## 产品判断与剩余问题

设施奖励已产生不同用途：种子回到种植，鲜花进入花箱、建设或茶；材料路线能改变本轮优先地点。但采集仍是固定位置、固定动作，取完全部节点的要求容易让玩家机械跑完每处。设施建设和供餐过程仍较短，不能凭三个设施数量宣称内容足够。

下一步应优先验证有空间差异的探索与可持续制作：路线之间应有不同发现或解法，建设完成后应改变角色能到达的位置或操作方式。只有重复轮次的选择与自主继续得到证据，才扩大内容量。当前尚未证明 60–90 分钟主动内容，也未进行新玩家留存测试。

本轮新增设施、街景及修正已补充[第二轮真机验证](journey-physical-v4-2026-09-07.md)；[第一轮真机记录](journey-physical-2026-09-07.md)保留为历史。Android 模拟器首装出现现有 Godot/Mapbox 库的 16 KB 页大小兼容提示，本轮未修复或认证其兼容性。

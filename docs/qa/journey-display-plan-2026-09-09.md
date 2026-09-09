# 手工作品陈列目标接续

- 日期：2026-09-09。
- 状态：实现与代码测试通过，独立模拟器包和本机启动入口已准备；尚未安装到设备或进行新流程的触控体验验收。
- 目标：让完成设施后的自主布置选择，继续驱动采集、制作和场景变化。
- 本轮遵照用户自行测试的安排，没有操作真机或模拟器、截图巡检、覆盖 APK、迁移试玩库或重启连接服务。

## 已发现的问题

完成茶露台后，从空陈列位进入工作台只会切换地点，无法保留玩家想做什么、摆在哪里的意图。新增计划接入时还发现，选定计划后未退出布置模式会继续屏蔽场景里的其他物件；完成制作后停留在配方面板也会中断返回原位置的引导。

随后复现确认回包丢失的分支：服务器已保存计划或取消，但两次响应都丢失；点击重连后权威状态恢复，场景却仍处于布置模式。现改为在计划状态变化时清除布置模式，重连恢复不再依赖面板原来的成功回调。恢复时不重播奖励或强制关闭重连面板。

## 实现结果

- 在完成设施的空陈列位选择已解锁作品，将项目、位置和配方存成一个追踪目标。计划与取消均不消耗或发放资源。
- 原位置显示 45% 透明的对应 3D 作品预览，不产生实体碰撞或投影；取消后消失，实际摆放后恢复实体材质。
- 目标按库存依次指向缺少的材料、苗圃工作台和最初的陈列位；作品已摆在别处时可以收回再搬过去。
- 选定或取消计划后退出布置模式，恢复探索；工作台优先显示所选配方，成功制作对应作品后收起面板并保留成功反馈。
- 服务器拒绝操作时保留面板和现有状态。实际摆放只消费一件库存，并清除该位置的计划。
- 手工计划与工程、发现、聚会计划互斥，玩家改选时以最新意图为准；已经举行的聚会保留。无关工程的自动追踪不会覆盖手工计划。
- 修正配方排序的 GDScript 类型推断错误。备用地图布局直接使用已有坐标，不再先执行一次不需要的相机投影。

## 验证证据

| 检查 | 结果 | 覆盖与限制 |
| --- | --- | --- |
| Godot 导入 | 通过 | 加载新增类；使用隔离的 ADB 地址，不连接设备 |
| GdUnit 旅程与地图标记 | 103 项通过 | 含 7 项手工计划用例；最终日志无脚本或引擎错误 |
| 重连修复后定向回归 | 28 项通过 | 8 项手工计划、10 项接续和 10 项命令恢复；与前述检查有重叠，不累计为新增 28 项 |
| 服务端旅程、迁移与 HTTP | 133 项通过 | 含 17 项计划规则用例和 23 项迁移用例 |
| TypeScript | 通过 | `pnpm typecheck` |
| 独立 APK | 通过 | 签名、启动图标、编译后的玩法资源和模拟器地址校验通过 |
| APK 资源启动 | 通过 | 从 APK 解出的资源在 headless Godot 中登录独立服务并进入选城界面，未建场；所含手工计划代码正确解析原位目标 |
| 实际玩家触控与观感 | 未验证 | 本轮未截屏、运行触控脚本或记录主动游玩时间 |

客户端检查实例化真实 `JourneyPlace` 场景，通过按钮回调验证面板关闭、成功反馈、失败保留和目标变化；检查茶露台喷泉、育苗床花箱、补给站灯的预览材质、位置与可达操作点。使用 headless 模式，不证明实际像素表现、遮挡、触摸手感或性能。

数据库测试只使用 `sensen_farm_test_display_20260909`。其中一例将合成的领域 11 存档迁移到 12，逐表核对历史保留，再通过 `PgStore` 执行计划、制作、摆放；新建 store 重新读取计划，逐次重放相同请求，核对状态、历史和费用不再变化。这是持久化测试，不是 APK 冷启动测试。

证据：

- [客户端 XML](../../reports/report_855/results.xml) 与 [日志](../../output/journey-facility-choice-2026-09-09/client-tests.log)。
- 重连修复：[修复前失败报告](../../reports/report_856/results.xml) 中 5 个断言失败；[修复后报告](../../reports/report_857/results.xml) 中 28 项通过，[日志](../../output/journey-facility-choice-2026-09-09/recovery-tests.log) 无脚本或引擎错误。新增用例通过真实计划、取消和重连按钮，验证三次 POST 使用同一命令、随后 GET 恢复状态、待确认标记清除，以及场景恢复探索。
- [服务端 JSON](../../output/journey-facility-choice-2026-09-09/server-tests.json)。
- [计划场景测试](../../tests/journey/test_display_plan.gd)、[领域测试](../../server/test/domain/journey_display_plan.test.ts)、[迁移测试](../../server/test/db/domain_migration.test.ts)。

复现命令：

```sh
ADB_SERVER_SOCKET=tcp:127.0.0.1:5048 godot --headless --path . --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/journey -a res://tests/map/test_journey_markers.gd
node output/journey-facility-choice-2026-09-09/server-checks.mjs test/domain/journey test/db/domain_migration.test.ts test/http/app.test.ts
pnpm --dir server typecheck
```

## 备用体验版本

- [APK](../../output/journey-facility-choice-2026-09-09/sensen-workshop-preview-2026-09-09.apk)：应用名 `Sensen Workshop09-09`，包名 `com.sensen.workshoppreview0909`，版本 `0.2.0-workshop.20260909`，约 125 MiB；Android 10 及以上、ARM64。
- [本机 Godot 启动入口](../../output/journey-facility-choice-2026-09-09/Open-Workshop-Preview.command)：使用同一 APK 解出的游戏资源，可双击运行。此入口已检查脚本语法；本轮没有打开图形窗口进行体验操作。
- APK 连接本机 Android 模拟器的宿主地址 `http://10.0.2.2:3134/v1`；Godot 入口连接 `http://127.0.0.1:3134/v1`。这是本机测试包，不能直接作为合伙人外发包使用。
- 独立服务已启动，端口 `3134`，数据库 `sensen_farm_journey_workshop_preview_20260909`，领域版本 12。正常新存档开局，没有复制、修改原试玩存档或注入资源；本机和 Android 使用各自安装身份。
- 现有设备、会议 APK、会议存档和原连接服务保持原状。本轮没有执行任何设备安装或输入命令。
- SHA256：`87f13d2197a44a388e0b909534f82907b40fec02343c30b88c369f7f4c189dd5`。
- [打包验证结果](../../output/journey-facility-choice-2026-09-09/preview-verification.json)，复核命令：`node output/journey-facility-choice-2026-09-09/verify-preview.mjs`。

### 重连修复版 v2

- [新版 APK](../../output/journey-facility-choice-2026-09-09/sensen-workshop-preview-v2-2026-09-09.apk)：版本 `0.2.0-workshop.20260909-v2`，版本号 `2026090903`。包名、独立服务与安装身份规则保持一致，旧 APK 和旧启动入口仍保留。
- [新版本机 Godot 入口](../../output/journey-facility-choice-2026-09-09/Open-Workshop-Preview-v2.command)：使用独立解出的 v2 资源，脚本语法检查通过；没有自动打开窗口或安装到模拟器。
- [v2 验证结果](../../output/journey-facility-choice-2026-09-09/preview-verification-v2.json)：签名、包名、版本号、启动图标、资源和服务健康检查通过。headless 加载实际 APK 字节码，确认原位目标与新增恢复状态已打包；本次资源检查不登录、不操作存档，不代表 Android 启动或触控验证。
- SHA256：`f5510160624ecd9e077cdaaf61c092d47981bb6efcdea12ade39887282a9eca6`。
- 仍为本机模拟器测试包，连接 `http://10.0.2.2:3134/v1`，不能直接外发给合伙人。未迁移数据库或重启现有服务；导出后已恢复主项目 Godot 导入索引。
- 复核命令：`node output/journey-facility-choice-2026-09-09/verify-preview.mjs --v2`。

## 后续验收

1. 新存档可使用独立备用版本。以后更新已有存档的测试版时，显式迁移对应数据库到领域 12，并核对完整存档与历史；本轮没有改动会议或现有试玩数据库。
2. 在对应的新客户端和服务端上，以自然获得的资源走通选择、取消或改选、采集、制作和原位摆放；中途退出再进入应保留计划。
3. 检查预览在实际 3D 画面中的辨识度、与实体的区别、小屏面板和相机拖动后的点击反馈。
4. 继续评估完成基础设施后的选择是否改变玩家下一轮采集、种植和料理安排。该功能提供一个持续的自主目的，不能单独证明选择深度或 60–90 分钟主动游玩的目标完成。

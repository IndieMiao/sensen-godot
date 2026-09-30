# 0.17.11 水塘网格目录 + 旧金山水塘发版记录

2026-09-30。源码 farm-dev `e354a60`（8544199 网格目录 + e354a60 旧服兜底）。调研见 [pond-data-on-mapbox-research](../product/pond-data-on-mapbox-research-2026-09-30.md)。

## 服务端 `ponds-cells-20260930`

- 线上 Journey 服 `https://farm.sensenjoy.cn/preview/journey/v1`，从 `accounts-google-20260929` 切换；领域 28、内容 761deabf2a207d3e 不变，无表结构变化。
- 镜像 = 原线上镜像 + 覆盖 server/src、server/data（新增 `ponds/locations.json`）等；无新依赖。
- 演练（线上库副本）：13 张表逐字节一致（83 农场 / 94 玩家 / 1697 命令），`/v1/ponds/cells` 返回旧金山 6 塘，旧 `/v1/ponds?region_id=` LA/上海各 6 塘，catalog revision 仍 `2c6e2a2f…`。
- 切换 **2026-09-30 09:23:35–09:23:52 UTC**（约 17 秒维护），同样校验通过；配置与网络保持。脚本与证据：`output/ponds-cells-20260930/backend/`，服务器 `/opt/farm/journey-preview/releases/ponds-cells-20260930/`（回滚备份在 private/，仅 root）。
- 旧包（≤0.17.10）走旧接口，看不到旧金山、其余不变。

## Android 0.17.11

- versionCode `2026093002`，SHA-256 `9c73d7c4c42cff4a1fe6d073ba6cc2db02f7fc9a2d05c4c0595dcb64fd3e7895`（186,491,503 字节），证书 `38771d94…`
- 与 0.17.10 差异：`party_travel.gdc`、`system_ponds.gdc`、`city_map_view.gdc`、`classes6.dex`、`assets.sparsepck`、manifest
- 下载站：[美国](https://download-us.sensenjoy.cn:8443/farm/releases/cells-20260930-9c73d7c4c42c/sensen-journey-cells-0.17.11.apk) · [OSS](https://oss.sensenjoy.cn/farm/releases/cells-20260930-9c73d7c4c42c/sensen-journey-cells-0.17.11.apk)，两站全量 + Range 校验通过
- vivo V2509A 真机（线上服）：旧金山 Fishing 筛选可见 Clover/Blossom/Pebble 等，进入 Blossom Pond 联机正常；LA 水塘、农场、换装正常；无 Godot 报错。第一次 adb install 卡在 vivo 外部来源确认页（未装上），重装后代点确认完成。

## iOS 0.17.11 (1)

- pck 差异同 Android；归档 pck 哈希一致（`dec848d1…`）
- iPhone 14 Pro（iOS 26.3）开发签名直装，XCTest `testScriptedSteps` 驱动：旧金山钓鱼筛选可见花间鱼塘/蕨影鱼塘，进入蕨影鱼塘联机正常；农场、换装正常。测试后已卸载 Runner。
- TestFlight 上传成功，App Store Connect 状态 VALID。

## 发 Joey

- Slack DM `D0C1MHLA3GQ` 附 APK（`F0C566L5DD5`）；飞书云盘 `MvVHbuuOcoADCwx920JcmOSdnOf`（授权查看，回下载哈希一致）+ 消息 `om_x100b64fb791478a0b17ca67c2f00e82`；均含 TestFlight 0.17.11 (1)。

## iOS 真机自动化备忘

- `tests/ios/JourneyDeviceUITests.swift` 新增 `testScriptedSteps`：`TEST_RUNNER_JOURNEY_STEPS="tap:x,y;wait:n;shot:name"`，工程 `output/ios-readiness-20260924/device-qa`，`build-for-testing` 一次后 `test-without-building`，`xcrun xcresulttool export attachments` 取截图。
- 需 iPhone「设置 → 开发者 → 启用 UI 自动化」；开启后仍报 `Connection peer refused … XCTestManager_IDEInterface` / runner code 74 时，**重启 iPhone** 后恢复。

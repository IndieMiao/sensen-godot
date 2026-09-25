# iOS TestFlight 0.16.42 (1) · 2026-09-26

与 Android 0.16.42 同步：已有农场的玩家冷启动跳过选城页，直接落在自己农场。同时修复 iOS 地图左上角比例尺压住城市标题、指南针压住任务按钮的问题。流程见 [ios-testflight-automation.md](ios-testflight-automation.md)。

## 构建

| 项目 | 值 |
| --- | --- |
| 应用 | `app.gensen.maps` / Gensen `XN4Z77ZX73` / **0.16.42 (1)** |
| 源码 | farm-dev `ab9920e`（启动直达农场）、`d676072`（iOS 导出排除 tmp/server/packages）、`5c6fc90`（隐藏 Mapbox 比例尺与指南针） |
| 游戏包 | 从主工程 `--export-pack "iOS"` 重新导出，1559 项，51,273,288 字节，SHA-256 `5bc072eb…c8b53`；相对 build 3 新增 0.16.38–0.16.42 全部游戏改动，脚本/数据与 Android 0.16.42 一致；去掉误入的本地 `tmp/`（Xbot 探针）与 13.5 MB `server/`、`packages/` node_modules 元数据 |
| Xcode 工程 | 复用 build 3 的 release-export（含 listener 恢复修复），替换 `sensen.pck`、`prepare_ios_signing.py` 设版本 |
| 原生 | `MapUnderlay.swift` 在建图后设置 `ornaments.options.scaleBar/compass.visibility = .hidden`：游戏每帧驱动相机，SDK 默认 `.adaptive` 永不隐藏；保留 Mapbox logo 与 ⓘ（条款要求，测试也以 About this map 判定原生地图） |
| 上传 IPA | 84,500,282 字节，SHA-256 `dfc2978d46b7e63a13284915a587b6f7d5486ce9fc70c5f536f9dd4362e68f92`；Apple Distribution: Gensen（云管理），`get-task-allow=false`、`beta-reports-active=true`、无设备列表；PCK 与 native UUID `53F2AE7D-…` 均与真机测过的归档一致 |

## 上传

- CLI 导出仍 `No Accounts`（退出码 70）；按回退流程用 Organizer：Custom → App Store Connect → Upload → 保留符号、关闭 Manage version and build number、不勾 internal only → 自动签名 → 核对 Review 页 → Upload。
- 2026-09-26 00:31 `Upload completed with warnings`，仅 MapboxCommon / MapboxCoreMaps 缺 dSYM 两条既有警告。
- Organizer 曾同时列出两份 0.16.42 (1)（其一是带比例尺的作废归档）；按 native UUID 核对后把作废副本移出 `~/Library/Developer/Xcode/Archives`（未删除）再分发。
- 00:39 手机 TestFlight 列表出现 0.16.42 (1)。

## 真机（iPhone 14 Pro / iOS 26.3）

| 阶段 | 结果 |
| --- | --- |
| 开发签名归档原位安装 | 已有洛杉矶农场冷启动直达地图「我的农场」，原生地图控件存在；前后台、进出农场通过 |
| 比例尺修复后重测 | 标题上黑色标尺与右上指南针消失，logo/ⓘ 保留，测试通过 |
| TestFlight 安装 | 仅对明确显示 0.16.42 Build 1 的 Gensen 详情页点安装，确认"此 App 已经安装"后出现「打开」；设备回读 `0.16.42 (1)` |
| 最终 TestFlight 包 | `testFarmOwnerColdLaunchLandsOnMap` 通过，截图复核：直达农场、无比例尺/指南针、前后台、农场 180 金币存档、返回地图 |
| 数据 | TestFlight 安装前即时备份与安装后、最终测试后三个文件逐字节一致 |
| 清理 | 移除 XCTest runner，保留 Journey 0.16.42 (1) 并回到前台 |

`farm_choice.json` 在首次启动新客户端时由服务端版本覆盖：0.16.40 起后端把该农场鱼塘改为土地并换了 layout id，客户端按服务端同步；位置与身份文件不变，旧文件私有备份在本次输出目录。

## 已知限制

- iOS 游戏 POI 查询、城市浅色样式、定位桥未接入：地图显示 Mapbox 自带图标并提示"地点暂不可用"。
- Voice Profile 在 iOS 走系统浏览器（`OS.shell_open`），非应用内 WebView。
- Joey 设备安装未核实；未另发邀请。未做完整农场/钓鱼/矿井玩法验收。

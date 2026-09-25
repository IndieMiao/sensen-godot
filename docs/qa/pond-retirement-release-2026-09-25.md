# Journey 0.16.40 发布验证

2026-09-25，按用户要求合并 `worktree/rapid-harbor-4666`，推送 `farm-dev`，同步线上服务并重新打包 APK。运行源码为 `a303b16b251e0ea69d1ebc630392990e50c9efb1`；合并是从 `90f2c78` 的快进，保留主工作区原有 78 个未跟踪文件。

## 发布结果

- 原 Journey 包名 `com.sensen.journeypreview`，版本 **0.16.40 / 2026092503**，178,346,711 字节。
- SHA-256：`190aa3e7d38f810866be0ea1185e1aac5f1582ff608ed903be46288f221cdc09`。
- 原证书 SHA-256：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。
- 后端 `pond-retirement-20260925`，领域 **28**，内容 **761deabf2a207d3e**；镜像 `sha256:4e24116978259fd83db76401c8ddb57239c0c7ad2ee8b9d5b19c9de95803a737`。
- 正式切换窗口为 **19:24:35–19:24:53 CST**，公网健康、数据库连接与版本回读通过。
- [美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/pond-retirement-20260925-190aa3e7d38f/sensen-journey-pond-retirement-0.16.40.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/pond-retirement-20260925-190aa3e7d38f/sensen-journey-pond-retirement-0.16.40.apk)。两站完整下载、字节数、SHA-256、Range 206、release.json 和 SHA256SUMS 均通过回读。

农场人工鱼塘及其钓鱼入口退役，原塘位恢复为地面；自然地理水域、12 个地图钓鱼点和三种鱼塘保持。包含已在 0.16.39 验证的鱼塘美术、英文按钮修正，同时保留 Voice Profile、GodotMap / GodotVoice / GodotWebView 和无 Godot logo 的启动背景。新建地形使用生成版本 3。

## 当前数据迁移

没有使用历史用户快照。先从当时的生产库新建独立副本演练，正式切换时再阻断 Journey 流量、停止旧 writer、保存新备份并迁移。切换前后按完整农场行和各表指纹校验；允许的差异仅为本轮明确定义的领域、内容、人工塘地形及派生缓存处理。

| 数据 | 结果 |
| --- | --- |
| 农场 | 77 个全部保留；4 份地理农场的人工塘转换为土壤 |
| 资产与状态 | 作物坐标、成熟时间、库存、装备、钱包、矿井、版本、用户位置和搬迁资格保持 |
| 地理 | 来源、自然水域、非鱼塘区域和非鱼塘锚点保持；更新地形 ID、校验和及相应绑定 |
| 历史 | 1,655 条历史命令、41 条建场记录保持；账号和在线表逐行指纹一致 |
| 待处理状态 | 没有需要取消的农场抛竿，没有待失效的搬迁预览；清除派生访客快照 |
| 重复执行 | 第二次迁移为 0 条，所有迁移后行保持相同 |
| 新服务启动 | 迁移后的全部行与启动前基线相同 |

保留既有数据库、身份和语音配置，两个 Docker 网络以及 `NODE_OPTIONS=--network-family-autoselection-attempt-timeout=1500`。备份和凭据只保存在服务器发布目录的受限 `private/`，不进入 Git 或公开下载。切换脚本在尝试领域迁移后遇错会保留维护状态，不会自动启动不兼容旧 writer 或恢复旧存档。本轮切换成功，维护状态已解除。

## 验证范围

- 服务端使用本机独立 PostgreSQL：**78 个文件、851 项测试通过**；TypeScript 检查通过。
- Godot 农场、钓鱼和地图鱼塘：**33 个套件、290 项通过**，测试报告 0 失败、0 orphan。引擎退出另有 5 个 ObjectDB 实例提示，本轮没有进行全局泄漏验收。
- 生产主机副本完成实际 HTTP/WebSocket 的 12 个地点进入、双人同塘、16 人容量契约、真实时间鱼获结算、独立背包、幂等、农场和矿井进入，以及重启后保留。测试写入只发生在副本；演练容器和数据库已清理。
- APK 检查包名、递增版本、签名、启动场景、公开接口、5 个正式 autoload、原用户目录和无观察器／QA 入口。地形及地图鱼塘目录与合并源码一致；Voice Profile 和换装脚本与此前 0.16.39 包逐字节一致。
- `emulator-5560` 覆盖安装并回读同一 APK；本次冷启动 PID 16256 确认 `logged_in=true has_farm=true`，城市选择页截图已检查。4 个当前身份／选择／偏好文件逐字节一致，另 3 个原本不存在的文件仍不存在。测试进程由 runner 正常停止，模拟器保留。

本轮未安装用户手机、未进行新的真机全玩法或 iOS 验收。此前 0.16.39 的手机验证仍是该包的历史证据，不能作为 0.16.40 的手机验收。未发送新的 Slack／飞书消息。

原始日志、发布清单、数据保留报告和截图在 [本轮产物目录](../../output/pond-retirement-release-20260925/)；[下载验证](../../output/pond-retirement-release-20260925/release/download/verification.json)、[APK 检查](../../output/pond-retirement-release-20260925/release/artifact-verification.json)、[模拟器验证](../../output/pond-retirement-release-20260925/release/emulator-verification.json)。

## 分支与工作区清理

`worktree/rapid-harbor-4666` 的本地和远端分支均已删除，父工作区和嵌套 integration 工作区已移除登记。清理前归档了 **18,543 个文件／链接、5,820,868,433 字节文件内容**，逐文件 SHA-256 或链接目标核对通过；嵌套工作区未提交改动另存二进制补丁。只排除了可重建的 `.godot`、`node_modules` 和 Git 工作区指针，没有丢弃视频、APK、QA 证据或集成改动。

归档位于 [worktree-cleanup-20260925-pond-retirement](../../output/worktree-cleanup-20260925-pond-retirement/)，清单为该目录的 `manifest.json`。主工作区的 `output/pond-pitch-2026-09-25` 与 `output/farm-pond-removal-2026-09-25` 已链接到保留产物，两个此前发送的 MP4 哈希再次核对一致。

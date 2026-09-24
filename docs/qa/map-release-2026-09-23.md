# Journey 地图正式更新 · 2026-09-23

用户明确要求先发布当前「无地标跳转场景」版本，并通过飞书／Slack 发给本人，附简要更新说明。

- 正式包：`com.sensen.journeypreview`，`0.16.32 / 2026092311`，170,969,957 字节。
- SHA-256：`fea6a68ead20b45a8a123347cdaa7cf8acf2912e8a0f65b469e9bf00ff87d25a`。
- 原始证书：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。
- 内容基线：`b31cfd1`，仅递增正式版本。洛杉矶／上海城市地图、27 类 125 张 POI 图标、国家级缩放、自动切城、城市飞行动画、白卡与青柠样式；玩家详情可拜访农场。未接入地标 3D 场景跳转。
- 正式导出显式排除 `assets/landmarks`、`modules/landmark`、所有 tools/tests/docs/output/observer；APK 解包检查排除试验场景资源、QA autoload 和启动参数。上海和洛杉矶配置均已打包。
- 179 项原生窗口地图测试通过，0 errors / failures / orphans。初次 headless 运行受视口缺失和尺寸假设影响，不作为通过记录；原生报告：`output/map-release-2026-09-23/native-tests/report_1/results.xml`。
- 模拟器正式包覆盖安装、全包回读、冷启动登录通过；本次新采集的五份身份／外观／偏好文件逐字节一致，农场、地形、资产、搬迁状态与安装前一致。未使用历史存档恢复。此处不声称本轮做过完整触摸流程。
- 真机未连接，本轮未安装或验收真机。
- 线上健康正常，`shoreline-farm-20260921` / domain 27 / content `50c2dbdde04c9678`。线上容器 `server/src` 和 `packages/blueprint-core/src` 共 61 文件与本地 SHA-256 全部相同，无后端部署和数据库迁移。

## 下载

- [OSS](https://oss.sensenjoy.cn/farm/releases/map-20260923-fea6a68ead20/sensen-journey-map-0.16.32.apk)
- [美国 DMIT](https://download-us.sensenjoy.cn:8443/farm/releases/map-20260923-fea6a68ead20/sensen-journey-map-0.16.32.apk)

两站均使用全新不可变版本目录，只发布 APK、release.json、SHA256SUMS。全量下载、SHA-256、Range 206、清单和校验文件回读通过。

发布中发现下载域名仍解析至旧 IP `179.255.158.180`，而既有 SSH 别名指向当前 DMIT `179.255.151.51`；新主机原 Caddy、证书和文件服务均正常。只更新 `download-us` 的 A 记录（RecordId `2100781640581942272`，TTL 600），保留其他服务和 DNS。权威 DNS 已返回新地址。首次 DMIT 完整校验通过 curl `--resolve` 连接新地址并保留正常 TLS 验证；本地递归 DNS 尚有旧缓存，普通域名复核结果另记。没有修改游戏 API 域名。

## 交付

飞书已发送并回读确认：本人 `ou_7b45631cce70958a721957138e2a03fa`，既有 bot 私聊，消息 `om_x100b640f14d1acacb10eee45edbd477`。内容为同一 APK 两个下载链接与更新说明，未附私人配置／存档。消息回读不等于用户已读。

用户随后通知 Slack 连接恢复；当前会话工具列表仍未暴露 Slack 接口，浏览器也无可用实例。Slack 发送未完成，不能按历史 Joey 回执冒称已发送。

证据及实际消息正文：`output/map-release-2026-09-23/`。

## 后续补验与在线修复

美国线路普通 DNS 已更新，使用原域名的全量下载哈希及 Range 内容再次通过，无需地址覆盖。用户自行把本包安装到 V2509A 后反馈首次生成失败；已定位并上线 Node 地址族连接等待配置修复，见 [新装机检查](fresh-install-geography-2026-09-23.md)。此操作不改业务镜像或数据库，首次发布时的不可变清单不覆盖。

真机补充：用户自行安装的 base.apk 已从 V2509A 完整回读，与上述公开 APK 的 SHA-256、原证书、版本和无观察器内容一致。修复后用户的新身份已建场；原身份的58格/187金币农场仍在，原74个farm行校验一致，新建后总数为75。

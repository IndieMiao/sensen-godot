# 发布记录的两个来源

正式 [P0 Demo release log](../release/release-log.md) 在基线 `6ed012f96ce0a85ad3f738d9fdb6ac2d922f955b` 与导出逐字节相同，不另建正式版本表。以下单节仅见于未合入分支 `docs/geofarm-demo-1117`（`1146f09891f8d98b751331e296e30080686de50a`；PR #1088 已关闭）；是独立验证包旁证，不是正式发布或本次授权。

## 独立验证包 GeoFarm DEMO 0.0.1（2026-11-17）

- SGODOT-499 的旧金山地理农场小样，独立包 `com.sensen.geofarmdemo` / `2026111701`，显示名 **Gensen GeoFarm DEMO**；不作为 P0 或商店版更新，不替换已有包。代码来自独立 demo 分支完整头 `b6b0f6eae7f579d517ee0caa8bc7c41296fc2f2b`。
- APK：`geofarm-demo-2026111701.apk`，**123,807,624 字节**；SHA-256 `d90a2b7e799f2edc93c4a2efdc831d7541bb5efe853e089746e1e980dcc999ef`。内部 debug 导出，证书 SHA-256 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`；不是 Play 上传证书。导出副本仅包含 demo、必要地图桥和字体，无游戏 autoload 或账号入口。
- 公共 Census/DataSF 数据离线预生成，版本 `sf-20261117-v1`：5954 源区块中 5802 可选、152 排除，固定内缩 8 米、按面积约 800 格，实际 764–824 格。Mapbox 只提供底图和镜头；手机不生成农场、不请求定位。未知土地用途保留未知，外圈路径是生成规则，不是现场道路测量。
- 生成 manifest SHA-256 `06efe65cdc31aad901be056da4b0a3696fc3e0cb124dfdfcf1c2c838a94d111a`；完整静态文件 hash 与引用均核验。预生成网格由独立开发机容器托管，认领数据单独持久化；无正式游戏服、正式密钥或真实玩家数据。随机安装凭据只保存其 hash，公共认领列表不返回凭据。
- 本次临时 HTTPS 根：`〔服务地址〕`，提供静态索引/农场和 `/claim`、`/claims`、`/health`。开发机仅回环 3188，固定 cloudflared 2026.11.0 隧道；服务保留到本次验收结束后再关闭，不作为长期地址。
- 出包回读：包名/版本/签名/ZIP、实际入口、独立用户目录、零 autoload、12 个脚本/场景逐源码 hash、动态农场资源、固定公网配置、Mapbox 库、DEMO 图标及无定位/麦克风/相机/广告 ID 权限通过。Node22 服务合成 HTTP 检查覆盖幂等、竞占、一安装一块、持久化重启、写失败、体积/频率上限及静态 hash 拒绝；Mac 无代理公网索引/认领列表读取通过。
- Android 安装全包回读、两安装身份的认领/互见/访问农场、返回/拖移/双指缩放通过；两条真实认领经同 CID 容器重启后公开记录与磁盘 hash 保持。设备 curl 通过 Android 系统解析所得 IP 加进程级 `--resolve` 验证索引/认领列表 TCP/TLS/HTTP，保留两次静态 curl DNS 失败；APK 原生网络正常。首轮 AVD 硬件键盘暴露导致未弹软键盘，保留 adb 文字输入记录；随后同一 APK、仅临时设 AVD `hw.keyboard=no`，真实 Gboard 触键输入、首个 Back 仅收键盘留卡、第二个 Back 回图均通过，没有新增认领，测试配置恢复原 hash。用户验收另行进行。构建进程和私有 adb 已退出，独立演示服务按批准保留。没有正式部署、存档迁移或常规 OSS 发布。
- 构建与部署证据：SGODOT-499 `312b913b`、`3967d4e5`；本地交付清单 `geo-farm-demo-1117/DELIVERY-r1.json`。

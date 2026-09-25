# Journey APK 的美国下载镜像

用户于 2026-09-18 反馈美国访问原 OSS 慢，要求将 APK 上传到现有 DMIT。
已部署到 DMIT 洛杉矶主机；仅托管公开发布物，游戏 API 和存档仍使用原香港服务。

- SSH 别名：`dmit-crs2ddcugh`；主机 `179.255.151.51`。
- 域名：`download-us.sensenjoy.cn`，阿里云 DNS A 记录，TTL 600。
- HTTPS 下载：`https://download-us.sensenjoy.cn:8443/farm/releases/` 加版本目录和文件名。
- 系统 Caddy 服务，配置 `/etc/caddy/Caddyfile`，源码配置见同目录 [Caddyfile](Caddyfile)。
- `/srv/sensen-downloads` 仅保存公开 APK、`release.json`、`SHA256SUMS`，关闭目录列表；每次发布使用版本与哈希组成的新目录。
- TCP 80 用于证书 HTTP challenge 和 HTTPS 跳转；8443 用于独立 HTTPS 下载。443 及 18443 的现有 Xray、1194 的 OpenVPN 与原 nftables 规则保持。
- Caddy 自动申请/续期证书，开机启动；支持 Range 断点续传、明确 APK MIME/附件下载与不可变缓存。

## 当前版本

[Journey 0.16.42 / 2026092505](https://download-us.sensenjoy.cn:8443/farm/releases/farm-home-20260925-9c53f5335566/sensen-journey-farm-home-0.16.42.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/farm-home-20260925-9c53f5335566/sensen-journey-farm-home-0.16.42.apk)。

178347467 字节；SHA-256 `9c53f53355669b94936c143bb7d4733f7a33d23491908f72335c1c0607b4e4a4`。已有农场的玩家冷启动跳过选城页，直接进地图并落在自己农场。原签名无观察器；V2509A 覆盖安装、整包回读、身份文件与冷登录核验。两站全量、Range、哈希和清单通过。后端保持 `pond-retirement-20260925` / domain 28。详见 `docs/qa/farm-home-launch-2026-09-25.md`。

## 历史版本 0.16.41

[Journey 0.16.41 / 2026092504](https://download-us.sensenjoy.cn:8443/farm/releases/mine-camera-20260925-24562afc8bc8/sensen-journey-mine-camera-0.16.41.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/mine-camera-20260925-24562afc8bc8/sensen-journey-mine-camera-0.16.41.apk)。

178346759 字节；SHA-256 `24562afc8bc8addd9e9c42461cfd75e7d3941e9a0805f964c177047d4b267754`。矿井新楼层默认最远视野 0.8，宽度增加 25%；保留双指缩放及同层重连／前后台时的自选视角。113 项原生检查、三种尺寸的 36 次 Android 触摸通过。原签名无观察器 APK 已在模拟器和 V2509A 覆盖安装、回读和冷登录核验，各自当前数据保持；新相机完整交互为隔离模拟器证据。两站全量、Range、哈希和清单通过。后端保持 `pond-retirement-20260925` / domain 28，无新迁移。详见 `docs/qa/mine-max-view-2026-09-25.md`。

## 历史版本 0.16.40

[Journey 0.16.40 / 2026092503](https://download-us.sensenjoy.cn:8443/farm/releases/pond-retirement-20260925-190aa3e7d38f/sensen-journey-pond-retirement-0.16.40.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/pond-retirement-20260925-190aa3e7d38f/sensen-journey-pond-retirement-0.16.40.apk)。

178346711 字节；SHA-256 `190aa3e7d38f810866be0ea1185e1aac5f1582ff608ed903be46288f221cdc09`。农场人工塘退役并恢复地面，真实地理水域和 12 个地图钓鱼点保留；包含鱼塘美术、Voice Profile 与原生 WebView。原包名／原签名／无观察器。后端 `pond-retirement-20260925` / domain 28 / content `761deabf2a207d3e` 已配套上线，77 个农场及资产和历史保留。851 项服务端与 290 项原生检查通过，正式包模拟器覆盖安装、包回读、冷登录及当前身份保留通过；用户随后要求真机安装：同一包已在 V2509A 通过 Tailscale ADB 覆盖安装、整包回读及冷登录核验，5 个当前文件和农场资产保持。两站完整下载、Range、哈希和清单验证通过；不可变清单保留首发状态，后补手机证据详见 `docs/qa/pond-retirement-release-2026-09-25.md`。

## 历史版本 0.16.38

[Journey 0.16.38 / 2026092501](https://download-us.sensenjoy.cn:8443/farm/releases/voicematch-20260925-a651401ae41c/sensen-journey-voicematch-0.16.38.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/voicematch-20260925-a651401ae41c/sensen-journey-voicematch-0.16.38.apk)。

178431631 字节；SHA-256 `a651401ae41ccf19984d4fefbf054ab7ac1753596bb0cb5cf476a36f86423566`。换装页新增 Voice Profile 入口（安卓应用内 WebView 打开 match.sensenapp.com，Gensen 主题、英文），去掉启动 Godot logo。原证书；模拟器覆盖安装保留身份与登录，V2509A 覆盖安装哈希与身份文件核验。服务端保持 integrated-20260924。详见 `docs/qa/voice-match-android-2026-09-25.md`。

## 历史版本 0.16.37

[Journey 0.16.37 / 2026092405](https://download-us.sensenjoy.cn:8443/farm/releases/motion-20260924-b0bf11c1c6cf/sensen-journey-motion-0.16.37.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/motion-20260924-b0bf11c1c6cf/sensen-journey-motion-0.16.37.apk)。

178410560 字节；SHA-256 `b0bf11c1c6cf4e70e04e20dfb556d4455ddea60c316d256a18b2e24b4acf9d96`。修复鱼塘相机距离导致可见角色待机、跑步被冻结，统一动作切换姿势重置。66 项原生检查、124 次模拟器输入和 33 次隔离真机动作输入通过。原签名正式包已在 V2509A 与模拟器覆盖安装、回读与冷登录核验，当前身份和存档保持；两站全量、哈希、Range、清单均通过。服务端保持 integrated-20260924；本轮没有新消息交付。详见 `docs/qa/avatar-motion-2026-09-24.md`。

## 历史版本 0.16.36

[Journey 0.16.36 / 2026092404](https://download-us.sensenjoy.cn:8443/farm/releases/integrated-20260924-931618e56d20/sensen-journey-integrated-0.16.36.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/integrated-20260924-931618e56d20/sensen-journey-integrated-0.16.36.apk)。

178410540 字节；SHA-256 `931618e56d206529e8bec54f3685c8d7e1e9de8dcf27e7a64f526e0dab7a950b`。整合两城 12 个固定系统鱼塘/三种场景、明亮清澈的 2.2 倍流速水面、五层矿坑美术与自由镜头修复，保留 Griffith 场景入口。服务 `integrated-20260924` 已上线，domain 27 / content 50c2dbdde04c9678 不变，75 个农场和全部历史数据保留。

原包名、原证书、无观察器；842 项服务端和 423 项原生检查通过，隔离 Android 54 次实际输入通过。**同一正式包已在 V2509A 和模拟器覆盖安装、回读与冷登录验证**，各自当前身份和资产保持。手机本轮未重复完整新玩法。两个站点全量、SHA-256、Range 206 和清单校验均通过。本轮没有新增外部消息交付。详见 `docs/qa/integrated-release-2026-09-24.md`。

## 历史版本 0.16.32

[Journey 0.16.32 / 2026092311](https://download-us.sensenjoy.cn:8443/farm/releases/map-20260923-fea6a68ead20/sensen-journey-map-0.16.32.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/map-20260923-fea6a68ead20/sensen-journey-map-0.16.32.apk)。

170969957 字节；SHA-256 `fea6a68ead20b45a8a123347cdaa7cf8acf2912e8a0f65b469e9bf00ff87d25a`。LA/上海、125张语义POI图标、国家级缩放与城市飞行、统一白卡/青柠UI；不含地标3D跳转。原包名、原签名、无观察器；179项原生地图检查、模拟器原身份覆盖更新验证通过；用户安装到V2509A的同一包已回读核对。两个站点全量与Range校验通过，2026-09-23已将下载域名更新到当前DMIT地址。

用户本人飞书交付已发送回读；本会话Slack缺少可调用接口，未发送。首次建场的OSM连接失败已通过1500ms Node地址尝试等待配置修复；原有74个农场及历史记录未变。用户清数据后的新身份后来新增1份农场，旧身份的原农场仍保留。见 `docs/qa/map-release-2026-09-23.md` 和 `docs/qa/fresh-install-geography-2026-09-23.md`。

## 历史版本 0.16.9

[Journey Preview 0.16.9 / 2026092105](https://download-us.sensenjoy.cn:8443/farm/releases/shoreline-farm-20260921-9d30d59440c7/sensen-journey-shoreline-farm-0.16.9.apk)。
[OSS 备用](https://oss.sensenjoy.cn/farm/releases/shoreline-farm-20260921-9d30d59440c7/sensen-journey-shoreline-farm-0.16.9.apk)。

156414135 bytes；SHA-256 `9d30d59440c78917d0d93ae3b45598b2d29934136c8e61642cd969b0c5ad1735`。
服务端 `shoreline-farm-20260921` 已上线，domain 27 / content `50c2dbdde04c9678` 不变。OSM 标注不足时补充 ESA WorldCover 2021 的可靠地表覆盖，原失败选址现在可生成；真实水体保留，未知区域不直接变为陆地。32 米规格、旧地形与冻结预览保持，切换前后 9 张表精确一致。836 项服务端测试及实际选址的隔离搬迁、钓鱼和矿井检查通过。
**手机保留 0.16.8 的当前预览页面，未安装 0.16.9。** 原选址在新线上服务下预览成功，尚未发送搬迁确认；原 47 个作物格、资产、旧地形和一次选址机会保留。新 0.16.9 APK 的错误提示及水岸表现改进已在模拟器验证，原签名与无观察器状态核对通过。公开清单分别标明新包未真机安装、0.16.8 的线上预览已验证，未把预览成功当作完整搬迁验收。
DMIT 与 OSS 的完整下载、SHA-256、Range 206、清单及校验文件均已回读通过。详见 `docs/qa/farm-generation-error-2026-09-21.md`。

## 上一版 0.16.8

[Journey Preview 0.16.8 / 2026092104](https://download-us.sensenjoy.cn:8443/farm/releases/compact-farm-20260921-f230b7776070/sensen-journey-compact-farm-0.16.8.apk)。
[OSS 备用](https://oss.sensenjoy.cn/farm/releases/compact-farm-20260921-f230b7776070/sensen-journey-compact-farm-0.16.8.apk)。

156413227 bytes；SHA-256 `f230b7776070301f2d92b20ae6543b615b31e1f583fb36f4d01ac8d217dcbbaa`。
新客户端的新建农场与新选址预览使用精确 32×32 米布局（40×40 格、800mm/格、160 米真实地理选区）；旧存档和已有 v1 预览不改变。选址框采用清晰蓝色，拖动、缩放与地图保持一致。服务端 `compact-farm-20260921` 已上线，domain 27 / content `50c2dbdde04c9678` 不变，切换前后 9 张表、原始状态、地形及冻结预览逐项一致。
同一原签名、无观察器正式 APK 已在 V2509A 和模拟器覆盖安装并核对哈希，线上切换后的冷启动登录通过；手机选址拖动、缩放和取消验证通过。原账号、47 个作物格、资产和旧地形保留，重新选址机会未使用；真机未进行搬迁确认，公开清单明确完整真机搬迁流程未验证。DMIT 与 OSS 的完整下载、SHA-256、Range 206、清单及校验文件均已回读通过。详见 `docs/qa/compact-farm-2026-09-21.md`。

## 历史版本 0.16.6

[Journey Preview 0.16.6 / 2026092102](https://download-us.sensenjoy.cn:8443/farm/releases/farm-relocation-20260921-d3dc5e2037fc/sensen-journey-farm-relocation-0.16.6.apk)。
[OSS 备用](https://oss.sensenjoy.cn/farm/releases/farm-relocation-20260921-d3dc5e2037fc/sensen-journey-farm-relocation-0.16.6.apk)。

156409751 bytes；SHA-256 `d3dc5e2037fcb79700926746911a92ae403fe6d15877842b303087b429b099df`。
配套 domain 27 / content `50c2dbdde04c9678` 已上线，74 份旧农场获得一次主动重新选址机会，迁移保留原始存档、版本、身份、资产及历史记录，不自动搬迁。预览和取消不消耗机会，用户原账号的机会仍未使用。
原签名、无观察器正式包已在模拟器验证，DMIT 与 OSS 的完整下载、SHA-256、Range 206、公开清单及校验文件均通过回读核对。用户随后连接 V2509A，**同一公开 0.16.6 APK 已覆盖安装并通过冷启动登录检查**；安装包哈希、原签名及五份身份文件一致，原账号、47 个作物格、资产和旧地形保留，重新选址机会仍未使用。
真机截图停留在城市选择页，未进入农场，也未发送选址预览或确认请求；本次真机证据仅覆盖安装与登录，不能视为搬迁流程验收。不可变公开清单继续保留首次发布时 `physical_validation: false` 的记录，后补真机证据见 `docs/qa/farm-relocation-2026-09-21.md`。

## 历史版本 0.16.5

[Journey Preview 0.16.5 / 2026092101](https://download-us.sensenjoy.cn:8443/farm/releases/private-geographic-farm-20260921-79f86aaf9465/sensen-journey-geographic-farm-0.16.5.apk)。
[OSS 备用](https://oss.sensenjoy.cn/farm/releases/private-geographic-farm-20260921-79f86aaf9465/sensen-journey-geographic-farm-0.16.5.apk)。

156390062 bytes；SHA-256 `79f86aaf9465ed5b90bf0548bd398d655ca5907a855dc0e32b4363c83ab8f0d4`。
街区与农场统一为私有农场，新建按真实地理生成，保留旧地形、作物和资产。配套 domain 26 / content `50c2dbdde04c9678` 已上线，74 份旧农场完整迁移。原签名、无观察器更新包已在 V2509A 安装并冷启动验证，两个下载站完整下载与 Range 校验通过。详见 `docs/qa/private-geographic-farm-2026-09-21.md`。

## 历史版本 0.16.4

[Journey Preview 0.16.4 / 2026091905](https://download-us.sensenjoy.cn:8443/farm/releases/water-detail-20260919-f6d05bc633f4/sensen-journey-water-detail-0.16.4.apk)。
[OSS 备用](https://oss.sensenjoy.cn/farm/releases/water-detail-20260919-f6d05bc633f4/sensen-journey-water-detail-0.16.4.apk)。

156355815 bytes；SHA-256 `f6d05bc633f45b315025e14f6e81cd0ec5ee81bf9c425ca08fd3bc1cc753148f`。
农场池塘、街区湖泊/河流增加沉积石床、局部光纹、平面岸景倒影、自然岸石和植被。
35 项 Godot 测试和模拟器钓鱼验证通过；正式包已在模拟器覆盖安装并核对 APK 哈希及原存档。
用户随后重连 V2509A，**同一公开 0.16.4 APK 已真机安装和验证**，原身份、装备、47 个作物格及金币保留。
不可变公共清单保留初次发布时的模拟器验证状态；后补真机证据见 QA 文档。
保留原 Journey 包名和签名；服务端 domain 25 / content 50c2dbdde04c9678 不变。
DMIT 与 OSS 均通过全量下载、哈希及 Range 206 校验，旧版本路径保持。
详见 `docs/qa/water-detail-2026-09-19.md`。未经用户明确要求，不向 Joey 发送消息或 APK 链接。

## 后续发布

1. 构建并核对唯一 `com.sensen.journeypreview` 更新包、原签名、版本递增。
2. 在用户目录准备临时上传目录；上传 APK、清单和 SHA256SUMS，先核对服务器哈希。
3. 在 `/srv/sensen-downloads/farm/releases/` 创建新的版本/哈希目录，以 `.part` 写入 APK，完成后原子重命名；文件 root 所有、0644，目录 0755。不要覆盖已有版本文件，也不要上传配置、账号或备份。
4. Caddy 的配置支持所有新版本路径；仅增加文件不需要重载服务。
5. 从公开 HTTPS 地址完整下载并校验，验证 Range 返回 206 且字节与原包一致，再发下载链接。海外优先提供 DMIT，保留 OSS 备用。

首轮部署脚本、DNS 回执、下载/Range 校验和飞书回执见
`output/farm-composition-2026-09-18/dmit/`；原 Caddy 配置备份保存在
`/var/backups/sensen-downloads/Caddyfile.before-farm-view-20260918`。

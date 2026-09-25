# 已有农场直接进地图：0.16.42

用户要求：已经选定农场的玩家打开 App 后不再选择城市，直接定位到自己农场的坐标。运行源码为 `ab9920e`。

## 行为

- 冷启动时若本地农场缓存可用（`FarmChoice` → `FarmBlueprint`），选城页把农场所在城市写入 `region_choice.json` 后直接进地图；上次浏览的其他城市会被农场城市覆盖。
- 城市地图首次安装时镜头直接落在自己农场（zoom 16，无飞行），不再显示城市总览；无农场用户仍看总览。
- 仅冷启动第一张选城页判断（静态 `_boot_checked`）；从地图主动回到选城页照常显示。
- 未覆盖：重装／清数据后本地无缓存时仍先出现一次选城页；服务端已删农场而本地有缓存时仍跳过选城，由地图按 `NO_FARM` 进入选地。

## 验证

| 项目 | 结果 |
| --- | --- |
| Godot | `test_city_select` 6 项通过（新增 `owned_farm_region`）；map/ui 套件 7 项失败在未改代码上同样复现 |
| 桌面无头 | 缓存上海农场、上次城市设为洛杉矶：跳过选城，地图在上海、镜头 = 农场中心、zoom 16 |
| 测试包 V2509A | 冷启动直达洛杉矶农场；上次城市改为上海后仍落在洛杉矶农场并改回；农场、地图筛选、换装、城市面板巡检正常；`godot.log` 无 error |
| 正式包 | 与 0.16.41 相同的发布工程（仅版本号不同）；2127 个条目一致，运行脚本仅 `city_select.gdc`、`map_poc.gdc` 变化，其余为场景生成 ID 与版本清单；原签名 `38771d94…` |
| 正式包 V2509A | 从测试包 `-d` 覆盖安装 0.16.42；整包回读哈希一致，5 个身份文件不变，冷启动登录（`has_farm=true`）并直接落在农场 |
| 发布 | DMIT + OSS 完整下载、Range 206、release.json、SHA256SUMS 通过；后端保持 `pond-retirement-20260925` / domain 28，未部署 |

本次未做模拟器验证。

## 交付

- `com.sensen.journeypreview` **0.16.42 / 2026092505**，178,347,467 字节，SHA-256 `9c53f53355669b94936c143bb7d4733f7a33d23491908f72335c1c0607b4e4a4`。
- [美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/farm-home-20260925-9c53f5335566/sensen-journey-farm-home-0.16.42.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/farm-home-20260925-9c53f5335566/sensen-journey-farm-home-0.16.42.apk)。
- 用户要求发给 Joey：Slack 私信附完整 APK（文件 F0C4EQGKQES）；飞书云盘上传并仅授予 Joey 查看，私信发链接；云盘回下载哈希与消息回读通过。不作为后续版本的长期授权。

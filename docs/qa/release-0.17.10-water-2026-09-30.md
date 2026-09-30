# 0.17.10 清澈水体（PR #4）发版记录

2026-09-30。源码 farm-dev `79ab77f`（合并 PR #4「优化清澈水体、动态焦散与风格化泡沫」）。流程按 [发版手册](release-playbook-android-ios.md)。

## Android

- APK：`output/accounts-release-20260929/android/water/sensen-journey-water-0.17.10.apk`，186,488,555 字节
- SHA-256 `64bde5ec0a6e363f999dfdcf7227f68dccb76aba7946a8e4edda8103ac868c83`
- 包名 `com.sensen.journeypreview`，versionCode `2026093001`，versionName `0.17.10`，证书 `38771d94…8515673`
- 与 0.17.9 的 CRC 差异：鱼塘相关 `.gdc`/shader（fishing_water、water_shore、pond_scenery、pond_stone、pond_water、pond）、新增鱼塘贴图/泡沫/HDR 天空资源、`uid_cache.bin`、`classes6.dex`、`AndroidManifest.xml`；无其他变动
- 未发布到下载站
- 已发 Joey：Slack DM `D0C1MHLA3GQ` 附 APK（文件 `F0C6DUH1SU8`）；飞书云盘文件 `Fh5ubH3dToXCMhx8VE3cfvlPnwc`（授权 Joey 查看，回下载哈希一致）+ 消息 `om_x100b64f8672094a8b2e369b14f545aa`；两边都附 TestFlight 0.17.10 (1)

## iOS

- TestFlight `0.17.10 (1)`，App `6815092667`，处理状态 VALID；GensenMap Internal 群组自动可见
- pck 与 0.17.9 的差异与 Android 一致；归档内 pck 哈希 = 导出 pck（`828e5e35…`）
- iOS 真机未验

## 真机验收（vivo V2509A，USB，Vulkan Forward Mobile / Mali-G1-Ultra）

从 0.17.8 覆盖安装，账号/农场保留（logged_in=true has_farm=true）。

- 鱼塘：LA Willow Pond（gourd）、Pebble Pond（crescent）进入正常；水体清澈、浅深过渡、水底石、岸边泡沫、焦散/高光随时间移动（两帧对比确认）。
- 钓鱼：抛竿→咬钩→跑鱼流程正常。**遗留（非本次引入，PR 未改镜头）**：钓鱼镜头下鱼塘大半在屏幕左侧外，浮漂贴近左边缘。
- 主要页面：地图（LA、Fishing 筛选、鱼塘卡片）、农场、换装均正常。
- `files/logs/godot.log` 与 `logcat -s godot` 无 error。
- 截图：`output/accounts-release-20260929/android/water/device/`

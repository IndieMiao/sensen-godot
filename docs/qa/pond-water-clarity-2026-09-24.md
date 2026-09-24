# 鱼塘水色、清澈度与水纹速度

2026-09-24。用户提供设计参考图，要求水塘更明亮、清澈，水纹流动更快。本地版本为 **Journey 0.16.35 / 2026092403**；正式包已构建并核验原证书，尚未公开发布或安装到 V2509A。

## 实际调整

- 共享水面材质采用更明亮的青蓝浅水与蓝青池心水色，降低视觉水深和绿色遮盖，提亮水底矿石并保留深浅变化。
- 减少水底折射扭曲，扩大石底纹理与光斑的空间尺度，使石块轮廓更容易辨认；保留局部岸边倒影与浮漂涟漪。
- 水纹的时间倍率设为 `2.2`，同时驱动表面波纹与水底光斑漂移。抛竿、咬钩、浮漂反馈和服务端结算计时保持原规则。
- 系统鱼塘的草地平面原先使用默认节点名，被一起加入岸边反射层。现在明确标记为 `BankGround`，由已有反射过滤排除，避免大面积草地颜色进入水面；树木、石岸和植被继续参与反射。

实现位于 [water.gdshader](../../modules/fishing/water.gdshader) 和 [pond_scenery.gd](../../modules/ponds/pond_scenery.gd)。共享材质也用于既有农场及街区水域；不更改水域轮廓、导航、抛竿范围、装备、鱼获配置或存档。

## 证据与范围

| 项目 | 结果 |
| --- | --- |
| 原生回归 | 鱼塘及钓鱼相关 27 项通过，含既有农场池塘几何、岸线与导航兼容 |
| 原生渲染 | 三种鱼塘均生成实际 GPU 前后图片；实测草地反射层关闭，编译后的速度参数约 2.2，预览不启动网络 |
| Android 操作 | 66 次实际输入通过，覆盖三种鱼塘、沿岸行走、抛竿/收线、确认鱼获入包、背包查看、地图原位返回及三种显示尺寸 |
| 移动端画面 | 检视了钓鱼状态下的浮漂、鱼线、进度条和结果；运行日志没有脚本编译/运行错误 |
| 稳定帧率 | 每种鱼塘等待 4.5 秒后，以约 250 ms 间隔采样 20 次，三种场景的中位数和最低值均为 60 FPS；仅为此模拟器短时采样 |
| 内容与包一致性 | 新旧鱼塘目录逐字节一致；最终 APK 的 29 个相关运行资源与本次 QA APK 逐字节一致 |

测试使用隔离的 `com.sensen.journeypondqa` 和本地 3201 服务。原有农场格、钱包、账号及地点目录保持一致；测试账号通过正常钓鱼获得一条新鱼。完整测试会话和后续帧率采样均由项目 runner 正常停止，模拟器显示尺寸恢复。

水面采样点用于记录同一镜头下的 RGB 变化，数据见 [color-comparison.json](../../output/pond-water-2026-09-24/color-comparison.json)。设计参考用于调整材质方向，不表示已复刻参考图的全部美术或获得用户视觉确认。真机和 iOS 本轮未验收。

## 查看效果

- [葫芦池前后对比，左旧右新](../../output/pond-water-2026-09-24/gourd-before-after.png)
- [月牙池前后对比](../../output/pond-water-2026-09-24/crescent-before-after.png)
- [曲湾池前后对比](../../output/pond-water-2026-09-24/meander-before-after.png)
- [三种鱼塘新版预览](../../output/pond-water-2026-09-24/three-ponds-clear-water.png)
- [模拟器水纹动态录像](../../output/pond-water-2026-09-24/runtime/water-motion-android.mp4)
- [原生动态预览](../../output/pond-water-2026-09-24/water-motion.mp4)

## 安装包与状态

[Journey 0.16.35 APK](../../output/pond-water-2026-09-24/release/sensen-journey-ponds-0.16.35.apk)，178,385,449 字节。

SHA-256：`205e667bf2adcd1302bc0dbba5de8aa11070a61a572243f2bc65dcb8b129e15a`。

原包名 `com.sensen.journeypreview`、证书 `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`、原用户目录和正式 API 均已核对；没有包含 QA 账号、入口或观察器。校验记录见 [apk.json](../../output/pond-water-2026-09-24/release/apk.json)。

本次材质调整没有新增服务端变更。此前系统鱼塘功能的配套后端仍待上线，公共服当前不会因此自动开放新入口。本轮未进行后端部署、公开下载发布、真机更新或新的 Slack/飞书交付。

准备命令使用 `prepare_system_pond_qa.gd -- --water-clarity` 和 `prepare_system_pond_release.gd -- --water-clarity`，输出保存于独立的 `output/pond-water-2026-09-24/`，保留 0.16.34 的原包与交付证据。

## 后续 Slack 交付

用户随后指定通过 Slack 向本人发送 PNG 和 MP4。新版水色前后对比图与 Android 水纹录像均已上传到已验证的本人 DM，并回读确认文件 ID、名称、大小和类型：[PNG 消息](https://gensenapp.slack.com/archives/D0C0V4YULKT/p1790234320549469)、[MP4 消息](https://gensenapp.slack.com/archives/D0C0V4YULKT/p1790234325416999)。回执与文件哈希见 [slack-delivery.json](../../output/pond-water-2026-09-24/slack-delivery.json)。这次图片/视频交付不包含 APK 或服务端发布。

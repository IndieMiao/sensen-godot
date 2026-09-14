# 简体中文与语言切换验证

日期：2026-09-10。状态：客户端实现和本地验证完成；中文版已覆盖安装到 vivo V2509A 并验证中文首屏。未更新公开下载，也没有进行真人体验验证。

## 玩家入口

- 城市选择页、地图页的右上角均有语言图标，菜单提供“简体中文”和“English”。
- 没有语言偏好时默认简体中文；选择写入独立的 `user://language.cfg`，重启后恢复。
- 城市和地图当前界面即时更新。地图切换保留相机、农场选择和预览，不重载场景。
- 农场、地点、换装等页面使用所选语言；从这些页面返回地图即可再次切换。
- 偏好写入失败时保留原语言，并显示错误提示。

## 实现边界

词典为 `assets/localization/zh_CN.json`，共 1097 条英文原文到简体中文的映射。`Localization` 自动加载 Godot Translation，`L10n` 处理动态模板、数量、资源名。静态控件保留原文，使用 Godot 的自动翻译。

覆盖城市、选地、地图、街区、农场、摊位、背包、目标、居民对话、请求、工作台、工程、探索点、厨房、聚会、旧章节界面和换装。字体沿用 Nunito，并添加随包 Noto Sans SC 回退。协议字段、资源 ID、内容数据和存档结构保持原值。

Android Mapbox 标签通过 `setLanguage` 跟随偏好，移除原先仅允许英文名称的过滤；iOS 通过 `LANG` 桥消息调用地图 SDK 的标签本地化。没有译名的地名由 SDK 回退到地图数据提供的名称。OpenStreetMap 署名保留专有名称。

## 本地证据

| 检查 | 结果 |
| --- | --- |
| 相关 GdUnit 回归 | 43 个套件、380 项测试通过，无错误、失败、跳过或孤立节点 |
| 专项语言测试 | 8 项，含保存失败、偏好恢复、占位符一致性、中文字体全字覆盖、状态不变和标记双向刷新 |
| 原生 Godot 画面 | 169 次双语场景截图与控件边界检查通过；世界画面另有像素非空检查 |
| 视口 | 360×640、390×844、960×720；街区聚会和旧章节补查为 390×844 |
| 入口输入 | 实际输入打开菜单并选择，两种语言往返；语言入口与“我的农场”互不重叠 |
| 重启 | 导出资源包下，以独立进程依次验证中文、英文、中文偏好恢复 |
| 导出 | Android 预设资源包成功导出；从包内加载词典、中文字体、语言图标及编译脚本成功 |
| Android | 插件编译及 4 项 JVM 单元测试通过 |
| iOS | `xcodebuild` Debug 构建通过，`CODE_SIGNING_ALLOWED=NO` |

测试在 `output/localization-qa/project` 中运行，用户目录为 `sensen-localization-qa-20260910`，网络端点为无效测试域名。图形探针额外拒绝 HTTP 请求。测试未使用正常玩家存档。

本地证据位置：

- `output/localization-qa/project/output/localization-visual/report.json` 及同目录 PNG。
- `output/localization-qa/focused-tests.log`、`android-tests.log`、`ios-build.log`、`visual.log`。
- `output/localization-qa/project/reports/report_1/results.xml`。
- `output/localization-qa/localization.pck`；这是验证用资源包，不是已发布客户端。

## Android 真机安装

按用户“安装到真机”的要求，于 2026-09-10 23:38 完成 vivo V2509A 的 Workshop 覆盖升级。

- 包名：`com.sensen.workshoppreview0909`，桌面名称：`Sensen Workshop09-09`。
- 版本：`0.2.0-zh-CN.20260910`，版本号：`2026091003`。
- 构建沿用 `prepare_farm_app_export.gd --farm-app-public-workshop`，仅在生成的导出配置中提升版本；导入、Android Debug 导出成功。
- 保持原调试签名，升级前后证书 SHA-256 一致。执行 `adb install -r` 返回 `Success`，未卸载或清除数据。
- 升级前备份原 APK 和 `files` / `shared_prefs`；升级后、启动前的同范围 tar 备份逐字节一致。
- APK 包含 1097 条中文词典、Noto Sans SC、语言图标及编译脚本，正常城市选择入口及在线服务 `https://farm.sensenjoy.cn/preview/journey/v1`；不含 QA 入口和观察器。
- 冷启动返回 `Status: ok`；1080×2344 真机截图确认中文城市标题、上海、洛杉矶、定位按钮及右上语言图标正常显示。
- 手机原装的是 USB 测试版本；此次沿用已发布在线 Workshop 配置。安装身份和本地文件保留，但旧本地服务的农场进度与在线服务分开，本次未迁移服务端数据。
- 后续输入检查期间前台出现其他应用的安装界面，未完成语言菜单真机交互。进程日志抓取为空，现有 `godot.log` 是旧运行记录，因此不据此宣称运行日志检查通过。

安装包：`output/localization-device-2026-09-10/sensen-workshop-zh-CN-2026-09-10.apk`。
SHA-256：`64c172f205035d1ce728aaf3efce30fe2c54aa60f767b3a3bbf308eb64d71e6b`。
中文首屏：同目录 `01-launch-zh.png`；构建日志：`import.log`、`export.log`。
`private/` 存放旧安装包与含安装凭据的私有备份，不用于公开分发。

## 2026-09-11 农场连接修复

用户反馈点击自己的农场后显示“已离线，农场尚未连接”。实际原因是旧 USB 测试服的
`farm_choice.json` 在覆盖升级后仍被地图当作已有农场，而新在线服对同一安装身份返回
`404 NO_FARM`。农场场景未绑定会话，却仍被允许进入，因此只显示无法操作的空场景。
上一次安装检查只覆盖了中文首屏，没有发现这一升级兼容问题。

修复内容：

- 农场读取保留 `NO_FARM` 等响应结果，区分没有农场和连接失败。
- 在线服确认没有农场时，忽略旧缓存的“已拥有”含义，显示正常选地界面；不删除缓存文件。
- 点击“我的农场”先等待登录并确认服务端会话，防止重复进入；失败留在地图，可再次点击重试。
- 选地确认允许重新登录，只有服务器确认农场后才进入场景。
- Debug 启动日志只记录登录是否成功、有无农场及结果代码，不记录身份凭据。

验证结果：8 个相关套件、95 项测试通过，无失败、错误或孤立节点。覆盖迟到登录、旧缓存与
`NO_FARM`、连接失败后重试、重复点击、选地建场后绑定会话、命令恢复和双语回归。
使用原签名于 2026-09-11 00:04 覆盖安装到 vivo V2509A，版本
`0.2.0-zh-CN-fix.20260910`，版本号 `2026091004`。
安装身份、城市/农场选择、语言偏好和待确认命令文件的内容均与升级前一致。

真机日志：`Farm connection: logged_in=true has_farm=false result=NO_FARM`。
真机已进入上海地图的“选择农场布局 / 安置农场”界面，实时地图中文标签正常显示。
本次未替用户创建在线农场，也未迁移旧测试服进度；最终位置和建场由用户确认。

证据位于 `output/localization-device-2026-09-10/`：`fix-tests.log`、`fix-export.log`、
`fix-device-godot.log`、`fix-selection.png`。修复安装包为
`sensen-workshop-zh-CN-fix-2026-09-10.apk`，SHA-256：
`5e63e1687010956caaa5a3aa164bd3c5ae82060ffbf82f20eb9f952c6195c942`。
公开下载未更新。

## 未完成的验证

尚未在 Android 真机上完成语言菜单选择及切换后的重启验证；城市首屏和实时 Mapbox 中文地名已目视检查。iOS 未安装真机。地图 SDK 的标签译名覆盖不由本地词典保证。此前本地场景截图使用合成状态，不代表玩家已达成进度或玩法已获得验证。

一次扩大的英文回归还发现 5 项非本地化断言失败：`test_farm_hud` 的目标排序，`test_visitor_farm` / `test_farm_scene` 的作物尺寸，`test_crop_field` 的实例坐标，以及 `test_place_entry` 的相机尺寸。前四项涉及已有目标排序或未提交的农场美术工作；最后一项是未改动的相机恢复路径。本次保留这些代码与测试，未宣称全库回归通过。涉及 `frame_post_draw` 的场景测试不能使用 headless 运行；扩大回归在该处停止，最终 380 项为明确选择的相关套件。

## 复验

先运行 `godot --headless --path . --script res://tools/dev/prepare_localization_qa.gd`，再导入生成的测试工程。不要在正常工程用户目录运行会清理存档的测试。

图形检查运行 `godot --path output/localization-qa/project --scene res://tools/dev/localization_visual_probe.tscn`。

GdUnit 英文历史断言使用环境变量 `SENSEN_LANGUAGE=en`；语言专项套件自行切换并恢复语言。Godot 会消费 `--language` 参数，所以它不作为应用自动加载后的测试覆盖入口。`tools/run_tests.sh` 已设置英文测试环境。

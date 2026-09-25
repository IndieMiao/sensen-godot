# 矿井默认最大视野：0.16.41

根据用户在真机上的反馈，矿井新楼层、轮次或实例现在默认使用现有最远缩放 **0.8**，视野宽度比原来的 1.0 增加 **25%**。双指缩放范围仍为 0.8–1.4；同层刷新、重连与前后台切换保留手动视角。规则见[产品记录](../product/mine-max-view-2026-09-25.md)。运行源码为 `2185e00`。

## 验证

| 项目 | 结果 |
| --- | --- |
| 修改前回归 | 新默认视野断言在旧代码上失败，实际仍是 zoom 1.0 |
| Godot | 10 个套件、113 项通过，0 失败、0 orphan；含矿井、ScenePan、农场相机、头像与 OnlineSpace |
| 联机相机 | 服务端入场站位、新楼层、另一实例均采用 0.8；同层重连保留自选缩放与平移 |
| Android 实际输入 | 36 次触摸，3 次同进程前后台切换，720×1280、780×1688、960×720 三种尺寸通过 |
| 双指与操作 | 从最远视野放大、再缩小、焦点保持、拖动、离屏头像回中、背包和五层切换通过；缩放不触发采矿 |
| 正式包一致性 | 相机的两份编译脚本与 Android QA 包逐字节一致；相较 0.16.40，有 1,549 个资源条目完全一致 |
| 导出场景 | 12 个 PackedScene 解码后节点、资源引用和属性一致；二进制差异为生成的节点／资源 ID，另有资源索引变化 |
| 模拟器正式包 | 原包名覆盖安装、完整 APK 回读、冷启动登录和 4 个当前文件／3 个缺省文件保持通过 |

Android 操作在独立 `com.sensen.journeymineartqa` 本地场景与命令夹具中进行，没有把本地采矿夹具称为生产结算。观察文件加入当前 PID 校验。24 张 Android 截图及原生日志保留；第一／四层前后对照和 Android 默认视图已检查。QA 结束恢复模拟器原显示尺寸，并由 runner 停止应用。

下图左侧为原默认视野，右侧为最大默认视野：

![第一层视野对照](../../output/mine-max-view-2026-09-25/comparison-floor-1.png)

[第四层对照](../../output/mine-max-view-2026-09-25/comparison-floor-4.png) · [Android 手势结果](../../output/mine-max-view-2026-09-25/android/report.json)。

## 唯一正式 APK 与真机

- `com.sensen.journeypreview`，**0.16.41 / 2026092504**，178,346,759 字节。
- SHA-256：`24562afc8bc8addd9e9c42461cfd75e7d3941e9a0805f964c177047d4b267754`。
- 原证书：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。
- 正式 API、启动场景、5 个 autoload、原用户目录与 project.binary 保持；包内不含观察器或 QA 入口，GodotMap / GodotVoice / GodotWebView 及 Voice Profile 保留。

用户提供新的无线调试端口后，通过 Tailscale 重新发现并连接 **V2509A / 10AFAF162200319**。先读取当时安装的 0.16.40 和当前账号，保存新的基线，再覆盖安装 0.16.41。手机完整 APK 回读哈希与本次产物一致，原签名核验通过。

五个实际存在的 `install_key.txt`、`farm_choice.json`、`region_choice.json`、`ui_state.json`、`language.cfg` 安装前后与冷启动后逐字节一致。外观文件、服务端覆盖和 Voice Profile 页面覆盖原本不存在，之后仍不存在。当前农场 **0 个耕作格、180 金币、5 个背包条目**，农场 ID、版本、地形、位置、搬迁信息和排除时钟的完整 state 保持。没有恢复此前 4 条目或 2 条目的旧状态。

本次冷启动 PID **17915** 的进程日志确认 `logged_in=true has_farm=true`；城市选择页截图已检查，无脚本错误或崩溃。手机显示设置保留，测试进程由 runner 正常停止。相机完整交互验证来自隔离模拟器，真机本次验证为安装、冷登录与数据保留，没有操作真实账号的采矿、战斗、购买、搬迁或其他资产，也未重复全玩法真机验收。

[APK 检查](../../output/mine-max-view-2026-09-25/release/artifact-verification.json) · [真机验证](../../output/mine-max-view-2026-09-25/phone/verification.json) · [真机冷启动](../../output/mine-max-view-2026-09-25/phone/cold-city.png)。

这是客户端调整，后端继续为 `pond-retirement-20260925` / domain 28 / content `761deabf2a207d3e`，没有服务端部署或数据迁移。本轮没有 Slack／飞书发送。

## 公开下载

[美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/mine-camera-20260925-24562afc8bc8/sensen-journey-mine-camera-0.16.41.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/mine-camera-20260925-24562afc8bc8/sensen-journey-mine-camera-0.16.41.apk)。两站完整下载、字节数、SHA-256、Range 206 及对应字节、release.json、SHA256SUMS 均已回读通过。公开清单明确是客户端调整、已完成真机安装核验；全玩法验收范围仍以上文为准。

证据目录：[本轮产物](../../output/mine-max-view-2026-09-25/)，[公开下载验证](../../output/mine-max-view-2026-09-25/release/download/verification.json)。当前主工作区原有 78 个未跟踪文件哈希保持。

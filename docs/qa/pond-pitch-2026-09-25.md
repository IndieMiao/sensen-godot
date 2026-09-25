# 钓鱼点 Pitch 美术与跨平台渲染核对

后续用户要求真机覆盖安装：已完成 V2509A 上 0.16.39 的安装与检查，见 [真机报告](pond-pitch-phone-2026-09-25.md)。下文保留最初本地美术阶段的证据与边界。

2026-09-25，本地 `worktree-rapid-harbor-4666`。美术目标、可查看的高清图与录像见 [设计记录](../design/pond-pitch-2026-09-25/README.md)。本轮实现圆润暖白岸石、花叶丛、明亮草甸、深浅水吸收／散射颜色、动态焦散和太阳闪光。

## 验证结论

| 项目 | 实际结果 |
| --- | --- |
| Godot 回归 | 32 项，0 失败，覆盖已有鱼塘／钓鱼、导航、动作、相机和 3 项新增美术约束 |
| 原导航保留区 | 12 个地点的实际石头顶点检查通过；目录及站位／鱼获规则未改 |
| 浮漂可见性 | 近景发现大石遮挡；新增射线／真实三角面检查在修复前失败、修复后通过，最终截图再次确认可见 |
| 原生渲染 | 三种鱼塘横屏、岸石水体近景、390×844 竖屏及 1920×1200 展示图 |
| Android 渲染 | 独立 `emulator-5580` 上同一 APK 完成同样五组画面，另录约 12 秒动态视频 |
| 运行资源 | 同镜头报告逐项核对引擎、尺寸、镜头变换、正交宽度、shader 时间、MSAA、阴影配置、目录与水 shader 哈希 |
| 网络与账号 | 展示实例 session=null，独立用户目录，所有记录 `network_booted=false`；未验证或宣称在线鱼获结算 |
| APK 安装 | 离线 QA 包安装后回读整包，SHA-256 与本地文件相同；非 Journey 发布包 |
| 清理 | runner 结束后 QA 进程停止；专用模拟器恢复 1280×800 原始尺寸并保留运行 |

[最终测试日志](../../output/pond-pitch-2026-09-25/tests-final.log)、[Android 场景检查](../../output/pond-pitch-2026-09-25/android-qa-final.log)、[最终录像会话](../../output/pond-pitch-2026-09-25/android-motion-final.log)。

## Godot 和 Android 截图为何可能不同

实际启动日志确认，本轮桌面为 **Metal / Mobile**，Android 模拟器为 **Vulkan / Mobile**。旧 `config/features` 里的 `GL Compatibility` 标签并不等于实际使用 Compatibility 渲染；现已改为与配置一致的 `Mobile`。

发现并修正了一个确定的默认差异：

| 设置 | Godot 默认桌面 | Godot 默认 Android | 本轮显式配置 |
| --- | --- | --- | --- |
| Directional shadow size | 4096 | 2048 | 两端 2048 |
| Soft shadow filter quality | 2 | 0 | 两端 2 |
| MSAA 3D | 项目设为 2 | 项目设为 2 | 保持 2，即 4× |

桌面、美术截图与 APK 都从同一 `project.godot` 取得这些值。该阴影设置作用于项目的方向光，也会影响其他使用方向光的场景；安卓过滤开销已做本轮模拟器短时采样，低端手机整体预算仍需真机复核。

截图脚本同时固定了 **1280×800、同一地点种子、同一镜头、shader 时间 12 秒及角色姿态**，以免把水波相位、窗口比例和默认装扮差异当成 shader 问题。QA 在内存中将 `TIME` 替换为受控时间参数；生产 shader 继续使用真实 `TIME`。

最终同帧差异如下。数值为 RGB 每通道平均绝对差，范围 0–255；这是**两个运行平台之间的差异，不是对参考图的还原分数**。

| 画面 | 平均差 |
| --- | ---: |
| 月牙池横屏 | 0.1002 |
| 葫芦池横屏 | 0.0992 |
| 曲湾池横屏 | 0.1160 |
| 岸石／水面近景 | 0.0502 |
| 竖屏 3D 区域 | 0.0636 |

竖屏整图平均差为 2.2482，主要来自 Android 顶部安全区将 HUD 下移。静态 3D 地景位置和色调一致，不应为了让测试图完全相同而取消手机安全区。剩余少量差异集中在阴影及抗锯齿边缘。[逐项原始数据](../../output/pond-pitch-2026-09-25/parity.json) 与 [可视对照](../../output/pond-pitch-2026-09-25/desktop-android.png)。

本轮证明了上述 Metal/Vulkan 路径的场景一致性，不能推论所有 Android GPU、OpenGL Compatibility 回退或 iOS 都相同。已有的反射代码在 Compatibility 下不启用平面倒影；因此不要拿 Compatibility 截图当作此 Mobile 美术版本的验收图。本轮未操作或验收 Android 真机／iPhone。

## 动态、性能与录像

最终视频是 Android `screenrecord` 捕获的实际画面，1280×800、H.264、约 12 秒。已检查首、中、尾帧，水面闪光、焦散及浮漂随时间变化。首次录像被新 AVD 的全屏提示遮挡，未作为交付成片；按照新的 UI 树坐标关闭系统提示后重录并复核。

在最终多场景会话，预热 4 秒后每 0.5 秒采样，共 24 次：中位数 60 FPS、最低 54 FPS。后续清除系统提示的独立录像会话，24 次采样均为 60 FPS。两次数据均保留：[多场景采样](../../output/pond-pitch-2026-09-25/performance-sequence.json)、[录像会话采样](../../output/pond-pitch-2026-09-25/android/performance.json)。宿主为 M4，且与其他任务共享 GPU；这些是短时模拟器数据，不是手机性能承诺。

## 产物与并行隔离

APK：`com.sensen.pondart.rapidharbor / 0.16.37-pond-art / 2026092501`，78,327,220 字节；SHA-256：

```text
57d67e78f7cb031764c2d423d3502eb7eb3d5ba3ba50d497e068568031075ed8
```

[安装回读记录](../../output/pond-pitch-2026-09-25/apk-validation.json)。测试包保留在专用模拟器，测试进程已停止。本任务未更新原 Journey、未更换真实身份／存档、未执行生产发布或发送外部消息。

Godot 的默认 `shutdown_adb_on_exit=true` 也被实际确认；仅隔离 AVD 不能解决它造成的共享 ADB 停止。本轮为导出与设备操作增加独立 ADB `5041`、独立 AVD／serial `5580` 和独立包名，具体命令见 [并行测试说明](parallel-godot-android.md)。

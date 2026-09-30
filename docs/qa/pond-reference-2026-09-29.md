# 池塘参考图材质与细节回归

2026-09-29，`worktree/calm-cloud-3509`，基于 `f1e6be6` 的本地修改。目标与实际图片见[设计记录](../design/pond-reference-2026-09-29/README.md)。

## 结果

| 检查 | 结果 |
| --- | --- |
| `tests/ponds` | 最终 12 项通过，0 error / failure / orphan；包含 12 地点岸石导航边界、浮漂遮挡、相机和角色动作 |
| `tests/fishing` | 21 项通过，0 error / failure / orphan；共享钓鱼规则、几何及水体行为 |
| 桌面 | Godot 4.7.2 / Metal / Mobile；三种形状、参考构图、岸石、荷叶、树近景和 390×844 竖屏 |
| Android | 独立 `emulator-5586`、ADB `5053`；同一实际运行场景，Vulkan / Mobile；8 张固定时间视图和动态会话 |
| 跨平台 | 7 组画面尺寸、相机、时间、MSAA、阴影、目录与 shader 哈希一致；3D 平均 RGB 差 0.0079–0.0520 / 255 |
| 运动 | Android 约 12 秒实录，复核前、中、后帧；焦散网格变形、光斑闪烁、鱼影位移与浮漂涟漪可见 |
| 性能采样 | 独立动态会话预热 4 秒，之后 24 次、每 0.5 秒采样，均为 60 FPS；这是 M4 模拟器短时结果，不是手机性能验收 |
| QA APK | 原生模板导出，安装后完整 APK 回读与本地逐字节相同；runner 结束后应用进程已停止，模拟器保留 |
| 网络／数据 | 所有捕获报告 `network_booted=false`、session=null；地点目录 SHA-256 不变，未写生产或用户手机数据 |

跨平台差值只描述 Metal 和 Vulkan 的一致性，不是对设计图的还原分数。竖屏比较排除了平台安全区不同造成的 HUD 区域；未宣称 iOS、实体 Android 或 Compatibility 后端的验收结果。

交付时另开桌面动态预览的短采样为 51–70 FPS、中位数 52，32 draw calls、约 104 万三角形／帧，见[桌面预览采样](../../output/pond-reference-2026-09-29/live-preview/performance.json)。该窗口与其他桌面工作负载共享宿主，未进一步归因；不要把上面的 Android 模拟器 60 FPS 推广为所有设备或桌面会话的性能保证。

## 证据

- [最终池塘测试](../../output/pond-reference-2026-09-29/tests-ponds-final.log)、[钓鱼测试](../../output/pond-reference-2026-09-29/tests-fishing.log)
- [最终 Android 会话](../../output/pond-reference-2026-09-29/android-qa-final.log)、[性能原始数据](../../output/pond-reference-2026-09-29/android-final/performance.json)
- [跨平台逐项数据](../../output/pond-reference-2026-09-29/parity.json)、[APK 回读](../../output/pond-reference-2026-09-29/apk-validation.json)
- [同机位前／后](../../output/pond-reference-2026-09-29/before-after.png)、[设计／实际渲染](../../output/pond-reference-2026-09-29/reference-runtime.png)
- [最终 Android 录像](../../output/pond-reference-2026-09-29/android-final/water-motion-android.mp4)

最终 QA 包：`com.sensen.pondart.calmcloud / pond-reference-2026-09-29 / 2026092901`，84,396,538 字节，SHA-256：

```text
f21e8b89a955632b8492b0d60dba65eb3ecff9c3d818c60c28829a3e7d5bfce9
```

目录 SHA-256：`2c6e2a2f5f6efa3742912257fa8a0b4844cbf89277e5867ac88157784770a187`。

## 复现

直接运行 `tools/dev/open_pond_art.command`。它生成当前工作树的独立预览项目，关闭网络启动，不复用 Journey 用户目录。拖动、缩放、空格暂停和 R 复位均保留。

```sh
# 纹理只生成 pond art，不重写地点目录。
python3 tools/art/bake_pond_bed.py

# 单帧参考构图；预览项目由上面的 launcher 或 prepare_pond_pitch.gd 生成。
POND_ADB_PORT=5054 tools/dev/pond_art_godot.sh \
  --path output/pond-reference-2026-09-29/project --resolution 1280x800 \
  -- --capture --shot=reference --out=res://../review

# 已安装的隔离 QA 包：一个 runner 会话覆盖所有形状与录像。
POND_ADB_PORT=5053 ADB="$PWD/tools/android/pond_art_adb.sh" \
  tools/android/run_test.sh --serial emulator-5586 com.sensen.pondart.calmcloud -- \
  python3 tools/dev/pond_art_android_qa.py output/pond-reference-2026-09-29/android-review
```

该场景仍采用原有池塘轮廓、导航、玩家、物品和钓鱼结算规则。当前美术比基准更清澈、更柔和，但草甸绒感、岸边植物密度和参考图的间接光尚有差别。本轮没有公开发布、手机安装、后端迁移或外部消息交付。

## 后续：用户本人 Gensen 飞书交付

用户随后明确要求将对比图和视频发给本人，并指定 Gensen 飞书。实时 `whoami` 确认 profile=`gensen`、brand=`feishu`、用户张邵杰 `ou_7b45631cce70958a721957138e2a03fa`；以该 profile 的 bot 发到既有私聊。三条消息均已回读，图片资源、视频文件名／12 秒时长／封面均存在：

- 修改前后对比：`om_x100b648cc140708cb1da4c5221b6282`
- 设计图与实际渲染：`om_x100b648cd8d55484b3d7a22b549c87a`
- Android 动态视频：`om_x100b648cd6c2e8a4b277d771504a339`

[消息回读证据](../../output/pond-reference-2026-09-29/feishu-delivery/messages-readback.json)。这是本人素材交付，不代表用户已读，也不授权后续版本或其他收件人的发送。

# 移动端导出与真机验收

一期只走查“能装、能跑、帧率数据能读出来”，不追求商店上架签名/发行流程。下面按
安装模板 → 配置 preset → 真机验收步骤，三步走。

## 1. 安装 Export Templates

导出模板版本必须和编辑器版本完全一致（本项目 `4.7.2.stable`），否则导出会失败或提示
模板缺失。

1. 编辑器菜单 `Editor > Manage Export Templates...`。
2. 如果列表里 `4.7.2.stable` 一行是灰的（未安装），点 `Download and Install`（需要能连
   外网；断网环境改用 `Install from File` 手动下载对应版本的
   `Godot_v4.7.2-stable_export_templates.tpz` 再本地安装）。
3. 安装完成后该行状态变为“已安装”，`Project > Export...` 里对应平台 preset 才能正常打包。

## 2. Android preset

`Project > Export... > Add.. > Android`。

- **资源过滤**：`Resources` 标签页的导出过滤规则应排除 `addons/gdUnit4/*`、`tests/*`、
  `assets/avatar/source/*.fbx`（运行时只需要 parts/base/thumbs/manifest，这三类目录只在编辑器
  测试和转换管线阶段用到，不必随包分发；Android/iOS 两个 preset 都要设置）。
- **纹理压缩**：`Texture Format` 勾选 `ETC2` 和 `ASTC`（一期渲染管线是 `mobile`，两种格式
  都开，覆盖新旧机型；只有 ASTC 支持的机型也不会因为缺 ETC2 资源出问题）。
- **架构**：只勾 `arm64-v8a`（真机验收只关心当前主流 64 位机型，不需要 `armeabi-v7a`/
  `x86_64`，减小包体和导出耗时）。
- **签名**：一期不发商店，`Keystore` 用编辑器自带的 debug keystore 即可（`Editor Settings
  > Export > Android > Debug Keystore` 默认已经指向 Godot 内置的 debug.keystore，不用额外
  申请证书）。
- 前置依赖：`Editor Settings > Export > Android` 下的 `Android SDK Path` /
  `Debug Keystore` 需要能定位到本机 Android SDK（`adb`、`build-tools`）；首次导出 Godot 会
  在缺失时给出明确报错，按提示装 SDK/命令行工具即可。

## 3. iOS preset

`Project > Export... > Add.. > iOS`。

- **Team ID**：`Application > Team ID` 目前填占位值（例如 `TODO_TEAM_ID`）——一期只做真机
  跑分验收，不做 App Store/TestFlight 分发，实际签名分发前需要替换成正式 Apple Developer
  Team ID。
- **纹理压缩**：只用 `ASTC`（iOS/Metal 不支持 ETC2，不要勾错）。
- 导出 iOS 产出的是 Xcode 工程，需要在 macOS 上用 Xcode 打开、选真机、Build & Run；一期不
  在这里做自动化打包脚本。

## 4. 真机验收步骤

验收目标：15 个角色、`merged` 策略下，记录真机 FPS/帧时/显存，判断是否达标（无绝对
及格线，用于和 `direct` 策略、和不同角色数横向比较，定位性能瓶颈方向）。

1. 按上面 preset 导出安装到真机（Android: 直接装 APK；iOS: Xcode Build & Run）。
2. 应用启动后默认打开的是换装场景（`dressing_room.tscn`）；压测场景不是 main scene，
   真机上没有场景切换入口的情况下，导出前临时把 `project.godot` 里
   `run/main_scene` 改成 `res://scenes/stress_test/stress_test.tscn` 再导出（验收结束记得
   改回来，不要把这个改动带进正式提交）。
3. 打开压测场景后：把数量滑条拖到 `15`；确认策略按钮显示“策略: merged”（默认就是
   merged，如果之前被切换过再点一下切回来）。
4. 静置 3–5 秒等 HUD 数字稳定（刚重建角色阵列的头几帧会有加载抖动，不计入读数）。
5. 记录 HUD 上的 `FPS`、`帧时`、`显存` 三个数字到下表；同一台机器建议至少测
   `merged` 和 `direct` 两种策略，角色数覆盖 `1/5/10/15/20`，用于判断性能拐点。

### 记录表格格式

| 机型 | 策略 | 角色数 | FPS | 帧时(ms) | 显存(MB) | 备注 |
|---|---|---|---|---|---|---|
| 示例：iPhone 12 | merged | 15 | | | | |
| 示例：iPhone 12 | direct | 15 | | | | |
| 示例：小米 12 | merged | 15 | | | | |

如果某台机器帧率不达预期，归因方向按优先级排查（对应 spec 风险备忘）：

1. **surface 数**：`direct` 策略下每个部件独立绘制，先看是不是同材质部件太多没有走
   `merged`。
2. **阴影/灯光设置**：压测场景默认只有一盏 `DirectionalLight3D`，如果换成正式场景要检查
   阴影分辨率、灯光数量是否超预算。
3. **动画开销**：确认 `RigActivity` 的活动度阈值（`reduced_distance`/`sleep_distance`）在
   目标机型上生效——远处/画面外角色应该已经暂停动画播放，如果没生效说明距离阈值需要
   针对场景相机再调。

## 已知限制

一期不包含 PCK 远程下载/热更新：所有角色部件资产随安装包一起打入，没有“先装小包、
进游戏再拉资产”的分包机制。真机验收只验证“内置资产能装能跑”，不涉及网络下载场景。

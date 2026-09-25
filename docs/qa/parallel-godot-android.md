# Godot / Android 多分支并行测试

本轮钓鱼点美术分支使用以下隔离配置。另一个需求可以继续用自己的工作树和模拟器，不需要排队占用同一台 Android。

| 资源 | 本美术分支 | 另一个分支 |
| --- | --- | --- |
| 源码 | `worktree-rapid-harbor-4666` | 其独立工作树 |
| Godot 导入缓存 | 本工作树 `.godot` | 其工作树 `.godot` |
| AVD 数据 | `output/pond-pitch-2026-09-25/avd` | 原有 AVD |
| Android serial | `emulator-5580` | 本轮发现原模拟器为 `emulator-5560` |
| ADB server | TCP `5041` | 保留其已有端口；本轮亦观察到 `5038`、`5039` |
| 测试包 | `com.sensen.pondart.rapidharbor` | 其独立测试包 |
| 账号 / 服务 | 离线，禁止 Net boot；独立用户目录 | 独立测试账号、服务端口和数据库 |
| Android 构建 | 官方模板直接导出，未使用 Gradle | 含插件的构建须使用其工作树 `android/build` |

**只隔离模拟器不够。** 实际检查确认 Godot 4.7.2 编辑器默认 `export/android/shutdown_adb_on_exit=true`，导入／导出结束会停止所连接的 ADB 服务。早期导出后观察到了 5037 断连，因此本轮新增以下两个入口，通过子进程环境隔离 ADB；没有修改共享编辑器偏好：

- `tools/dev/pond_art_godot.sh`：Godot 的 Android 子进程仅连接 `5041`。
- `tools/android/pond_art_adb.sh`：连接相同服务，且不额外接管 USB 真机。

其他分支也应显式使用自己的 `ADB_SERVER_SOCKET`，或自行决定是否关闭导出后停止 ADB 的偏好。`-s` 仍然必须指定，因为每个 ADB 服务可能同时发现多台模拟器。不要使用全局 `adb kill-server`、不带 serial 的设备写操作、全局 `pkill godot`、共用 Gradle 输出、共用 QA 包名或共用测试账号。离线截图只需独立窗口和用户目录；有服务器的测试还需独立监听端口及数据。

## 重现本轮环境

从本工作树运行：

```sh
# 独立 AVD；已有设备占用端口时只报告，不会关闭或覆盖它。
tools/android/start_pond_art_emulator.sh

# 在另一终端导入、准备隔离项目并导出。导出时不要同时测试本分支设备。
tools/dev/pond_art_godot.sh --headless --editor --path . --import
tools/dev/pond_art_godot.sh --headless --path . --script tools/dev/prepare_pond_pitch.gd
tools/dev/pond_art_godot.sh --headless \
  --path output/pond-pitch-2026-09-25/project \
  --export-debug 'Android Pond Art' ../gensen-pond-art.apk

tools/android/pond_art_adb.sh -s emulator-5580 install -r \
  output/pond-pitch-2026-09-25/gensen-pond-art.apk

ADB="$PWD/tools/android/pond_art_adb.sh" tools/android/run_test.sh \
  --serial emulator-5580 com.sensen.pondart.rapidharbor -- \
  python3 tools/dev/pond_art_android_qa.py output/pond-pitch-2026-09-25/android
```

AVD 脚本默认读取本机 `Pixel_9_Pro.avd/config.ini` 的系统镜像设置，生成全新的本地 AVD，不复制旧用户数据。可用 `POND_AVD_TEMPLATE`、`POND_AVD_PORT`、`POND_ADB_PORT` 改配置；若换端口，安装及 runner 命令需相应更改。没有设置 `ANDROID_SDK_ROOT` 时使用本机标准 SDK 路径。

QA 脚本在同一个 runner 会话中检查四张横屏图、一张竖屏图、运动与短时帧率，完成后恢复本模拟器尺寸并停止目标应用。首次全屏提示通过当前 UI 树寻找 `Got it` 按钮关闭；不会使用历史截图坐标。APK 是离线开发展示包，不是替换用户 Journey 的发布包。

## 并行不代表性能测量独立

两台模拟器仍共用宿主的 GPU、内存和 CPU。功能、交互和美术截图可以并行；正式帧率对比应在其他重型任务退出后进行，并最终在目标手机复核。本轮没有把 M4 模拟器帧率称为手机性能。

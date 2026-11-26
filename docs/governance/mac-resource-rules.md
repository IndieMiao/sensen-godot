# 〔机器名〕 资源规则（sensen-godot）

> 2026-11-20 切换导出的历史记录，不是新的批准或现行执行授权。〔…〕标示隐去的环境或身份信息；原件定位见[迁入说明](README.md)。

导出时间：2026-11-20 16:5x CST（奕星只读子代理整理）。规则以较新的用户原话 / 奕星定为准；下面每条都标了出处，方便回查。

来源（只读）：
- PM 手册 `pm-playbook.md` 第 4 节（三天教训）及「4 补」（11-05 / 11-07 / 11-09 / 11-10 / 11-12）
- 大乔工位 `〔私有路径〕`
- 大乔台账 `pm/sessions/roster.md`（「安卓模拟器分配与巡检」「Mac 重活排队」「内存报告门槛」等规则区，以及 11-16 ～ 11-20 的 Q 窗登记流水）
- 共享记忆：feedback-close-emulators-after-tests、feedback-register-heavy-runs-with-daqiao、feedback-private-adb-grabs-usb-phone、godot-editor-mode-touches-adb、project-〔机器名〕-limited-use-2026-11-11、persistent-tmp-paths、feedback-never-pattern-kill、feedback-mengtian-emulator-on-〔机器名〕、feedback-yase-ios-simulator-allowed、device-adb-no-blind-taps、ios-sim-coldstart-check、gensen-ui-review-location
- `pm/adb-emulator-scan-notice.txt`（私有 adb 六步做法）

---

## 1. 总原则：同一时间只跑一样重活，先登记

- **重活**＝ Godot（gdUnit、`--import`、`--editor`、桌面拍图 / 渲染）、导出 APK / AAB、Gradle、iOS `xcodebuild`、安卓或 iOS 模拟器、大批量数据生成。
- 动手前先找**大乔**登记，等她核过内存门、确认没有别的重活后回「开」（或在台账写「台账即授权」）。**同一时间只允许一样重活**，Godot 导入 / 导出 / 渲染一律串行。（奕星 11-12 19:4x、11-13 09:2x；记忆 feedback-register-heavy-runs-with-daqiao，起因：11-13 哪吒未登记起 Godot 约 500 MB，Mac 空闲不到 100 MB。）
- 一次登记把要跑的测试、导入、拍图连着跑完，别零散地起很多次；跑完马上关，逐个 PID 报释放。
- 测完关自己起的模拟器、Godot、测试服、私有 adb，用 `ps` / `lsof` 确认没残留；只关自己的，分不清归属先问奕星；关模拟器不清数据（不 wipe-data）。（用户 10-07；记忆 feedback-close-emulators-after-tests）

## 2. 内存门

- **现行口径（11-17 17:53 大乔更正，奕星沿用）**：开窗前和运行中看 **free + inactive + speculative ≥ 1.5 GB**（`vm_stat` 页数 × 页大小）；低于就暂停 / 降速 / 不开新窗。
  - **raw free 不能当门**：本机 raw free 常态只有约 250 MB（11-17 曾按「raw free < 500 MiB」误停后裔的任务）。
  - **swap 只记录、不硬停**，但要盯：报告时写 `sysctl vm.swapusage` 的 used / total（11-18 起 swap 池 4096 MB，此前 8192 MB / 7168 MB）。swap 持续上涨接近满、或有会话 / 进程出错，当轮报奕星。
- 旧口径（留档，已被取代）：11-06「swap > 90% 报奕星」；11-12～13「空闲页 < 100 MB 或 swap > 85% 才报」。
- 冻结日 / 大活前先看一次空闲：11-13 奕星定「09:30 前空闲低于 1.5 GB，就在交接边界先重置大乔和小乔」。
- 其他内存大户：Gradle 守护进程（约 1.6 GB，空闲 3 小时自退；`./gradlew --stop` 会停同版本全部守护进程，必须挑没人出包的空档，由蒙恬执行）；`coreaudiod` 等用户系统进程只报用户、不碰。

## 3. 模拟器

### 〔机器名〕
- **只允许一台安卓模拟器，只给李元芳**：AVD `Liyuanfang_P0`，控制台 5590 / adb 5591，私有 adb 服务 **5091**。（用户 11-06 09:21：「李元芳仍然保持在 〔机器名〕」；奕星定 Mac 最多一台。）
- 其他人要模拟器、或李元芳要第二台（多人 / 语音两机），**一律去 〔机器名〕**。Mac 上出现第二台模拟器，大乔当轮报奕星和主人。
- **iOS 模拟器只给亚瑟**（用户 bot 778，11-12）：同一时间一台；用完 `xcrun simctl shutdown` + `simctl delete` 自建设备；李元芳安卓模拟器或 iOS 出包在跑时错开；开之前找大乔登记（开始时间、用途、预计时长）。iOS 18.6 模拟器运行时跑 x86_64 模拟器包（Godot 官方模板只有 x86_64 模拟器切片）；模拟器录屏只能写 `/tmp`（写 `〔私有路径〕` 报 Code=513）。
- 模拟器先写 `p0_server.txt` 再启动（11-06 曾误连正式服建了测试号，手册 4 补第 17 条）。

### 〔机器名〕（MSI 〔机器名〕，Ubuntu，12 线程 / 37 GB；与 cardigan 等项目共用）
- 每人独立 AVD、端口分开、不共用 AVD 目录（奕星 11-06）：
  | 主人 | AVD | 控制台 / adb | 私有 adb 服务 | 其他 |
  |---|---|---|---|---|
  | 司空震 | Pixel_API_36 | 5594 / 5595 | 5071（〔机器名〕 上） | 本地服 3110 |
  | 蒙恬 | Mengtian_〔机器名〕 | 5596 / 5597 | 5073（〔机器名〕 上） | 模拟器检查只在 〔机器名〕 做 |
  | 李元芳（第一台） | Liyuanfang_〔机器名〕 | 5598 / 5599 | 5075 | Mac→〔机器名〕 反向隧道 3135（连回 Mac 本地服 3125） |
  | 李元芳（第二台，11-10 起） | 同一 AVD `-read-only` | 5600 / 5601 | 5075 | |
  | 程序员临时复现 | 先向大乔登记 | 从 5602 起 | 从 5077 起 | |
- **〔机器名〕 限用（用户 11-11 18:4x 终端原话：「目前〔机器名〕的占用比较高可以先不要过度使用」）**：gensen 员工在 〔机器名〕 开模拟器 / 测帧 / 跑重活前**先问奕星**；能一台不开两台，做完立刻关。cardigan 的进程和窗格一律不碰。
- 测帧率门槛（11-10 奕星定）：开测前负载 ≤ 12 且 `x86_pkg_temp` ≤ 85 °C（acpitz 只作参考）；同一次开机内改前 / 改后交替各 ≥ 3 轮，只报相对差；中途别的项目负载 > 6 就停。
- GPU：模拟器与建模员渲染共用显卡，`nvidia-smi` 显存 > 5 GB 报奕星。

## 4. adb 与端口归属

### 铁律
- **绝不跑不带 `-P` 的裸 adb**（连 `adb devices` 也不行）：客户端发现 5037 没服务就会自动拉起一个默认服务，立刻抢走插在 Mac 上的用户真机。查有没有手机插着用 `system_profiler SPUSBDataType`，查端口用 `lsof -tiTCP:<端口> -sTCP:LISTEN`。（10-08 起多次事故；记忆 feedback-private-adb-grabs-usb-phone）
- **不碰 5037**。每轮收尾查 `lsof -tiTCP:5037 -sTCP:LISTEN`，是自己起的（核 cwd）就按 PID 停；来路不明的用 `lsof -p <pid>` 看 cwd 定位到 worktree，报奕星。
- 私有 adb 一律这样起：`ADB_LOCAL_TRANSPORT_MAX_PORT=5553 ANDROID_ADB_SERVER_PORT=<端口> adb -P <端口> --one-device emulator-<控制台端口> start-server`（`--one-device` 挡 USB，`MAX_PORT=5553` 挡扫描别人的模拟器）；起完 `adb -P <端口> devices` 只能看到自己的，看到别人的立刻 kill-server 重起。完整六步见 `pm/adb-emulator-scan-notice.txt`。
- **Godot 编辑器模式（`--import` / `--editor`）会加载 Android 导出插件去连 5037**：先起一个只认不存在模拟器的受限服务（如 `adb -P <端口> --one-device emulator-5999 start-server`），再 `ANDROID_ADB_SERVER_PORT=<端口> godot --headless --path . --import`。导入 / 导出结束时 Godot 会停掉这个服务，之后要用 adb 先重新 `start-server --one-device`。
- 用完 `adb -P <端口> kill-server` 释放；服务重起后 `adb reverse` 会丢，要重加。

### 〔机器名〕 私有 adb 端口归属（以台账和各人交接为准）
| 端口 | 归属 | 用途 / 备注 |
|---|---|---|
| 5037 | **禁用** | 系统默认 adb，谁起谁就会抢用户 USB 真机 |
| 5039 | 韩信 | 旧 USB 真机装机用；10-15 起停用 |
| 5071 | 蒙恬 | Mac 上 Godot 导入 / 导出 / 出包（〔机器名〕 上的 5071 是司空震的，不同机器） |
| 5073 | 后裔 | Mac 上旧 Houyi_P0 用过（11-06 起 Mac 只留一台模拟器，基本不用）；〔机器名〕 上 5073 是蒙恬的 |
| 5079 / 5081 / 5089 | 哪吒 | 近期用 5089（导入用 `--one-device emulator-5999`） |
| 5083 | 刘邦 | 导入 / 测试 |
| 5085 | 亚瑟 | 导入 / 测试（另有本地服 3137） |
| 5091 | 李元芳 | Mac 模拟器 Liyuanfang_P0（emulator-5590，adb 5591） |
| 5093 | 李元芳 | Godot 导出专用（`--one-device LYF_NO_USB_DEVICE`） |
| 5113 | 盘古 | Godot 导入 / 单测（上官婉儿身份文件里也写 5113，刘邦 Q1117-01 登记也写过 5113——同号不得同时用，串行规则保证） |
| 5065 / 5067 / 5069 | 历史 | 10-07～08 亚瑟、刘邦等早期用过，现不再分配 |
| 〔机器名〕：5071 / 5073 / 5075 / 5077+ / 5095 | 〔机器名〕 | 司空震 / 蒙恬 / 李元芳 / 临时复现 / 马可波罗（〔机器名〕 本机的端口，与 Mac 不冲突） |

其他端口：李元芳本地服 3125；Mac→〔机器名〕 隧道 3135；冒烟包烤入地址 `〔地址〕:3110`（经隧道）；〔机器名〕（〔地址〕）上 3170 是 p0-voice-dev（别动），3188–3192 是 GeoFarm / 动态农场演示服务（不在 Mac 上，保留到用户验收结束，之后由蒙恬按 PID / CID 关）。

## 5. 用户的 USB 真机

- 用户的 vivo 〔设备〕、iPhone（iPhone 13 / 14 Pro）可能插在 Mac 上，**一律不碰**：不装、不卸、不清数据、不改设置、绝不按坐标盲点。（记忆 device-adb-no-blind-taps）
- 10-15 起安卓包不再 USB 装机，APK 经飞书发用户自装（>100 MB 走云盘链接或 OSS 链接 + SHA-256 + versionCode）；不再开装机窗口。
- 用户真机测试期间（奕星会通知）：不跑 adb、模拟器、Godot `--import` / `--editor`、导出，等通知解除。
- 发现 USB 上插着用户手机而手上的活可能碰到它，先停、问奕星（例：11-13 亚瑟发现 iPhone 插着先停，用户 bot 811 回「iPhone 插着可以」——他只用模拟器、不往手机装东西）。

## 6. 进程：只按 PID 关，绝不按模式杀

- 永远不用 `pkill`、`killall`、`pgrep | xargs kill`。10-08 00:41 一次 `pkill -f "…" -U $(id -u) --` 在 macOS 上把 `--` 当成匹配模式，误杀本机全部其他 Claude 会话。
- 起后台服务 / 模拟器时把 PID 写进自己 output 目录；关前 `ps -p <PID> -o command=` 核对是自己的再 `kill <PID>`；也可 `lsof -tiTCP:<自己的端口> -sTCP:LISTEN` 查 PID。模拟器用 `adb -P <私有端口> -s emulator-<端口> emu kill`（先 `adb shell sync`）。
- `cd dir && node … &` 的 `$!` 是外层子 shell 的 PID；用 `cd dir; node … &` 或 `(cd dir; exec node …) &`，起后用 lsof 核对。
- `pgrep -f` 会匹配到排队 subshell 本身；kill 前逐个核 PID 和父进程，别 kill 计算出来的 ppid（11-18 曾差点 kill 1）。
- 关别人的进程：先找主人；查不到主人报奕星，不替人关（大乔「只看、只提醒、不替人关」）。

## 7. 外置盘 〔私有路径〕

- **必须挂载**：所有 worktree（`〔私有路径〕`）、协作目录 `〔工作区〕/`（PM 手册、台账、报批）、各人工具目录（如 `〔私有路径〕`）都在这块盘上；未挂载时这些文件全部不可用。切换期间**不要动挂载**。
- 临时 worktree、产物、大文件一律放 `〔私有路径〕`（系统盘曾只剩 20 GB；手册第 4 节第 10 条）；临时 worktree 用 `git worktree remove` 删。`/tmp` 会被系统清理，`〔私有路径〕` 只是指向 〔机器名〕 的符号链接，重启后可能消失。
- 例外：iOS 模拟器录屏 / 截图必须写 `/tmp`（写 〔机器名〕 无权限）。
- 写文件一律 POSIX 路径（`〔私有路径〕`、`〔私有路径〕`），写完 `ls -b | grep 'C:'` 确认没产生文件名带 `C:\` 的垃圾文件（API 中转会把路径改写成假的 Windows 路径）。

## 8. Q 窗（重活资源窗口）台账格式

11-16 起大乔用「Q 号」登记每个重活窗口，写在台账 `pm/sessions/roster.md` 的巡检流水里。格式要点（从 Q1116-01 ～ Q1117-79 归纳）：

```
| <登记时间> | **重活登记 Q<MMDD>-<NN>（<人>·<用途>）：绝对起止 HH:MM–HH:MM（硬顶 HH:MM）**
  范围：单 Godot / 单 Gradle / 模拟器几台 / 私 adb <端口> / 有无导包、服务、设备、截图、HTTP listener；输入头（完整 SHA）
  门（<实测时间>）：free+inact+spec <N>MB、swap used/total、无 godot/qemu/gradle/java
  台账即授权（本人 herdr read 自取，不往输入框投）／或「开」由大乔投递
| <完成时间> | Q…完成并释放：逐 PID 列出（全部已退）、<端口> 无监听（大乔复核）、结果摘要 |
```

规则：
- 起止写**绝对时间**；写入时已过起点，就另写一行「更正（以本条为准）」给新的绝对起止，不能把不足的时长默认顺延。
- **硬截止**到点就停，不续跑、不顺延；runner 判断剩余时间不够就不启动（例：Q1117-42 判剩余 < 5 秒，Godot 未启动并关掉私有 adb）。
- **释放即许可结束**：提前跑完也要报释放；之后再要跑就新登记一个 Q 号，**不沿用旧窗**（11-16 有人误复用已释放的窗口加测，已更正）。
- 提前开窗也要新写一行，写明「取代 <时间> 行的起点」，硬顶不变。
- 完成后必须有 **PID / 端口释放证明**：逐 PID `ps` 确认退出、私有 adb 端口 `lsof` 无监听、容器按 CID 清理（〔机器名〕 上的窗也写 CID）。
- 特殊资源要写进范围并单独批，例如「特批 1 个本地 Python 测试 listener（记 PID / 端口 / 绝对 deadline，到点全清）」。

## 9. 定时任务（cron）

- 会话内 CronCreate 建的循环任务 **7 天自动过期**（最后触发一次就删，不是「丢」）；第 6 天主动删掉按原提示词重建，新 ID 记台账。`/clear` 不清会话 cron，会话重启要重建。（奕星 11-13 查明）
- 定时任务触发的**正式服写操作一律先问奕星**。

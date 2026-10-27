# 本地 Android 测试（Steam Deck / Linux）

2026-10-02 在 Steam Deck（SteamOS，主机名 steamdeck）上首次从零搭起环境，`farm-dev`
打包，并在模拟器上完成手动全流程测试和 Mac mini 的脚本化探针测试。功能测试优先用
第 5 节的探针方式（隔离的内存服务器，不碰线上）；第 4 节的手点方式会在线上服务器
留下数据，只在需要测真实注册或线上流程时使用。

## 1. 一次性环境

| 项 | 本机位置 |
| --- | --- |
| Godot 4.7.2 | `~/.local/opt/godot-4.7.2/`，`~/.local/bin/godot` 软链 |
| 导出模板 | `~/.local/share/godot/export_templates/4.7.2.stable/` |
| Android SDK | `~/Android/Sdk`（build-tools 36/37） |
| JDK | `~/.local/opt/jdk-21` |
| 编辑器设置 | `~/.config/godot/editor_settings-4.7.tres` |
| AVD | `SteamDeck_Phone_API_37`（x86_64，google_apis），启动器 `~/.local/bin/android-emulator` |

```sh
# Godot 与模板（GitHub release，模板约 1.2GB）
mkdir -p ~/.local/opt/godot-4.7.2 && cd ~/.local/opt/godot-4.7.2
gh release download 4.7.2-stable -R godotengine/godot-builds \
  -p 'Godot_v4.7.2-stable_linux.x86_64.zip' -p 'Godot_v4.7.2-stable_export_templates.tpz'
unzip -oq Godot_v4.7.2-stable_linux.x86_64.zip
ln -sf "$PWD/Godot_v4.7.2-stable_linux.x86_64" ~/.local/bin/godot
unzip -oq Godot_v4.7.2-stable_export_templates.tpz -d /tmp/gdtpl
mv /tmp/gdtpl/templates ~/.local/share/godot/export_templates/4.7.2.stable
```

`tools/android/setup_android_build.sh` 写死了 macOS 模板路径
（`~/Library/Application Support/Godot/...`）。Linux 上把 `TEMPLATE_ZIP` 换成
`~/.local/share/godot/export_templates/4.7.2.stable/android_source.zip` 后运行，再装插件：

```sh
python3 tools/android/prepare_voice_plugin.py
python3 tools/android/prepare_webview_plugin.py
python3 tools/android/prepare_google_signin_plugin.py
python3 tools/android/prepare_notify_plugin.py
```

首次 `godot --headless --path . --import` 会生成编辑器设置。随后确认或追加：

```
export/android/android_sdk_path = "/home/deck/Android/Sdk"
export/android/java_sdk_path = "/home/deck/.local/opt/jdk-21"
export/android/shutdown_adb_on_exit = false
```

`shutdown_adb_on_exit` 默认是 true，导出结束会停掉 ADB 服务，必须关掉
（见 `parallel-godot-android.md`）。导入日志里的约 95 条 `Resource file not found: res://`
来自首轮导入顺序及 FBX 引用的缺失贴图，不影响导出。

仓库根目录要有 `mapbox_token.txt`（pk token，已在 `.gitignore`），否则地图不可用。
这个文件只在本机，不入库。

## 2. 打测试包

不要用默认 preset 直接给模拟器装：它是 `com.sensen.journeypreview`（会与正式
Journey 冲突），而且只有 arm64。临时改 preset 打独立测试包，打完立即还原：

```sh
cp export_presets.cfg /tmp/export_presets.orig
# preset.0：package/unique_name="com.sensen.farmdevqa"，package/name="Farm Dev QA"，
#           architectures/x86_64=true
P="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890"
GRADLE_OPTS="$P" JAVA_OPTS="$P" godot --headless --path . --export-debug "Android" build/farm-dev-qa.apk
cp /tmp/export_presets.orig export_presets.cfg && git status --short   # 必须是干净的
```

- Gradle 首次要下载 `gradle-8.11.1-bin.zip`，直连会超时，经 FlClash 代理 `127.0.0.1:7890` 可用。
  `GRADLE_OPTS` 里**不要**写 `-Dhttp.nonProxyHosts=a|b`：`gradlew` 会把 `|` 当成管道而报错。
- debug 包使用 Godot 默认 debug 证书，不能覆盖正式 Journey 安装；正式签名 keystore 不在本机。
- 产物约 300MB（arm64 + x86_64）。检查：`aapt2 dump badging`、
  `unzip -l ... | grep -E 'mapbox_token|lib/x86_64'`。

## 3. 模拟器

```sh
nohup ~/.local/bin/android-emulator -port 5560 -no-snapshot-save > /tmp/emu.log 2>&1 &
adb -s emulator-5560 wait-for-device
adb -s emulator-5560 install -r build/farm-dev-qa.apk
```

端口用 5560，因为它是 `tools/android/run_test.sh` 的默认 serial。

**模拟器只能软件渲染。** 宿主 GPU（AMD VanGogh / RADV）没通过模拟器的 Vulkan 检查，
最终用的是 `swangle` + `lavapipe`；Godot 日志显示 `llvmpipe`。后果：

- Mapbox 底图显示为黑底白线（POI、头像、3D 角色正常），这是模拟器的渲染问题；
  地图视觉须在真机复核。
- 场景切换需 25–50 秒，帧率很低；这里不做流畅度或性能结论。

## 4. 手动全流程测试

在同一个 runner 会话里完成整轮测试（退出时会强制停止 App）：

```sh
tools/android/run_test.sh --wait 3000 com.sensen.farmdevqa &   # 后台保持会话
S="adb -s emulator-5560"
$S exec-out screencap -p > shot.png      # 每次操作后截图确认，再决定下一步
$S shell input tap X Y
$S shell input text 'xxx'
$S shell input swipe x1 y1 x2 y2 600     # 拖镜头 / 摇杆
```

注意：

- 首次启动会弹出系统的 "Viewing full screen" 提示，要先点掉。
- 登录 / 注册表单输入后，字段上方会出现标签，整体布局会**下移约 50px**。每填完一个字段
  都要重新截图取坐标，否则下一段文字会打进上一个字段。
- 注册用 `@example.com` 邮箱，验证码这一步点"稍后"跳过（服务端注册即返回 token，验证可选）。
- 注册和建农场会在**线上服务器**新增数据，只用新注册的测试账号，不要碰真实用户账号。

2026-10-02 测试覆盖与结果（账号 `qa.farmdev.20261002@example.com`，上海）：

| 步骤 | 结果 |
| --- | --- |
| 注册 → 跳过验证 → 昵称 → 选城市 → 生成农场 | 通过；180 金币，赠送萝卜 6、生菜 3 |
| 行走模式点地面不种地；切到种地：翻土 / 播种 / 浇水 ×2 | 通过；8 小时后成熟 |
| 接取 NPC 委托、背包、人物装备页 | 通过 |
| 路边摊位买种子（180→162，生菜 1→4） | 通过 |
| 街角苗圃采集木料、新手矿坑开采 / 摇杆 / 退出 | 通过 |
| 强制停止后冷启动：自动登录 → 地图 → 农场，数据保留 | 通过 |
| 收获、交付委托 | 未测（成熟需 8 小时） |

发现的问题：引导按钮"种植生菜"只移动角色不播种；目标面板在可以继续翻土时显示
"田畦已满"；底部种子栏会挡住新翻的地块。截图在 `output/farm-dev-qa-2026-10-02/`
（不入库）。

## 5. 脚本化探针测试（Mac mini 的方法，推荐）

这是 Mac mini（`/Volumes/ACASIS/projects/sensen-godot`）一直用的方法，2026-10-02 已在本机
完整复现。它比第 4 节的手点更安全，也更可靠：

- **不碰线上**：`server/tools/*_qa_server.ts` 用 `MemoryStore` 在 `127.0.0.1:3195` 起一个
  内存服务器，不连数据库。每次启动从夹具新建一个一次性账号和农场。
- **不靠坐标**：QA 工程的主场景是 `tools/dev/game_ui_probe.tscn`，它走 `10.0.2.2:3195`
  （模拟器访问宿主机）登录。`game_ui_observer.gd` 持续把场景、控件名与边界、农场格子、
  背包等写到 `user://game-ui-proof/state.json`。
- **逐步断言**：`tools/dev/*_android_qa.mjs|py` 用 `run-as` 读 `state.json`，按**控件名**取
  中心点去 tap，并断言服务端确认后的状态。截图和状态存在 `output/<批次>/android/`。
- 独立包名 `com.sensen.journeyuiqa` 和独立用户目录，不影响正式 Journey。

### 额外依赖

- Node v26.4.0 和 pnpm 11.7.0（与 Mac 一致）：解压到 `~/.local/opt/node-v26.4.0-linux-x64`，
  软链到 `~/.local/bin`。然后在仓库根目录运行 `pnpm install --frozen-lockfile`。
- 夹具在 Mac 上，不入库，用 `scp` 拉到本机相同路径，保持 600 权限，不要提交：

```sh
mkdir -p -m 700 output/farm-mode-2026-09-22/private \
  output/ui-redesign-2026-09-21/device/private/baseline/avatar
scp -p macmini:/Volumes/ACASIS/projects/sensen-godot/output/farm-mode-2026-09-22/private/source-farm.json \
  output/farm-mode-2026-09-22/private/
scp -p macmini:/Volumes/ACASIS/projects/sensen-godot/output/ui-redesign-2026-09-21/device/private/baseline/avatar/outfit_local.json \
  output/ui-redesign-2026-09-21/device/private/baseline/avatar/
```

`qa-account.json` 和 `qa-before.json` 由 QA 服务器每次启动时重新生成，不用拉。
`ssh macmini` 是 `~/.ssh/config` 里的别名（Tailscale `100.82.205.49`，用户 `zhangshaojie`，密钥登录）。

### 运行（以农场种地流程 farm-mode 为例）

```sh
# 1. 内存 QA 服务器（另开终端或后台），看到 {"ready":true,"port":3195,...}
(cd server && pnpm exec tsx tools/farm_mode_qa_server.ts) > output/farm-mode-2026-09-22/qa-server.log 2>&1 &
curl -s localhost:3195/v1/healthz

# 2. 生成 QA 工程，并只在 QA 工程里打开 x86_64（模拟器需要；主工程 preset 不动）
godot --headless --path . --script res://tools/dev/prepare_farm_mode_qa.gd
Q=output/farm-mode-2026-09-22/qa-project
sed -i 's/^architectures\/x86_64=false/architectures\/x86_64=true/' $Q/export_presets.cfg

# 3. 导入 + 导出（Gradle 走代理，见第 2 节）
godot --headless --editor --path $Q --quit
GRADLE_OPTS="$P" JAVA_OPTS="$P" godot --headless --path $Q \
  --export-debug 'Android Game UI QA' ../farm-mode-qa.apk

# 4. 安装，并在同一个 runner 会话里跑场景脚本
adb -s emulator-5560 install -r output/farm-mode-2026-09-22/farm-mode-qa.apk
tools/android/run_test.sh com.sensen.journeyuiqa -- node tools/dev/farm_mode_android_qa.mjs

# 5. 结束后停服务器（不要用 pkill -f，会连调用它的 shell 一起杀掉）
kill %1   # 或者按端口找到 PID 再 kill
```

2026-10-02 本机结果与 Mac 9-22 记录一致：8 步全部通过（行走、种地无种子提示、买种子、
翻土 / 播种 / 浇水、切回行走不种地），13 次触控，`passed: true`。
产物在 `output/farm-mode-2026-09-22/android/`（`result.json`、每步的 png 和 json）。

### 其他场景

`tools/dev/` 下还有 `fishing_android_qa.mjs`、`equipment_android_qa.mjs`、
`private_farm_android_qa.mjs` 等，每个都对应一个 `prepare_*.gd` 和一个
`server/tools/*_qa_server.ts`。照上面同样的四步跑；运行前先读脚本开头，确认它要的包名、
夹具路径和 `output/` 批次目录，缺的夹具从 Mac 同一路径拉。

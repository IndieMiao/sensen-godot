# 真机 QA 流程步行器与首轮真机复核 —— 记录（2026-09-07）

## 1. 起因

用户反馈「启动 app 就卡住」。从 iPhone 拉回 `Documents/first_run.json`：`age_gate_blocked: true`——年龄门曾判定
未满 13 岁（年份列表从当年往前排，最上面一项就是当年，误点即 0 岁），之后每次启动都停在拦截页。
这是 COPPA 中立年龄门的设计，但对测试等于死锁。

## 2. 做了什么

- 拦截页在 debug 构建里加「Dev: reset age gate」（`age_gate_page.gd`）；选完日期即清掉「请选完整生日」提示。
- `modules/app/qa_flow.gd`：无人值守步行器。启动参数 `--qa-flow=social` 或环境变量 `SENSEN_QA_FLOW=social`
  触发，AppRouter 在非测试进程里挂上；走 年龄门 → 同意 → 登录（Dev）→ 四 Tab → 设置 → 探针页 → 切语言
  → 切回 → 登出，每步截图到 `user://qa/NN_name.png` 并写 `report.json`（场景、栈顶、locale、耗时、错误）。
  走的是页面真正的处理函数，不模拟触控（模拟器 / 真机都无法从外部注入触控）。
- 导出排除 `server/*`（此前 node_modules 被打进 pck，38 MB → 29 MB）。
- 真机截图暴露并修掉四处：触屏平台不再设按钮 tooltip（内部注记画在左上角）；LineEdit 补主题样式
  （原为引擎默认深色）；壳内页面不再叠第二层安全区（Tab 页标题比压栈页低 40 px）；设置页语言按钮
  图标压字（建按钮时文字为空导致图标居中）。
- `tools/i18n/check_glyphs.gd`：检查主题字体覆盖 zh_CN.po 全部字符（当前 0 缺字）。

## 3. 怎么跑

```bash
# 导出 + 真机构建 + 安装 + 带环境变量启动（个人团队签名，bundle com.sensen.mapg3）
godot --headless --path . --export-debug iOS build/ios/sensen.ipa
xcodebuild -project build/ios/sensen.xcodeproj -scheme sensen -configuration Debug -sdk iphoneos \
  -destination "id=<UDID>" -allowProvisioningUpdates DEVELOPMENT_TEAM=53LT77CV6R -derivedDataPath build/ios/derived build
xcrun devicectl device install app --device <UDID> build/ios/derived/Build/Products/Debug-iphoneos/sensen.app
xcrun devicectl device process launch --terminate-existing --device <UDID> \
  --environment-variables '{"SENSEN_QA_FLOW":"social"}' com.sensen.mapg3
# 约 10 秒后拉回报告与截图
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer --domain-identifier com.sensen.mapg3 \
  --source Documents/qa/report.json --destination /tmp/report.json
```

模拟器：本机 4.7.2 导出模板的模拟器切片只有 x86_64（目录名叫 arm64_x86_64 但归档是单架构），
iOS 26 模拟器运行时不再接受 x86_64 应用，所以模拟器路线走不通；要走得自己编 arm64 模拟器模板。
真机路线不受影响。

## 4. 结果

两轮各 15 步、0 错误、约 9 秒。截图在 `~/Downloads/sensen-qa-2026-09-07/`。
探针页可达；PAUSED / RESUMED 计数仍需人手切后台（步行器不能把应用切到后台）。

## 5. 用「iPhone 镜像」从 Mac 上操作真机（2026-09-07 验证）

前提：iPhone 与 Mac 同一 Apple 账户，Wi‑Fi + 蓝牙开；「系统设置 → 隐私与安全性 → 辅助功能」给运行
Claude Code 的终端授权；`brew install cliclick`。

- 找窗口：`CGWindowListCopyWindowInfo`（/tmp/winlist.swift 那种小脚本）拿「iPhone镜像」窗口的 bounds；
  截图 `screencapture -x -R x,y,w,h`（`-l <windowid>` 对这个窗口无效）。
- **坐标坑**：从 Read 工具看到的缩略图是 ~275 px 宽，不是 600；按缩略图坐标算出来的点要经两点校准
  的线性映射再交给 cliclick（本次得到 `T = 0.46·R + (1081,125)`）。校准方法：`cliclick m:` 移到已知点，
  `screencapture -C` 带光标截图看落点。
- 切后台：⌘1（主屏）；回前台用 `xcrun devicectl device process launch <bundle>`（不带 `--terminate-existing`
  会把后台进程唤到前台）。**不要用 Spotlight 点搜索结果**：国行输入法的候选栏和结果排布会变，
  两次点到了 Safari 和地图。
- 镜像期间 Mac 键盘算硬件键盘，iOS 不弹软键盘——键盘相关验证要在手机上手点。
- 国行 iOS 首次联网会弹「允许使用无线数据」，需要点一次。

## 6. 真机端到端互聊（M2 alpha）：局域网服务 + 桌面实例 + 真机（2026-09-07）

目标：手机与桌面各登一个 Firebase QA 账号，通过本机起的服务互发一句文本，顺带看聊天页底部输入框的键盘避让。

### 6.1 各端怎么指到同一台服务

- 本机起服务：`cd server && env $(cat .env 里的变量) PORT=3101 NODE_USE_ENV_PROXY=1 pnpm exec tsx src/index.ts`
  （`NODE_USE_ENV_PROXY=1` 才会走 HTTPS_PROXY 去拉 Google JWKS；`healthz` 在 `/v1/healthz`）。
- 桌面实例：`SENSEN_SERVER_BASE=http://127.0.0.1:3101/v1`（`Net.base_url()` 先看这个环境变量）。
- 真机：`devicectl device copy to` 写 `Documents/server.txt` = `http://<Mac 局域网 IP>:3101/v1`（`user://server.txt`）。
- 真机走明文 http 要两把 Info.plist 钥匙（导出预设 `additional_plist_content`）：
  `NSAppTransportSecurity/NSAllowsLocalNetworking`（ATS 放行局域网），`NSLocalNetworkUsageDescription`
  （iOS 14+ 本地网络权限；没这项 connect() 直接 EHOSTUNREACH，Godot 报 `request failed: 25`）。
  **发布前要从预设里拿掉这两项**（记在 R 发布链）。

### 6.2 真机连 Firebase：国内网络要经 Mac 的代理

Godot 的 HTTPRequest 不读 iOS 系统代理；国内直连 googleapis 超时（`transport error: 13`）。客户端本来就按
`HTTPS_PROXY` / `NO_PROXY` 环境变量走代理（api_client.gd `env_proxy_for`），而 `devicectl launch
--environment-variables` 能给真机进程塞环境变量，所以不用改代码：

- FlClash 只监听 `127.0.0.1:7890`，用 `tools/dev/proxy_relay.py 7891` 把它转到局域网口；
- 启动真机时带 `"HTTPS_PROXY":"http://<Mac IP>:7891","NO_PROXY":"<Mac IP>"`（自家服务不走代理）。

### 6.3 login 流

`SENSEN_QA_FLOW=login SENSEN_QA_LOGIN=email:password [SENSEN_QA_DM=@handle] [SENSEN_QA_SAY=文字]`：
真实 Firebase 密码登录 → `POST /v1/auth/firebase` 绑服务端 user → 连 IM WebSocket → 进壳 IM 页 →
按 handle 开单聊 → 发一句；`SENSEN_QA_PHOTO=<路径>` 再把这张图当选中的发成图片消息（不弹系统选图器）；
截图 `im_tab / chat_open / chat_sent / photo_sent`，report.json 同 §3。
QA 账号：qa-alice@sensen.test（handle alice）、qa-bob@sensen.test（handle bob）。

### 6.4 构建侧的两个坑

- xcodebuild 用 Xcode GUI 同一份 DerivedData 会卡死；命令行构建单独给 `-derivedDataPath build/ios/derived-cli`。
- codesign 第一次从终端签名会弹「钥匙串」密码框（进程里看到 SecurityAgent），要在图形界面输密码并点
  **始终允许**，否则命令行构建在 codesign 一步无限等。

### 6.5 结果（2026-09-07 20:55）

桌面 bob 发「hello from mac」→ 手机 alice 开单聊时历史已有 → 回「hello from iphone」→ 桌面 bob 页面
经 WebSocket 即时收到。两端 login 流各 3 步、0 错误；截图在 `~/Downloads/sensen-qa-2026-09-07/e2e/`。
键盘避让要在手机上手点（镜像不弹软键盘），见 §6.6。

### 6.6 要手点的验证：SENSEN_QA_WATCH 观察窗

镜像不弹软键盘、devicectl 拿不到屏幕，所以键盘弹起这类验证只能人在手机上点。步行器加了观察窗：
`SENSEN_QA_WATCH=<秒>` 让流程跑完后每 3 秒补拍一张（`watch_NN.png`，同样进 report.json），人在这段
时间里点输入框，拉回截图看视口有没有按预期上移（iOS 键盘是系统层，不在视口截图里；看到的是
输入框位置变化 + 下方留白）。例：

```
xcrun devicectl device process launch --terminate-existing \
  --environment-variables '{"SENSEN_QA_FLOW":"login","SENSEN_QA_LOGIN":"qa-alice@sensen.test:…",
  "SENSEN_QA_DM":"@bob","SENSEN_QA_WATCH":"60","HTTPS_PROXY":"http://<Mac IP>:7891","NO_PROXY":"<Mac IP>"}' \
  --device <UDID> com.sensen.mapg3
```

截图改用 `RenderingServer.force_draw()` 同步出帧：等 `frame_post_draw` 在被遮挡的窗口（测试进程）里永远不来。

**首轮观察窗结果（21:06–21:16）**：47 张补拍分成两组——点输入框前 25 张一样，键盘弹起后 22 张一样；
弹起后整页上移约一个键盘高，标题「QA bob」和两条消息都被推出屏幕，只剩输入框（截图在
`~/Downloads/sensen-qa-2026-09-07/e2e/iphone-alice-keyboard/`）。这是 SHIFT 模式对聊天页的错误形态：
改成 KeyboardAvoider.Mode.SHRINK（收 SafeArea 底边，列表变矮、输入框上浮、标题不动），26bf205。

**第二轮（21:12–21:22，SHRINK）**：布局对了——标题「QA bob」和两条消息留在原位，输入框浮在键盘上方
（`keyboard_up_shrink_v1.png`）；但用户反馈输入框一直抖。原因：容器重排把子节点吸附到整像素，
浮点位移与量回来的底边互相追着改，每帧在两个值间跳（测试用真 MarginContainer + VBoxContainer 复现，
位移 405.13 → 每帧漂）。位移 ceil 到整像素 + 亚像素差不反馈，bc8841b。

**第三轮（21:24–，取整后）**：按 report.json 顺序分组，键盘弹起前 147 帧一样，弹起过渡 2 帧，之后连续 8 帧
（24 s）逐字节相同——不抖了。用户顺手用中文输入法发了「弟弟的姐姐」并在输入框里打「大家都开心」，
CJK 字形正常、气泡在标题下正常排布（`keyboard_up_shrink_v2.png`）。A5 键盘避让在聊天页收口。

## 7. 2026-09-08 新增钩子

- `SENSEN_QA_ME=1`：登录后先进「我的」页拉资料（顺带 B7 装扮同步）截 `me_tab`；`SENSEN_QA_FOLLOWERS=1` 再压栈自己的关注者列表截 `followers`。
- `SENSEN_QA_MAP=1`：进地图 Tab 等角色装配后截 `map_tab`；`SENSEN_QA_FAKE_LOCATION=lat,lng` 模拟一次定位（桌面没有 GPS）并走真实上报路径。
- `SENSEN_PORTRAIT_DEBUG=1`：头像离屏渲染图落到 `user://qa/portrait_NN.png`。
- iOS 带 Mapbox 的工程用 `tools/ios/setup_ios_g3.sh` 出（导出 + 注入 Swift / SPM），再按 §6 的 `xcodebuild -derivedDataPath build/ios/derived-cli` 构建；worktree 里要有 `mapbox_token.txt`（gitignored，从主检出拷）。


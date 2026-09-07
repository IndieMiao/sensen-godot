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

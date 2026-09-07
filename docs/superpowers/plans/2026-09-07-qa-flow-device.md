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

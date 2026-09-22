# 0.11.0 UI / 美术截图交接

2026-09-16 用户要求当前版本各界面截图并附文字，滚动界面完整，用于转交 UI / 美术设计。

- 基线：Journey 0.11.0 / 2026091607 的生产界面代码；截图过程中未修改生产 UI。
- 独立 `com.sensen.uihandoff` 展示应用在 Android emulator-5560 渲染；所有采集场景按 `tools/android/run_test.sh` 执行，退出后停止应用并保留模拟器与原有存档。
- 138 个页面与主要状态：118 个主流程/系统状态、20 个旧存档与内部工具附录。涵盖城市、地图/选址、换装、农场/摊位、背包/装备/委托、三处地点、聚会、拜访、五层矿井、组队与语音。
- 原始手机截图 720×1560。56 处滚动内容逐段截图，按实际偏移拼接，校验从零覆盖至末端无缺段。横向列表另有完整横条；首屏、内容裁图与固定页头/页尾各保留一次的长图分别保存。
- 非自然游玩状态使用展示数据，实际绘制仍来自当前组件。语音人数和发言人为 UI 展示，未录音/通话。Android 麦克风授权为真实系统弹窗，测试应用名不同，已标注系统流程参考。
- 旧存档兼容和内部导演工具单列附录，避免当成新玩家主流程。开发压力测试、性能探针和工具页面不列为玩家界面；不穷举每个数值、逐句对话或同构道具变化。
- 已检查整套截图缩略图、长图样例和 PDF 全部页面缩略图；修正展示数据未解锁聚会、装备筛选选中态与离线示例后补拍。PDF 封面文字重叠已修正并重新渲染检查。
- 232 页 PDF 含 138 个界面首屏及完整滚动内容续页。离线 HTML 可搜索；CSV/JSON 有入口、说明、状态与代码定位。

交付：

- `output/ui-handoff-2026-09-16/Sensen-0.11.0-UI美术交接.zip`：唯一交接压缩包。
- `output/pdf/sensen-0.11.0-ui-handoff.pdf`：可单独转发的 PDF。
- `output/ui-handoff-2026-09-16/Sensen-0.11.0-UI设计交接/index.html`：离线图册入口。
- `output/ui-handoff-2026-09-16/delivery-verification.json`：文件、数量、ZIP 完整性校验。

复用工具：`tools/dev/ui_handoff_capture.gd`、`ui_handoff_android.mjs`、`tools/art/build_ui_handoff.py`、`render_ui_handoff_pdf.py`、`verify_ui_handoff.py`。所有临时 APK、运行日志与隔离数据位于交接包以外。

## 飞书交付

用户于本轮明确要求发送到飞书。PDF 与完整 ZIP 已上传至用户自己的飞书云空间，并由 CLI bot 发往既有对话，消息读回验证包含两个链接。

- 消息 ID：`om_x100b659c661bc0a4dd4be8b1f3806d6`。
- [街角四季-0.11.0-界面图册.pdf](https://a91obh1e4d.feishu.cn/file/ZOxibApqMo6L8Hx2K0mc2L2Knyb)。
- [Sensen-0.11.0-UI美术交接.zip](https://a91obh1e4d.feishu.cn/file/D7LObYELGoDT7GxGh19cehpFnxh)。

# 钓鱼进度与失败反馈验证（2026-09-19）

依据 [产品契约](../product/fishing-feedback-2026-09-19.md)，本轮版本按用户要求使用 **0.16.1 / 2026091902**。保持原 Journey 包名与签名，服务端 domain 24 / content 38e6db02b26b8b43 不变。

已完成的检查：

- Godot 原生渲染：13 项钓鱼测试全部通过，无脚本错误、失败或孤儿节点。覆盖原有按压／动作／自由岸边／远端表现，以及待结算逃鱼、取消请求失败、错过咬钩、会话消失和重连不得误展示旧鱼获。
- UI 进度条由 4→14 逻辑像素，最多六组加减反馈，约 0.72 秒淡出；顶端百分比；提示位于安全区域上部约 23%；按钮底部间隔为 48–74 像素。
- Android 模拟器真实触控完整场景通过：错过咬钩、主动让鱼逃脱、再次抛竿并钓获、退出恢复场景。22 次按压事件；两个失败结果均未增鱼，成功增加一条，采集到「＋／−」两类飘字。
- 画面检查修复了失败提示末尾引号独占一行的问题，改成两行短句。该文案修正和本次抛竿序号恢复检查包含在后续真机构建中。

本轮的失败测试使用普通触控让绿条远离鱼，不假设松手不操作必然失败：部分普通鱼轨迹可能恰好留在底部绿条内而被钓获。未修改难度或鱼获规则来满足测试。

截图、录像、构建与安装回执位于 `output/fishing-feedback-2026-09-19/`；独立模拟器账号与真机原账号分别验证。真机上的临时观察器只读场景树和状态以获取触控边界，最终交付包移除观察器。

## 真机与发布

V2509A (`10AFAF162200319`) 通过同一套完整普通触控流程，含 10 次收线按压变化；原长发外观下已检查顶部提示、按钮上移、加宽进度和加减飘字。错过咬钩与逃鱼均有明确说明、均不增加背包；重试成功后新增一条鱼。原公网存档 v228→v236，47 个原田地条目与库存、钱包保持一致；五份身份／选择／外观文件逐字节相同。

移除只读观察器后重新导出同版本正式包，覆盖安装到 V2509A；正常城市／地图／农场入口冷启动通过，无脚本错误。拉回手机安装包，哈希与下述发布文件一致，原公网存档与试玩结束快照一致。

- 版本：`0.16.1` / `2026091902`。
- 包名：`com.sensen.journeypreview`；唯一用户交付 APK。
- 文件：`152086313` bytes；SHA-256 `288e80703febbe069b86ffbf794a55d21a2307a705818933aef553fa58659aca`。
- 签名 SHA-256：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`，与原 Journey 更新链一致。
- [美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/fishing-feedback-20260919-288e80703feb/sensen-journey-fishing-0.16.1.apk) · [OSS 备用](https://oss.sensenjoy.cn/farm/releases/fishing-feedback-20260919-288e80703feb/sensen-journey-fishing-0.16.1.apk)。两处均完成 HTTPS 全量下载、哈希与 Range 206 指定片段校验。
- 服务端规则、数据版本和运行服务不变，本轮无数据库迁移。

关键证据：`device/missed-bite.png`、`device/fish-escaped.png`、`device/progress-increasing.png`、`device/fishing-feedback.mp4`、`device/result.json`、`device/final-smoke.json`、`release/download/verification.json`，均位于上述 output 目录。模拟器验证使用独立账号；未把自动控制脚本视作自然玩家的难度／经济接受度验证，SGODOT-129 保留该观察范围。

新 APK 已[通过 Slack 发给 Joey](https://gensenapp.slack.com/archives/D0C1MHLA3GQ/p1789786525989639)并回读验证两个下载地址；SGODOT-129 评论 `09f34c6d-168a-420c-bd95-12298460dbf6` 已追加本轮证据。回执见 `output/fishing-feedback-2026-09-19/delivery/receipt.json`。

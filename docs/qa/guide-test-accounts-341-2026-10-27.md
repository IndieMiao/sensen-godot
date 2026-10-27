# SGODOT-341：0.2.12 隐藏测试号与主号保留

依据：奕星批准 B 方案；不知火舞定版 `aa0e971b`（取代 `82593a7b` 的首次建家时机与旧文案）。普通客户端默认只发 `choose_home`，不发 `guide`。隐藏开关只让之后新建的独立测试号在首读前声明 `guide_v3`，不修改现有主号/测试号的引导进度。

## 实现与身份边界

- Settings 的 Version 行外观不变。3 秒内连点 7 次，再长按 2 秒才打开 Test options；中途无计数、Toast 或样式反馈。滚动、短按、超时、失焦取消手势。
- 子页沿用 Settings/SettingRow/CommandButton：New-player guide / For new test accounts；Current account Main/Test；Start new test account；测试号多 Return to main account。新建须确认，返回不确认。只有测试号的 Version 后加 ` · Test`，HUD 不加内容。
- `p0_player.txt` 始终为主号凭据。首次新建测试号前，将原始字节写到 `p0_main_identity.backup`，flush 后读回一致才允许切换；有不同备份或写入失败时拒绝切换，不覆盖身份。
- `p0_test_options.json` 仅记录设备开关、当前测试 id、该 id 创建时的引导选项与主号外观存储 key。原子写入成功后才重启运行时。测试 id 为 `g3test-` 加随机 32 位十六进制，便于识别；每次确认新建才换 id，不在切开关时建号。
- 测试号的 tips/quickbar 位于独立的 `p0_test_accounts/<id>/`，外观按测试 id 存储。返回主号读取原身份与原偏好，不把测试状态写回原文件，也不恢复历史服务器存档。缺失的主身份文件可由已验证的备份恢复；已有不同文件不覆盖。
- 切换先等当前命令队列结束，再丢弃旧场景/运行时、重新读服务器。旧回包不能覆盖新账号。没有调用任何服务器 reset/迁移接口。
- 普通账号保持 legacy；未来完整引导通过验收后才由最后一笔启用 `GUIDE_V3_READY`。本轮不改服务端。

周瑜审阅跟进：`guide_not_now` 静默，后续建家命令继续用回包 seq；打开的 Today 最多约 4Hz 重算；进度按不知火舞确认用 ` · ` 拼入正文并清空显示副本的 tail。

## 自动回归

- 身份/设备开关/重启保留/备份失败/身份冲突/丢失文件恢复/隐藏手势/子页内容：新增 9 条。
- Today 4Hz 与进度、Show 节点/目标保持：相应回归通过。
- 最终 `tests/p0 + tests/ui_kit`：**1761 条，178 suites，0 errors/failures/skipped/orphans**，`reports/report_840/results.xml`。
- 最终代码核心提交 `735b6506`；没有 `--import` / `--editor`、生产迁移或用户手机操作。

## 真实本地 HTTP 往返

独立桌面用户目录 `gensen-liubang-341-test-options`，本地 `127.0.0.1:3184` 的隔离 PR-C-s2 服务；代码快照记录在 `output/liubang-341-test-options/service-source.txt`，服务器存档独立保存在同目录。不是线上服务，也不是用户主号。

实际通过 UI 执行：主号 legacy → 隐藏手势 → 开启开关 → 确认新建 → 测试号首读进入引导 → 选城/建家 → 隐藏页 Return to main account → 原主号。主身份与备份逐字节一致；返回时主号金币、背包、田格、农场坐标一致。没有脚本替换服务器存档。

## Android 覆盖安装

使用独立 AVD `Liubang_Guide_341`、`emulator-5618`、ADB 5083、包 `com.sensen.guide341qa`；启动私有 ADB 前只读确认没有 USB 手机，ADB 还启用了禁止 USB 的设备过滤与 `ADB_LOCAL_TRANSPORT_MAX_PORT=5553`。

1. QA 版 `341001 / 341-qa.1`：原主号进入 legacy，用户流程新建 `g3test-` 测试号，引导/独立外观 key/独立 UI 路径全部确认。
2. 留在测试号，使用 `install --no-incremental -r` 覆盖安装 `341002 / 341-qa.2`，不卸载、不清数据。
3. 冷启动仍是原测试号，引导状态保留；主身份文件及备份的哈希与安装前相同。
4. 在新版中 Return to main account，回到原主号；金币、背包、田格、农场坐标一致。
5. 最后由 Android 原生 `input tap` / `input swipe` 注入完整隐藏手势，确实打开 Test options。

两版均验签，同一签名；安装后完整 APK 读回与各自构建产物相同。6 份核心 GDScript 与提交 `735b6506` 逐字节相同。QA 使用官方 Android 模板与隔离服务，验证账号/文件持久化和界面输入，不宣称地图插件、语音或用户真机验收。

排障记录：增量安装工具曾报告成功但包不可见，后改为流式安装；第一轮 QA 注入坐标误用了桌面比例，修正测试驱动后重跑完整 341001→341002。失败轮次不作为验收。导出曾改写共用的类缓存，已让各 QA 项目独占类/UID/编辑器缓存，只复用导入资源，并恢复 FakeTransport 测试索引；最终全量通过。无账号切换的桌面对照也有相同 5 个 RefCounted 退出警告，未随切换增加。

## 审阅材料与待决事项

材料均在 [SGODOT-341](https://plane.sensenjoy.cn/zili/browse/SGODOT-341/)，刘邦署名：

- `0e972321`：主号 Off 页、测试号 On 页、新建确认卡、Version Test/返回 Main 两张，约 4 秒完整隐藏手势视频。灰圆为 QA 输入指示，不是游戏中途反馈。
- `b1fde743`：覆盖安装后 Test/返回 Main 两张 Android 图、全部布尔检查报告。
- 本地文件：`output/liubang-341-test-options/`。系统桌面排障截图仅留本地，未上传。

测试号停在选城根页或启动失败页时，尚未有 Settings 入口可直接返回主号。已在 `707c07db` 请求不知火舞确认只对测试号开放系统返回键进入既有 Test options 的方案；未擅自改变这条流程。正常建家后的返回与覆盖安装返回均已验证。#495 尚未合入时保留现有 home flow；若后合 #505，按周瑜说明将确认前 ack 移到 HOME-PIN-CONFIRM 的 move_pressed 回调并复测。

合入前仍需周瑜复审、不知火舞走查、李白记录 q 文案与用户看图。所有自己启动的 Godot、3184 服务、模拟器和私有 ADB 已关闭；AVD 数据及材料保留。

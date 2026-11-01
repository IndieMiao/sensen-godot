# 355 第一批 A 客户端契约接入

以下早期记录保留作历史；当前实现与验收范围以末节“HOME-1 走查返修”及最新 PR 评论为准。

本轮是开发草稿，PR 只面向 `feat/355-b1`，由亚瑟审；**不是 farm-dev 发版变更**。按哪吒 11-02 的 `355-b1-A-view-contract.md` 和 `355-b1-A-client-checklist-liubang.md` 实现，v4q(1) 初稿 `28d1c01b` 尚待批准/校准。A1/A2 帧及缺口/满级/解锁正式文案未到，使用清单占位文案与现有组件。

从farm-dev `ade61b9b`开工，集成分支建立后rebase到 `bc558130`；range-diff确认功能补丁 `dd68b0ee` 与 `b640f3ca` 等价。新基线包含怪物接口，不由本PR实现F/G。

## 已实现

- HOME-1 按 `next.skills[]` 显示 Farming/Fishing/Cooking 各自需求，只有表中出现的项才显示；`next.travel` 非空时增加 Stamps/Other climates。顺序保持材料、金币、技能、出门。现有 NEED-TILE HFlow 自动换行，不提前制作新面板样式。
- 按当前面板的第一个缺口写按钮；服务器 `skills_short {skill,need,have}` / `travel_short {kind,need,have}` 的后备提示使用相同格式。来源项的 Skills 导航沿既有技能页与 Back 返回，出门项 Show 打开地图，不移动角色。
- `homestead.max`（缺省时读内容表max_level）控制满级与Decor满级提示，不把10或17写进判断。`next == null` 且到达上限时写 `Max level for now`，无升级按钮。
- `next.energy_gain` 控制升级页脚，正数显示+N，0不显示；HOME-2只显示事件 `energy` 的实得正值，0或缺字段省略，不再按等级推断 Energy full。
- 田数只读 `homestead.plots.now` / `next.plots`；增长时显示 Fields N / +N to till，不从等级推算，不处理新档网格。
- 背包四档名字/价格/容量从内容表bag_upgrades读取；新表没合前仍显示基线表的价格。假view测试会覆盖60/150/300/600及其它值，不把设计初值写进产品逻辑。
- 补新解锁id，移除old_tree、clay_bank、plots_40/48展示；city_gather、pip_first_dive、stall_upgrade、travel_gates保持无行。third_stove的说明为three dishes at once，避免提前承诺之后才解锁的保温柜12份。

图标占位：healing_potion用star、vein_mines用stone、decor_set_1/2用wood；sword/stamp已有。数字写进名称的orchard_10/sprinklers_12等按契约给出的语义id占位，若后续id/容量口径变化由协议同步，不自行推导新上限。没有新增图标或修改主题。

## 验证方法

新 `test_p1_home_contract_355.gd` 使用本地假view，未占用哪吒计划提供的 `tests/p0/fixtures/home_view_355.json` 路径。覆盖技能/出门格顺序及每类缺口、可省略门槛、动态田数/收益、Lv17满级和改为19的上限、四档可变价格、解锁/隐藏行、Today仍只管Lv1–2、16格窄屏换行、Skills往返和出门Show、服务器拒绝码。

已有HOME/Today/Looks/Profile/快熟作物回归的skills fixture迁到数组，过时Energy full及农场采集点解锁期望按本契约更新；未改变其它采集/网格/厨房玩法测试。基线内容文件及服务端没有修改，内容变更后的联调须等哪吒服务端分支。

本地已有类缓存缺最新ExternalLink/P0NotifyIOS，只用 --script 补对应本地索引；未用 --editor/--import，也没有启动ADB。首次新导航测试误用Close而非Back，已按既有返回导航语义修正。新测试带原生ResourceUID生成的.uid。

最终 `tests/p0 + tests/ui_kit` **2080/2080，206组，0 errors/failures/flaky/skipped/orphans，exit0（report_904）**；新增契约测试9条，含Home原始返回目标的保留。日志 `output/liubang-355-a/full-delivery.log`。首轮全量的导航测试失败已由最终全量覆盖，不将首轮记为通过；report_903的2079是补返回链回归前的阶段结果。

rebase后的集成基线再跑全量：**2087/2087、207组、0 errors/failures/flaky/skipped/orphans、exit0（report_905）**，包含上游新增7条怪物接口回归，日志 `output/liubang-355-a/rebased-full.log`。之后仅更新说明与过时注释，没有修改执行逻辑。

## 截图说明

`output/liubang-355-a` 的截图是**假view驱动实际Godot UI的功能证据，不是已批准的A1/A2帧或真实服务端联调**。独立userdir `gensen-liubang-355-a`，P0 transport替身，无线上调用；复用农场背景只是显示环境，不代表新网格/采集搬出已经实现。画面中的数值仅为r9/契约示例，实际代码只读view/内容表。

覆盖Lv5/15/16/17 HOME-1及滚动到底、满级隐藏按钮、HOME-2实得+50/+17/0。A1/A2的技能/出门分组样式与最终文案等不知火舞/安其拉定稿后再对齐，不把当前截图作为设计验收完成。

最终10张功能截图、假view模型JSON和测试摘要上传355；截图进程正常退出，测试均结束，无本人后台服务或Godot进程留存。

待项：v4q(1)批准与校准内容、哪吒服务端实际view联调、A1/A2帧及正式文案、占位图标确认。不得据本草稿单独上线，不合farm-dev、不改存档/最低版本；集成分支min_version与清档由对应负责人处理。

## 亚瑟审核后三项对齐

按355 af674e41及不知火舞7d9aa825：田数行为 `Plots N · now M`，不承诺翻土；满级用中性灰 `Highest level for now`；暂不显示vein_mines/iron_sword，回血药healing_potion和potion_heal两个id都识别。HOME-1/HOME-2与隐藏解锁回归同步。

已rebase到集成分支 **3592ace2**（含v7骨架）；为遵守不强推规则，用无内容变化的merge保留原发布头b64029bc为祖先，后续普通快进推送。树内容与rebase结果26f43143一致，工作头8a6f865f。新基线全量 **2079/2079、206组、0 errors/failures/flaky/skipped/orphans、exit0，report914**；测试数因上游移除旧换料用例变化，不是跳测。

返修图使用Lv1/8/16/17、Lv15实得+50、Lv16不回体力、Lv1 Today材料行，仍是假view功能实拍。设计提出的Lv9 Today技能缺口行与A清单“只管Lv1–2，先不扩”的范围冲突，已在355 b09101d6请求确认，未伪造该行或自行扩范围。布局继续使用已测的现有自动换行组件，正式帧分组样式待走查反馈。

## HOME-1 走查返修

355 `85a4af12`、奕星 `23ef600e` 明确本轮五处与 Lv8 Today，覆盖之前的占位口径。依据 v4q(1) `e53c18c9`、A1 `310:179667` / A2 `311:180478`：

- 页脚只写 `Upgrading is free of Energy`，Energy 实得只进 HOME-2。
- 按钮及拒绝提示为 `Need Fishing Lv5` / `Need 3 more stamps` / `Need 1 more climate`；优先顺序技能、出门、材料、金币，展示格仍先材料和金币。
- `Climates` 使用正式 globe 图标；HOME 专用 NeedTile 子类将圆心固定四列，长标签按格宽缩小，技能和出门各起一组，不修改其它页面的 wrap 组件。
- Today 每级均读 next，技能/出门缺口也出，技能行去重；只 Upgrade 行亮红点，交付优先、追踪第三行保底和引导优先保持。旧/不完整 skills 字典无法确定新门槛时不出升级行。
- 对齐 b1 `33be4590`，已含 #624 网格、#628/#631 正式图标、#630 三种材料定义；不在客户端补原始 id 的硬编码名字。Decor 合并保留内容容量上限与动态 Homestead 等级上限。

定向 51/51；修后全量 2081/2081、206组、0 errors/failures/flaky/skipped/orphans（report_3），随后在材料/图标完整的集成基线上再验。截图仍由隔离假 view 驱动（userdir `gensen-liubang-355-a-review2`），名称从实际内容读取，数值是覆盖分支的测试示例，非真实服务端或生产数据。材料目录 `output/liubang-355-a-review2/media`，包括 Lv1/8/16/17、HOME-2 两态、Lv8 Today。

五处修改仍需不知火舞按新头复看；v4q 批准与真实 view 联调不由截图代替。PR 仅指向 feat/355-b1，不自合、不部署，不运行 editor/import。

材料/图标完整基线最终结果：**2081/2081、206组、0 errors/failures/flaky/skipped/orphans、exit0，report_4**，代码树586af950，之后仅更新本文。日志 `/tmp/liubang-355-a-review2-integrated.log`；未修改代码后重复跑测试。

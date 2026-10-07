# 新稿行 29 / 34 / 35 复核

2026-10-06。当前 Figma 行节点 `482:478 / 482:563 / 482:580`，使用 `get_screenshot(maxDimension=4000)` 捕获 3324×1080 原图，再按 4 卡裁成左右两片，24 卡均已逐张查看。这里只检查这三行，不重复 current 子任务已审的行 27 / 28。

图像、裁片和 SHA-256 保存在本目录。它们是**本次定点数据修复前**的当前云端截图，不能用作修复后的验收图。未点击原型；角色和业务跳转判断还参考当前生成数据与规则，未宣称真实 Figma reaction 回读或运行时状态持久化已测。

## 确定问题与本地修复

| 问题 | 证据 | 处理 |
|---|---|---|
| MINE-4 的 Floor 5 数据目标为 MINE-5，后者已击败精英并得到石英 2。到达不等于战斗结算。 | 行34左，MINE-4 `482:569` → MINE-5 `482:571`；§13.3.9。局内 Express 0 体力合法，错误在直接进入奖励结果。 | 主卡目标改 `MINE-5-ARRIVAL`。新增独立到达态，精英 Not defeated / Run in progress，不填未知敌方数值，不给奖励；MINE-5 只留画外独立结果审阅。 |
| MINE-5 的 Quartz 2 在正文和 Return to entrance 上方重复，容易误读为“返回时给予／消耗”。 | 行34左第4卡。 | 已结算 Quartz 改为普通结果 fact，仅正文显示一次。 |
| Resident meal 的 +20 在正文和 Accept 上方重复，且语义像“领取即恢复”。未显示实物去向与 04:00 前未吃失效。 | 行34右第4卡、行35左第1卡；§3.4.5 明确实物、可不吃、家城04:00失效。 | 本例固定为无保温柜且背包有空间：Veggie Plate×1 → Bag/Dishes；When eaten: Up to 20 Energy；Eat before 04:00 home time。前后 HUD 都142/200，领取不吃。 |
| Claim Done 回普通 Hana 初始面板，会再打开0/1可领取状态。 | RESIDENT-MEAL-DONE → RESIDENT-TALK → RESIDENT-MEAL。 | 新增 `RESIDENT-TALK-MEAL-CLAIMED`：今日1/1，Today’s meal只查看已领取态；Done返回该状态。 |
| 六张居民 Profile 都显示同一个普通头像；已有12个独立 res_* 候选主件。 | 行35左右的 Pip / Granny Wu / Mira / Old Kai / Rafa / Ivo。 | 对全部12个 RES-* 补显式 icon，绑定既有 res_* 主组件；不把这些候选头像升级宣称为已批准最终立绘。 |

定点改动主卡：MINE-4、MINE-5、RESIDENT-MEAL、RESIDENT-MEAL-DONE，以及12个RES-*。`current-all.json` 与分区12同步；原 84+204=288 主卡不增项。新状态单独置于 `data/flow-repair-states.json`；精确清单在 `data/flow-repair-report.json`。本地一致性检查通过，云端重建与新截图待主代理执行。

## 24 卡覆盖

| 卡 | 当前可见信息与结果 |
|---|---|
| SOC-2-ERROR | 无遮挡；Host unavailable、邀请剩余12:20和查看入口清楚。建议补“未花费任何资源”，见下。 |
| SOC-3 | 无遮挡；帮工1/2、Mia互关、自动浇收、补播Off清楚。缺真正任务开关／邀请对象选择，见下。 |
| HELPER-INBOX | 接收方语气、Alex农场、自动轮0体力、最多3农场与Accept/Not now清楚。源动作已是本角色局部接受反馈，不再跳离线结算。 |
| HELPER-SUMMARY | 已完成9格浇水、6萝卜与View farm清楚。仓库／包裹规则冲突仍在画外注释，不把它改成确定去向。 |
| HELPER-ONSITE | 谁付体力、谁出种子、每格2、36/40与13/15均可见；句子略重复。后继HUD未扣2的样例矛盾见下。 |
| HELPER-BUDGET | Host budget 15/15与琥珀Sow明确；免费收获提示应限定一年生，见下。 |
| SOC-5 | Mia收件人、所选鱼1与菜1、合计2件、今日1/3及Send gift均可见；符合§12.4.1。 |
| GIFT-SENT | 接收人、Sent、Inbox与24h领取时间清楚，无角色偷换。 |
| COMBAT-LOOT | 已获得铜1可见；随机示例注释放画外，没有把它写成必掉。 |
| COMBAT-HEAL | Potion Used与HP Full可见；符合§13.3.8药水回满HP，不是恢复Energy。 |
| MINE-4 | 6/6与Express Free可见；到达→击败的错误目标已本地修复。 |
| MINE-5 | 已击败、局完成、石英2可见；重复奖励已本地修复。 |
| MINE-KO | 未完成局保留、HP回满、Continue Free与Go home清楚；与精英完成是独立状态，不据相邻卡推断连续发生。 |
| RESIDENT-TALK | Hana、Familiar、52/90、Meal/Lesson入口与Chat语义清楚。 |
| RESIDENT-CHAT | 好感+2结果清楚；返回初始52/90是静态分镜局限，不能声称原型实现了日内持久化计数。 |
| RESIDENT-MEAL | 数量1可见；领取/吃的语义、去向、到期和重复20已本地修复。 |
| RESIDENT-MEAL-DONE | 领取1/1可见；回到已领Hana状态已本地修复。 |
| RESIDENT-TEACH | Tasted正确，但没有真正显示教会的菜名与原料；见下。 |
| RES-PIP | 名称、职业、52/90、Dessert可读；同脸已本地绑定res_pip。 |
| RES-GRANNY | 名称、职业、Soup可读；同脸已本地绑定res_granny_wu。 |
| RES-MIRA | 名称、职业、Rare or better可读；同脸已本地绑定res_mira。 |
| RES-KAI | 名称、职业、Grilled可读；同脸已本地绑定res_old_kai。 |
| RES-RAFA | 名称、职业、Soup可读；同脸已本地绑定res_rafa。 |
| RES-IVO | 名称、职业、Grilled可读；同脸已本地绑定res_ivo。 |

## 其余发现，未在本次定点修复中擅改

1. **Helpers配置不是完整可操作面板。** §12.3.4要求Water / Harvest / Replant三个开关；SOC-3只给状态文字。Invite helper是提交样式，但页面没有尚待邀请的选定对象。建议邀请入口先导航到选人，再对确定收件人提交；任务开关用真实控件，不能把状态文字算成交互完成。
2. **到场补播数值样例未对账。** HELPER-ONSITE是142体力、每格2、主人预算13/15，按Sow×1之后到HELPER-BUDGET的15/15合理，但HUD仍142，应为140（或不要把两个独立夹具直接当连续结算连线）。
3. **免费收获提示范围过宽。** HELPER-BUDGET的“You can still water and harvest”应为water and harvest annual crops；§12.3.1–3的多年生采摘仍需2体力并受15/40预算限制。
4. **失败邀请未明确未扣费。** SOC-2-ERROR只说主人不在线，未重申资源没有扣除；这是失败执行后关键结果，比重复邀请通用条件更值得显示。
5. **教学卡缺真正的新知识。** RESIDENT-TEACH说菜名和原料已揭示，却不展示它们；View Cookbook仍是通用目标。并非完全没有来源：§7.16.3给Hana可教22/38/39/46，§7.14第22页明确 Corn Cake、Corn×2、Fine、40 Energy、15秒、1次火候。可以把其中一页作为注明来源的示例，显示真实名称/原料并打开对应页；不能一面说revealed，一面只写“Hana’s recipe”。
6. **居民角色上下文的数据修复方向正确。** 当前RES-*动作是`context.resident`，不再全部跳Hana或Gifted玩家礼物页；这是生成数据检查，不是本轮实际点按证明。六张Favourite dishes仍统一用烤鱼图标；Dessert/Soup可改已有对应菜系图标以减少误读。
7. **Granny / Ivo的上海场景需明确语境。** 当前卡显示Shanghai · Outpost且Talk可用；§9.4城市例明确两者不在上海。如果这是实地交互，应换正确示例城市；如果是异地资料浏览，应表明远程状态并让交互先到场，不能把统一HUD当作居住规则。

本轮没有发现标题、数量、正文互相压住或关键操作被遮挡。这个结论不覆盖原型实际滚动、触控、服务器结算、读屏或其它行。

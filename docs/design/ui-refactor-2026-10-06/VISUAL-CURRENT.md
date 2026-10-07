# 当前204张流程卡：完整视觉审计

2026-10-06。本轮重新从 Figma 读取 07–12 六个分区，逐条检查 **36 条完整行、204 张当前卡**。所有截图来自本次审计，无旧缓存替代；没有写入 Figma。覆盖表与 SHA-256 在 `audit-evidence/current/coverage.json`。

结论：已有一致的奶油色、场景和图标体系；问题主要出在信息顺序、语义组件和状态表达。原稿中的标题/数量/状态混排、操作与查看同型、说明过小在六个分区均可见。本轮归一化已处理大部分文案层次，但视觉审计发现，单靠 JSON 重建会遗漏后期加到 Figma 的单件领取、火候环、失效后场景操作等内容，必须补充。

## 新增阻塞与明确边界

| 编号 | 严重性 | 证据 | 发现及所需处理 |
|---|---|---|---|
| V04 | 高 | 07-row-03 / 07-row-07 | TUT-3-11/12/END、COOK-P0-4 的 213/200 下 Bonus 叠写。HUD必须派生 recovering/full/bonus；满条与超上限不显示自然恢复倒计时。 |
| V05 | 高 | 07-row-07、07-row-12、10-row-06 | Experiment“已投入”与背包候选必须独立；COOK-P0-3、COOK-HERB-HEAT必须保留场景火候环。4/5槽保留槽位，未定原料不能自行填定。 |
| V06 | 高 | 08-row-01、08-row-05 | 洒水器3×3和温室4×4悬在建筑屋顶，不能证明实际占地或有效覆盖。重构稿应明确标为Coverage schematic，表现中心占地/周围8格与4×4，真实场景注册、碰撞锚点待运行场景验证。 |
| V07 | 高 | 07-row-10 | live PARCEL-1中Perch行有Claim，但原all-screens.json缺这一按钮。重构应保留单件领取；不得把种子点击接成“Perch已领”回执。 |
| V08 | 高 | 各Sheet右上×，尤其10-row-02 / 10-row-05 | 原稿通用×虽然只有约32px，但很多卡依赖它退出。新Sheet必须保留独立44px关闭入口；只有提交按钮的页面不能失去取消途径。 |
| V09 | 高 | 10-row-06 | GUESTBOOK没有可见选中标记，却有Post selected note。使用共享单选行，显式显示当前留言；未选择不可提交。 |
| V10 | 高 | 10-row-03 / 10-row-04 | SOC-2→SOC-2-INBOX切换了邀请方与城市；HELPER-INBOX→HELPER-SUMMARY跨了角色与离线时间。发送/接收/结算分镜应分开，不冒充同一玩家连续点击后的结果。 |
| V11 | 高 | 11-row-02 | Buff要在Energy附近常驻剩余时间/次数。live BUFF-LAST/TIMEOUT已是轻Toast并保留Cast/Sow；旧JSON的Continue不能被重构为强制Back，也不能丢场景操作。 |
| V12 | 中 | 09-row-03、07-row-05 | Arrived Tokyo与Shanghai HUD冲突；满包与当前局2/2并不意味着已开始局不可继续。状态卡应展示对应角色/地点/当前门禁，避免把独立夹具混排。 |
| V13 | 范围边界 | 08-row-01/03、12-row-01至05 | 高等级农场、实际多灶锚点、作战敌人、不同居民3D仍大量复用场景示意。这不妨碍共享UI重构，但不能作为新3D内容或运行场景验证完成。 |
| V14 | 规则边界 | 08-row-03、10-row-06、11-row-02 | Cook All实际批次扣料、共做需交量/奖励、4/5槽配方和临时容量到期仍有未定规则。确认区不能靠笼统“会用材料/会有奖励”通过验收。 |

既有问题 V01（标题混排）、V02（命令/导航/取消同型）、V03（正文与触区过小）见 `CURRENT-AUDIT.md` 和本轮组件约定。以上新增项需在本地实现中核对；即使本地构建通过，云端原稿仍是本报告截图所示状态。

## 证据来源

直接下载受 DNS 限制，随后使用 screenshot 工具允许的 base64 回包保存原 PNG；未改变系统代理。工具请求均为 `maxDimension=16000`，六张返回均未缩小。原图含Figma导出边缘40px；行裁切记录了精确坐标，没有对截图内容重绘或替换。

| 分区 | Figma节点 | 卡数 | 原图尺寸 | SHA-256 |
|---|---|---:|---|---|
| 07 | 396:2 | 73 | 2576×14080 | `e0742b7e472788006f835ef3f420f74705fc8d791e29b29d31b04732207f3958` |
| 08 | 430:14 | 30 | 2576×5120 | `2fd0e4bb57653aca23aeed579be1915ff64fcf4c9820f30992ba9abd0bb1b2b6` |
| 09 | 430:16 | 18 | 2576×3200 | `d1a28fd57fe7d1c7136a8c11ffaef049225b34b95c40dbd5388f4c86fe1c849b` |
| 10 | 438:3178 | 38 | 2576×7040 | `4ca63e7f58646842aaf35f6b8a74ab1e209923a7c51844e9c71fa84e6ce6fd5e` |
| 11 | 438:3180 | 12 | 2576×2240 | `9a8e4a7d2c160c96a3f770062dbc201f45dfac8d2186479a39243a9584f3d590` |
| 12 | 438:3182 | 33 | 2576×6080 | `3e3c83dc00a06f9eb831e98bec53cd88b74c55b4d5eef19defe97761c8313f5e` |

## 逐行检查记录

下表涵盖每张卡；每行图片完整保留该行所有卡和稿外注释。健康度均为“需重构”，不意味着每张卡都存在每一种问题。

| 步骤 | 完整截图 | 覆盖ID | 主要观察 |
|---:|---|---|---|
| 1 | [07 / 01](audit-evidence/current/07-row-01.png) | TUT-1, TUT-1-2, TUT-3-01, TUT-3-02, TUT-3-03, TUT-3-04 | 选城确认与信息入口均像执行；场景教学提示比HUD倒计时更易读。 |
| 2 | [07 / 02](audit-evidence/current/07-row-02.png) | TUT-3-05, TUT-3-06, TUT-3-06B, TUT-3-07A, TUT-3-07B, TUT-3-07C | 首鱼奖励/品质/剩余容量混在标题；Keep与Eat语义不分。 |
| 3 | [07 / 03](audit-evidence/current/07-row-03.png) | TUT-3-08, TUT-3-09, TUT-3-10, TUT-3-11, TUT-3-12, TUT-3-END | 213/200状态的Bonus与HUD下行叠写；升级奖励和下次目标可拆清楚。 |
| 4 | [07 / 04](audit-evidence/current/07-row-04.png) | MAT-1, MAT-2, MAT-3, MINE-P0-1, MINE-P0-2, MINE-P0-3 | 采集列表混入Ready/等级；Clay Bank弹层同时保留Timber计时；矿层进度与场景石头示意未同步。 |
| 5 | [07 / 05](audit-evidence/current/07-row-05.png) | MINE-P0-4, MINE-P0-5, MINE-P0-6, MINE-P0-7, MINE-P0-8, CRAFT-1 | 满包、日局数与日切规则合在同一失败卡；重开局需突出结束当前局。 |
| 6 | [07 / 06](audit-evidence/current/07-row-06.png) | CRAFT-2, CRAFT-3, CRAFT-4, GEAR-P0-1, GEAR-P0-2, HOME-P0-1 | 制作收益在底部小字；Gear虽恢复六槽，装备按钮与效果字号仍极小。 |
| 7 | [07 / 07](audit-evidence/current/07-row-07.png) | COOK-P0-1, COOK-P0-2, COOK-P0-3, COOK-P0-4, COOK-P0-5, COOK-P0-6 | Experiment选中材料挤成单一文本条；火候环必须保留原生控件；满包菜应保留同菜身份。 |
| 8 | [07 / 08](audit-evidence/current/07-row-08.png) | COOK-P0-7, COOK-P0-8, STORE-1, STORE-2, COOK-P0-9, COOK-P0-10 | 仓库选中Torch与网格值需保持同步；Cook Again费用/经验不能藏于按钮或细字。 |
| 9 | [07 / 09](audit-evidence/current/07-row-09.png) | BOARD-1, BOARD-2, BOARD-3, TODAY-1, TODAY-2, BAG-1-P0 | 委托完成/日限/下一份混排；Today三条可理解；Bag格子结构是后续复用锚点。 |
| 10 | [07 / 10](audit-evidence/current/07-row-10.png) | PARCEL-1, PARCEL-2, PARCEL-3, PARCEL-4, PARCEL-5, PARCEL-6 | live PARCEL-1第一条已有单件Claim，静态JSON漏记；期限/数量/来源混入标题。 |
| 11 | [07 / 11](audit-evidence/current/07-row-11.png) | PROFILE-1-P0, KEEP-P0-1, KEEP-P0-2, ENERGY-P0-1, COOK-KEEP-BRANCH, SAVE-RETRY | 换装无明显选中勾；低体力四件事需分开；保存失败应保留编辑和退出。 |
| 12 | [07 / 12](audit-evidence/current/07-row-12.png) | BOARD-DROPPED, COOK-HERB-HEAT, MAT-GLOVES-RESULT, FISH-P0-CAST, MINE-CONTINUE, BUILD-RETRY | 再做香草鱼有实际火候环；续局仍需显示4/6，不能由普通信息卡代替操作层。 |
| 13 | [07 / 13](audit-evidence/current/07-row-13.png) | PARCEL-ONE | 单件领取后清晰展示余下两包，但已领回执与待领列表使用同一信息行样式。 |
| 14 | [08 / 01](audit-evidence/current/08-row-01.png) | FAC-1, FAC-2, FAC-3, FAC-4, FAC-5, FAC-6 | 效果藏末尾；3×3范围悬在温室屋顶，无法证明真实覆盖；放置取消与预览同样描边。 |
| 15 | [08 / 02](audit-evidence/current/08-row-02.png) | TRAP-1, TRAP-2, TRAP-3, TRAP-4, TRAP-5, TRAP-6 | 鱼笼数量/容量/时长跨多行；返回整理后继续按钮是审阅快进；现场鱼笼锚点缺失。 |
| 16 | [08 / 03](audit-evidence/current/08-row-03.png) | COOK-P1-1, COOK-P1-2, COOK-P1-3, COOK-P1-4, COOK-P1-5, COOK-P1-6 | 多灶标签并未明确锚到各灶；排队材料/扣料待定；Cook All缺实际批次计划。 |
| 17 | [08 / 04](audit-evidence/current/08-row-04.png) | COOK-P1-7, COOK-P1-8, FAC-GH, TRAP-DONE, DEX-P1-1, DEX-P1-2 | Preview温室实际扣料应Craft；Lucky Double两份品质要独立；DEX-P1-1是五态说明非真实图鉴。 |
| 18 | [08 / 05](audit-evidence/current/08-row-05.png) | FAC-GH-PLACE, FAC-GH-DONE, DOUBLE-RESULT, FAC-LIMIT, TRAP-NOROOM, COOK-EMPTY | 4×4占地悬浮而未注册地块；双份菜数量与品质混标题；上限/满包用长按钮原因代替动词。 |
| 19 | [09 / 01](audit-evidence/current/09-row-01.png) | MAP-2-FREE, MAP-3-FREE, MAP-4-FREE, MAP-5-FREE, MAP-6-FREE, MAP-7-FREE | Browse/Travel/Fly形态无区别；大地图几乎无定位信息；落地首访奖励应独立。 |
| 20 | [09 / 02](audit-evidence/current/09-row-02.png) | MAP-8-FREE, LOCAL-FISH, LOCAL-CATCH, LOCAL-SHOP, LOCAL-TRADE, LOCAL-BOUGHT | 当前城市与所访地点基本有位置芯片；鱼种/XP与入口动作混排；当地购买与回家应区分。 |
| 21 | [09 / 03](audit-evidence/current/09-row-03.png) | HOME-RETURN, PASS-1, PASS-2, TRAVEL-RETRY, TRAVEL-RECONNECT, FOG-THREE | Passport进度层次不足；重连到达Tokyo但HUD仍Shanghai；三态解释页不应进入产品导航。 |
| 22 | [10 / 01](audit-evidence/current/10-row-01.png) | MAP-4-PAID, MAP-4-GATE, MAP-5-PAID, TRAVEL-GUIDE, TRAVEL-CANCEL, TRAVEL-REFUNDED | 出发40体力/200币/许可应常驻在确认区；取消退款应区别于保留旅程；在途可做/不可做不能压细字。 |
| 23 | [10 / 02](audit-evidence/current/10-row-02.png) | DAYPASS, DAYPASS-EXPIRED, PERMIT-1, PERMIT-DONE, TICKET-1, SECOND-HOME | 日票去向清楚但极小；证件成本占多域；第二故乡7日锁需成为确认后果。 |
| 24 | [10 / 03](audit-evidence/current/10-row-03.png) | SECOND-HOME-DONE, SOC-1, SOC-1-GATE, SOC-1-CONFIRM, SOC-2, SOC-2-INBOX | SOC-2发给Mia而下张变Mia邀请自己，发送/接收角色视角跳变；关系进度链接是快进。 |
| 25 | [10 / 04](audit-evidence/current/10-row-04.png) | SOC-2-ARRIVE, SOC-2-ERROR, SOC-3, HELPER-INBOX, HELPER-SUMMARY, HELPER-ONSITE | 帮工邀请接受后直接离线结算是时间/角色快进；补播必须明确谁付体力、谁供种子。 |
| 26 | [10 / 05](audit-evidence/current/10-row-05.png) | HELPER-BUDGET, SOC-5, GIFT-SENT, GIFT-CLAIM, GIFT-DETAIL, SOC-6 | 礼物两物品被挤一行；Gifted不可售是必要限制；访问与自己农场截图相同需保留对象身份。 |
| 27 | [10 / 06](audit-evidence/current/10-row-06.png) | GUESTBOOK, TOGETHER, TOGETHER-PROGRESS, TOGETHER-DONE, EXPAND-4, EXPAND-5 | 留言没有可见选中态却可Post；共做未给实需/实奖不得伪造；4/5槽必须保留独立槽位。 |
| 28 | [10 / 07](audit-evidence/current/10-row-07.png) | EXPAND-RECIPES, TRADER | 八配方名称成对挤标题；旅行商人当前据点与Show目标要一致。 |
| 29 | [11 / 01](audit-evidence/current/11-row-01.png) | BUFF-FARM, BUFF-FISH, BUFF-HANDS, BUFF-TRAVEL, BUFF-CREEL, BUFF-REPLACE | Buff效果、品质对应时长和替换损失应分层；查看当前Buff也被画为主执行按钮。 |
| 30 | [11 / 02](audit-evidence/current/11-row-02.png) | BUFF-ACTIVE, BUFF-CASTS, BUFF-LAST, BUFF-TIMEOUT, BUFF-RATIONS-USE, BUFF-CREEL-END | Buff常驻胶囊离Energy太远；live失效已改轻Toast+Cast/Sow，JSON未完全同步；临时容量到期仍未定。 |
| 31 | [12 / 01](audit-evidence/current/12-row-01.png) | HOME-LV4, HOME-LV5, HOME-LV6, HOME-LV7, HOME-LV8, HOME-LV9 | 等级后果文字清楚但不能以同一农场底图代表独立外观完成；容量数值混标题。 |
| 32 | [12 / 02](audit-evidence/current/12-row-02.png) | HOME-LV10, MINE-3, COMBAT-1, COMBAT-LOOT, COMBAT-HEAL, MINE-4 | 战斗HP/武器/药水需留在操作层；清层场景仍满岩石，是非运行状态美术示意。 |
| 33 | [12 / 03](audit-evidence/current/12-row-03.png) | MINE-5, MINE-KO, RESIDENT-TALK, RESIDENT-CHAT, RESIDENT-MEAL, RESIDENT-MEAL-DONE | 败退和Elite完成必须分支；居民赠餐日额度与XP区别需保留；实际敌人画面缺失。 |
| 34 | [12 / 04](audit-evidence/current/12-row-04.png) | RESIDENT-TEACH, RES-PIP, RES-GRANNY, RES-MIRA, RES-KAI, RES-RAFA | 五名居民有不同候选头像；会话不应跳成同一个Hana；场景共享不表示角色归属改变。 |
| 35 | [12 / 05](audit-evidence/current/12-row-05.png) | RES-IVO, RES-HANA, RES-SAM, RES-LENA, RES-TOMO, RES-THEO | 六名居民头像各异但信息层级重复且过小；职业/喜好/友情应独立。 |
| 36 | [12 / 06](audit-evidence/current/12-row-06.png) | RES-NADIA, DEX-MILESTONE, COOK-MILESTONE | Nadia同样需稳定身份；里程碑应区分已获奖励、下阶段门槛，避免领取与查看混淆。 |

## 不能从截图得出的结论

本审计没有点击线上原型，没有验证真实保存/交易、读取顺序、屏幕阅读器、键盘焦点、倒计时精度、手势冲突或真实设备触区。卡内字号和控件几何由可见截图与该分区只读元数据辅助判断；没有宣称WCAG全项通过。新的本地HTML和原生导入包属于另一个验收对象，必须分别记录检查，不能用这些旧云端截图代替新稿验收。

## 已落实的本地补充与后续验收

视觉审计后，V04–V11相关的HUD Full/Bonus、2–5材料槽、火候环、示意覆盖图、单件Claim、44px通用关闭、留言选中态、邀请视角分离、Buff胶囊/轻反馈/场景操作已补入当前数据和原生导入器。旧稿专有格子与Gear修正由独立适配器提供。`figma-plugin/local-validation.json`包含专项结构断言。该记录是本地结果，新的云端画面以主流程cloud记录的真实截图为准；原始六分区仍保持本报告证据内容。

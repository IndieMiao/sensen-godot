# P0 英文文案逐字核对清单（阶段 5 输入，SGODOT-235）

- 作者：李白（产品口径），2026-10-08；方案依据：`docs/product/gameplay-plan-v2-2026-10-02.md` §1.5 q(1)–q(51)。
- 用法：阶段 5 主要页面巡检时，逐页对照"应出现的文案"。**设计依据是 Figma 页面 14（LOCK-28）**；本清单列的是方案已定的文案，其中标 ★ 的条目是页面 14 画完之后才定的（q(44) 起），Figma 可能还没跟上——实现与 Figma 不一致时，先查本清单的 q 号：方案已定的以方案为准，并请设计补稿。
- 只列 P0 会出现的界面；P1 / P2（旅行、社交、Coast、碳素竿、鱼笼、亮片、洒水器、3–5 层与战斗）不列。

## 0. 通用规则

| 规则 | 说明 |
|---|---|
| 一律英文 | 玩家可见文案不出现中文（LOCK-23）；物品名 ≤ 18 字符 |
| Energy，不写 Stamina | 体力一律 `Energy` |
| 分隔符 | 半角空格 + `·` + 半角空格：`Cast · 5 Energy` |
| x/y = 已用 / 上限 | `Meals today 60/300`、`Mine runs today 1/2`、`0/3 today · 40 coins`（茶：已喝杯数，价格写下一杯，q(48)） |
| 主行动键 | 第一行动词，第二行体力价或原因；第二行 ≤ 80 px（约 16 字符），长原因进按下后的 toast（q(44)）；0 体力的移动写 `· Free` |
| 不写 Got it | Toast、TipCard、四件事卡都不写 `Got it`；点卡外 / 返回键关闭（q(26)、q(49)） |
| 缺口写在按钮上 | 中性灰不可用态，如 `Need 6 more Timber`、`Farming Lv3`、`No room · free a slot first`（LOCK-10） |
| 不做跳转 | `Show my plots` / `Show on map` / `Where to fish` 只移动相机或打开面板（LOCK-08）；`Where to fish` 所在的第一次变灰解释卡排 P1，P0 不出（q(98)） |
| 世界提示只写名字 | 设施挂图标钮，交互半径内最近的一个展开名字条（图标 + 名字 + 至多一条事实）；门 = 门图标 + 目的地（`Farm` / `Map`）；NPC 头顶只写名字（`Mei`），对话中只保持高亮；座位只有 `i-seat` 图标；任何地方都不出现点按引导语（Tap to …）与手指（LOCK-07 / 16 / 17 / 30 v2，q(62)） |
| 径向菜单无字 | 四瓣环在屏幕中央，瓣上只有图标，不写行动名与原因；点灰瓣才在环心出单行气泡 `No water nearby` / `Enter the mine` / `Mine floors 3–5`（LOCK-03 v2，q(62)） |
| 快满写实得 | `Eat · +12 Energy`、`Hot Tea · +12 Energy · 40 coins`、`Rest · +25 Energy`（q(26)）。热茶（茶馆）与咖啡（驿站）同价同效：标称都是 +30，当天第 1 / 2 / 3 杯 40 / 50 / 60 coins、两种共用 3 杯；柜台快满时写实得，如差 3 满时 `Coffee · +3 Energy · 40 coins`，不是数值错（§3.4.4） |
| XP 飘字 | 全额 `+10 XP`；等级差减额写实际百分比 `+7 XP · 75%`（不画箭头、不做长按）；Cooking 带轨名与品质星 `+10 Cooking XP ★`，同页第 2 锅 `+5 Cooking XP ★ · 2nd today`（不叠百分比），第 3 锅起 `No XP · 3rd today`（q(55)、q(94)） |
| 倒计时 | 秒级实时计时写 m:ss：`Cooking 0:42`、`9:28 remaining`、`The stove is busy · 0:22 left`、徽标胶囊 `0:22`、体力回复 `+1 in 2:41`；句子里的倒计时按分钟向上取整（最少 `1m`），不足 1 小时写 `42m`、整点 `2h`、其余 `9h 12m`：`Available again in 42m`、`Ready in 42m`、`Expires in 59m`、`Resets in 9h 12m`；不出现 `Available again in 42:00` 这类像钟点的写法，也不出现 `60m`（q(97)） |

## 1. HUD 与体力卡（LOCK-06、LOCK-09）

| 位置 | 应出现 |
|---|---|
| 体力卡 | `142/210` · `+1 in 2:41` · 满 `Full` · 超上限大数字 `230/210`、小字 `Bonus +20`（q(94)） |
| 位置芯片 | `Shanghai · Homestead` / `Shanghai · Farmhouse`（农舍室内，K-1）/ `Shanghai · Reed Pond` / `Shanghai · Mine · Floor 2` / `Shanghai · Xuhui Market Square`（q(46)：不是 Shanghai Market Square） |
| Energy 卡 | 标题 `Energy 0/210 · +1 in 3:59`；信息行 `Wait · Full in 13h 20m`；分组 `RECOVER`；唯一按钮 `Free to do now` |
| RECOVER 瓦片 · Eat | `3 dishes in bag` · `Open bag ›` / 灰 `No dishes in bag` |
| RECOVER 瓦片 · Cook | `4 fish in creel` · `Show kitchen ›` / 离家灰 `At home` |
| RECOVER 瓦片 · Tea ★ | `0/3 today · 40 coins` → `1/3 today · 50 coins` → `2/3 today · 60 coins` / 灰 `Need 15 more coins` / `3/3 today` / `Energy full`；引导 `Show on map ›`（q(46)、q(48)） |
| RECOVER 瓦片 · Rest ★ | `Available` / 灰 `Rested today` / `Ready in 1h 12m` / `After 2h away` / 离家 `At home`；引导 `Show bench ›`（q(46)） |
| 体力不足（主行动键琥珀） | `Sow ×1 · Need 2 Energy` / `Cast · Need 5 Energy` / `Mine · Need 2 Energy`；矿口入口卡 `Enter mine · Need 2 Energy` 与下行梯小卡 `Floor 2 · Need 2 Energy` 同样琥珀、按下弹 Energy 卡（主行动键不显示，q(102)） |

## 2. 农场、驿站、长椅、工作台、采集点

| 位置 | 应出现 |
|---|---|
| 主行动键 · Farming | `Sow ×1 · 2 Energy`（档 2–4：3 / 4 / 6）/ Row Hoe `Sow ×3 · 6 Energy` / 灰 `Sow · Pick a seed`（种子用完自动回到这一态，q(44)）/ `Till · Free` / `Water · Free` / `Harvest · Free` / `Fertilize · Free`；选中堆肥时只有已播未熟、未施过的格写 `Fertilize · Free`，其他格按格子状态走（同选中种子），P0 不出 `Fertilize · Nothing to feed`（q(94)） |
| 快捷栏幽灵格 ★ | `Seeds` / `Bait` / `Torch`（只写名词，q(44)）；钉住格归零写 `0` + `Buy at Homestead Stall` |
| 驿站棚（无人值守，LOCK-17） | 名字条 `Homestead Stall`（q(62)）；抽屉标题 `Homestead Stall`；Tab `Buy / Stall Board`；挂委托板的 `!` 时点棚停在 Stall Board 页（q(44)）；Buy 页新上架的行写 `◆ New for you`，棚上同时只挂一枚徽标，委托在时不挂 ◆（q(76)） |
| 驿站委托板 | `Pond Catch · 2 Pond Crucian · 14 coins` / `Track` / `Tracked` / `Ready to deliver` / `Deliver` / `Requests today 4/6`（q(55)）；新号交教学委托前不显示 `Next request`，交完显示 `Next request 4h`；保留期里的空槽画成普通空槽，不带倒计时（q(99)） |
| 长椅 | 名字条 `+60 Energy` / 用过灰 `Rested today`（q(62)）；按钮 `Rest · +60 Energy` / 快满 `Rest · +25 Energy` / 冷却 `Rest · back after 2h away · 1h 12m to go` / 已用卡 `Used today` / `Uses 1/1` / 灰字 `Available again in 9h 12m`（到 04:00 换日的倒计时，不写 tomorrow；只有 `Close`，q(94)、q(96)） |
| 工作台 ★ | 名字条 `Workbench`（q(62)）；只有 `Tools / Supplies` 两个 Tab（q(31)）；按钮在卡片右下（q(45)）；缺料 `Need 6 more Timber`；门禁 `Farming Lv3`（堆肥配方，q(44)）；放不下 `No room · free a slot first`；铜镐 `Equip` / `Equipped`；手套 `Owned · always on`（q(46)） |
| 工作台效果句 ★ | `Copper Pickaxe · 2 Stone per rock`（LOCK-29）/ `Gather Gloves · +1 at every gathering spot`（q(45)）/ 堆肥 `Crops ready 20% sooner`（q(46)） |
| 采集点 ★ | 名字条 `Timber Grove`（其他写名字，如 `Reed Bank`）/ 没好 `Timber Grove · Ready in 2h 10m` / 未开 `Clay Bank · Homestead Lv2`（q(46)、q(62)）；P0 共 5 处，没有 Old Tree（q(43)） |
| 采集与入库飘字 ★ | 进仓库 `+6 Timber · Stored` / 进背包 `+2 Worm Bait` / 回家入库 `Stored · 12 Stone · 3 Copper Ore`（数字在前、不带 ×，q(46)） |
| 农舍门牌 / 升级面板 ★ | 名字条：农舍 `Farmhouse`、门牌 `Homestead Lv1`、木牌 `Upgrade Plaque`（q(62)）；标题 `Homestead Lv1 → Lv2`；What changes `Max Energy 210 · Meals 210 a day` / `Spice Rack · seasonings off your bag` / `Clay Bank · Clay next to the Reed Bank`；满级 `Highest level for now`（q(46)）；横幅 `Homestead Lv2` / `Clay Bank opened`；不在家（从个人页远程打开）时升级按钮灰显 `At home`，点它出 toast `Upgrade at home · Going home is free`，不写 `Go home to upgrade · Free`（q(93)） |
| 信箱 ★ | 名字条 `Mailbox`；有在列包裹时小牌 `Parcel`，背包满也挂（q(50)、q(62)、q(79)） |

## 3. 鱼塘与钓鱼

| 位置 | 应出现 |
|---|---|
| 主行动键 · Fishing ★ | `Cast · 5 Energy`（离岸远也是这句，q(44)）/ 途中 `Cast · On the way`（不灰显）/ 灰 `Cast · Creel full` / 灰 `Fishing · No water nearby` |
| 鱼篓角标 | `Creel 7 · 6 free` / 满 `Creel full · 0 free slots · Sell or cook first`（只在角标与 toast）；满时点角标出 toast + `Open bag ›`，不满时点角标直接开背包 Fish 页；满篓**没有** `Open Bag` / `Go home · Free` 次按钮，回家用位置芯片（q(83)） |
| 鱼饵用完 ★ | toast `Out of Worm Bait · no bait on the hook`（q(44)） |
| 挂上 / 取下鱼饵 ★ | 点快捷栏饵格 toast `Worm Bait on the hook · used at the bite`，再点取下 `No bait`；首次升级横幅按 `Use bait` 也出挂上那句（在水边选中饵格并闪一次，不在水边只挂上留到下一竿），不跳转（q(77)） |
| 钓获卡（首次） | `Caught!` / `Pond Crucian · Common` / `Fish-dex 3/N` / `First catch! +15 XP` / `New city! +10 XP` |
| 逃走 ★ | 保护期内 `It got away · Energy refunded (9 left today)` / 保护期外 `It got away · 3 Energy back`（q(49)，不写 `protected left`） |
| 挣脱 ★ | 卡 `Too strong` / `Fishing Lv4 needed · You: Lv3 · 30 XP to go` / `+3 Energy back`，无按钮；末行写实退：保护期内 `Energy refunded (8 left today)`，保护期外 `+3 Energy back`（q(55)）；第二次起飘字 `Got away · Lv4 · Energy refunded (8 left today)` / `Got away · Lv4 · 3 Energy back`（q(50)）；鱼竿不够 `Too heavy for your rod` / `Reed Rod · Fishing Lv3 · 80 coins` |
| 鱼塘 pin 与卡 ★ | `Reed Pond · Beginner pond · 0.8 km` / 其他 `Pebble Pond · River · 2.3 km`；卡 `Beginner pond` + `A nearby pond for your first catch.`（仅 Reed Pond）/ `Distance 0.8 km` / `Recommended Lv1–3`（River `Lv4–5`）/ `Details ›` / `Go`；鱼表剪影写名字 + `Fishing Lv N`（q(48)） |
| 图钉卡原因行 ★ | 图钉挂标记时副标题下一行：鱼塘 `Pond Catch · Pond Crucian 0/2`（只在已接下、鱼不够时）/ 集市 `Market Board · 2 requests`（1 条 `Market Board · 1 request`）/ 居民据点 `Pip · New request` / 交付点 `Pond Catch · Ready to deliver` / 据点 ◆ `New for you · Reed Rod` / 居民新对话 ◆ `Pip · New chat`；几件同时写一件加 ` · +1 more`（q(103)） |
| 进塘与凑齐 ★ | 进挂 ! 的塘 Info toast `Pond Catch · Pond Crucian 0/2`（教学卡之后）；钓到要的鱼飘字 `Pond Catch 1/2`；凑够 Success toast `Pond Catch · 2/2 · Deliver at the Stall`，鱼塘 ! 消失、家图钉 ✓（q(103)） |
| 委托的鱼还钓不上 ★ | 已接下但鱼的等级高于玩家 Fishing 等级：鱼塘不挂 !；Today 委托行小字 `Fishing Lv4 needed`，点开是那条鱼的四件事卡 `Fishing Lv4 needed · You: Lv2 · 230 XP to go`；委托卡交付按钮缺口 `Fishing Lv4 needed`（不写 `Need 1 more Rare fish`）（q(104)） |

## 4. 厨房与烹饪

| 位置 | 应出现 |
|---|---|
| 灶台 | 名字条 `Stove 1/1 · Empty`（q(62)）；顶栏 `Stove 1/1 · Cooking Lv2 · Empty`；待收 `Stove · Ready · Grilled Crucian` |
| Cookbook 页格与详情卡 ★ | 页格不打勾（能做看 `Can cook` 筛选、排序与详情卡按钮）；已知未做的页半彩 + 底部角签 `Try it`（primary 绿），做过的页全彩不标，未知页不挂签；详情卡第二行 `Fine · First cook +20 XP`（稀有度 · 状态）；玩家界面不出现 `Tasted`（q(92)） |
| Cookbook 按钮四态 | `Cook` / 灰 `Need Wild Herb ×1` / 灰 `Cooking Lv4 · 3rd slot` / `Try in Experiment ›` |
| Experiment | `From your bag` + 右侧 `2 / 2 slots used`（q(94)）；调味料格带 `Rack` 角标、写仓库实数（如 `Rock Salt 12`，不写 /30，q(46)）；`Not for cooking`（金锦鲤）；`In pot`（q(94)）；锅下槽位卡不写原料名，结果行只写菜名 / `Unknown dish` / `Tried before` / `?` + 色点 + 时长，不出 `Ready to cook` / `Ready to queue`；按钮灰显原因 `Add an ingredient` / `Needs a main ingredient` / `Stove busy`；点锁 toast `Cooking Lv4 · 60 XP to go`（q(92)） |
| 火候 | `Tap when the needle hits gold!` / `Nice heat! ★` / `Missed · still cooking` / `Perfect! ★★ · Extra portion` |
| 出锅卡 COOK-4 ★ | 首做 `New recipe!` + 奖励条 `First cooked · +10 Cooking XP · Cookbook 1/48`（只放首做 XP；本锅 XP 照常飘 `+5 Cooking XP ★`，q(55)）/ 重复 `Dish ready`（从灶上收时条 `Collected from Stove 1`，q(94)） / 失败 `Mystery Dish` + `Hmm… not a dish` + `A clue was added to your Cookbook` + 灰字 `Can't be sold or delivered`（q(55)）/ 退料 `No dish this time` + 名字行 `Ingredients back` + 第二行 `9 left today` + `OK`（q(66)）；按钮只有 `Eat · +45 Energy` / `Keep`，Gift 在 P0 只是卡底灰字 `Gift later from your bag`（q(94)）；没有 Cook Again 按钮（q(46)、q(48)、q(49)） |
| Queue ×2 ★ | Cooking Lv5 起、灶在烧且队列空时计时卡次按钮 `Queue next ›`；抽屉主按钮 `Queue`（q(84) 的胶囊词 `Ready to queue` 随 q(92) 退役）；排队中 `Cooking · Queued 1`，灶台图标钮挂 `+1`（q(71)）。人在厨房时轮转 toast `Grilled Crucian kept · Herb Grilled Fish cooking`；下一锅未知 `Grilled Crucian kept · Unknown dish cooking`；前一锅黑暗料理 `Mystery Dish kept · Herb Grilled Fish cooking`；前一锅新手期退料 `Ingredients back · Herb Grilled Fish cooking`；可叠加如 `Ingredients back · Unknown dish cooking`；人不在厨房不出（q(82)）；轮转时出锅的是新菜：Success toast `New recipe! Herb Grilled Fish kept`（不带下一锅后半句），灶台飘字 `First cooked · +20 Cooking XP`，不弹出锅卡（q(85)） |
| Cook Again ★ | 收走后点灶台：`Cook Again` / `Choose recipe ›`，第 2 锅 `Cooks today 2nd` / `Cooking XP Half`（q(48)） |
| 保温柜 | 名字条 `Warming Cabinet 4/6`（q(62)）/ `Take one` / `Kept · Warming Cabinet 5/6` / `Cabinet full · Herb Grilled Fish sent to bag` / `Cabinet and bag full · dish left on the stove` / `Bag full · dish left on the stove` |
| Cooking Lv4 之后 Today ★ | `3rd slot open · try Fine fish + Potato + Rock Salt`（q(46)） |

## 5. 矿洞

| 位置 | 应出现 |
|---|---|
| 矿口 | 点击触发，主行动键不显示矿口动词（q(102)）；名字条 `The mine · Runs today 0/2`；入口卡 `Enter mine · 2 Energy` / `Continue run · Free` / 次级 `New run · 2 Energy` + `Current run will end · Runs today 1/2` / 灰 `New run · Clear Floor 2 first` |
| 矿口用尽 ★ | 点矿口直接开 MINE-P0-8，灰按钮 `Mine runs today 2/2 · Resets in 9h 12m`；不出 `Enter mine · No runs left`（q(102)） |
| 满包 ★ | `Enter mine · Bag full` / `Floor 2 · Bag full`（不扣体力，q(48)）；岩石灰 `Bag full · free a slot to mine`；主行动键 `Mine · Bag full` |
| 楼梯与电梯 ★ | 点击触发，主行动键不显示（q(102)）：下行梯名字条 `Floor 2 · 2 Energy`（到过只写 `Floor 2`），去没到过的层出小卡按钮 `Floor 2 · 2 Energy`；灰 `Floor 2 · Clear Floor 1 first`；上行梯名字条写目的地：第 1 层 `Farm`、第 2 层 `Floor 1`；电梯名字条 `Elevator`；面板 `Entrance · Free` / `Floor 1 · Free` / `Floor 2 · Here`（P0 没有 Express） |
| 飘字 | `Floor 2 · −2 Energy` / `Floor 2 cleared · Elevator stop` / `Run ended at daily reset`；P0 没有 `Run complete`；MINE-P0-7 不写 `Unmined rocks on Floor 2 are lost`（q(46)） |
| 火把 | `Light Torch · Free` / `Lit · this floor` |

## 6. 据点（家一套）与居民

| 位置 | 应出现 |
|---|---|
| 名字 ★ | `Xuhui Tackle Shop` / `Lotus Tea House` / `Xuhui Market Square` / `Huangpu Travel Post`（q(32)、q(46)） |
| 掌柜名字条 | `Finn` / `Ama` / `Mei` / `Sigrid`（只写名字；最近的一个主色描边、放大 1.1 倍，对话中保持高亮，q(62)）；问候选项 `Trade` / 信息问句 / `Just passing by` |
| Mei 问候 ★ | `Morning! Row Hoes just came in — sows three plots at once, Farming Lv4. Anything I can get you?`（q(46)） |
| Ama 问候 ★ | `Sit a minute. Hot tea, 30 Energy a cup.`（不写 back，也不带价格，价格看柜台，q(46)、§10.8）；满体力 `You look rested. Tea's here when you need it.`；三杯用完 `That's three cups today. Come back tomorrow.`；喝后 `Enjoy. Next cup's 50 coins.`。**问候写标称的 30，柜台按钮快满时写实得**（如差 15 满时 `Hot Tea · +15 Energy · 40 coins`，q(26)）：两处数字不同是设计，不是错 |
| 柜台饮品页 | 事实行 `Cups used 0/3`（已用 / 上限，茶与咖啡共用 3 杯）；价格行 `Hot Tea · +30 Energy · 40 coins`（不带 `(1/3)`）；按钮 `Hot Tea · +30 Energy`；用尽 `Cups used 3/3` + 灰按钮 `Tea 3/3 today · Resets in 9h 12m`（不写 `back tomorrow`；不写 `Drinks left today 3 of 3`，q(98)） |
| 渔具铺柜台 ★ | 只有 Buy 一页、不显示 Tab 条；`Reed Rod · 80 coins`（`Fishing Lv3` / `Owned`）/ `Worm Bait · 2 coins` · `30 left today` / `Sold out · 9h 12m`；收鱼 × 0.8；渔情板只作摆设，不挂图标钮与名字条（q(46)、q(62)） |
| 集市柜台 ★ | `Buy | Market Board`，只有 Row Hoe 一行，不贴背包（q(48)）；特产货架名字条 `City Specialty`、委托板名字条 `Market Board`（有可接委托时换 `!` 徽标）（q(62)）/ `Shanghai Postcard · 100 coins` / `Owned` |
| 驿站柜台 | 只卖咖啡 `Trade · get a coffee`；盖章台只作摆设 |
| 集市委托板 ★ | `Dusk Haul · Market Board` / `4 Fine fish · any kind` / `36 coins`（P0 不写 `+1 city stamp`）；`Market Basket` / `3 crops · 6 each`（q(46)） |
| 居民 ★ | 头顶名字条只写名字 `Pip` / `Old Kai`（q(62)）；Pip `Could you catch me a fish? Any kind is fine.`（对话条与委托卡同句）；Old Kai 需求行 `Rare fish · Golden Koi · Pond 0/1`；奖励行 `+5 Friendship · 20 coins` / `+5 Friendship · 50 coins`（q(46)）；赠餐 toast `Pip gave you Carrot Cake · in your bag`（菜进背包、没有吃，不写体力，q(94)）；好感进度 `52/90 · next Trusted`，最高档 Kindred 只写 `157`、进度条满格，资料卡 Friendship 行同样 `157`（q(91)） |
| 饮品满体力 ★ | 灰 `Energy full`（q(48)） |

## 7. 地图

| 位置 | 应出现 |
|---|---|
| HUD ★ | 两行 HUD 常驻，底部只有 `Bag`；没有旧底栏 `Map / Farm / Me`；P0 不显示 `Nearby Cities`（q(50)） |
| pin 卡按钮 ★ | 农场 `Go home · Free`；据点与鱼塘 `Go`；玩家就在这里时改 `Back to Homestead` / `Back to Lotus Tea House` / `Back to Reed Pond`，并且不显示 Distance 行（q(80)） |
| 家的 pin 与卡 ★ | 名牌 `Homestead`（不再写 `My Farm`）；卡 `Homestead` / `Your farm` / `Distance 0.8 km`（q(80)） |
| 据点卡 ★ | `Lotus Tea House` / `Tea house · Hot tea`（其他：`Tackle shop · Rods and bait` / `Market square · Requests` / `Travel post · Coffee`）/ `Distance 0.8 km` / `Online now 3`（0 人整行不显示）/ `Go`（q(80)） |
| 据点 pin | `Lotus Tea House · 3 online`；没人在时只写名字 `Lotus Tea House`；P0 城市级不聚合，每处一枚 pin，不出 `×N`（q(72)） |
| 标记 | P0 只有绿 ✓ / 金 ! / 青 ◆，没有 🔒 与 ★（q(48)） |

## 8. 背包、Gear、个人页、收件箱

| 位置 | 应出现 |
|---|---|
| 背包 | `Bag 19/25 · 6 slots free` / 7 个 Tab `All / Seeds / Fish / Produce / Dishes / Materials / Tackle` / 仓库堆 `Take 10 / Take all` / 不在家 `At home` |
| 料理详情卡 Gift ★ | 身边有居民 `Gift to Pip` / `Gift to Old Kai`；其他地方灰 `Gift to a resident`，点了 toast `Find a resident at an outpost to gift this dish`；今天已送过 `Gift already given today`（q(63)） |
| Gear ★ | `Bag | Gear`；Fishing 槽只有 Starter Rod / Reed Rod，P0 不列 Carbon Rod（q(46)） |
| 个人页 | P0 子集（PROFILE-1-P0）：`Profile` / `Edit look ›` / `Shanghai · <climate> · Since Oct 2` / 三张技能卡 / 农场卡（农场名 + `Level 2`）/ `Collections`：`Fish n/N` · `Pages n/N`（Pages 数做出过的页，和 Cookbook 页签同一个数，q(100)）；P0 不出 `Edit` / `Following` / `Followers` / `Mutual` / `Close Friends` / `All skills ›`（q(94)） |
| 技能页 ★ | 小标题 `First times` + NEED-TILE `Crops n/8` / `Fish n/7` / `Dishes n/14`（q(94)）；不显示 `Cities fished`（q(49)） |
| 收件箱 ★ | Tab `To do / Parcels / Updates`；To do 空态 `No invites right now`；Parcels 空态 `No parcels`；Updates 空态 `No updates yet`；规则行 `Parcels 3/8 · Kept 24h · Claim needs a free slot` / 满 `Parcels 8/8 · 2 more waiting · …`；`Claim all · 2 slots` / `Make room · 1 slot`；列表下方固定一行 `If not claimed: sellable items turn into coins at 80% · gifts go back · the rest is lost`（有包裹时显示，不随内容变，不写 regional seeds，q(81)）；Updates 只有三种：`Parcel expired · +18 coins` / `Parcel expired · Worm Bait ×3 lost` / `Pip's gift meal went back · unclaimed`，不出 Homestead 升级与领取记录（q(50)、q(79)）；铃铛数字 = 在列包裹（背包满也计）+ 未读 Updates，待发不计（q(79)） |
| 满包的被动获得 ★ | 铃铛下方 InboxNotice 卡三行：`Sent to Inbox` / 图标 + `Perch` + `×7` / `Expires in 24h ›`（BAG-5-2 定稿，替代原 toast `Bag full · Perch ×7 sent to Inbox · 24h`，LOCK-14）；同一回包多件：物品行写第一件，第三行 `+1 more · Expires in 24h ›`；Inbox 已满排队：`Inbox full · waiting` / 物品行照旧 / `Claim a parcel first ›`（多件 `+1 more · Claim a parcel first ›`）；不写 `2 rewards`、`saved for later`（q(87)）；居民赠餐：第三行 `From Pip · Expires in 9h 12m ›`（到 04:00 的倒计时），排队 `From Pip · Claim a parcel first ›`，不再出 toast `Bag full · Pip's meal sent to Inbox`（q(88)） |

## 9. 首会话与引导

| 位置 | 应出现 |
|---|---|
| TipCard（7 句，无按钮） ★ | `Pick a seed, walk up to a plot and press Sow. Hold to keep sowing.` / `Casting uses 5 Energy` / `Your creel is your bag: 10 fish per free slot.` / `Tap Cook to grill your first fish` / `Tap when the needle hits gold!` / `Energy comes back over time. A meal brings it back now.` / `Browse the map for free. Travel costs Energy and coins.`（q(44)）。`Levels unlock gear, fish and seeds. Basics never lock.` 不出卡，只在首次升级横幅的 Tip 行出现一次（q(86)） |
| 首次升级横幅 | `Fishing Lv2` / `Fine fish now stay on the hook` / 奖励药丸 `+3 Worm Bait` · `+3 Wild Herb`（技能升级不回体力，不出 `+50 Energy`，q(101)）/ Detail `New recipe: Herb Grilled Fish` / Tip `Levels unlock gear, fish and seeds. Basics never lock.` / `Use bait`；不写 `Level-up gift: …`（q(94)） |
| Today | `Radishes ready in 3h 32m` / `Farming Lv2 at your first harvest` / `Lettuce ready in 7h 58m`（浇水后，q(48)）/ `Fresh Fish Soup · when radishes are ready`（等料行，跟在萝卜行与其升级信息行之后，q(95)）/ `2 fish · the stove is free`（汤要的鱼不算；只剩汤的那条鱼时整行不出，q(95)）；首会话末三行 = 萝卜倒计时 / `Farming Lv2 at your first harvest` / 鲜鱼汤等料行；作物熟了等料行消失；不可数作物写 `when lettuce is ready`；作物复数按 q(58)，不写 `Lettuces`（q(98)）；升级写 `Lv2` 不带空格（q(98)） |
| 通知软提示 | `Get a ping when your radishes are ready?` · `Allow` / `Not now` |
| 结束态 ★ | 不出 `Session complete`；农场 + Today 三行，HUD `200/200` · `Full`（第二道菜吃下去回到满条；不进奖励区，q(101)）（q(44)） |

## 10. 系统态与命令（q(49)）

| 位置 | 应出现 |
|---|---|
| 横幅 | `Offline · Reconnecting…` + `Retry` / `Back online` / `Didn't go through · try again` |
| 离线时按钮 | 命令按钮灰 `Offline`；主行动键如 `Sow · Offline` |
| 维护卡 SYS-MAINT | `Down for maintenance` / `We'll be back around 14:30.`（设备本地时间、24 小时制；★ 结束时刻不在今天写 `We'll be back around Oct 10, 14:30.`）/ `We'll be back soon.`（没有预计时间或已过时）/ `Check again`（q(74)） |
| 强制更新卡 SYS-UPDATE | `Update to keep playing` / `This version is out of date.` / `Update`；两张卡都没有关闭按钮（q(74)） |
| 换场景加载 ★ | 加载画面写目的地位置芯片文字（如 `Shanghai · Willow Pond`），8 秒后加 `Taking longer than usual…`；打不开时卡片 `Couldn't get there` / `Check your connection and try again.` / 主按钮 `Retry` / 次按钮 `Go back`（q(78)） |
| 世界动作失败 | P0 只出横幅 `Didn't go through · try again`，**不出** toast `3 plots not sown · Energy returned`（P0 世界动作没有本地投影，那句 toast 留给以后有投影的版本，q(75)） |
| 去重与 stale_state | 不出任何提示 |
| 启动与账号 | `When were you born?` / `Pick your birthday` / `Continue` / `Before you start` / `Agree to continue` / `Terms of Service ›` / `Privacy Policy ›` / `Continue with Apple` / `Continue with Google` / `Continue with Email` / `Taking longer than usual…` / `Can't connect` / `That name isn't allowed` / `Try another name`（WP6，SGODOT-206） |

## 11. 方案内已统一的写法（巡检时以右列为准）

| 旧写法（方案或稿中残留） | 统一为 |
|---|---|
| `Creel full · Sell or cook first` | `Creel full · 0 free slots · Sell or cook first`（toast / 角标）；键面 `Cast · Creel full` |
| `Too strong · Fishing Lv 4 · 3 Energy back`（一行） | 卡片三行：`Too strong` / `Fishing Lv4 needed · You: Lv3 · 30 XP to go` / `+3 Energy back`（保护期内末行 `Energy refunded (8 left today)`，q(55)） |
| `Energy full · eat later` | `Energy full`（按钮灰显） |
| `Guest pass · 10 Energy · Host is online` | P2 内容；P0 不出现 |
| `It got away · +5 Energy · 9 protected left` | `It got away · Energy refunded (9 left today)` |
| `Sweet potato seeds just came in — Farming Lv5 to plant`（集市问候） | P0 用 Row Hoe 那句 |
| `Shanghai Market Square` / `Pudong Market Square` | `Xuhui Market Square` |
| `Compost · −20% time` | `Crops ready 20% sooner` |
| `1/3 today · 40 coins`（茶的第一杯） | `0/3 today · 40 coins` |
| `Stove 1/1 · Empty · Tap to cook` / `Workbench · Tap to craft` / `Mailbox · Tap to open` / `Tap to shop` / `Rest · +60 Energy · once a day`（世界里的指尖卡） | 名字条 `Stove 1/1 · Empty` / `Workbench` / `Mailbox` / `Homestead Stall` / `+60 Energy`（q(62)） |
| `Mei · Tap to talk` / `Mei · Talking` / 茶桌 `Sit` | 名字条 `Mei`（对话中只保持高亮）；座位只有 `i-seat` 图标（q(62)） |
| 径向菜单瓣旁 `Fishing · No water nearby` | 瓣上无字；点灰瓣气泡 `No water nearby`；主行动键仍写 `Fishing · No water nearby`（q(62)） |

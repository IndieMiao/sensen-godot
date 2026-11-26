# 旅行卡只写消耗 · 界面规格 v1（不知火舞 2026-11-11；q(318) 改版）

> **依据**：用户 bot 740（17:32）「所有这种自动计算的都移除，仅保留消耗……如果不够那么 toast 提示；这次可以先修改这个部分；其他的都类似处理」+ bot 741（17:33）「统一明确告诉用户要消耗多少即可，避免过多冗余的信息」，奕星核过。取代李白 q(318) 3e71eeda 的「按地板写 `→ N left`」那版（截图 302 308e62b6 / 1f24b303 作为「改前」）。
> **范围**：这一步只改旅行卡两张：城市确认卡 MAP-5（q(257) ②）、野外地点旅行卡 C3（v4q(3)，354:186011）。全游戏其他同类写法是第二步，见文末「第二步」清单，先不动。

## 1. 卡上写什么
- **只写消耗**：`Energy` · `15`、`Coins` · `60`（这一趟要花多少），**去掉 `→ N left`**。再访半价、首访价照现在的票价。0 成本（Trip 1，含兜底最近 3 城）照旧一行 `Cost` · `Free`。
- **卡上放当前持有量（主推 B，按用户 740「类似这样的组件上，放上消耗品当前的数量，比如金币等」；奕星 11-11 定，我先前用 741 把这半句读没了，已更正）**：每行左边标签后面跟一段小字写现有多少，右边仍只写这一趟花多少：左 `Energy` + ` · You have 200`、右 `15`；左 `Coins` + ` · You have 230`、右 `60`。小字同标签的样式（Caption 12 secondary），不加行高、不加图标；右边票价照旧 Bold。数字是此刻 HUD 上的数（体力含额外、金币照钱包），开卡时取、开着时随 HUD 变。**不写 `→ N left`、不写缺口**（741）。
- 备选 A（只写票价、不放持有量，持有量看 HUD）：配文里附一句给用户挑，帧只出一张作对照。
- 其他行不动：`Distance`、`Fish here`、`Visit`（`First visit · stamp + 10 Energy` / `Return visit · half price`）、`Day Pass · 7h left`（倒计时，不是资源计算）、卡底 `Return home is always free`。

## 2. 按钮
- **一律写 `Fly`，常亮**（主键绿），不再写缺口、不再变灰或变琥珀。
- 点 `Fly`：够就照现在起飞；不够就**留在卡上，出 toast**（ToastLayer，落在快捷栏位置，同现有）：
  - 体力不够：`Need 15 Energy`（**现有句**，q(264) ① `not_enough_energy` 那句，数字是这一趟的体力票价），Info 样式。不自动开 Energy 卡（照 q(257) ⑥ 现行）。
  - 金币不够（含「付完会低于 40」）：`Need 60 coins · keep 40 after the trip`（**新**，数字是这一趟的金币票价；40 是钱包地板，固定数，不是算出来的差额）。原来点灰键出的 `Wallet floor · keep 40 coins` 不再用在旅行卡上。
  - 两样都不够：只出金币那句（q(22) 顺序，金币在前，照现行）。
- 服务端拒绝（`not_enough_coins` / `not_enough_energy`）切回后出的 toast 用上面同两句（改 q(257) ⑥ 的缺口原文）。四处（点 Fly 两句 + 服务端切回两句）一律 **Info** 样式，不用红色 error（付不起不是出错；周瑜问，11-11 定）。**toast 位置和折行（11-11 奕星看报批图后改，取代先前「照 q(16)、盖住接受」）**：旅行卡开着时，toast **放在卡片顶边上方 8、左距 16**（在地图上、HUD 下面），不压卡上任何一行——这条 toast 说的就是卡上体力 / 金币两行，盖住它们等于白说；这是 q(16)「抽屉里放在固定操作区上方」的例外，只限这两张旅行卡（代码现成：卡上方有地方时 `anchor_above(content)`）。金币那句**中英文都固定两行、在「 · 」处断、去点**：`Need 60 coins` / `keep 40 after the trip`（中文「需要 60 金币」/「付完还要留 40」），英文也打开 break_at_dot（只这一句）。体力那句一行。
- **钱包地板 40 怎么讲清楚**：卡上不写；只有点了付不起时，toast 里说 `keep 40 after the trip`。理由：741 要求只告诉玩家花多少；地板只在付不起时才相关，toast 是唯一需要它的地方。

## 3. 不变
票价、钱包地板 40、扣费时机（q(261)「先起飞后对账」）、飘字 `−60 coins` / `−15 Energy`、日票、盖章、`Return home is always free`。

## 4. 推翻 / 复议
- **197 LOCK-10 复议**（旅行卡例外）：LOCK-10 锁「缺口写在按钮上（如 Need 6 more Timber），按钮是中性灰的不可用态，琥珀只留给体力不足与缺口环」。旅行卡改成：按钮常亮写动作 `Fly`，不够时用 toast 说要花多少；按钮不再灰、不再写缺口。NEED-TILE 环本身旅行卡不用，不涉及。
- **LOCK-02 不复议**：LOCK-02 锁的是主行动键（Farming / Fishing / Mining / Combat）的琥珀 `Need N Energy`，旅行卡不是主行动键；当初 q(264) 是照着它给旅行卡用了琥珀，这次只推翻 q(264) ① 里旅行卡那部分。
- 推翻：q(264) ①（旅行卡琥珀 `Fly · Need N Energy`、付完小于 0 只写票价）、q(257) ②（`→ N left`）③（灰 `Need N more coins`、点了 `Wallet floor · keep 40 coins`）⑥（拒绝码 toast 原文）、§11.8.2 表下「`→ N left` 写付完后剩多少，40 地板交给按钮缺口去说」、李白 q(318) 3e71eeda 的 ①。
- 新英文 2 句：`Need %d coins · keep 40 after the trip`（中文建议「需要 %d 金币，付完还要留 40」）；`You have %d`（中文用表里现成的「已有 %d」，跟在标签后面，前面的 ` · ` 由布局加）。

## 5. 帧（安其拉出，改前用周瑜实拍）
- 城市卡（洛杉矶回访 60 金币 / 15 体力），**按 B 出**：①够（钱包 230、体力 200）：`Energy · You have 200` | `15`、`Coins · You have 230` | `60`、`Fly`；②金币不够（钱包 80）：`Coins · You have 80` | `60`，下面 toast `Need 60 coins · keep 40 after the trip`；③体力不够（体力 10、钱包 230）：`Energy · You have 10` | `15`，toast `Need 15 Energy`。
- 野外卡（Bellows Quarry 60 / 20），B：够的一态 + 金币不够一态。
- 备选 A 一张：城市卡①不带 `You have`，作对照。所有帧都带地图页 HUD（顶上体力和金币看得见）。
- 改前对照：周瑜 302 e700621c / 793c152b 的「改前」那排（`60 → 0 left` + 灰 `Need 40 more coins`；琥珀 `Fly · Need 15 Energy` 用 q(264) 帧 Q367-ENERGY-SHORT 266:178479）。



## ★★ v4（定稿版，取代 v3 里的「You have」；用户 bot 756，11-11 18:29，om_x100b607074cfc8a4c0eeeae4cc4d6b3，奕星 mget 核过：「把you have xxx去掉, 把所有消耗的 前面加 "-"号 例如 "⚡️Energy            -20"」）
- **卡上两行**：左边 `[体力图标] Energy`、`[金币图标] Coins`（图标照 v3：`P0Logic.icon("energy")` / `P0Logic.icon("coin")`，16 px、垂直居中、间隔 4，标签文字保留）；**右边写 `−20`、`−60`**（这一趟的票价前加负号，Bold，右对齐，其他行同样式）。**不写 `You have N`**（中英都去，`You have %d` 这句作废，不入表；`已有 %d` 是表里早就有的，别处在用，不删，只是这里不用）。
- **负号用 `−`（U+2212 真负号）**，不用 `-`（连字符）：游戏里扣减一律是 `−`（飘字 `−30 Energy` / `−120 coins`、矿层 `Floor 2 · −4 Energy`、温室 `−20%`），和加号 `+10 Energy` 等宽、对称。`−` 和数字之间不留空格。中文同样写 `−20` / `−60`，标签照中文表「体力」「金币」。
- **0 成本**：Trip 1（含兜底最近 3 城）照旧一行 `Cost` · `Free`，不写 `−0`。
- **其余照 v3**：`Fly` 常亮；付不起 toast 放在卡片顶边上方 8、左距 16；金币那句两行 `Need 60 coins` / `keep 40 after the trip`（中文「需要 60 金币」/「付完还要留 40」），体力那句 `Need 15 Energy` 一行；toast 写字，Info 样式。
- 新英文：只剩 `Need %d coins · keep %d after the trip` 一句。
- **流程（奕星 11-11 定，省一轮）**：不先出帧，周瑜直接在 #1001 改、拍图，我验实拍，李白出第四版报批（只发改前 / 改后实拍对比一张）。row 160 帧不补 v5（实拍就是定稿依据；以后谁要 Figma 帧再补）。

## ★ v3：加图标（用户 bot 746，11-11 18:06，附 742 截图，奕星核过：「能同意用icon 就不要只用文字, coin energy 前面加icon」）
- **卡上两行**：标签最前面加图标，用全游戏现成的那两个：体力 `P0Logic.icon("energy")`、金币 `P0Logic.icon("coin")`（HUD 体力卡、金币胶囊、`+N coins` 飘字用的同一套）。16 px，和标签字垂直居中，图标和字之间隔 4；标签文字保留（用户说的是「前面加」，不是替换）。排出来是：左 `[体力图标] Energy · You have 200`、右 `15`；左 `[金币图标] Coins · You have 230`、右 `60`。图标同时管住「这一行是哪种东西」和「You have」，「You have N」后面不再另配图标。右边票价照旧只写数字（同一行左边已经有图标，右边再加一个就重复了）。
- **toast**：推荐**这次照旧写字**（`Need 60 coins` / `keep 40 after the trip`、`Need 15 Energy`）。理由：toast 组件左边只有一个状态图标位（Info 的 i），在句子中间插金币图标是新的 toast 样式，要改组件、改中文表的拼法；放到第二步统一做（见下）。用户要这次就带，就写成 `Need 60 [金币图标]` 这种，图标代替单位词，中文同样处理。
- 其他行（Distance / Fish here / Visit / Day Pass）没有对应的消耗品图标，不加。
- 帧：B 的五帧（城市三态、野外两态）标签前加图标；A 对照那张也加（A 只是不写 You have）。

## 第二步：全游戏同类写法（排期另定，先不动；盘点 = 子代理只读 origin/farm-dev，约 45 处，不知火舞归类）
用户 740「其他的都类似处理」+ 741「只告诉要消耗多少」。按「这个数是不是玩家要花的东西」分五类，每类一个改法；**推荐整体照旅行卡做：按钮只写动作和价钱、常亮，不够时 toast 说要什么；不写「→ 剩多少」「还差多少」**。

| 类 | 在哪（代码位置） | 现在写 | 推荐改成 |
|---|---|---|---|
| ① 付完剩多少 | 旅行卡、野外卡（p0_map.gd `_fare_left`） | `60 → 40 left` | **第一步已改**：只写 `60` |
| ② 金币差额（按钮 / toast） | 商店 / 驿站买东西（item_info_rules.json 8 处 `Need {coins_short} more coins`）、茶馆柜台饮品（p0_counter_drawer.gd:438）、Energy 卡茶格（p0_logic.gd:920）、牌室 Deal（p0_blackjack.gd:103）、工作台建造（p0_material_logic.gd:634）、家园升级按钮（p0_logic.gd:2582）、拒绝 toast（p0_runtime.gd:1223 / 1248） | `Need 240 more coins` | 按钮写动作 + 价钱，常亮（`Buy · 240 coins`，现有买按钮写法照旧）；不够时 toast `Need 240 coins · keep 40 after`（同旅行卡那句的句式，数字是价钱）。其中茶、牌室、旅行三处差额里算进了 40 地板，改后只在 toast 里说地板 |
| ③ 材料差额（按钮 / toast） | 驿站要材料的货（item_info_rules.json:750）、家园升级（p0_logic.gd:2582-2589）、工作台（p0_material_logic.gd:636）、委托板交付（p0_board.gd:66 / 69）、居民委托按钮（p0_logic.gd:2168 `_request_gap`）、Locals 键（p0_locals.gd:55）、Cook Again（p0_kitchen_logic.gd:762）、拒绝 toast（p0_runtime.gd:1270） | `Need 6 more Timber`、`Harvest 3 more Radishes`、`Need 3 more fish` | 按钮写动作，常亮（`Upgrade`、`Deliver`、`Cook`）；**材料格照旧写「已有 / 需要」**（NEED-TILE `Timber 4/10`，这是「要花什么、花多少」，不是算出来的差额）；不够时 toast 写缺哪样、不写差几个：`Not enough Timber`（新句式，两样以上写第一样）。委托卡的进度行照旧 `Radish 2/5` |
| ④ 等级 / 经验差额 | 驿站锁定种子 `85 XP to go`（p0_item_info.gd:566）、摆件 `1 level to go`（:440）、门禁信息卡 `2 levels to go` / `18 XP to go · harvest 9 radishes`（p0_logic.gd:178-197）、钓鱼门禁 `Fishing Lv2 · 3 XP to go`（:76）、跑鱼说明（:98）、厨房第 3 槽 toast（p0_kitchen_logic.gd:157）、拒绝 toast（p0_runtime.gd:1246）、家园旅行门禁 `Need 2 more stamps`（p0_logic.gd:2469） | `85 XP to go`、`1 level to go` | 只写要求：`Farming Lv4`、`Home Lv5`、`3 stamps`（要什么等级 / 几枚），不写还差多少 XP / 级。**技能抽屉（p0_skills_drawer.gd:77 / 84 `Next: Lv5 · 88 XP to go`）建议保留**：那是专门看进度的地方，不是消耗；这一处问用户 |
| ⑤ Today 家园行 | p0_logic.gd:1872-1890 | `Home Lv3 · Timber 6 to go` / `400 coins to go` / `2 stamps to go` | 改成「已有 / 需要」：`Home Lv3 · Timber 4/10`（和升级面板的材料格同一个数） |
| ⑥ 每日剩余次数（不是消耗品） | 祈祷 `2 left today`（p0_logic.gd:2237）、Rest `Uses left · 1 today`（:2385）、退体力 / 钓鱼保护 / 掌柜问候 / 售罄 toast 里的 `N left today`（服务端给的数） | `2 left today` | **建议保留**：这是每天能用几次的规矩，玩家要靠它决定今天用不用，不是「付完剩多少」。问用户 |
| ⑦ 只写价钱的（已经是用户要的样子） | 主行动键 `Need 2 Energy`、矿口 / 楼层 `Need N Energy`、采集 `Gather · Need 3 Energy`、Rest `+N Energy`（旅行卡的 `Fly · Need N Energy` 第一步已拿掉，不在这里） | — | 不动（LOCK-02 主行动键琥珀写法照旧） |

**锁定项**：② ③ ④ 都碰 **LOCK-10「缺口写在按钮上、按钮中性灰」**。推荐第二步把 LOCK-10 这半句整体改成「按钮写动作和价钱、常亮；不够时 toast 说要什么；NEED-TILE 已有 / 需要照旧」，一条复议批全局，不再一处一处例外。旅行卡这次的例外（197 6e66f7db）到时并进去。LOCK-02 不动。实施前逐条再对 197（委托卡、驿站抽屉等可能各有锁定项）。
**图标和负号（用户 746 + 756）**：第二步凡是写**消耗**的地方，一律写成「图标 + `−`数字」（`−` 是 U+2212）：`Cast · 5 Energy` 的价钱部分 → `[体力] −5`，买东西 `240 coins` → `[金币] −240`，材料消耗 `Timber 4/10` 那类「已有 / 需要」的格不算消耗写法，照 NEED-TILE；得到的东西照现行 `+`（`+10 Energy`）。材料缺口 toast `Not enough Timber` → `Not enough [木头图标]`；toast 组件加一种「句中图标」写法，旅行卡的两句 toast 到时一起换。**注意 LOCK-02**：主行动键锁的是「动词 + 体力价」（如 `Sow ×1 · 2 Energy`），把 `Energy` 换成图标要复议 LOCK-02，到时和 LOCK-10 一起发。
**新英文**（第二步）：`Need %d coins · keep 40 after`（② 通用句式）、`Not enough %s`（③），其余用现有写法或删字。
**要用户定的两件**：技能抽屉的 `XP to go` 留不留（推荐留）；每日剩余次数留不留（推荐留）。

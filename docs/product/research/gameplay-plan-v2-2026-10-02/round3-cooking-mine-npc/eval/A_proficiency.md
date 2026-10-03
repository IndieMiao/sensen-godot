# 方案 A：烹饪 = 第三条熟练度技能轨 Cooking Lv1–10（XP 来自做菜）

> 辩护稿。目标：给出可直接并入玩法方案的完整设计，并诚实列出最可能被攻击的点。全文中文，结论先行，表格优先；物品写 id + 中文 + 英文。

---

## 0 结论先行

1. **Cooking 是与 Farming / Fishing 平行的第三条 10 级技能轨，XP 只来自"把原料做成菜"**：每做成一道菜按菜品稀有度给 **4 / 8 / 16 / 32**（4 槽签名页 44、5 槽盛宴页 60），火候 Good ×1.25、Perfect ×1.5；首次做成一道菜的一次性 XP **10 / 20 / 40 / 80**（5 槽 120）**从 Farming / Fishing 移交给 Cooking**。吃、赠、交委托、买配方卡、品尝一律 0。
2. **等级差衰减照用**：每道菜有 Cooking 内容等级（Common 1 / Fine 2 / Rare 4 / Legendary 6 / 4 槽签名 7 / 5 槽盛宴 9），d = Cooking 等级 − 内容等级，d ≤ 1 全额、2 → 75%、3 → 50%、4 → 25%、≥ 5 灰色；d 在开火扣料那一刻锁定。它是防"两根小萝卜刷到满级"的唯一闸，也是把玩家推向 Rare → Legendary → 异城食材的路标。
3. **阈值 0 / 30 / 100 / 220 / 400 / 650 / 950 / 1,350 / 1,900 / 2,600**，由三类玩家日做菜次数（5 分钟 ≈ 3 道、30 分钟 ≈ 6–7 道、重度 ≈ 10–12 道）反推：首会话第 27 分钟 Cooking Lv2（45 XP ≥ 30）；30 分钟玩家约第 19–22 天满级；重度第 11 天（≥ 8 天 ✓）；5 分钟玩家约第 100 天（接受并说明，旋钮在 Lv9–10）。
4. **等级最主要的后果是投料槽 2 → 3 → 4 → 5，落在 Lv1 / Lv3 / Lv6 / Lv9**。槽位从 Homestead 移交 Cooking；灶口 1 → 2 → 3（Homestead Lv1 / 4 / 8）、调味架储物、保温柜、大锅、名厨招牌**留在 Homestead**。一句话分工：**农场决定厨房有多大，技能决定你的手能做什么**。
5. **4–5 槽配方是旅行的去处**：新增 8 页（4 槽 5 页、5 槽 3 页，Cookbook 48 → 56），其中 7 页要求 ≥ 2 或 ≥ 3 个气候带的地区特产，稀有度一律 Legendary（回复 70，Buff 槽预留给 P3）。Lv6 起 Common 变灰、Lv7 起 Fine 变灰、Lv8 起 Rare 只剩 25%，全额 XP 只在 Legendary 与签名 / 盛宴页——Cooking 的后半程由异城食材供养，这正是会议要的"让玩家去更多城市拿食材"。
6. **UI 不加新面板**：头像外圈由双色改三色（Farming 绿 / Fishing 蓝 / Cooking 琥珀各 1/3），技能页三张轨卡，门禁卡、灰色提示、升级横幅复用现有模板；厨房面板顶栏加一行 Cooking 等级与槽位点。
7. **对现有方案的改动集中在三处**：料理章"烹饪本身不是技能"与首做 XP 归轨规则改写；农场等级章 Lv2 行去掉"第 3 投料槽"、删投料槽公式；技能章首竿 / 首提 +5 → +10，补回首会话 Fishing Lv2 少掉的 10 XP。灶台不另设等级；专用器具（发酵罐 / 果冻模）在 Cooking Lv5 / Lv7 预留行放 P2；料理 Buff 在 Legendary 与签名 / 盛宴页上预留 P3。

---

## 1 定位与分工

| 问题 | 方案 A 的回答 |
|---|---|
| Cooking 与 Farming / Fishing 的关系 | **下游轨**：原料来自前两轨，Cooking 只衡量"把原料变成菜"的熟练度。它不替代 Cookbook（图鉴仍是收藏线），不替代 Homestead（厨房大小仍是房子的事） |
| 为什么是熟练度而不是材料门禁 | 做菜每天发生 3–12 次，是全游戏频率最高的动作；按次数积累的熟练度让**每一次开火都是进度**，材料门禁只在升级那一刻有感。做菜本来 0 体力 0 金币，再加材料门禁等于第二份 Homestead 账单，而料理章的核心承诺是"做菜永远是即时满足" |
| 为什么不并进 Homestead | Homestead 已经承担体力池、食物上限、开垦、背包、社交槽、旅行资格七件事，再把"手艺"塞进去，升级面板会变成杂货单；而且 Homestead 的节奏由金币决定（30 分钟玩家 8–9 周），会议要的"初级 2 种食材 → 最终 5 种"若挂在 Homestead 上，第 5 槽要等两个月 |
| 农场（房子）管什么 | 灶口数 1 / 2 / 3（Lv1 / 4 / 8）、调味架储物（四种调味料各 30 份不占背包，Lv2）、保温柜 6 / 12（Lv3 / 8）、大锅 Double（Lv6）、名厨招牌（Lv10） |
| 技能（手艺）管什么 | 投料槽 2 / 3 / 4 / 5、火候金区加宽、做菜便利（再做一份 / 排队 / 全部开火 / 双线索）、专用器具（P2）、Buff 强化（P3） |
| 不做的事 | 不设烹饪体力消耗；不设每日 XP 封顶（只留防脚本 3,000）；不给吃菜 / 赠菜 / 委托 XP；Cooking **不参与** Homestead 升级的技能和门禁（仍是 Farming + Fishing ≥ 2N − 1）；不设灶台等级 |

---

## 2 对象与命名

| 类别 | id | 中文 | 英文（用户可见，≤ 18 字符） | 说明 |
|---|---|---|---|---|
| 技能轨 | `cooking` | 烹饪 | Cooking | 10 级，与 `farming` / `fishing` 同一套等级、XP、等级差机制 |
| 等级 | `cooking_lv1` … `cooking_lv10` | — | Cooking Lv4 | — |
| 内容等级 | `dish_content_level` | 菜品内容等级 | Lv N（随页显示） | 按稀有度与槽数派生（§3.2）；与原料轨的内容等级（用于 Cookbook 排序）并存 |
| 投料槽数 | `cook_slots` | 投料槽 | Slots 3 / 5 | 2 / 3 / 4 / 5，随 Cooking Lv1 / 3 / 6 / 9 |
| 配方页类别 | `page_standard` / `page_signature` / `page_feast` | 普通页 / 签名页 / 盛宴页 | — / Signature / Feast | 1–3 槽 / 4 槽 / 5 槽 |
| 一次性奖励 | `first_cook`（移交自原料轨）/ `first_mystery` / `dish_mastered` | 首做 / 首次黑暗料理 / 精通 | First cooked / Mastered | 不受等级差、不受防脚本上限 |
| 升级礼 | `cooking_lv2_gift` | 升级礼 | Level-up gift | 岩盐 `rock_salt` Rock Salt ×3 + 配方卡 `recipe_card_dish_salt_grilled_fish` Salt-Grilled Fish |
| 便利 | `cook_again` / `queue_two` / `clue_double` / `cook_all` | 再做一份 / 排队两锅 / 双线索 / 全部开火 | Cook Again / Queue ×2 / Double Clue / Cook All | 分配见 §5 |
| 火候加宽 | `steady_hand_1` / `steady_hand_2` | 稳手 I / II | Steady Hand I / II | 全部菜金区各 +5 个百分点 |
| 称号 | `title_star_chef` | 星级厨师 | Star Chef | Lv10 永久痕迹（Cookbook 里程碑的 Home Cook / Line Cook / Head Chef / Master Chef 名字不动） |
| 新标签 | `Any regional fish · 2 zones` / `Any regional fish · 3 zones` | 两带地区鱼 / 三带地区鱼 | — | 只允许出现在签名 / 盛宴页（§6.1） |
| 新标签 | `2 different regional crops` / `3 different regional crops` | 两种 / 三种不同地区作物 | — | 同上 |
| 事件 | `skill_xp{track: cooking, amount, mult, reason}`、`skill_level_up{track: cooking, …}`、`outleveled_first{track: cooking, item}` | — | — | 复用技能章事件 |
| 拒绝原因 | `SKILL_LEVEL_REQUIRED{track: cooking, needed, current, xp_to_go}` | — | Cooking Lv6 needed | 槽位不足时服务端兜底 |

---

## 3 XP 来源与等级差

### 3.1 来源表

| 来源 | XP（全额） | 受等级差 | 说明 |
|---|---|---|---|
| 做成 Common / Fine / Rare / Legendary 菜 | **4 / 8 / 16 / 32** | 是 | 每次出锅一次；大锅 Double 出 2 份仍按**一次**计（Double 省时间不省 XP，否则 Homestead Lv6 的玩家 XP 翻倍） |
| 做成 4 槽签名页 / 5 槽盛宴页 | **44 / 60** | 是 | 稀有度仍是 Legendary，但 XP 单独一档，因为它多花 1–2 份异城原料与 30–60 秒 |
| 火候品质 | Good ×1.25、Perfect ×1.5，**向下取整** | 乘在等级差之后 | Common Good 5；Fine Good 10；Rare Good 20 / Perfect 24；Legendary Good 40 / Perfect 48；签名 Good 55 / Perfect 66；盛宴 Good 75 / Perfect 90 |
| 槽数 / 原料数 | **不另加** | — | 稀有度派生表已把族数算进去（Common 1 族 20 → 2 族 Fine 40 → 3 族 Rare 70），再按槽数加分是重复计数；"用更多食材"的奖励体现为**能做出更高档的菜** |
| 首次做成一道菜 | **10 / 20 / 40 / 80**；5 槽盛宴 **120** | 否 | 从 Farming / Fishing **移交**；56 页合计 2,460（Travel Biscuits 不给） |
| 首次做出黑暗料理 | 10 | 否 | 之后 0；黑暗料理**永远**没有重复 XP |
| 一道菜 Cooked ≥ 10（Mastered；Cooking Lv5 后 ≥ 7） | +15 一次性 | 否 | 56 页上限 840；给"反复做同一道菜"一个终点奖励，不给持续奖励 |
| 吃 / 赠 / 交委托 / 买配方卡 / 品尝 / 页变 Tasted / 翻 Cookbook | 0 | — | 不付原料的动作不给 XP |
| 防脚本上限 | 每轨每日 3,000（一次性不计） | — | 重度极端日：12 锅盛宴 Perfect = 1,080，碰不到 |

### 3.2 内容等级与衰减表

| 菜品类别 | Cooking 内容等级 | 全额（d ≤ 1）到 | 75% | 50% | 25% | 灰色（d ≥ 5，5% 概率 1 XP） |
|---|---|---|---|---|---|---|
| Common（1–2 槽） | 1 | Lv1–2 | Lv3 | Lv4 | Lv5 | **Lv6 起** |
| Fine（1–3 槽） | 2 | Lv1–3 | Lv4 | Lv5 | Lv6 | **Lv7 起** |
| Rare（1–3 槽） | 4 | Lv1–5 | Lv6 | Lv7 | Lv8 | **Lv9 起** |
| Legendary（1–3 槽） | 6 | Lv1–7 | Lv8 | Lv9 | Lv10 | — |
| 4 槽签名页 | 7 | Lv6–8 | Lv9 | Lv10 | — | — |
| 5 槽盛宴页 | 9 | Lv9–10 | — | — | — | — |

规则（与 Farming / Fishing 同一张倍率表，不另造）：
- **d 在开火扣料那一刻锁定**：开火时按当时 Cooking 等级算好这锅的 XP，出锅照发；离开厨房或切后台出锅为 Plain，XP 照给（不乘品质）。
- **一次性奖励不受等级差**：首做、首次黑暗料理、Mastered 永远全额。
- **Lv10 之后** XP 继续累计并显示（"Lv10 · 3,418 XP"），不再有解锁。
- 小数随机取整与现行规则一致（Fine 8 × 75% = 6；Rare 16 × 25% = 4；Common 4 × 25% = 1）。

### 3.3 为什么"0 体力的烹饪"可以给 XP，而且刷不动

| 质疑 | 回答 |
|---|---|
| 技能章总则是"XP 只来自付了体力的产出" | 原料本身付过体力（鱼每竿 5，作物每格 2–6，岩盐来自矿洞每局 10 + 2/岩石），做菜**消耗**这些原料。Cooking XP 等于把那份体力在**另一条轨**上再记一次账——同一轨内没有任何动作被计两次 |
| "播了不收"式的无损刷 | 不存在：开火即扣料，失败也消耗 Common / Fine 原料；黑暗料理 0 XP |
| 每体力 XP 失控 | 烤鲫鱼 4 ÷ 5 = 0.8；时蔬拼盘 4 ÷ 2 = 2；香草烤鱼 8 ÷ (5 + 2) ≈ 1.1；河鲈 + 香草（Rare）16 ÷ (5 + 2) ≈ 2.3；清蒸鲟鱼 32 ÷ (5 + 2 + 2) ≈ 3.6。与 Fishing 的 1 → 8 同量级且低于其上段 |
| 两根小萝卜 5 秒一锅刷满级 | Lv6 起 Common 灰色、Lv7 起 Fine 灰色——"刷最简单的菜"在第一周末就失效；Lv8 起 Rare 只剩 25%，要全额只能做 Legendary / 签名页，而它们要传说鱼或异城特产 |
| 重度玩家 3 口灶 + 大锅 | Double 按一次计；3 口灶只是并行，不改每锅 XP；重度每日 10–12 锅是时间与原料的上限，不是 XP 规则的漏洞 |

---

## 4 阈值与节奏

### 4.1 三类玩家的日做菜次数（阈值反推的输入）

| 画像 | 每日做菜 | 构成 | 首做（发现）速率 | 依据 |
|---|---|---|---|---|
| 5 分钟 | **≈ 3 道** | 1 道 Common 赠礼（烤鲫鱼送 Pip）+ 2 道 Fine 委托（鲜鱼汤 ×2）+ 每周 1–2 次实验；**不为体力做菜**（他 120 天一口菜都不需要吃） | 0.7 页 / 日 | 现行三餐表 A |
| 30 分钟 | **≈ 6–7 道** | 正餐 3 + 夜宵 1 + 赠礼 / 委托 1–2 + 实验 1 | 1.5 页 / 日 | 现行三餐表 B |
| 重度 | **≈ 10–12 道** | 早餐 3 + 晚餐 2–3 + 赠礼 / 委托 2–3 + 实验 2 + 存给明天 1–2；3 口灶 1–3 分钟做完 | 2.5 页 / 日 | 现行三餐表 C |

### 4.2 阈值表

| Lv | 累计 XP | 本级增量 | 节奏意图（30 分钟玩家） |
|---|---|---|---|
| 1 | 0 | — | 起点 |
| 2 | **30** | 30 | **首会话第 27 分钟**：烤鲫鱼 Good 5 + 首做 10 = 15，香草烤鱼 Good 10 + 首做 20 = 30，合计 45 ≥ 30 |
| 3 | 100 | 70 | 第 2 天：第 3 投料槽，第一道三族菜 |
| 4 | 220 | 120 | 第 4 天：稳手 I、排队两锅 |
| 5 | 400 | 180 | 第 5 天：双线索 |
| 6 | 650 | 250 | 第 7 天：第 4 投料槽（第一周结束时与 Farming / Fishing 同在 Lv6） |
| 7 | 950 | 300 | 第 9 天：稳手 II |
| 8 | 1,350 | 400 | 第 11–12 天：行囊 +1、全部开火 |
| 9 | 1,900 | 550 | 第 15–16 天：第 5 投料槽 |
| 10 | 2,600 | 700 | 第 19–22 天：称号 |

设计说明：
- 增量约每级 × 1.2–1.5；Lv9–10 两级占总量 48%（与 Farming 的 48% 一致），把第三周留给"签名菜周"。
- Lv2 = 30 的来历：一道 Common 首做（15）不够，一道 Fine 首做（30）正好够——Lv2 发生在玩家**第一次见到档差**的那一刻，而不是第一次开火。
- Lv3 = 100：30 分钟玩家第 2 天 4 锅 + 2 页首做 ≈ 57，累计 102；第 3 槽在第 2 天晚上到手，比现行方案（Homestead Lv2，第 5 天）早 3 天。Fine 鱼 + 调味 = Rare 70 本来就在第 2 天可做，所以三族菜提前不增加体力风险（食物上限 200 在上面兜着）。
- 微调余地：模拟后允许 ±20% 并注明。

### 4.3 到达天数（手算，含等级差与首做；待数值校验章的会话模拟复核）

| 画像 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 | Lv7 | Lv8 | Lv9 | Lv10 |
|---|---|---|---|---|---|---|---|---|---|
| 5 分钟（3 道 / 日，不旅行、不吃） | 1 | 3 | 7 | 13 | 21 | 31 | ≈ 50 | ≈ 68 | **≈ 100** |
| 30 分钟（6–7 道 / 日，每周 1 次旅行） | 1 | 2 | 4 | 5 | 7 | 9 | 11–12 | 15–16 | **19–22** |
| 重度（10–12 道 / 日，每日旅行） | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 9 | **11** |

三条账的要点：

| 画像 | 第 1 周 | 第 2 周 | 第 3 周起 |
|---|---|---|---|
| 30 分钟 | 日 1：45（Lv2）；日 2：4 锅 + 2 首做 ≈ 57 → 102（Lv3）；日 3–7 每日 5–7 锅 + 1.5 首做 ≈ 90–145 / 日，Lv4 日 4、Lv5 日 5、Lv6 日 7（≈ 695） | Lv6–7 时 Fine 25% → 0、Rare 75%：5 锅 Rare ≈ 68 + Legendary（Fishing Lv7 后每日 0–1 道鲟鱼菜）≈ 36 + 首做 ≈ 60 → **≈ 165 / 日**；Lv7 日 9、Lv8 日 11–12 | Lv8 起 Rare 25%（≈ 22）+ Legendary 2 道（75%，≈ 54）+ 签名页 2 道（第二周那次跨带旅行带回的地区鱼，≈ 88）+ 首做 ≈ 75 → **≈ 215 / 日** → Lv9 日 15–16、Lv10 日 19；**完全不旅行**的路径只有 Rare + 在家 Legendary + 首做 ≈ 136 / 日 → Lv10 第 21–22 天 |
| 重度 | 日 2：165；日 3：336（Lv4）；日 4：553（Lv5）；日 5：810（Lv6）；日 6：1,128（Lv7）；日 7：1,453（Lv8）——每日 2.5 页首做（≈ 100）占一半 | Lv8 起 Rare 25%、Legendary 75%、签名页全额：6 Rare ≈ 27 + 4 Legendary ≈ 108 + 2 签名 ≈ 88 + 首做 100 ≈ **320 / 日**；日 9 ≈ 2,100（Lv9）；日 10 起 1 道盛宴（60）→ 日 11 ≈ 2,860（**Lv10**） | 之后 XP 只是纪念 |
| 5 分钟 | 日 1：45；之后 3 锅 ≈ 22 + 首做 ≈ 10 → 33 / 日；Lv4 日 7 | Lv4–6 时 Fine 衰减，他把 1 道委托换成 Rare（Fine 鱼 + 自种香草）：≈ 32 / 日；Lv6 日 21、Lv7 日 31 | Lv7 起 Rare 50% → 25%，Fishing Lv7（第 33 天）后偶尔 1 条鲟鱼：20–30 / 日；Lv8 ≈ 日 50、Lv9 ≈ 日 68；Lv9–10 靠 Legendary 50% + 首做 ≈ 20 / 日 → 约第 100 天 |

### 4.4 四条目标逐条校验

| 目标 | 结果 | 怎么保证 |
|---|---|---|
| 首会话 Cooking Lv2 | **第 27 分钟**（香草烤鱼出锅）；只做烤鲫鱼不到（15 < 30） | 阈值 30 = 一道 Common 首做 + 一道 Fine 首做；慢玩家 1.5 倍仍在 45 分钟窗口内；Lv2 立刻能用：岩盐 ×3 + 盐烤鱼卡 + 背包里还有 2 条 Common 鱼 |
| 30 分钟 ≈ 3 周满级 | **19–22 天** ✓（目标 21 ± 5） | 第二周 Rare 75%、第三周靠 Legendary + 签名页；每周 1 次跨带旅行带回的地区鱼够做一周签名菜（鱼不腐烂） |
| 重度 ≥ 8 天 | **11 天** ✓ | 衰减让他第 8 天起只能靠 Legendary / 签名 / 盛宴页；每天旅行拿地区鱼才有 2 页签名；全押做菜没有意义——原料仍受钓鱼 / 种植体力限制，一天做不出第 13 锅 |
| 5 分钟 ≤ 90 天 | **≈ 100 天** ✗，按口径接受 | 他不吃菜、不旅行、Lv8 后只有偶尔的鲟鱼；与他的 Fishing 84 天同量级、Farming 56 天更慢。他的 Cooking 停在 Lv8–9 并不妨碍任何事（Common / Fine / Rare 都在他手里）。旋钮：Lv9–10 阈值 1,900 / 2,600 → 1,700 / 2,350（−10%）可把他拉回 ≈ 90 天，30 分钟玩家提前 1–2 天、重度不变 |

---

## 5 每级解锁表（Cooking Lv1–10）

性质沿用技能章：**门禁** / **改变日常** / **便利** / **称号**；每级至少一样新东西。

| Lv | 累计 XP | 解锁 | 性质 | 玩家当天的"不一样" |
|---|---|---|---|---|
| 1 | 0 | **2 投料槽**；Recipes / Experiment 两个 Tab；Cookbook；单主料必成菜；初始已知 `dish_grilled_crucian` 烤鲫鱼 Grilled Crucian、`dish_radish_salad` 萝卜生菜沙拉 Radish Salad | 起点 | 5 秒烤出第一道菜 |
| 2 | 30 | 升级礼 `cooking_lv2_gift`：`rock_salt` 岩盐 Rock Salt ×3 + 配方卡 `dish_salt_grilled_fish` 盐烤鱼 Salt-Grilled Fish（页变 Tasted）；便利 `cook_again`：出锅面板的三选一旁多一个 **Cook Again**，料够即原地再开火 | 门禁 + 便利 | 首会话最后 3 分钟：手里有盐、有鱼、Recipes 页多一行亮着的 Cook |
| 3 | 100 | **第 3 投料槽** → 三族菜（Rare 70）从此可做；3 槽页在 Recipes 行的锁字 `3 slots · Cooking Lv3` 消失 | **改变日常 ①** | 第 2 天晚上第一道 `dish_fisher_stew` 渔家炖锅 Fisher's Stew |
| 4 | 220 | `steady_hand_1` 稳手 I：全部菜金区 +5 个百分点；便利 `queue_two` 排队两锅：Recipes 行长按 → 同一口灶顺序做 2 锅，一次确认，火候各自出现 | 便利 | 1 口灶也能"排两锅" |
| 5 | 400 | 便利 `clue_double` 双线索：每条**新的**失败组合在 Hidden 页翻 2 槽线索（原 1 槽）；Mastered 阈值 Cooked 10 → 7；**P2 预留行**：`tool_ferment_jar` 发酵罐 Ferment Jar 配方（酸奶 / 泡菜，新菜系 Pickled） | 便利（+ P2） | 实验命中率明显上来；第一件专用器具（P2） |
| 6 | 650 | **第 4 投料槽** → 4 槽签名页可做：1 页在家可做（`dish_homestead_feast`），4 页需 ≥ 2 个气候带的地区特产 | **改变日常 ②** | 第一次"为了一道菜去另一个气候带" |
| 7 | 950 | `steady_hand_2` 稳手 II：金区再 +5（累计 +10）；**P2 预留行**：`tool_jelly_mold` 果冻模 Jelly Mold 配方（甜品新页） | 便利（+ P2） | Rare 的 Perfect 概率从约 25% 到约 35% |
| 8 | 1,350 | 旅途行囊 Provisions 3 → **4 格**（只收 Trail Food）；便利 `cook_all` 全部开火：Recipes 页顶部 **Cook All**，按料够的顺序把所有空闲灶一次排满 | 便利 | 3 口灶 1 分钟排满；出远门多带一份干粮 |
| 9 | 1,900 | **第 5 投料槽** → 5 槽盛宴页可做（≥ 3 个气候带） | **改变日常 ③** | 一道菜装下三趟旅行 |
| 10 | 2,600 | 称号 `title_star_chef` Star Chef；Cookbook 签名 / 盛宴分组金丝带；名片常驻；**P3 预留行**：料理 Buff 时长 +1 h | 称号（+ P3） | 大师 |

补充：
- 火候金区叠加上限 **60%** 不变（账号首次教学 50% / Mastered +10 / 名厨招牌 +5 / 稳手 +10）。
- 灶口、调味架储物、保温柜、大锅、名厨招牌仍在 Homestead Lv1 / 2 / 3 / 4 / 6 / 8 / 10，一行不改（§9）。
- 会议问到的三个"待细化"在表里的落点：**灶台解锁 / 升级** → 不另设灶台等级，灶口数仍随 Homestead；若 P2 想要"铁灶"之类的外观升级，作为 Homestead 外观 a / b 的一部分，不带数值。**专用器具** → Cooking Lv5 / Lv7 两个预留行，P2 填入；器具是厨房设施（像调味架），不是 Tools & Gear 装备。**料理 Buff** → Legendary 与签名 / 盛宴页每页 1 个 Buff 槽已在总表预留，P3 与矿井 / 战斗 / 装备合成一起细化；Cooking Lv10 的"+1 h"是 P3 的第一个旋钮。

---

## 6 4–5 槽：派生规则扩展与 8 页新配方

### 6.1 派生规则（1–3 槽不变，4–5 槽新增两行）

| 槽数 | 菜品稀有度 | 规则 |
|---|---|---|
| 1–3 | 原 4 × 3 派生表（最高原料稀有度 × 原料族数） | 不变 |
| 4 | **Legendary · 签名 Signature** | 满足其一：① 最高原料 Rare 且 3 族（原规则的自然延伸）；② 3 族 + 含 **≥ 2 个气候带**的地区特产 |
| 5 | **Legendary · 盛宴 Feast** | 3 族 + 含 **≥ 3 个气候带**的地区特产 |

补充规则：
- **气候带口径与旅行许可相同**：地区作物随品种固定（`crop_pineapple` 菠萝 Pineapple 热带 / `crop_sweet_potato` 甘薯 Sweet Potato 亚热带 / `crop_pumpkin` 南瓜 Pumpkin 温带 / `crop_beet` 甜菜根 Beetroot 冷温带）；地区鱼 = 钓到时所在城市的气候带，随鱼堆记录并显示（"Smelt · Temperate"），同一种鱼不同气候带是两堆。
- "Legendary 必有 Rare 原料"原则改写为"必有 Rare 原料 **或** ≥ 2 带特产"：跨气候带的旅行成本被当作稀有度的等价物，与"两带特产 + 100 金币 = 一张旅行许可"是同一个想法。
- **4–5 槽只匹配指定的 4–5 槽页**；凑不成 → 黑暗料理（Rare / Legendary 原料退回）。用重复原料把第 4 / 5 槽填满**不会**降回 3 槽页——否则"多塞一根萝卜"就能把 Rare 菜当签名页拿 XP。
- 允许签名 / 盛宴页使用跨稀有度标签 `Any regional fish`（稀有度已由气候带规则固定，不再有歧义）；这是"标签不得跨稀有度"的**唯一例外**，1–3 槽页仍不允许。
- 5 槽页烹饪 90 秒、火候 3 次（第 30 / 55 / 80 秒）：命中 1–2 次 Good（+10），3 次 Perfect（+20，第 2 份 Plain）。4 槽页沿用 Legendary 的 60 秒 / 2 次。

### 6.2 新页总表（#49–56；回复一律 70，首做 XP 4 槽 80 / 5 槽 120，重复 XP 44 / 60）

| # | id | 中文 | 英文（UI） | 槽 | 原料 | 族 | 需要的气候带数 | 时长 · 火候 | 菜系 | Buff 槽（P3 预留） | 原料轨内容等级 | 用途 | 回收 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 49 | dish_homestead_feast | 农家盛宴 | Homestead Feast | 4 | Any Rare fish ×1 + Any Rare vegetable ×1 + Any Fine fruit ×1 + Any seasoning ×1 | W + F + O + S | 0（**在家可做**） | 60 s · 2 | Stew | Harvest Focus | Fishing 4 / Farming 5 | Eat · Gift · Request | 20 |
| 50 | dish_two_seas_grill | 双海烤鱼 | Two-Seas Grill | 4 | Any regional fish ×2（两带）+ Any Common vegetable ×1 + rock_salt ×1 | W + F + S | 2 | 60 s · 2 | Grilled | Steady Hands | Fishing 1 | Eat · Gift · Request · Trail | 14 |
| 51 | dish_two_zone_stew | 两带炖锅 | Two-Zone Stew | 4 | 2 different regional crops + Any Fine fish ×1 + crop_herb ×1 | F / O + W + S | 2 | 60 s · 2 | Stew | Travel Rations | Farming 5 | Eat · Gift · Request | 24 |
| 52 | dish_north_south_soup | 南北鱼汤 | North-South Soup | 4 | fish_tilapia ×1 + fish_smelt ×1 + crop_potato ×1 + rock_salt ×1 | W + F + S | 2（热 / 亚热 + 温 / 寒） | 60 s · 2 | Soup | Roomy Creel | Fishing 1 / Farming 3 | Eat · Gift · Request | 12 |
| 53 | dish_beet_yam_cakes | 甜菜甘薯饼 | Beet & Yam Cakes | 4 | crop_beet ×1 + crop_sweet_potato ×1 + Any Common fish ×1 + rock_salt ×1 | F + W + S | 2（冷温带 + 亚热带） | 60 s · 2 | Grilled | Harvest Focus | Farming 5 | Eat · Gift · Request · Trail | 18 |
| 54 | dish_world_platter | 环球拼盘 | World Platter | 5 | Any regional fish ×3（三带）+ crop_lettuce ×1 + rock_salt ×1 | W + F + S | 3 | 90 s · 3 | Salad | Steady Hands | Fishing 1 | Eat · Gift · Request | 22 |
| 55 | dish_four_zone_hotpot | 四带火锅 | Four-Zone Hotpot | 5 | 3 different regional crops + Any Fine fish ×1 + crop_chili ×1 | F / O + W + S | 3 | 90 s · 3 | Stew | Angler Focus | Farming 5（辣椒 Farming 4） | Eat · Gift · Request | 30 |
| 56 | dish_passport_pie | 护照派 | Passport Pie | 5 | crop_pineapple ×1 + crop_sweet_potato ×1 + crop_pumpkin ×1 + crop_beet ×1 + crop_herb ×1 | F + O + S | 4 | 90 s · 3 | Dessert | Travel Rations | Farming 5 | Eat · Gift · Request · Trail | 34 |

读数：
- #49 是 Lv6 的"在家兜底"：Lv6 的 30 分钟玩家当晚就有一页可点亮，不会出现"升了级却一页都做不了"。它按原规则（Rare × 3 族）成 Legendary，不需要任何旅行。
- #50 / #54 用地区鱼：任何城市的 Common 地区鱼 Fishing Lv1 就能钓，所以"到了外城当天就能拿到那一带的一味"。#52 把罗非鱼与胡瓜鱼放在同一口锅里——两种 Common 地区鱼永远不会在同一座城出现，这页就是"你去过两种气候"的证明。
- #56 四种地区作物齐全，是全表最远的一页（四带 = 至少三趟不同气候带的旅行，或在温室里种齐），放在 Dessert · Trail Food，是出最远门时带的干粮。
- 硬约束复核：总页数 56 ≤ 60；Legendary 16 ≥ 6；含鱼 38 / 56 = 68% ≥ 40%；Grilled + Dessert 29 / 56 = 52% ≥ 30%；六菜系各 ≥ 3；Cookbook 里程碑按 1/6、2/5、3/4、全部换算为 **9 / 22 / 42 / 56**（称号名不变）。

### 6.3 签名 / 盛宴页在 P0 期间（无 Buff）值什么

| 价值 | 内容 |
|---|---|
| 全额 XP | Lv6–10 唯一不衰减或少衰减的来源（§3.2） |
| 首做 XP | 80 / 120，8 页合计 760 |
| Cookbook | 单独分组 Signature / Feast，金框加丝带；"全部 Discovered" 里程碑包含它们 |
| 赠礼 / 委托 | 对口味为 "Rare 以上" 的居民命中 +3；委托可按"任意签名页"要菜，金币按原料回收价 × 0.8 + 品质加成 |
| 城市成就 | 页上记录首做城市；"Local 本地人"条件可引用本气候带的签名页 |
| 回复 | 70，与 Legendary 相同——**不动体力账**，日食物上限 200 照旧封顶 |

---

## 7 与地区食材 / 旅行的联动

### 7.1 每级"在家能做到哪、哪些要异城食材"

| Cooking Lv | 在家能做的最高档 | 需要异城食材的部分 | 全额 XP 来自 |
|---|---|---|---|
| 1–2 | Fine（Common 主料 + 调味；Fine 鱼单做） | — | Common / Fine |
| 3–5 | Rare（三族；Fine 主料 + 另一族）；Legendary 在家只有 3 页：`dish_legend_sashimi` 传说鱼刺身 Legend Sashimi、`dish_steamed_sturgeon` 清蒸鲟鱼 Steamed Sturgeon（Fishing Lv7）、本气候带那一页地区 Legendary（家格 Market 卡 500 + 本带地区种子） | 另外三个气候带的地区 Legendary 页（Market 只卖本带的卡）；`dish_pineapple_barra` 菠萝尖吻鲈 Pineapple Barra 对非热带玩家 | Rare / Legendary |
| 6–8 | 4 槽 #49 农家盛宴（在家）；Legendary 同上 | 4 槽签名页 #50–53 需 ≥ 2 带；**Lv8 起 Rare 只有 25%**，全额实际只来自 Legendary 与签名页 | Legendary / 签名页 |
| 9–10 | — | 5 槽盛宴页 #54–56 需 ≥ 3 带，是 Lv9–10 唯一全额来源 | 盛宴页 |

### 7.2 与旅行门禁的阶梯对齐

| 旅行侧已有的门槛 | 烹饪侧对应的页 | 共同口径 |
|---|---|---|
| Travel Permit 旅行许可 = 两个气候带的特产 + 100 金币 | 4 槽签名页 = 两带特产 + 2 槽家常料 | 同一次 Trip 3–4 带回的 10 条胡瓜鱼，既能做许可，也够做一周签名菜（鱼不腐烂） |
| Trip 5 Continental = 许可 + 印章 ≥ 5 | 5 槽盛宴页 = 三带特产 | Trip 5 到达的第三个气候带，是盛宴页的最后一味 |
| 外城 Market 地区卡（Rare 200 / Legendary 500） | Lv8 起 Rare 25%，Legendary 成主力 | 外城 Market 的卡从"收藏"变成"XP 来源"，常客 −10% 有了理由 |

算例（亚热带家城上海）：家 = 亚热带；青岛 547 km（Trip 4，温带）钓胡瓜鱼 → 两带 → #50 / #52 / #53（甘薯在家 + 甜菜根要冷温带，#53 对他是三带）；曼谷 2,891 km（Trip 5，热带）→ 三带 → #54 / #55。热带家城新加坡 1,600 km 内全是热带：签名页对他要 Trip 5（与旅行许可的购买路线同一处公平兜底），Lv6–8 期间他靠 #49 与在家 Legendary 不会 0 全额 XP。

两条待社交章确认的接口：① 邻居赠送的**生鱼 / 作物**是否可入菜——建议可以，气候带标记随物品走，"朋友从东京寄来一条鱼"是最自然的社交拉力；② 居民委托可否指定签名页——建议可以，但只对关系 ≥ 信赖的居民出现。

---

## 8 与 Farming / Fishing 的 UI 一致性

### 8.1 头像环：双色改三色

| 项 | 现行 | 方案 A |
|---|---|---|
| 头像外圈 | 112 px，双色技能环：Farming 绿半圈 / Fishing 蓝半圈，按等级进度填充 | **三段环**：Farming 绿（左上 120°）/ Fishing 蓝（右上 120°）/ Cooking 琥珀（下方 120°），段间 6° 留白；每段按"本级进度"填充；满级段实心带细金边 |
| 为什么不放别处 | — | 等级环的职能是"一眼看到三条进度"；放到灶台状态牌上只有进厨房才看得见，而 Cooking XP 的飘字就发生在厨房，环放头像上才能让玩家在田里、塘边也看见它在长 |
| 点开 | 个人面板（Skills / Passport / Inbox / Tools & Gear / Settings） | 不变 |
| 风险 | 每段只有约 110 px 弧长，进度细 | 环宽 6 → 8 px；段少于 10% 进度时至少画 4 px 起笔，避免"看不见" |

### 8.2 技能页、Today、门禁卡、灰色提示、升级仪式

| 位置 | 现行 | 方案 A 的改动 |
|---|---|---|
| 技能页 Skills | 两张轨卡 | **三张轨卡**，第三张 "Cooking Lv4 · 212 / 400 XP · Next: Lv5 · Double Clue"；"首次类进度"行的 Dishes first-cooked 4 / 56 移到 Cooking 卡下 |
| 今天的目标 Today | 第二项固定来自技能页（Next level） | 三轨取**最近一次升级的那条**；文案 "Cooking Lv3 · 2 more dishes" |
| 门禁卡（四件事同屏） | 种子摊 / 柜台 / 工作台 | 新增两处：Recipes 行按钮 `4 slots · Cooking Lv6`（点行弹卡："Needs 4 slots · Cooking Lv6 · 180 XP to go · about 12 dishes · Unlocks Signature dishes"）；Experiment 页第 4 / 5 槽画成锁定槽 |
| 灰色与减额 | 钓获 / 收获飘字；柜台三态 XP 标签 | 出锅飘字 "+16 Cooking XP" / "+12 XP ▾"（长按 "Reduced · 75% · you outlevel this dish"）/ 灰字 "Outleveled"；Recipes 每行 XP 三态标签 Full / 50% / None；第一次变灰弹卡 "You've outleveled Grilled Crucian. It still feeds and gifts, but gives no XP. Cook Rare or better for full XP." [Cookbook] [Got it] |
| 升级仪式 | 任一轨首次 Lv2 全幅 ≤ 3 秒；其余 1.5 秒；改变日常类全幅 | Cooking Lv2 在首会话里是**账号第二次**升级，用 1.5 秒横幅 + 升级礼入包动画（教学句已在 Fishing Lv2 说过）；Lv3 / 6 / 9（新槽）全幅 ≤ 3 秒，动画是灶台上多出一个槽位；Lv10 称号全幅 |
| 升级回体力 | 首次升级 +50、其后每级 +30 | 一致：Cooking 每级 +30（首会话第 27 分钟 213 → 243 / 200，仍在 +50 奖励区内） |
| "还差多少"的第二单位 | harvest 9 radishes / about 6 casts | "about 12 dishes"（客户端用该玩家最近 7 天每锅均值换算） |

### 8.3 厨房面板改动

| 区块 | 改动 |
|---|---|
| 顶栏 | `Stove 1/3 · Empty` 右侧加 `Cooking Lv4 · ●●●○○`（5 个槽位点，亮的是可用槽） |
| Recipes 行 | 槽数超过可用槽的页：按钮灰显 `4 slots · Cooking Lv6`；每行右上 XP 三态小标签 |
| Experiment | 槽位 2–5 个横排；锁定槽画锁 + `Lv6` / `Lv9`；From your bag 食材行里地区鱼 / 地区作物带气候带角标（Tropical / Temperate …），凑齐两带时第 4 槽页在 Cookbook 里微光 |
| 出锅面板 | 三选一 Eat / Keep / Gift + Lv2 起第四个小按钮 Cook Again；首做条 "New recipe! · +40 Cooking XP · Cookbook 12/56" |

### 8.4 英文文案表（用户可见一律英文）

| 场景 | 英文 | 中文释义 |
|---|---|---|
| 等级 | Cooking Lv1 … Lv10 / Cooking Lv3 → Lv4 | 等级 |
| 飘字 | +16 Cooking XP / +12 XP ▾ / Outleveled / New recipe! +40 Cooking XP | XP 入账三态与首做 |
| 门禁 | Needs 4 slots · Cooking Lv6 / 3 slots · Cooking Lv3 / 180 XP to go · about 12 dishes / Unlocks Signature dishes | 槽位门禁四件事 |
| 解锁行 | 3rd slot / 4th slot / 5th slot / Steady Hand I / Steady Hand II / Cook Again / Queue ×2 / Double Clue / Cook All / Provisions · 4 slots / Ferment Jar / Jelly Mold | 每级解锁 |
| 横幅 | Cooking Lv2 · Rock Salt ×3 · Recipe: Salt-Grilled Fish / Cooking Lv3 · 3rd slot · Rare dishes unlocked / Cooking Lv6 · 4th slot · Signature dishes / Cooking Lv9 · 5th slot · Feast dishes / Star Chef | 升级横幅 |
| 页类别 | Signature / Feast / Needs 2 climate zones / Needs 3 climate zones / Smelt · Temperate | 签名 / 盛宴与气候带角标 |
| 变灰 | You've outleveled Grilled Crucian. It still feeds and gifts, but gives no XP. Cook Rare or better for full XP. | 首次变灰解释卡 |
| 技能页 | Full XP now: Rare dishes · Steamed Sturgeon / Dishes first-cooked 12/56 / Mastered 3 | 技能页三行 |
| 规则提示 | Double cooks 2, counts as 1 for XP / Mystery Dish gives no XP | 两条防刷提示（长按可见） |

所有名字 ≤ 18 字符（Homestead Feast 15、North-South Soup 16、Four-Zone Hotpot 16、Beet & Yam Cakes 16、Steady Hand II 14）。

---

## 9 与现有第 7 / 8 章（及第 4 / 14 / 15 / 16 章）的冲突与修法

| # | 位置 | 现行写法 | 改为 | 理由 |
|---|---|---|---|---|
| 1 | 第 7 章结论 #4、§7.6.2 | "烹饪本身不是技能，长期成长体现在 Cookbook 完成度与厨房升级"；重复烹饪 0 XP | 烹饪是第三条技能轨；重复烹饪给 4 / 8 / 16 / 32（§3.1），受等级差 | 本方案的核心 |
| 2 | §7.6.2、§7.16.5、第 4 章 §4.2.3 / §4.3 两张来源表 | 首做 XP 10 / 20 / 40 / 80 归"内容等级最高原料所在轨，同级含鱼归 Fishing"（48 页 Fishing 920 / Farming 780） | **全部归 Cooking**；Fishing / Farming 来源表删去"首次做成一道归本轨的料理"两行；"归轨规则"只保留为 Cookbook 排序用的内容等级 | 有了 Cooking 轨以后"做菜涨 Fishing"会被当成 bug；Farming / Fishing 各失去约 1–2 天的一次性 XP（现行模拟已说明首做 XP 对 3 周满级贡献约 1–2 天），在 ±20% 微调带内 |
| 3 | 第 4 章 §4.3.1 首竿 / 首提 | +5 / +5 | **+10 / +10** | 首会话 Fishing Lv2 的 70 XP 里有 10 来自烤鲫鱼首做；移交后第 1 条鱼 = 10 + 10 + 10 + 15 + 5 = 50，第 2–3 条 60，第 5–6 竿 70 → **仍在第 6 竿 Lv2**；会话末 Fishing 110–125（原 130–145），Lv3 仍在第 2 天 |
| 4 | §7.2.3 投料规则、§7.7 厨房升级表 Lv2 行、第 8 章结论 #2、§8.3.1 Lv2 行、§8.3.2 投料槽公式、§4.7.4 "灶口 1 → 3、调味架" | 投料槽 Homestead Lv1 为 2、Lv2 起 3；Lv2 调味架 = "第 3 投料槽 + 四种调味料存架上" | 投料槽 = Cooking Lv1 / 3 / 6 / 9 → 2 / 3 / 4 / 5，**删除**投料槽公式；Homestead Lv2 调味架只保留**储物**（四种调味料各 30 份不占背包，Recipes 一键做时自动从架上扣）；Lv2 "第一眼看见"改为"灶台墙上一排罐子，调味料不再占背包；庭院开黏土溪岸" | 槽位是手艺不是房子；Homestead Lv2 仍有黏土溪岸、多年生槽 +1、第二故乡槽 +1、密友槽 +1 与调味架罐子，不会变空 |
| 5 | §7.7 灶口、保温柜、大锅、第三口灶、名厨招牌 | 随 Homestead Lv1 / 3 / 4 / 6 / 8 / 10 | **不动** | 容量与并行是房子的事；Homestead 的六次"做菜方式变化"保留五次 |
| 6 | §7.4.1 派生表读法"Legendary 必有 Rare 以上原料" | 只有 Rare × 3 族或传说鱼 | 加一条："或 ≥ 2 个气候带的地区特产 + 3 族"（仅 4–5 槽页） | §6.1 |
| 7 | §7.3.3 "标签不得跨稀有度" | 无例外 | 签名 / 盛宴页允许 `Any regional fish`、`N different regional crops` | 稀有度已由气候带规则固定 |
| 8 | §7.14 配方总表 48 页、§7.6.1 里程碑 8 / 20 / 36 / 48、§7.10 硬约束 | 48 页 | 56 页（新增 #49–56）；里程碑 9 / 22 / 42 / 56；硬约束复核全部通过（§6.2） | — |
| 9 | §7.5.1 Mastered 阈值 Cooked ≥ 10 | 固定 | Cooking Lv5 起 ≥ 7；Mastered 另给一次性 +15 Cooking XP | §3.1 |
| 10 | §7.2.4 金区加宽 | 教学 50% / Mastered +10 / 名厨招牌 +5，上限 60% | 加稳手 I / II 各 +5；上限 60% 不变 | §5 |
| 11 | 第 11 章行囊 Provisions 3 格 | 固定 3 | Cooking Lv8 起 4 格 | §5 |
| 12 | 第 4 章 §4.1 对象表、§4.7 门禁表、§4.8.4 技能页 | 两轨 | 加 `cooking` 轨、`skill_level · cooking` 门禁表（三行：3 / 4 / 5 槽）、技能页三卡；"永不锁"行"烹饪 / 进食 / 配方实验 / 黑暗料理"保留——Cooking Lv1 的 2 槽永远可用 | 一张表登记全部门禁的原则不变 |
| 13 | 第 8 章 §8.1.1 技能和 ≥ 2N − 1 | Farming + Fishing | **不变**，Cooking 不计入 | Cooking 是两轨的下游，计入会把同一份原料算两次；且不必重跑 Homestead 模拟 |
| 14 | 第 10 / 16 章 HUD、第 16 章 HUD-1 生图简报 | 双色技能环 | 三段环（§8.1）；文案"two-color ring" → "three-segment ring" | — |
| 15 | 第 14 章导演表、首会话 XP 账与体力账 | 第 16 分钟 "+10 Fishing XP"；第 27 分钟 "+20 Fishing XP"；结束 213 / 200 | 见 §10 | — |
| 16 | 第 15 章模拟 | 两轨 + 首做归原料轨 | 加 Cooking 轨（§4 的手算需复核）；Farming / Fishing 去掉首做 XP 后若 30 分钟玩家 Fishing 超出 26 天，旋钮是 Fishing Lv8–10 再 −5%（2,400 / 3,100 / 4,000 → 2,280 / 2,950 / 3,800） | 在 ±20% 带内 |

---

## 10 首会话影响

### 10.1 导演表改动（只列变化的行；体力含"每级 +30"）

| 累计时间 | 现行 | 方案 A | 备注 |
|---|---|---|---|
| 9–14 分钟 | 第 1 条鱼 40 XP（首竿 5 + 首提 5 + 首城 10 + 首钓 15 + 钓获 5） | 第 1 条鱼 **50**（首竿 10 + 首提 10 + …）；技能条 "Fishing 60/70 · Lv 2 in 10 XP · about 2 casts" | 补回烤鲫鱼首做移走的 10 |
| 14–16 分钟 | 出锅 "First cooked! +10 Fishing XP · Cookbook 1/48" | 出锅 "First cooked! **+15 Cooking XP** · Cookbook 1/56"（Good 5 + 首做 10）；头像环下方琥珀段第一次亮起 | 玩家第一次看到第三条轨 |
| 18–22 分钟 | 第 5–6 竿 → 70–85 → Fishing Lv2 | 不变（60 → 70–85） | Lv2 仍在第 6 竿、约第 22 分钟 |
| 25–28 分钟 | 出锅 "New recipe! Herb Grilled Fish · +20 Fishing XP · Cookbook 2/48"；Eat 置灰 → Keep | 出锅 "New recipe! Herb Grilled Fish · **+30 Cooking XP** · Cookbook 2/56"（Good 10 + 首做 20）→ 累计 45 → **横幅 1.5 秒 "Cooking Lv2 · Rock Salt ×3 · Recipe: Salt-Grilled Fish · +30 Energy"**；Recipes 页多一行 Salt-Grilled Fish（Tasted，背包里 2 条 Common 鱼 + 岩盐，按钮 Cook 亮）；出锅面板多出 Cook Again 按钮 | 门打开 = 立刻有料能用；**可停点**：做不做盐烤鱼都行 |
| 28–30 分钟 | 结束 213 / 200；头像外圈蓝半圈 | 结束 **243 / 200 · bonus**（+30 升级回复，仍在 +50 奖励区内）；头像三段环：蓝段 Lv2、琥珀段 Lv2、绿段空；技能页三卡 "Cooking Lv2 · 45/100 · Next Lv3 · 3rd slot" | 若觉得 243 太高，旋钮是 Cooking 升级回复改为 +20 |

### 10.2 首会话 XP 账（修订后）

| 事件 | Fishing | Cooking |
|---|---|---|
| 第 1 条池塘鲫鱼（首竿 10 + 首提 10 + 首城 10 + 首钓 15 + 钓获 5） | 50 | — |
| 第 2、3 条池塘鲫鱼 | 60 | — |
| 首次做成烤鲫鱼（Common Good 5 + 首做 10） | 60 | **15** |
| 第 4 竿 Fine 鱼挣脱 | 60 | — |
| 第 5、6 竿 Common（若其一为鲤鱼首钓 +15） | **70（或 85）→ Lv2** | — |
| 第 7 竿河鲈（蚯蚓）10 + 首钓 30 | 110–125 | — |
| 首次做成香草烤鱼（Fine Good 10 + 首做 20） | 110–125 | **45 → Lv2** |
| （可选）盐烤鱼 Fine Good 10 | — | 55 |

### 10.3 风险与处置

| 风险 | 处置 |
|---|---|
| 5 分钟内两次升级横幅（Fishing 第 22 分钟、Cooking 第 27 分钟）过载 | Cooking Lv2 用 1.5 秒横幅（不是全幅），教学句不重复；升级礼入包动画 0.8 秒 |
| 新玩家分不清三条轨 | 首会话里三条轨的第一次入账都伴随飘字写明轨名（"+15 Cooking XP"），头像环三段分色；Farming 段在第二次会话首收时亮 |
| 结束体力 243 看起来"太满" | 奖励区本来就不回复，差别只是第二次会话进场多 30；若要压，Cooking 每级 +20 |

---

## 11 最可能被攻击的 5 点与回应

| # | 攻击 | 回应 |
|---|---|---|
| 1 | **"做菜 0 体力却给 XP，违反'XP 只来自付了体力的产出'总则；重度玩家会把所有鱼都做成菜刷 Cooking。"** | ① 原料付过体力且被消耗，Cooking XP 是同一份体力在**另一条轨**上的记账，同轨内无动作被计两次；② 等级差衰减按 Cooking 内容等级执行：Lv6 后 Common 灰、Lv7 后 Fine 灰、Lv8 后 Rare 25%，"把所有鱼做成菜"在第二周起只对 Legendary / 签名页有效，而这些受传说鱼掉率与旅行节奏约束；③ 黑暗料理 0、Double 按一次计、3,000 防脚本上限照用；④ 每体力 XP 0.8–3.6，低于 Fishing 上段的 8。重度玩家本来就会把鱼做成菜（原料价 44 金币换 200 体力），方案 A 只是让这件事有了进度条，没有改变他的行为 |
| 2 | **"第三条轨让 HUD、技能页、首会话都过载；头像三段环太细看不见。"** | 不新增任何面板：三段环、三卡技能页、门禁卡、灰色提示、升级横幅全部复用两轨模板；首会话只多一个 1.5 秒横幅与两处飘字的轨名变化，Today 面板仍 ≤ 3 行。三段环每段约 110 px 弧长、8 px 环宽，最小起笔 4 px；对照：现行体力条 240 × 12 px 的三段色就在它旁边，尺度一致。若内测证明三段难辨，退路是环只画**最近一次有进度的两条轨**，第三条在技能页看 |
| 3 | **"把投料槽从 Homestead 搬走，掏空了 Homestead Lv2 的'第一眼看见'，也让 Homestead 对料理的六次改变少了一次。"** | Homestead Lv2 仍有四件可见的事：调味架罐子（调味料不占背包，Recipes 一键做自动扣）、黏土溪岸开放、多年生槽 2 → 3、第二故乡槽 1 → 2；厨房的其余五次变化（保温柜 / 第二口灶 / 大锅 / 第三口灶 / 名厨招牌）一行不动。而搬走槽位换来的是会议明确要的东西：槽位随手艺长到 5 个，30 分钟玩家第 15 天拿到第 5 槽，而不是挂在 Homestead 上等两个月。"农场决定厨房多大、技能决定手能做什么"比"槽位也是房子的事"更容易向玩家解释 |
| 4 | **"Cooking 完全依附 Farming / Fishing，不是独立成长：重度玩家 11 天满级只是顺手；三类玩家的 Cooking 天数和他们的 Fishing 天数几乎一样，等于多画一条一样的曲线。"** | 它**有意**是下游轨：会议要它做的是两件事——槽位解锁与把玩家推向异城食材，不是另一个 grind。独立性体现在分化处：5 分钟玩家 Farming 56 天、Cooking ≈ 100 天（他不吃不旅行）；种田向 30 分钟玩家 Fishing 39 天但 Cooking 仍约 22 天（他每天做 4–5 道菜）；只钓不做菜的玩家 Fishing 满级时 Cooking 可能还在 Lv4。曲线不同的地方正是"做菜习惯"不同的地方。对比另两个方案：B（材料门禁）会让 Cooking 的节奏变成第二个 Homestead 账单，C（并入 Homestead）让第 5 槽等两个月——两者都做不到"每一次开火都是进度" |
| 5 | **"4–5 槽页打破派生表与'Legendary 必有 Rare 原料'原则，回复还是 70，P0 没有 Buff——没人会为它跑两个气候带。"** | ① 规则扩展只加两行、一条例外，且与旅行许可"两带特产 = 去过两个气候带"是同一口径，不是新概念；② P0 的动机已经够：Lv6–10 **唯一**的全额 XP、首做 80 / 120、Cookbook 独立分组、对 "Rare 以上" 居民 +3、委托可点名、城市成就可引用；③ 回复维持 70 是刻意的——方案的体力账（日食物上限、730 上界）一个数字都不用动，这比"签名页回 100"安全得多；④ 同一次旅行带回的地区鱼既做许可又做签名菜，边际成本接近零；⑤ #49 在家可做保证 Lv6 不是空级。若内测显示签名页做得太少，第一旋钮是把签名 / 盛宴的重复 XP 44 / 60 提到 52 / 72，不动回复 |

另一条会被提但较弱的攻击：**"5 分钟玩家约 100 天满级，超出 ≤ 90 天目标。"** 回应：他的 Cooking 停在 Lv8–9 不影响任何可做的事（Common / Fine / Rare 全在手里，4 槽 #49 在家可做）；与他 Fishing 84 天同量级；旋钮 Lv9–10 −10% 可拉回 90 天，代价是 30 分钟玩家提前 1–2 天。

---

## 12 待拍板与旋钮

| 项 | 建议 | 备选 |
|---|---|---|
| 首做 XP 归属 | 全部归 Cooking；Farming / Fishing 以首竿 / 首提 +10 补首会话，必要时 Fishing Lv8–10 再 −5% | 两边都给（原料轨 10 / 20 / 40 / 80 + Cooking 同额）：不动现有模拟，但一次出锅两条飘字，且"做菜涨 Fishing"的解释成本回来了 |
| 槽位落点 | Lv1 / 3 / 6 / 9 → 2 / 3 / 4 / 5 | Lv1 / 2 / 5 / 8（更早）：Lv2 在首会话给第 3 槽会让 Rare 三族菜出现在第 1 天，不建议 |
| Cooking 是否计入 Homestead 技能和 | 不计入 | 计入并改为三轨之和 ≥ 3N − 2（Lv10 需 28）：需重跑 Homestead 模拟 |
| 5 槽页火候 | 90 秒 3 次 | 60 秒 2 次（与 Legendary 完全同表，少一个特例） |
| 邻居赠送的生鱼 / 作物可否入菜 | 可以，气候带标记随物品走 | 不可（只允许赠菜）：签名页的社交拉力消失 |
| 升级回体力 | 每级 +30（与两轨一致） | Cooking 每级 +20：首会话结束 233 而非 243 |
| 5 分钟玩家 100 天 | 接受并注明 | Lv9–10 阈值 −10% |


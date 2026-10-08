# P1 第一步开发包：第 5 天之后的种田（40 格、卷心菜 / 玉米 / 黄瓜、洒水器）

- 日期：2026-10-08；起草：李白（SGODOT 方案回写 q(59)）。
- 依据：方案 `gameplay-plan-v2-2026-10-02.md` §17.3.3 第 1 行（q(52)），规则以第 5 章 §5.2.2、§5.3、§5.7、§5.8 与 q(22)、q(23) 为准；本包只写第一步要做的部分，以及为了在紧凑农场上落地而新定的口径（第 1 节，均已写回方案 q(59)）。
- 现状依据：`origin/farm-dev` 的 P0 实现（`assets/p0/p0_content.json`、`server/src/p0/*`、`modules/p0/p0_garden.gd`、`scenes/p0/p0_farm.gd`），S5 料理页取自 `febf15f2`（q(39) 的 14 页）。
- 模拟：`docs/product/research/gameplay-plan-v2-2026-10-02/p1-step1-2026-10-08/p1_step1.py`，结果在同目录 `out_14d.md`。

## 0. 目标与范围

**为什么先做这一步**：P0 的种田内容停在 Farming Lv4（番茄、辣椒）。重度玩家第 4 天、目标玩家第 6 天到 Farming Lv5，之后升级只给 +30 体力；30 格田在第 2 周开始卡住重度玩家（14 天里有约 1,660 点播种预算因为没有空田花不出去）。

**做**：

| # | 内容 | 门槛 |
|---|---|---|
| 1 | 田块 30 → 40 格（多出 10 格荒地） | Homestead Lv3 |
| 2 | 作物卷心菜 Cabbage、玉米 Corn | Farming Lv5 |
| 3 | 作物黄瓜 Cucumber | Farming Lv6 |
| 4 | 料理 4 页：Cabbage Stew、Cucumber Salad、Roast Veggies、Corn Cake（当期 14 → 18 页） | 随作物 |
| 5 | 洒水器 Sprinkler：工作台 Facilities 页签、放置模式、自动浇水、−15% 成熟时长 | Farming Lv6 |
| 6 | 便利 Coverage Overlay（田上叠显洒水器覆盖） | Farming Lv6 |
| 7 | Farming Lv5 / Lv6 升级横幅与门禁卡、技能页分母 | — |

**不做**（各自归到后面的步骤，或已定推后）：
- Sow Again（Lv5 便利）：与 Plot Marks 一起做，两者共用"格子记住作物"的标记（q(23)、q(44)）。
- 地区种子购买资格（Lv5）：随集市出售地区种子那一步（第 5、6 步的经济 / 居民内容）。
- 堆肥箱、苹果树、果木肥（Lv7）、温室、草莓（Lv8）、甜瓜与果树（Lv9）：后续步骤。
- 布置模式 Decorate：第 5 步。洒水器的"移动"在本步用状态卡上的 `Move` 进放置模式，不等布置模式。
- 配方卡（驿站每日 2 张）：随 NPC / 经济那一步；本步 4 页只能在 Experiment 里试出来。
- Homestead Lv4 以后的田数：随第 3 步（Homestead Lv4–5）一起定，见 1.1。

## 1. 已定口径（q(59)）

### 1.1 田块：Homestead Lv3 起 40 格

| 项 | 规则 |
|---|---|
| 田数 | Homestead Lv1–2 **30 格**（同 P0）；**Lv3 起 40 格**。升到 Lv3 那一刻多出 10 格**荒地**（翻地 0 体力，同 P0 的 10 格荒地） |
| 编号 | 0–29 的编号与位置**不动**（存档里的作物不搬家）；新 10 格编号 30–39 |
| 位置 | 建议：在现有 6 列 × 5 行的右边加两列（P0Garden 的 x = 16、18，y = 3…11），整块变 8 列 × 5 行；井（17, 8）会落进田里，挪到田外或由客户端与美术总监另定。周瑜 231 的采集点也压在这两列上：Rock Pile (18, 4) 会卡在新田的走道里，Timber Grove (17, 12) 的树干格 (18, 11) 压到一格新田；左侧（芦苇、黏土、矿口）与前排（出生点、出口）没有空位，所以保留右侧两列，把 Rock Pile、Timber Grove 挪到院子右上 / 右下角，用 PR-B 的「占地不重叠、不压田、不出院子」测试兜住，请不知火舞复核（周瑜 2026-10-08）；Timber Grove 挪到 (17, 12) 后树冠仍压到最后一行新田，一起挪开。Lv3 整圈篱笆东边在 12.95 m，新列东沿约 12.50 m，包得住，篱笆不用改（苏烈核过）。最终位置由客户端按 `P0Garden.FOOTPRINTS` 排，不得挡驿站棚、工作台、矿口与出入口的路 |
| 升级时刻 | HOME-2 的 Lv3 后果飘字加一行 `Plots +10`，新 10 格随篱笆一起从上方落位；HOME-1 的 Lv3「升了会怎样」加 `Plots +10`（方案原写 `Plots +40` 是地理农场的尺度） |
| 田数显示 | 紧凑农场的每一格都在画面里，**不做** `Plots 32/40` 一类的计数角标 |
| 已是 Lv3 的存档 | 版本更新后立即补上 30–39 号荒地（服务端迁移） |
| Lv4 以后 | 方案 §8 的开垦上限列（Lv1 200 → Lv10 600）是地理农场的尺度，P1 紧凑农场不用；Lv4–10 的田数随第 3 步重算（要连同 §4.4、§15 重度全种的上界一起复跑）。在那之前 Lv4 以上仍为 40 格 |

为什么挂 Homestead Lv3，而不是开局就 40 格：首周的约束是种子钱，不是田（V1：30 格因钱停播 100 次、因田满停 73 次）。目标玩家第 9 天到 Lv3，正好是 30 格开始卡住、手里也有钱的时候。Homestead Lv3 也因此在农场里多了一处看得见的变化（§17.3.2「每级有后果」）。开局 40 格的对照（E2）见第 6 节：目标玩家 Farming 多 7%，代价是 Lv3 少一个后果。

### 1.2 三种新作物（数值照 §5.2.2）

| id | 英文 | 档 / 体力 | 内容 Lv（= 门槛） | 族 / 稀有度 | 种子价 | 成熟 h | 产量 × 单价 | XP / 株 | 首收 | 变灰 Lv |
|---|---|---|---|---|---|---|---|---|---|---|
| `crop_cabbage` | Cabbage | 2 / 3 | 5 | 田 / Common（`F1`） | 10 | 12 | 1 × 13 | 3 | 15 | 10 |
| `crop_corn` | Corn | 3 / 4 | 5 | 田 / Fine（`F2`） | 11 | 16 | 3 × 5 | 4 | 20 | 10 |
| `crop_cucumber` | Cucumber | 2 / 3 | 6 | 田 / Common（`F1`） | 7 | 9 | 2 × 5 | 3 | 15 | — |

- 种子 `seed_cabbage` Cabbage Seeds、`seed_corn` Corn Seeds、`seed_cucumber` Cucumber Seeds，在农场驿站 Homestead Stall 出售，无日库存；未到等级时可见不可买，选中弹门禁卡（§4.8.7）。
- 作物图鉴与技能页的首次类进度：`Crops first-harvested n/11`。
- 复数：Cabbages、Cucumbers 加 s，Corn 不变（Today 行等处）。

### 1.3 料理 4 页（当期 18 页，Cookbook 仍显示 48 页剪影）

| # | id | 英文 | 槽 | 原料（`in`） | 稀有度 | 菜系 | 发现 | 作用 |
|---|---|---|---|---|---|---|---|---|
| 8 | `dish_cabbage_stew` | Cabbage Stew | 2 | `crop_cabbage` + `crop_potato` | Common | Stew | Experiment | 卷心菜的专属页 |
| 18 | `dish_cucumber_salad` | Cucumber Salad | 2 | `crop_cucumber` + `crop_herb` | Fine | Salad | Experiment | 黄瓜的专属页；香草的又一个去处 |
| 21 | `dish_roast_veggies` | Roast Veggies | 1 | `F2`（任意 Fine 蔬菜） | Fine | Grilled | Experiment（**田 × Fine 兜底页**） | 番茄、玉米单独下锅不再失败 |
| 22 | `dish_corn_cake` | Corn Cake | 2 | `crop_corn` ×2 | Fine | Dessert | Experiment | 第二道甜品：Pip 喜欢甜品，Fine 甜品送 Pip 好感 +3 |

- 数值全部由派生表得出（§7.4）：Common 20 · 5 s · 首做 10；Fine 40 · 15 s · 首做 20。
- 卷心菜、黄瓜是 `F1`，自动进入现有的 Veggie Plate、Fresh Fish Soup；玉米是 `F2`，进 Roast Veggies。
- 技能页 `Dishes first-cooked n/18`；出锅卡奖励条分母仍是 `Cookbook n/48`（q(55)）。
- **P0 已知差异**：P0 的 14 页没有田 × Fine 兜底页，番茄单独下锅出 Mystery Dish（新手期退料），与 §7.2.3「单主料必有一道菜」不符。P0 试玩期间不改，P1 第一步补回 Roast Veggies 后恢复。

### 1.4 洒水器（按 §5.7 原规则：占 1 格田，浇周围 8 格）

| 项 | 规则 |
|---|---|
| 门槛 | Farming Lv6（改变日常 ①）。工作台 Facilities 页签从 P1 起显示，第一步只有 Sprinkler 一张蓝图卡；Lv6 前卡片锁住，点了弹门禁卡 |
| 配方 | Timber 8 + Stone 6 + Copper Ore 3，从农场仓库先扣、再扣背包（同 P0 工作台） |
| 数量上限 | 3 + Homestead 等级：Lv1 4 / Lv2 5 / Lv3 6；到上限时蓝图卡按钮写 `Sprinklers 6/6 · Homestead Lv4 adds 1`，不进放置模式 |
| 建造 | 一步建造（q(22)）：材料齐时蓝图卡按钮 `Build` → 放置模式 → 再按 `Build` 才一次扣清材料并落位；`Cancel` 不扣任何东西；没有"做好未放"的库存 |
| 放在哪 | 一块**空田**：已翻或荒地、没有作物、没有别的设施。不合法时只把中心格染红，按钮写 `Plot occupied`（有作物或设施）/ `Outside your fields`（田外） |
| 覆盖 | 田格网上**周围 8 格**（含斜角；新加的两列与旧田连成一张网）。靠边的洒水器覆盖少于 8 格，预览小标写实数 `Coverage preview · 5 plots`。覆盖可以重叠 |
| 浇水 | 覆盖内的格**播种即开始生长**（跳过"已播待浇"）；放下洒水器时，覆盖内已播未浇的格立即开始生长 |
| 缩时 | 成熟时长在开始生长那一刻锁定：× (1 − 0.15〔覆盖〕− 0.20〔已施堆肥〕)，合计封顶 −35%。已经在长的作物不重算。浇水之后再施堆肥仍按 P0 规则：剩余时长 × 0.8 |
| 占格的代价 | 洒水器所在的格不能种。8 列 × 5 行的田全覆盖要 6 台，可种 34 格；30 格时 4 台、可种 26 格。模拟（E3 vs E）：目标玩家 Farming −1%、重度 −2.4%，在可接受范围内；保持 §5.7 与 FARM-5 稿的规则，不另做"走道洒水器" |
| 移动 / 拆除 | 点洒水器 → 状态卡（`Sprinkler · Waters 8 plots`、`Move`）。`Move` 进同一个放置模式，0 成本；原格变回已翻。**不可拆除**（q(22)） |
| 帮工 | P1 第一步没有帮工；以后帮工在覆盖内补播照常扣帮工体力（§5.7） |

### 1.5 Coverage Overlay（Farming Lv6 便利）

- **常显**：在 Farming 行动下站在田里时，被洒水器覆盖的田块描一圈浅蓝边；没被覆盖、已播未浇的格照旧显示水滴状态。
- **点击**：点洒水器时高亮它覆盖的格，与状态卡同时出现。
- 放置模式里的覆盖预览（3 × 3 浅蓝）人人都有，不算便利（q(23)）。

### 1.6 升级与门禁

| 场景 | 呈现 | 文案 |
|---|---|---|
| Farming Lv5 | MomentBanner LevelUp 1.5 秒（§4.8.6） | `Farming Lv 5` / `Cabbage, Corn` / `+30 Energy` / Detail `Next Lv6 · Cucumber, Sprinkler · 250 XP` |
| Farming Lv6（改变日常） | 全幅 ≤ 3 秒 | `Farming Lv 6` / `Cucumber, Sprinkler` / `+30 Energy` / `Today changes: no more watering` / 动作 `Show Workbench`（只移动相机到工作台，不打开、不跳转，LOCK-08） |
| 技能页 Next 行 | 只列当期内容（§4.8.6 技能页规则） | Lv4：`Next: Lv5 · Cabbage, Corn · 200 XP`；Lv5：`Next: Lv6 · Cucumber, Sprinkler · 250 XP`；Lv6 起：`Next: Lv7 · 300 XP`（第一步没有 Lv7 内容） |
| 门禁卡（§4.8.7 新增 3 行） | InfoSheet 四行 + `Show my plots` | 驿站种子 `Cabbage Seeds / Corn Seeds` · `Farming Lv5` · `120 XP to go · harvest 30 tomatoes` · `Unlocks Cabbage, Corn`；驿站种子 `Cucumber Seeds` · `Farming Lv6` · … · `Unlocks Cucumber`；工作台 `Sprinkler` · `Farming Lv6` · … · `Waters 8 plots for you` |

「还差多少」按 §4.8.7 的算法取：作物取玩家当前能种、全额 XP 的最高档，N = ⌈xp_to_go ÷ 每株 XP⌉。样例按 Lv4 的番茄（4 XP / 株）。

### 1.7 其他

- **旋钮 A 保留**：P0 矿洞第 2 层的石英并入岩盐（q(47)）。原定「P1 恢复原表」改为随第 4 步（矿洞 3–5 层与石英）一起恢复；第 1–3 步都用不到石英，提前恢复只会让盐变少。
- **英文文案**：见第 4 节；附录 B.5 同步。

## 2. 数据改动（`assets/p0/p0_content.json`）

字段沿用现有结构，名字按实现习惯取，下表只列要加的东西。

| 位置 | 改动 |
|---|---|
| `crops` | +3 条，字段同现有作物（`id, name, seed, seed_name, tier, energy, level, gate, seed_price, grow_h, yield, price, xp, first_xp, ingr`）：卷心菜 `tier 2, energy 3, level 5, gate 5, seed_price 10, grow_h 12, yield 1, price 13, xp 3, first_xp 15, ingr [F,1]`；玉米 `tier 3, energy 4, level 5, gate 5, seed_price 11, grow_h 16, yield 3, price 5, xp 4, first_xp 20, ingr [F,2]`；黄瓜 `tier 2, energy 3, level 6, gate 6, seed_price 7, grow_h 9, yield 2, price 5, xp 3, first_xp 15, ingr [F,1]` |
| `stall.buy` | + `seed_cabbage`、`seed_corn`、`seed_cucumber`（排在番茄之后，按门槛升序） |
| `cooking.recipes` | +4 页（`n` 8 / 18 / 21 / 22，`learn: [experiment]`），原料见 1.3；稀有度、回复、时长、首做 XP 走 `derive` |
| `homestead.levels[Lv3].unlocks` | + 田块 40（如 `plots_40`）；`start` 里 30 格的定义不变 |
| `workbench` | `tabs` + `facilities`；`recipes` + `craft_sprinkler`（`tab: facilities`，`out: facility_sprinkler`，新去向 `to: field` = 进放置模式，`cost [[wood,8],[stone,6],[copper_ore,3]]`，`gate [farming,6]`） |
| 新块 `facilities` | `sprinkler: {cover: ring8, grow_cut: 0.15, cap_base: 3, cap_per_homestead: 1}`；`grow_cut_cap: 0.35`（与堆肥 0.20 合计） |
| 新块 `garden` | 田格网坐标：`plots[id] = [col, row]`（0–29 = `[id % 6, id / 6]`；30–39 = 新两列），服务端算覆盖、客户端算位置都读它。现在格子坐标只在客户端 `P0Garden`，覆盖要服务端判，所以要挪到共享内容 |

## 3. 服务端（`server/src/p0/*`）

| 模块 | 改动 | 拒绝码 |
|---|---|---|
| `state.ts` | `Plot` 增加可选 `facility`（或独立 `facilities[]`：`{id, kind, plot}`）；`freshState` 不变（30 格）；`upgradeState` 迁移：Homestead ≥ 3 的存档补 30–39 号 `wild` | — |
| `homestead.ts` | 升到 Lv3 时追加 30–39 号 `wild`，回包带 `plots_added` 事件（客户端播落位动画） | — |
| `reducer.ts` · `sow` | 目标格在覆盖内：直接进 `growing`，`ready_at = now + grow_h × (1 − cut)`；`cut` = 0.15 + 0.20（已施堆肥），封顶 0.35 | 照旧 |
| `reducer.ts` · `water` | 覆盖内的格不需要浇（客户端不出 Water 键面）；仍收到时按 `already_growing` 拒绝 | `already_growing` |
| `reducer.ts` · `till` / `sow` / `harvest` | 有设施的格一律拒绝 | `plot_occupied` |
| 新命令 `place` | `{recipe: craft_sprinkler, plot}`：一次校验门槛、上限、材料、目标格，通过后扣材料、落位，并把覆盖内已播未浇的格转 `growing` | `skill_level_required`、`facility_cap`（带 `cap, homestead_next`）、`missing_materials`（带缺口）、`plot_occupied`、`bad_plot` |
| 新命令 `move_facility` | `{facility, plot}`：0 成本；原格回 `tilled`；新格同 `place` 的格校验；已在长的作物不重算 | `plot_occupied`、`bad_plot` |
| `view.ts` | 视图增加 `facilities`、每格 `covered`、蓝图卡的 `cap / used / missing`；驿站种子行照现有 `unlocked / xp_to_go` | — |
| `progress.ts` | Farming Lv5 / Lv6 无升级礼（`level_gifts` 不加）；+30 体力照旧 | — |
| 遥测（#23） | 新增 `facility_placed {kind, plot, covered}`、`facility_moved`；`plots_added`；种子购买沿用现有事件 | — |

## 4. 客户端

| 部分 | 改动 | 依赖 |
|---|---|---|
| 田块 | `P0Garden.plot_count()` 随 Homestead 等级（30 / 40）；`cell_of` / `id_of` 支持 30–39（读共享 `garden` 表，不靠 `COLUMNS`）；去掉"id ≥ 30 丢弃"（`p0_garden.gd:112`、`p0_farm.gd:232`）；`tests/p0/test_p0_garden.gd` 的 30 断言改成按等级 | 共享 `garden` 表 |
| 作物模型 | `crop_field.gd` / `crop_plant_mesh.gd` 加三种程序化植株（4 个生长阶段 + 成熟细节层：卷心菜叶球、玉米秆与穗、黄瓜藤与瓜）；`CROP_CODES` 加三码 | — |
| 图标 | `crop_cabbage / corn / cucumber`、`seed_cabbage / corn / cucumber`、`dish_cabbage_stew / cucumber_salad / corn_cake`、`facility_sprinkler`（`dish_roast_veggies.svg` 已有） | 安其拉出稿（UI 出稿归安其拉，不知火舞验收） |
| 洒水器模型 | 田上的 3D 洒水器 + 喷水的循环小动画（只在覆盖格有作物在长时播） | 先用简单几何体占位；正式模型按"新场景先真人设计"走美术总监（不插队打断现有 3D 制作） |
| 工作台 | 周瑜的工作台抽屉（PR-C，Tools / Supplies）加 Facilities 页签；Sprinkler 蓝图卡照 FARM-5 第五版（图标 + 名称 + 等级胶囊 + 一行效果 + M 号材料进度格 + 写缺口的按钮） | 周瑜 PR-C 合入 |
| 放置模式 | 模态编辑模式的第一个实现（LOCK-01 / 02 例外，q(23)）：按下场景区不召唤摇杆；HUD 只留第一行，快捷栏、主行动键与切换键隐藏；预览默认落在离玩家最近的合法空田，可拖可点；3 × 3 浅蓝覆盖 + 小标 `Coverage preview · 8 plots`；底部操作条 `Build` / `Cancel`；不合法时中心格染红、按钮写原因。之后的布置模式与 Plot Marks 共用这个壳 | — |
| 洒水器状态卡 | 点洒水器 → InfoSheet：`Sprinkler · Waters 8 plots` + `Move`；同时高亮覆盖格（1.5） | 224 InfoSheet |
| 主行动键 | 覆盖内的格播种后不再出 `Water · Free`；有洒水器的格键面不出劳作动词（与站在设施前相同） | — |
| 驿站 | 三种种子的货架行与锁态（现有 `_buy_row` 的 `Farming Lv%d · %d XP to go` 胶囊） | — |
| 横幅 | Farming Lv5（1.5 秒）、Lv6（全幅 ≤ 3 秒 + `Show Workbench`） | 233 MomentBanner |
| HOME-1 / HOME-2 | Lv3 后果行 `Plots +10`；升级时刻新 10 格随篱笆落位 | 苏烈 HOME 面板 |
| Cookbook | 4 页从剪影变可发现；`Dishes first-cooked n/18` | 哪吒厨房 |

## 5. 英文文案（附录 B.5 同步）

| 场景 | 文案 |
|---|---|
| 种子 / 作物名 | Cabbage Seeds / Corn Seeds / Cucumber Seeds / Cabbage / Corn / Cucumber |
| 菜名 | Cabbage Stew / Cucumber Salad / Roast Veggies / Corn Cake |
| 升级 | Farming Lv 5 · Cabbage, Corn · +30 Energy · Next Lv6 · Cucumber, Sprinkler · 250 XP / Farming Lv 6 · Cucumber, Sprinkler · +30 Energy / Today changes: no more watering / Show Workbench |
| 蓝图卡 | Sprinkler / Farming Lv6 / Waters 8 plots for you / Timber 8/8 · Stone 6/6 · Copper Ore 1/3 / Need 2 more Copper Ore / Farming Lv6 needed / Build / Sprinklers 4/4 · Homestead Lv2 adds 1 |
| 放置模式 | Coverage preview · 8 plots / Build / Cancel / Plot occupied / Outside your fields |
| 状态卡 | Sprinkler · Waters 8 plots / Move |
| Homestead Lv3 | Plots +10 |
| 门禁卡 | Cabbage Seeds · Farming Lv5 · 120 XP to go · harvest 30 tomatoes · Unlocks Cabbage, Corn / Cucumber Seeds · Farming Lv6 · Unlocks Cucumber / Sprinkler · Farming Lv6 · Waters 8 plots for you |
| 技能页 | Next: Lv5 · Cabbage, Corn · 200 XP / Next: Lv6 · Cucumber, Sprinkler · 250 XP / Next: Lv7 · 300 XP / Crops first-harvested 9/11 / Dishes first-cooked 12/18 |

## 6. 模拟复跑（14 天 × 30 seed，口径同 q(54) 的基线 D）

`p1_step1.py`（复用 `p0_v1.py` 的基线 D：旋钮 A + V2 机器人买卖打法），四个情形：D = P0；E = 本包；E1 = 只加作物与料理；E2 = 开局就 40 格；E3 = 洒水器占 1 格（本包采用的规则，覆盖全田要 5–6 台）。完整输出在 `out_14d.md`。

| 画像 | 指标 | D · P0 | **E · 本包** | E1 · 只加作物 | E2 · 开局 40 格 |
|---|---|---|---|---|---|
| 目标玩家 | 14 天 Farming XP（Lv） | 1,120（7） | **1,397（7）** | 1,293 | 1,500（8） |
| 目标玩家 | Farming Lv5 / Lv6 / Lv7 | 第 6 / 9 / 13 天 | **6 / 9 / 11** | 6 / 9 / 11.5 | 5 / 8 / 10 |
| 目标玩家 | 第 2 周日均播种体力 | 108 | **105** | 92 | 110 |
| 目标玩家 | 第 14 天钱包 | 1,013 | **1,292** | 1,123 | 1,100 |
| 目标玩家 | Cookbook（当期页数） | 13.1 / 14 | **17.1 / 18** | 17.1 / 18 | 18.0 / 18 |
| 重度 | 第 2 周日均播种体力 | 124 | **183** | 139 | 187 |
| 重度 | 14 天 Farming XP | 1,327 | **1,945** | 1,693 | 2,079 |
| 重度 | 14 天没花出去的播种预算 | 1,663 | **1,263** | 1,622 | 1,084 |
| 5 分钟 | 14 天 Farming XP | 760 | **819** | 819 | 830 |

读数：

1. **新作物是 Farming 的主要增量**：只加作物与料理（E1）就让目标玩家 Farming +15%：Lv5 起有 d ≤ 1 的作物，不再全种 75% 的番茄；40 格再加 8%。
2. **40 格主要给重度玩家体力去处**：重度第 2 周每天多花约 59 点在种田上；目标玩家画像的早场预算固定 110，模拟里看不出"多出来的体力去种田"，真实玩家要看试玩。
3. **洒水器占格的代价小**：E3（洒水器占格）比"不占田"只少 Farming 1%（目标）/ 2.4%（重度），重度第 2 周播种 183 → 171。所以保持 §5.7 原规则。−15% 时长对一天来一两次的玩家影响也小；它真正改变的是"不用再浇水"这一步，这正是 Lv6"改变日常"的用意。
4. **材料够造**：目标玩家第 9 天仓库约 Timber 15 / Stone 87 / Copper 10，第 14 天 Timber 44；木材最紧，第 9–10 天能造 1–2 台，第 14 天前约 4–5 台。
5. **钱包第 2 周堆到 1,000 以上**（P0 基线就是如此，本包只多约 280）：P0 封顶 Homestead Lv3，之后金币没有去处。这支持 §17.3.3 的条件「钱多没东西买 → 金币去处提到第 2 位」，但要等 P0 试玩数据确认（17.2.4），本包不改顺序。

模拟没有建模：浇水这一步的时间、洒水器的材料扣除（只按第 9 天后生效近似）、玩家看到新作物时多花体力的意愿（画像预算固定）、配方卡。

## 7. 测试清单（交给韩信，按 int6 的写法）

存档表（亚瑟准备）：**F4** Farming Lv4 差 10 XP 到 Lv5，Homestead Lv2，30 格里 10 格番茄在长；**F5** Farming Lv5、Homestead Lv2，钱包 300；**F6** Farming Lv6 差 0、Homestead Lv3（40 格），仓库 Timber 20 / Stone 20 / Copper Ore 7；**F6-满** 同 F6，已放 6 台洒水器；**H2→3** Homestead Lv2 材料与金币够升 Lv3。

| # | 怎么操作 | 期望 |
|---|---|---|
| T1 | 前置 F4。打开驿站 | 三种新种子可见：卷心菜、玉米灰显 `Farming Lv5 · 10 XP to go`，黄瓜 `Farming Lv6 · …`；点选弹门禁卡四行（1.6） |
| T2 | 前置 F4。收番茄跨过 Lv5 | 横幅 `Farming Lv 5` / `Cabbage, Corn` / `+30 Energy` / `Next Lv6 · Cucumber, Sprinkler · 250 XP`；驿站卷心菜、玉米变可买 |
| T3 | 前置 F5。买卷心菜种子 5、玉米 5，播种，等成熟收获 | 播种每格 −3 / −4 体力；收获卷心菜每株 +3 XP、首收 +15；玉米每株产 3 根、+4 XP、首收 +20；图鉴 `Crops first-harvested n/11` |
| T4 | 前置 F5。Experiment 放卷心菜 + 土豆；玉米 ×2；只放 1 个番茄；只放 1 根玉米 | 依次做出 Cabbage Stew（Common）、Corn Cake（Fine）、Roast Veggies（Fine）、Roast Veggies；没有 Mystery Dish；Cookbook 4 页点亮，技能页 `Dishes first-cooked n/18` |
| T5 | 前置 H2→3。升 Homestead Lv3 | 后果飘字含 `Plots +10`；新 10 格荒地随篱笆落位，位置连着原来的田；能翻地（0 体力），能播种；原 0–29 格的作物不动 |
| T6 | 前置 F6（差 0 到 Lv6）。收任意作物跨过 Lv6 | 全幅横幅 ≤ 3 秒 `Farming Lv 6` / `Cucumber, Sprinkler` / `Today changes: no more watering`；点 `Show Workbench` 只移动相机到工作台，不打开抽屉 |
| T7 | 前置 F6。点工作台 → Facilities | Sprinkler 蓝图卡：`Waters 8 plots for you`、材料格 `Timber 20/8 · Stone 20/6 · Copper Ore 7/3`、按钮 `Build` |
| T8 | P7 后按 `Build` | 进放置模式：摇杆不出、快捷栏与主行动键隐藏；预览落在最近的空田，3 × 3 浅蓝 + `Coverage preview · 8 plots`；拖到有作物的格 → 中心格红、按钮 `Plot occupied`；拖到田外 → `Outside your fields`；按 `Cancel` → 材料没扣 |
| T9 | 再进放置模式，放在一格空田、覆盖里有 2 格已播未浇，按 `Build` | 扣 Timber 8 / Stone 6 / Copper Ore 3；2 格立即开始长（倒计时出现）；覆盖内新播的格不再出 `Water · Free`，播下即长；成熟时长是基础的 85%（施过堆肥的 65%） |
| T10 | 放在田角 | 预览小标写实数（如 `Coverage preview · 3 plots`）；落位后只盖到这几格 |
| T11 | 点已放的洒水器 → `Move`，换一格空田 | 状态卡 `Sprinkler · Waters 8 plots`，覆盖格高亮；移动不扣材料；原格变已翻可播；已在长的作物倒计时不变 |
| T12 | 前置 F6-满 | 蓝图卡按钮 `Sprinklers 6/6 · Homestead Lv4 adds 1`，不进放置模式 |
| T13 | 前置 F6。Farming 行动下站在田里 | 被覆盖的田块描浅蓝边（Coverage Overlay）；没覆盖的已播格仍显示水滴 |
| T14 | 前置 Homestead Lv3 的旧存档（版本更新前已是 Lv3） | 进游戏后 30–39 号荒地已在 |
| T15 | 回归 | 翻地 / 播种 / 浇水 / 收获 / 施肥在 0–29 格与 30–39 格行为一致；Row Hoe 一次 3 格跨新旧两块时不越界 |

## 8. 建议拆卡

| 卡 | 内容 | 建议 | 依赖 |
|---|---|---|---|
| 服务端 | 第 2、3 节：内容、田块迁移、覆盖与缩时、`place` / `move_facility`、视图、遥测；服务端单测 | 周瑜（工作台与材料链） | — |
| 客户端 · 田与作物 | 40 格布局、三种植株、驿站货架、Lv5 / Lv6 横幅与门禁卡、HOME 后果行 | 苏烈（Homestead）或亚瑟 | 服务端卡；233 横幅 |
| 客户端 · 设施 | Facilities 页签、放置模式壳、洒水器状态卡与 Coverage Overlay | 周瑜（接着工作台 PR-C） | PR-C、224 InfoSheet |
| 料理 | 4 页内容与图标接入 | 哪吒（厨房） | 服务端卡 |
| UI 稿 | 9 个图标、放置模式与 Facilities 页签的帧、Lv6 全幅横幅 | 安其拉出稿 → 不知火舞验收 | — |
| 3D | 洒水器正式模型（先占位） | 美术总监安排，先真人设计 | — |
| 测试 | 第 7 节清单 | 韩信 | 全部 |

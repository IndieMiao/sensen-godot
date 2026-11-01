# 355 第一批 E / F / G：矿、新怪、武器 · 接口约定 v0.2（周瑜 11-02）

> 给：苏烈（E / F / G 服务端）、刘邦（F / G 客户端）、亚瑟（矿口卡、审客户端 PR）、后裔（审服务端规则层 PR）、上官婉儿（怪物文件）。
> 依据：方案 `355-gameplay-v4-2026-11-02.md` 第 3 章（3.2 清怪开梯子、3.3、3.5 怪物与守关表、3.6、3.8、3.11）、9.1 #8–#10；亚瑟的 `355-b1-tech-plan-2026-11-02.md`；后裔的 C 接口 `/Volumes/ACASIS/tmp/houyi-355/contract-c-v0.md`；上官婉儿的 3D 接口 v1（`355-b1-3d-plan-2026-11-02.md` 第 6 节）。代码按 farm-dev b2c46d3b 核过。
> **数值都是初值**，李白用模拟器校准，q 行 E / F / G 定稿后只改 json。标「默认」的规则是我先定的，q 行另有定就照 q 行改。
> **v0.1（11-02 01:3x）**：按 355 冲突清单第 3 节（以 v4 为准）对过 E / F / G；第 2 节未经用户确认，不作依据，只沿用其中「不改玩法」的 id。改动如下：
> - 武器 id 改成 `weapon_*`；
> - 精英史莱姆不再掉石英；
> - 浅坑 F5–9 的史莱姆固定 2 只；
> - 内容表不建过渡键（答苏烈 e521454f ③）；
> - **回血药的售卖处、价格、回血量、哪些层能喝都待用户定**（v4q(7) G），数值全放内容表，测试不写死；
> - 矿脉门槛、副产、精英掉落、Pip 委托出现方式待定（第 13 节）。
> 01:1x 那版「农场驿站卖、任何层能喝」的依据已撤回，不作数。
> **v0.2（11-02 02:0x）**：照 v4q(5) 复核 ①，离开一层时守关和精英回满血，防磨死（第 5 节第 9 条、用例 12a）。
> **v0.3（11-02 02:4x）**：照 v4q(5) ed84bb9b 对齐。
> - **日切时人在矿里就留在原层**：这一层按新一天重新生成，人回到楼梯口，血量不变，不再收层费；
> - 矿里的命令带当天的 `day`，对不上的回 `new_day`；
> - 电梯站不含 F1，最上一站是 Entrance（出矿）；
> - 第 7.1 节的 view 加了 `day`、站点今天付没付、下一层的 `locked`；
> - 补了 q 行的文案（第 7.4 节）。
> **改这份约定**：在 feat/355-b1 上用 PR 改本文件（`docs/tech/355-b1-contract-efg.md`），并找周瑜审（奕星定：接口变更归周瑜审）。以仓库这份为准；`/Volumes/ACASIS/tmp/zhouyu-355/contract-efg-v0.md` 只是 v0.2 以前的草稿。

## 0. 谁照哪节写、文件归谁
| 人 | 写 | 文件（只有他改，别人要改先说） |
|---|---|---|
| 苏烈 | E 服务端（第 2–7 节）+ F 服务端（第 8 节）+ G 服务端（第 9 节） | server/src/p0/mine.ts（重写）、state.ts 的矿和装备字段、content.ts 的矿和武器类型、reducer.ts 的矿和装备分支、workbench.ts、residents.ts 的新需求类型、`assets/p0/content/mine_b1.json`（新）、server/test/p0/mine_b1*.test.ts |
| 周瑜 | 第 10 节的接口落地 PR（先只移植史莱姆），然后写 E 客户端 | scenes/p0/p0_mine.gd、modules/mining/p0_mine_combat.gd、mine_combat.gd、mine_layout.gd、mine_art.gd；modules/mining/monsters/ 下的 monster_art.gd、monster_view.gd、monster_brain.gd 三个基类 |
| 刘邦 | F 客户端（第 10 节的三种新怪、守关、精英）+ G 客户端（第 9.6 节） | modules/mining/monsters/ 下的 bat_*、beetle_*、shroom_*、slime_king_*；G 的 Gear 页、快捷栏、物品卡、Pip 委托卡的文件（帧到了以后）|
| 亚瑟 | 矿口卡（地点卡的野外矿分支），读第 7.3 节的数据 | p0_map.gd、地点卡 |
| 后裔 | C：travel.here 认野外 id；`HOMESTEAD_SPACES` 去掉 `mine`；`best_floor` 的叠加字段从第 7.3 节取 | travel.ts、routes.ts、world.ts |

**合并顺序**（b1 内）：内容表和存档字段 → E 服务端 → 接口落地 PR（客户端，只移植史莱姆）→ F / G 服务端和 F 客户端并行 → E 客户端 → 第 3 周接 C。

## 1. id
| 东西 | id | 说明 |
|---|---|---|
| 矿 | 野外地点 id `wd-<row>-<col>`（C） | 开发期另有 `wd-dev-quarry`、`wd-dev-vein`（第 11 节） |
| 矿型 | `quarry`、`vein` | 第一批只有这两种（C 的 `type`） |
| 普通怪 | `mob_slime`（现有）、`mob_cave_bat`、`mob_rock_beetle`、`mob_shroomling` | 和 3D 文件同名 |
| 精英 | `mob_elite_slime`（现有）、`mob_elite_cave_bat`、`mob_elite_rock_beetle`、`mob_elite_shroomling` | 用基础怪的模型，只换材质参数 |
| 守关 | `boss_slime_king`（T1）、`boss_slime_king_iron`（T2）、`boss_slime_king_quartz`（T2） | 现有史莱姆放大、换色，加头饰 glb |
| 掉落 | `drop_t1_bat_wing`、`drop_t2_beetle_shell`、`drop_t2_glow_spore`、`drop_crown_shard` | 方案 3.5 |
| 新材料 | `coal`、`iron_ore` | 和 C 的建议一致；`stone`、`copper_ore`、`rock_salt`、`clay`、`quartz` 是现有的 |
| 武器 | `weapon_wooden_sword`、`weapon_copper_sword`、`weapon_iron_sword` | 照方案文档的 `weapon_*`（冲突清单第 2 节第 4 条，不改玩法）。现在代码里的 `sword_wooden`（`tools.combat`、`mine_p1.json`）在 v7 改名，不写迁移。武器进装备，不进背包 |
| 药 | `potion_heal` Healing Potion | 方案文档已有的 id。背包物品，可以叠；数值待定（第 9.4 节） |
| 物品前缀（`itemKind`） | `weapon_` 是 weapon，`potion_` 是 consumable，`drop_` 是 material | 内容补丁照这个加 |

## 2. 内容表（新段放 `assets/p0/content/mine_b1.json`）
**怎么接（答苏烈 e521454f ③，和亚瑟定的）**：
- b1 上不留旧矿，最后就用 `mine` 这个键，**不搞过渡键名**。
- 内容合并器不许重复键，所以**换内容和改写 mine.ts 放在同一个 PR**（E 服务端主 PR），一次做完：
  1. 删掉 `p0_content.json` 的 `mine.runs_per_day`、`mine.restart_floor`、`mine.floors`、`mine.rocks`、`mine.tempo_ms`，以及 `mine_p1.json` 的 `mine.express_unlock_floor`；
  2. `mine.monsters`、`mine.combat` 已经在 `mine_p1.json` 里：已有的键（`mob_slime`、`mob_elite_slime`、`combat.weapons.sword_wooden`）**就在原文件里改**；
  3. 新键（新怪、`types`、`potions`、`dev_sites`、`combat` 下的新键）放进 `mine_b1.json`；
  4. `floor_energy`、`rock_energy`、`picks` 沿用 `p0_content.json` 里的，不重复写。
- 苏烈的首 PR 只放类型和初始化函数，不碰内容表（奕星已回）。

旧 `mine.floors`、`mine.runs_per_day`、`mine.restart_floor`、`mine.express_unlock_floor` 全删（v7 不留旧矿）。下面是合并以后 `mine` 段的样子，数值都是初值，`_note` 写来源。

```json
{
  "mine": {
    "floor_energy": 2, "rock_energy": 2, "fee_per_day": true,
    "combat": {
      "hp": 100, "invulnerability_ms": 1000, "ko_keep_from": 11, "ko_lose": 0.5,
      "weapons": {
        "weapon_wooden_sword": { "name": "Wooden Sword", "attack": 3, "speed": 2.0, "tier": 1 },
        "weapon_copper_sword": { "name": "Copper Sword", "attack": 5, "speed": 2.0, "tier": 1 },
        "weapon_iron_sword":   { "name": "Iron Sword",   "attack": 8, "speed": 2.0, "tier": 2 }
      }
    },
    "potions": { "potion_heal": { "name": "Healing Potion", "price": 20, "stock": 5, "sold_at": "homestead", "gate": { "homestead": 4 }, "heal": "full", "floors": "any", "cooldown_ms": 3000 } },
    "monsters": {
      "mob_slime":              { "name": "Slime",          "hp": 9,  "damage": 10, "loot": [["copper_ore", 1, 35], [null, 0, 65]] },
      "mob_elite_slime":        { "name": "Elite Slime",    "hp": 36, "damage": 20, "elite": true, "loot": [["copper_ore", 2, 100]] },
      "mob_cave_bat":           { "name": "Cave Bat",       "hp": 5,  "damage": 6,  "loot": [["drop_t1_bat_wing", 1, 40], [null, 0, 60]] },
      "mob_elite_cave_bat":     { "name": "Elite Cave Bat", "hp": 20, "damage": 12, "elite": true, "loot": [["drop_t1_bat_wing", 2, 100]] },
      "mob_rock_beetle":        { "name": "Rock Beetle",    "hp": 18, "damage": 12, "stun_mult": 2, "loot": [["drop_t2_beetle_shell", 1, 35], [null, 0, 65]] },
      "mob_elite_rock_beetle":  { "name": "Elite Rock Beetle", "hp": 60, "damage": 20, "elite": true, "stun_mult": 2, "loot": [["drop_t2_beetle_shell", 2, 100]] },
      "mob_shroomling":         { "name": "Shroomling",     "hp": 12, "damage": 8,  "loot": [["drop_t2_glow_spore", 1, 35], [null, 0, 65]] },
      "mob_elite_shroomling":   { "name": "Elite Shroomling", "hp": 45, "damage": 14, "elite": true, "loot": [["drop_t2_glow_spore", 2, 100]] },
      "boss_slime_king":        { "name": "Slime King",          "hp": 80,  "damage": 18, "guard": true, "tier": 1, "first": [["drop_crown_shard", 1]], "pack": 5 },
      "boss_slime_king_iron":   { "name": "Ironback Slime King", "hp": 160, "damage": 22, "guard": true, "tier": 2, "first": [["drop_crown_shard", 1]], "pack": 8 },
      "boss_slime_king_quartz": { "name": "Quartz Slime King",   "hp": 200, "damage": 25, "guard": true, "tier": 2, "first": [["drop_crown_shard", 1]], "pack": 8 }
    },
    "types": {
      "quarry": {
        "bands": [
          { "from": 1,  "to": 4,  "mobs": [["mob_slime", 2, 3]], "rocks": [4, 6], "drops": [["stone", 30], ["copper_ore", 25], ["coal", 15], ["clay", 15], ["rock_salt", 15]] },
          { "from": 5,  "to": 9,  "mobs": [["mob_slime", 2, 2], ["mob_cave_bat", 1, 2]], "rocks": [4, 6], "drops": [["stone", 30], ["copper_ore", 25], ["coal", 15], ["clay", 15], ["rock_salt", 15]] },
          { "from": 11, "to": 19, "mobs": [["mob_cave_bat", 2, 2], ["mob_rock_beetle", 1, 2]], "rocks": [4, 6], "drops": [["stone", 25], ["copper_ore", 25], ["coal", 20], ["clay", 15], ["rock_salt", 15]] },
          { "from": 21, "to": 29, "mobs": [["mob_rock_beetle", 2, 2], ["mob_shroomling", 1, 2]], "rocks": [4, 6], "drops": [["stone", 20], ["copper_ore", 25], ["coal", 25], ["clay", 15], ["rock_salt", 15]] }
        ],
        "floors": {
          "5":  { "elite": "mob_elite_slime" },
          "10": { "guard": "boss_slime_king" },
          "15": { "elite": "mob_elite_cave_bat" },
          "20": { "guard": "boss_slime_king", "hp_mult": 1.5 },
          "25": { "elite": "mob_elite_rock_beetle" },
          "30": { "guard": "boss_slime_king", "hp_mult": 2 }
        }
      },
      "vein": {
        "gate": { "homestead": 8 },
        "main_weight": [[1, 10], [10, 40]],
        "bands": [
          { "from": 1,  "to": 9,  "mobs": [["mob_slime", 1, 1], ["mob_rock_beetle", 1, 2]], "rocks": [4, 6], "drops": [["stone", 40], ["coal", 20], ["copper_ore", 15]] },
          { "from": 11, "to": 19, "mobs": [["mob_rock_beetle", 1, 2], ["mob_shroomling", 1, 1], ["mob_cave_bat", 1, 1]], "rocks": [4, 6], "drops": [["stone", 35], ["coal", 20]] },
          { "from": 21, "to": 39, "mobs": [["mob_rock_beetle", 2, 2], ["mob_shroomling", 1, 2], ["mob_cave_bat", 1, 1]], "rocks": [4, 6], "drops": [["stone", 30], ["coal", 20]] }
        ],
        "floors": {
          "5":  { "elite": "mob_elite_rock_beetle" },
          "10": { "only": ["mob_elite_rock_beetle", "mob_elite_slime"] },
          "15": { "elite": "mob_elite_shroomling" },
          "20": { "guard": "boss_slime_king_iron" },
          "25": { "elite": "mob_elite_rock_beetle" },
          "30": { "only": ["mob_elite_rock_beetle", "mob_elite_shroomling"] },
          "35": { "elite": "mob_elite_shroomling" },
          "40": { "guard": "boss_slime_king_quartz" }
        }
      }
    },
    "dev_sites": [
      { "id": "wd-dev-quarry", "type": "quarry", "name": "Dev Quarry", "near": "gn-5391959", "mine": { "floors": 30, "main": "copper_ore", "main_from": 1, "side": null, "open_to": null } },
      { "id": "wd-dev-vein",   "type": "vein",   "name": "Dev Vein",   "near": "gn-5391959", "mine": { "floors": 41, "main": "iron_ore", "main_from": 10, "side": null, "open_to": 40 } }
    ]
  }
}
```
- `bands[].mobs`：`[kind, min, max]`，每层按种子在 min–max 之间取数。`floors["N"]` 覆盖这一层：
  - `add` 是在本段之外再加的怪；
  - `elite` 是加一只精英；
  - `only` 表示这一层只有这些怪（矿脉 F10、F30 的两只精英一组）；
  - `guard` 表示这一层只有守关、没有岩石；
  - `hp_mult` 是守关的血量倍数。
- 浅坑 F5–9 照 v4 3.5：史莱姆固定 2 只、蝙蝠 1–2 只（答苏烈 ②，和 v4q(5) 一致）。
- **精英史莱姆不再掉石英**（冲突清单第 3 节 §10.7「石英只在矿脉」，以 v4 为准），也不再有「每天第一次掉石英」。它掉什么待 q 行 E 定（第 2 节有一个提议：当天第一次击败掉铜 ×2，未确认）。这里先写铜 ×2、每次都掉，只是初值。`once_a_day` 这个机制服务端照旧支持，用不用由数据定。
- 矿脉的主矿：掉落表里没写主矿，按 `main_weight` 加进去：F1 起权重 10，到 C 给的 `main_from`（矿脉是 F10）起改为 40。副产 `side` 第一批掉不掉待定（第 13 节）。
- 矿脉的门槛 `gate.homestead: 8` 照 v4 2.7。冲突清单第 2 节有人提议「开局就能去」，未确认，所以写成数据：改它不用改代码。
- 守关的 `first`：每种守关个人第一次打倒必掉；`pack`：每次打倒给一包本矿主产（`main` 乘以 pack 个数）。
- **回血药 `potions.potion_heal` 的每个字段都待用户定**（v4q(7) G）。初值用的是现行方案文档的数（§10、附录：Homestead Stall 卖、20 coins、日库存 5、HP 回满），`floors: "any"` 也是待定的初值。服务端和测试都**从这里读**，不写死。

## 3. 存档 v7 的字段（服务端 state.ts；**存档格式变更要等 q 行 B 让用户点头才能上线**，开发照做）
```ts
/** 355 第一批：每座矿的长期进度（方案 3.6），键是矿 id（野外 id）。 */
export interface MineRecord { deepest: number; guards: number[]; first_at: number }   // guards：在这座矿打过的守关层号
/** 当天状态（方案 3.8）：按家城 04:00 清空，不进长期进度。 */
export interface MineDay {
  key: string;                                   // dayKey
  at: { mine: string; floor: number } | null;    // 人在哪座矿的哪一层；不在矿里时是 null
  hp: number;                                    // 本次下矿的血量；出矿或倒地后回满
  floors: Record<string, MineFloorState>;        // 键 "<mine>:<floor>"，只存今天进过的层
  picked: [string, number][];                    // 进本层以后捡到的东西（倒地扣一半用）；换层清空
  attack_at?: number; hurt_at?: number; drink_at?: number; swing_at?: number;
}
export interface MineFloorState { paid: boolean; broken: number[]; lit: boolean; mobs: number[] }   // mobs：每只怪剩下的血量，顺序同第 4 节生成的列表
export interface MineState { records: Record<string, MineRecord>; day: MineDay | null; notice: MineNotice | null }
export type MineNotice = { kind: 'reset'; at: number } | { kind: 'ko'; at: number; floor: number; lost: [string, number][] };
// P0State 里：
//   mine: MineState;                                      // 取代旧的 MineState（run、count、express、elite、completed 都删）
//   kills: Record<string, number>;                        // 按种的击杀数（方案 3.6，第二批成就回填）
//   guard_firsts: Record<string, { at: number; mine: string; floor: number }>;   // 每种守关个人第一次打倒
//   gear: { …现有; weapons: string[]; weapon: string };   // 起始 ['weapon_wooden_sword'] / 'weapon_wooden_sword'
//   day.mine_runs 删掉
```
- freshState 直接是这个形状（亚瑟的 v7 骨架会合进同一处）。不写迁移，v<7 按没有存档处理（亚瑟的方案 4.2）。
- `once_a_day` 掉落的计数（数据里有才用）放 `day`：`s.day.once: Record<kind, number>`。

## 4. 层生成（服务端，确定性）
```
floorSpec(c, site, floor, player, dayKey) -> { mobs: string[]; rocks: number; guard: string | null; hpMult: number; station: boolean }
```
1. `type = site.type`；最深层取 `site.mine.floors`，第一批的上限取 `site.mine.open_to ?? site.mine.floors`。超出就是 `bad_floor`。
2. 随机流：`seededRand(\`${player}:mine@${mineId}:${floor}:${dayKey}\`)`，用 boards.ts 里 #609 新导出的 `seededRand`，按方案 3.8，种子是「人 + 日期 + 矿口 + 层」。**每层的随机数按固定顺序取**：先定每种怪的只数（按 bands 的顺序），再定 add，再定岩石数。顺序写死，view 和命令才会算出同一个结果。
3. 先看 `floors["N"]`：有 `guard` 就只有守关，岩石 0；有 `only` 就只有那几只，岩石照本段；否则按本段的 mobs 加上 `add`，再加 `elite`。
4. 怪的顺序：按上面拼出来的顺序排，精英放最后、守关单独一只。`mine_attack` 的 targets / hurt_by 用这个下标（和现在一样）。
5. `station`：10 的倍数且 ≤ 这座矿的 `deepest`（F1 不是站；电梯机器在 F1 和各站都有，最上一站是 Entrance = 出矿，v4q(5) ⑪）。
6. 岩石的掉落：用本段的 `drops` 加上矿脉主矿的 `main_weight`；每块岩石的掉落用 `rockDrop` 现有的随机办法，键换成「矿 + 层 + 日 + 岩石号」。

**客户端不参与生成**：客户端照 view 给的怪物列表和岩石数来摆，位置用 mine_layout 的种子布点（键改成「矿 + 层 + 日」，岩石数取自 view）。

## 5. 规则
1. **进矿**：要人在这座矿的野外地点（`travel.here === mineId`，C 负责），开发矿不检查（第 11 节）。只能进 F1，或者这座矿的电梯站（10 的倍数且 ≤ `deepest`）。进的是今天没付过的层就扣 `floor_energy`。进矿时血量回满。
2. **换层**（`mine_floor {to}`）：
   - 往下（to = 当前层 + 1）：当前层的怪必须全部打倒（`mobs` 全是 0，守关算在内），否则回 `floor_locked {left}`；没有怪的层进来就算清完。
   - 往上（to = 当前层 − 1）：随时可以。
   - 坐电梯（`via: "elevator"`）：当前层是 F1 或电梯站，目标是电梯站（Entrance 是出矿，不发命令，见第 11 条）。到了当天没进过的站照收层费（v4q(5)：`Floor 20 · 2 Energy`）。
   - 进的是今天没付过的层，扣 `floor_energy`；扣完以后 `picked` 清空。
3. **纪录**：进了一层（付过或已付）且层号大于 `records[mine].deepest`，就更新 deepest，事件 `mine_record`。资历 = 所有矿 deepest 的最大值，只在 view 里算，不另存。
4. **岩石**：想敲才敲（`mine_rock`），每块扣 `rock_energy`，沿用 0.9 秒的节奏检查和 q(48) 的背包检查。火把（`mine_torch`）照旧。守关层没有岩石。
5. **守关**：守关层只有守关。打倒以后：`records[mine].guards` 加上这一层；第一次打这种守关就给 `first` 加 `guard_firsts[kind]`；每次都给 `pack`。**默认**：在这座矿打过的守关层，以后再进来（走梯子或坐电梯）都不再有守关，进来就开。每周重打放第二批。
6. **精英**：和普通怪一样，打倒就有掉落；数据里有 `once_a_day` 的，那一项每天只有第一次掉（精英史莱姆的石英已经去掉）。
7. **击杀**：每打倒一只，`kills[kind] += 1`。
8. **倒地**：血量到 0 时：
   - 层号 ≥ `ko_keep_from`（11）：从背包里扣掉 `picked` 里每样东西的 `⌊n × ko_lose⌋`（背包里不够就扣到 0）；
   - 人回到矿口（`day.at = null`）；`notice = {kind: 'ko', floor, lost}`；
   - 这一层今天仍算付过。
9. **离开一层，守关和精英回满血**（**默认**，v4q(5) 复核 ①，奕星 11-02：怪的血存在当天状态里，人出矿又回满血，不堵的话可以出矿、坐电梯回来接着打，铜剑打铁背王要 80 下，进出 3–4 次就磨死了）：
   - 人离开一层，不管是倒地、出矿（`day.at` 变 null）、上下楼还是坐电梯，这一层里**还活着的**守关和精英都回到满血；
   - 已经打倒的（hp 0）照旧算打倒，今天不再出现；
   - 普通怪不回血；
   - 层生成是确定性的，服务端知道这一层哪几个下标是守关和精英，在 `mine_floor`、`mine_enter`、倒地、notePresence 出矿这几处统一调一个 `restoreBosses(mine, floor)`。
10. **日切**（家城 04:00，`dayKey` 变了；v4q(5) ⑥，不知火舞定，周瑜按实现确认可行）：
   - `day` 整个换成新一天的：人如果在矿里，**留在当前这一层**，`at` 不变，血量不变；
   - 这一层按新一天的种子重新生成，怪、岩石、地上的掉落全部重刷（所以守关和精英自然是满血；打过的守关照旧不出现），记为今天已付过费，`picked` 清空；
   - `notice = {kind: 'reset', at, floor}`。客户端提示 `New day · Floor 12 has changed`，在原层原地重建，人放回楼梯口（客户端调现成的 `_go_floor(n)`）；
   - **这不算「离开一层」**（第 9 条），因为整层都重刷了，比回满血更彻底；
   - 服务端是懒结算：view 在拷贝上做、下一条命令落盘，两边算出同一层（种子相同）；
   - **防旧命令**：日切那一刻还在路上的挥刀、敲岩石，不能打到新一天的层上。所以矿里的命令（`mine_floor`、`mine_rock`、`mine_torch`、`mine_attack`、`mine_drink`）都带 `day`（客户端照 `view.mine.at.day` 发），和当前 `dayKey` 对不上就回 `new_day`，什么也不做；回包里的 state 已经是新一天的层，客户端照第 3 点重建，不弹错误。
   - 人不在矿里时，日切只是清掉 `day`。
11. **出矿**：不需要命令。客户端离开矿时把 space 改成地图（现有的 `GET /state?space=`），服务端在 notePresence 里把 `day.at` 设成 null。血量下次进矿回满。
12. **取消**：每天 2 局、Express、New run、Run complete、`ended` / `completed` 都删掉。

## 6. 命令、拒绝码、事件
| 命令 | 字段 | 说明 |
|---|---|---|
| `mine_enter` | `mine`, `floor?`（默认 1） | 从矿外进 |
| `mine_floor` | `to`, `via?: "ladder" \| "elevator"` | 矿里换层 |
| `mine_rock` | `floor`, `rock` | 沿用 |
| `mine_torch` | `floor` | 沿用 |
| `mine_attack` | `floor`, `targets?: number[]`, `hurt_by?: number`, `stunned?: number[]` | `stunned` 是这一下打中的、处在硬直里的岩甲虫下标（第 8 节） |
| `mine_drink` | `item` | 在矿里喝药 |
| `equip` | `item` | 沿用，加上武器 |

拒绝码（新的）：`unknown_place`、`not_open`、`not_here`（C 已有）；`bad_floor {max}`（层号超出、不是电梯站、不是相邻层；超过 `open_to` 时 detail 带 `not_open: true`）；`floor_locked {left}`；`not_in_mine`；`new_day`（命令的 `day` 不是今天，第 5 节第 10 条）；`no_potion`；`potion_cooldown {ready_in}`；`hp_full`。

矿里的命令（`mine_floor`、`mine_rock`、`mine_torch`、`mine_attack`、`mine_drink`）都带 `day`（`view.mine.at.day`）。沿用的：`need_energy`、`bag_full`、`not_owned`。

事件（新的）：
- `{kind:'mine_floor', mine, floor, cleared, station}`
- `{kind:'mine_record', mine, deepest}`
- `{kind:'mob_down', index, mob}`
- `{kind:'guard_down', mob, floor, first}`
- `{kind:'mine_ko', floor, lost}`
- `{kind:'heal', hp, item}`
- `{kind:'gear', id, slot:'weapon'}`

物品沿用 `item` 事件，血量沿用现有的 hurt 事件。

## 7. view
### 7.1 `view.mine`
```json
{
  "floor_energy": 2, "rock_energy": 2, "hp_max": 100, "rank": 23,
  "weapon": { "id": "weapon_copper_sword", "attack": 5, "speed": 2.0, "tier": 1 },
  "notice": null,
  "at": null | {
    "mine": "wd-254-114", "type": "vein", "name": "Ash Vein", "max": 40, "floor": 12, "hp": 76, "day": "2026-11-02",
    "stations": [ { "floor": 10, "paid": true }, { "floor": 20, "paid": false } ],
    "floor_state": {
      "floor": 12, "paid": true, "cleared": false, "rocks": 5, "left": 3, "broken": [true, false, …], "lit": false,
      "preview": null, "bag_ok": true, "station": false, "guard": null,
      "mobs": [ { "kind": "mob_rock_beetle", "hp": 18, "max": 18, "elite": false, "guard": false, "tier": 0 } ]
    },
    "next": { "floor": 13, "paid": false, "fee": 2, "open": false, "locked": null }
  },
  "records": { "wd-254-114": { "deepest": 23, "guards": [20] } }
}
```
- `at` 只在人在矿里时有；`floor_state` 只给当前层。换层以后看命令返回的 view。
- `mobs` 的顺序就是 targets / hurt_by 的下标。`tier` 只有守关有，其余是 0。
- `next`：往下一层的楼梯。`open` 表示本层清完了。`locked` 是 `"not_open"` 时，表示下一层超过了第一批的 `open_to`（矿脉 F41），楼梯是灰牌 `Floor 41 · Not open yet`。已经是这座矿最深层（浅坑到底）时，`next` 是 null，不画往下的楼梯。
- `stations`：电梯面板的各站。`paid` 表示今天进过（行写 `Free`），否则行写 `2 Energy`；最上一行 Entrance 由客户端加。
- `notice`：`{kind: 'reset', at, floor}`（日切，人留在原层）或 `{kind: 'ko', …}`；客户端显示一次。

### 7.2 `view.gear`
现有字段，再加 `weapons`、`weapon`；物品卡和 Gear 页用 `content.mine.weapons` 里的名字和数值。

### 7.3 给矿口卡和 C 用的
- C 的叠加字段 `best_floor` = `records[mine].deepest`，没有记录时是 0（后裔照这个填）。
- 矿口卡的其余内容由客户端算：矿型、最深层、主产和起始层来自 C 的 `mine` 块；每段的怪和守关来自 `content.mine.types[type]`；「你在这里到过第几层」和电梯站来自 `records`（10 的倍数且 ≤ deepest）。季节、新闻、钻地机第一批没有。

### 7.4 客户端文案（照 v4q(5) ⑪；以 q 行为准，这里只列 E 客户端要用的）
- F1 的上行梯名字条写 `Entrance`；电梯面板最上一站是 `Entrance · Free`。两处都是出矿，回到地图上这座矿的矿口，地图打开、矿口卡弹出，主键 `Enter mine · Free`。
- 电梯面板标题是 `Elevator · <这座矿的全名>`（例如 `Elevator · Ironvale Vein`）；行写 `Floor 10 · Free`、`Floor 20 · 2 Energy`，自己所在的那一站写 `Here`。
- 日切：Info toast `New day · Floor 12 has changed`。
- 矿脉 F40 下面的楼梯：灰牌 `Floor 41 · Not open yet`；浅坑最深层没有往下的楼梯。
- 倒地卡：标题 `Knocked out`；第一行 `You're back at the entrance.`；第二行 F1–10 写 `You kept everything.`，F11 起写 `You dropped half of what you found on this floor:` 加上掉落列表；第三行 `Your best here is still Floor 14.`；按钮 `Close`。

## 8. 伤害和校验（F 服务端）
- 玩家每下伤害 = 武器 `attack`。
  - 目标是守关、且武器 `tier` 低于守关 `tier`：伤害减半，向下取整，最少 1。
  - 目标下标在 `stunned` 里、且这种怪有 `stun_mult`：伤害乘以 `stun_mult`。
- 菇菇怪缩回时不受伤：客户端不把它放进 targets，服务端不另算。
- 怪打玩家：`hurt_by` 那只怪的 `damage`；无敌时间是 `invulnerability_ms`（沿用）。孢子算菇菇怪的一次普通命中。
- **校验**（方案 3.8 最后一条，进防作弊专题；第一批先拒绝明显不对的，异常只记日志）：
  - 两下的间隔 ≥ `1000 / speed × 0.9` ms，否则这一下作废（照现有的 `attack_at`）；
  - 一下最多打中 4 只；
  - `stunned` 里的下标必须也在 targets 里，而且是有 `stun_mult` 的怪；
  - 守关从这一层第一次被打到被打倒的时间低于 `血量 ÷ 武器每秒最大伤害 × 0.8` 时，写一条日志 `guard_fast`。

## 9. G 武器
### 9.1 装备
- **Gear 页现有的 Combat 槽变成可换**（结论第 4 节修订的说法）：存档里是 `gear.weapons` 和 `gear.weapon`；`equip {item}` 加一个分支：`weapons` 里有它就换成它。
- 战斗读 `gear.weapon`，不再读 `tools.combat`（`tools.combat` 删掉）。武器槽开局就装着木剑；Lv3 只是给铜剑（现行规则，冲突清单第 2 节第 5 条）。

### 9.2 铜剑：Pip「第一次下矿」委托
- 新的需求类型 `{"kind": "floor", "floor": N}`：进度 = 资历（所有矿的 deepest 取最大）。达到 N 就算凑够，交的时候不扣物品。
- 进度回调：`mine_record` 事件发生后，重算已接的这类委托（照现有的委托进度飘字）。
- 新的奖励类型 `reward.weapon: "weapon_copper_sword"`：放进 `gear.weapons`，如果当前武器档位更低就顺手换上，发事件 `gear`；只给一次（照现有的一次性奖励）。
- 委托本身（Pip 的第几条、N 是几、文案、Lv3 出现）由李白在 residents 数据里加，初值 N = 5。要不要在 Lv3 直接出现在 Today、不用去驿站接，待定（第 13 节）。

### 9.3 铁剑：工作台
- 配方 `{ id: "craft_iron_sword", out: "weapon_iron_sword", to: "weapon", gate: { homestead: 8 }, in: [["iron_ore", 6], ["drop_t2_beetle_shell", 3], ["wood", 4]], coins: 120 }`。数值是初值；Lv8 照 v4 2.7。
- `to: 'weapon'`：做好放进 `gear.weapons`，照 `to: 'gear'` 的写法；已经有了就不能再做（`owned`）。

### 9.4 回血药
- `mine_drink {item}`：只能在矿里（`day.at` 不为空），而且层号在 `potions[item].floors` 允许的范围内；扣 1 瓶；回血 `heal`（`"full"` 表示回满，数字表示回多少），不超过上限；冷却 `cooldown_ms`；血满时回 `hp_full`；层不允许时回 `not_here`。**售卖处、价格、库存、回血量、哪些层能喝都待用户定**，全读 `content.mine.potions`。
- 售卖：照 `sold_at`（现行是 `homestead`，即 Homestead Stall），日库存 `stock`，门槛 `gate`（v4 2.7：Lv4）。挂进柜台的写法照现有商品。

### 9.5 起始状态
新档的 `gear.weapons = ['weapon_wooden_sword']`、`weapon = 'weapon_wooden_sword'`。

### 9.6 G 客户端（刘邦，等帧）
- Gear 页加武器槽：列出拥有的武器、显示攻击和档位、可以换。
- 物品卡：武器和回血药各一种。
- 战斗快捷栏：只在矿里出现，放回血药，显示数量和冷却，点了发 `mine_drink`。
- 手上的剑跟着 `gear.weapon` 换：`combat_art` 里铜剑已经有了（美术 id 是 `copper_sword`，要做一层 `weapon_*` 到美术 id 的映射），铁剑换色。
- Pip 委托卡和 Today 行写「Reach Floor N」（文案按 q 行 G）。
- 工作台加铁剑配方行。

## 10. 客户端怪物接口（F）
目录 `modules/mining/monsters/`。**占位体、灰模、正式模型走同一个接口，换模型只换资源路径**（上官婉儿的接口 v1；亚瑟要求写明）：
- **占位怪从第一天起就走 `play(动作名)`**：动作名照 3D 约定（idle / move / windup / attack / recover / hit / die，加上 fly_high / stunned / hide / spore）。占位体用代码 tween 实现同名动作，不直接改变换。
- **时长和命中时刻从 json 读**：占位体也带一份同样格式的 json，放在 `modules/mining/monsters/placeholder/<id>.json`，键和 `assets/monsters/<id>/<id>.json` 完全一样（radius、hit_point、durations、hit_at、spore_at）。brain 只读 `view.meta`，不写死数字。
- 有 `assets/monsters/<id>/<id>.glb` 就用 glb 和它旁边的 json；没有就用占位体和占位 json。动作的循环方式由程序按 json 设置（idle、move、fly_high、stunned 循环，其余单次）。
- 头饰 glb 的原点在接触面中心，挂到史莱姆头顶，位置是 `meta.hit_point` 往上到身体顶，由 `attach()` 做。

```gdscript
# monsters.gd — 注册表（刘邦加新怪只改这里的 KINDS，加一行）
const KINDS := { "mob_slime": {"json": "mob_slime", "view": SlimeView, "brain": SlimeBrain}, … }
static func meta(kind) -> Dictionary     # 有 assets/monsters/<json>/<json>.json 用它，否则用 placeholder/<json>.json
static func spec(kind) -> Dictionary     # 从 json 换算出战斗用的数（radius、move_speed、aggro_range、attack_range、
                                         # windup_seconds、dash_speed、dash_seconds、recovery_seconds、stun_resistant、
                                         # knockback_resistance）；每只怪一份拷贝；HP 由战斗按 view 设
static func view(kind, spec) -> Node3D   # 新的外观节点（MonsterView）
static func brain(kind) -> RefCounted    # 新的 MonsterBrain
# 没注册的 kind 当史莱姆画、当史莱姆打：服务端先发了新怪，客户端也不会坏

# monster_view.gd — 外观（extends Node3D；仓库惯例：新文件不加 class_name，用 preload 引用）
var kind: String; var meta: Dictionary; var action: String; var action_time: float
func play(name: String) -> void                 # idle / move / windup / attack / recover / hit / die / 专用动作
func duration(name: String) -> float            # meta.durations[name]
func set_tint(params: Dictionary) -> void       # 精英、守关、以后的气候变体：只改材质参数
func attach(ornament: PackedScene, top := 1.0) -> Node3D   # 史莱姆王的头饰
func update(enemy: Dictionary, was: String, delta: float, stepped: bool, elapsed: float) -> void
#   每帧在 brain 之后调用：enemy 是战斗里这只怪的字典（phase、timer、flash、direction…）；was 是 brain 之前的 phase；
#   stepped = 这一帧 brain 跑过（暂停和落地缓冲期间是 false，外观照样更新，比如预警条照样淡出）

# monster_brain.gd — 行为（extends RefCounted；同样不加 class_name）
func step(enemy: Dictionary, fight, player: PlayerMover, dt: float, may_path: bool) -> bool
#   移动 enemy.mover，改 enemy.phase / timer；打中玩家时调 fight.touch(enemy)；
#   may_path = 这一帧还没有别的怪寻过路（每帧最多一只寻路）；返回自己这一帧寻没寻路
#   可以用 fight._slide(mover, offset)（防穿墙的小步移动）、fight._dash_step(enemy, player, offset)（冲到身体边缘就停）、
#   fight.invulnerability（玩家无敌剩余秒数）
func can_be_hit(enemy) -> bool                  # 菇菇怪缩回时 false：不进 targets
func stunned(enemy) -> bool                     # 岩甲虫硬直时 true：打中就报进 stunned
func on_hit(enemy, stun_s: float) -> void       # 挥刀打中时（按下那一刻）：默认是旧矿的短硬直，spec.stun_resistant 时不硬直
```
- 战斗的字典照旧（p0_mine_combat.gd 的 `enemies`）：`id`、`kind`、`node`（MonsterView）、`spec`、`brain`、`mover`、`index`、`hp`、`phase`、`timer`、`repath`、`direction`、`flash`、`did_hit`、`elite`。phase 的名字由各自的 brain 定；史莱姆是 idle / chase / windup / dash / recover / stunned。
- 行为（方案 3.5）：
  - SlimeBrain：现有的跳扑，从 mine_combat.gd 搬过来，行为不变；
  - BatBrain：快，平时 fly_high，俯冲时下来，打完回到空中；
  - BeetleBrain：慢，windup 后冲撞，撞完 stunned 2 秒，硬直时 `stunned()` 为 true；
  - ShroomBrain：被打后 hide 1 秒，`can_be_hit()` 为 false；每隔一段时间放 spore（打中算一次普通命中）；
  - SlimeKingBrain：照史莱姆，体型和数值放大，可以加一个蓄力重跳。
- 一层 4–5 只的时候，照 SGODOT-260：每帧最多一只寻路；模型不投实时阴影，用圆形假影。
- **接口落地 PR（周瑜）**：建 monsters.gd、monster_view.gd、monster_brain.gd，把史莱姆移到 slime_view.gd / slime_brain.gd 和占位 json（行为不变），p0_mine_combat.gd 改成按 view 的 `mobs[].kind` 走注册表。旧矿（scenes/mine、online_combat）还在用的 mine_combat.gd 不动。这个 PR 合了以后，刘邦只在 monsters/ 下加新文件和 KINDS 的行，不碰 mine_combat.gd 和 p0_mine*.gd。
- **导出**：json 不是资源，导出包默认不带。接口落地 PR 已在 export_presets.cfg 的 include_filter 加了 `modules/mining/monsters/placeholder/*.json,assets/monsters/*.json`。
- 发命令（客户端）：挥一下时，把命中的怪里 `can_be_hit()` 的放进 targets，其中 `stunned()` 的再放进 stunned；hurt 管线照现在的 `mine_hurt` 键。

## 10.1 矿层资源（3D 交，第一批继续用 mine_art.gd 代码拼，11-14 交，周瑜接）
- 配色：`assets/mine/types/<quarry|vein>/palette.json`，格式 `{"bands": [{"from": 1, "to": 9, "ground": "#rrggbb", "wall": "#rrggbb", "backdrop_tint": "#rrggbb", "fog": "#rrggbb"}, …]}`，按层段逐渐变深。
- 背景：`assets/mine/types/<type>/backdrop.glb`，在现有 `assets/mine/backdrop/mine_backdrop.glb` 上改，原点、朝向、尺度照现有的。没有这个文件就用现有背景加配色。
- 新矿石岩块：`assets/mine/rocks/rock_<iron_ore|quartz|coal|copper_ore>.glb`。原点在底面中心，Y 向上；尺寸照现在代码拼的岩石（半径约 0.47 m、高约 0.63 m，假影半径 0.52）；单个 surface，顶点色；≤ 400 三角面；不带动作（敲碎的抖动和缩小由程序做）。
- 摆件：`assets/mine/props/guard_arena.glb`（守关层）、`assets/mine/props/elevator_station.glb`（电梯站）。原点在地面中心，单位米。
- .import 必须带 uid。

## 11. 开发用矿（接 C 之前）
- 服务端解析矿 id：先查 C 的目录；查不到再查 `content.mine.dev_sites`。开发矿不检查 `travel.here`，其余规则和真矿一样。
- 客户端：调试步骤 `p0_dev mine:<id>[:<floor>]` 直接进矿；在 b1 上，农场的矿口暂时进 `wd-dev-quarry`，接 C 以后删掉。
- **发版前删掉 `dev_sites` 和农场矿口**（放进 M4 的发版清单）。

## 12. 测试清单
### 12.1 服务端（苏烈，vitest，`server/test/p0/mine_b1*.test.ts`）
1. 同一个人、同一天、同一座矿、同一层：view 和命令生成的怪物列表和岩石数一样；换一天就不一样；两个人不一样。
2. 浅坑 F1–4 史莱姆 2–3 只；F5–9 史莱姆正好 2 只、蝙蝠 1–2 只；F5 有精英史莱姆；F10、F20、F30 只有守关，没有岩石；F20 守关血量 ×1.5，F30 ×2。（只数从内容表读，不写死。）
3. 矿脉 F10 只有两只精英；F20 是铁背史莱姆王；F40 是石英史莱姆王；`open_to: 40` 时进 F41 回 `bad_floor`。
4. 清怪开梯子：本层还有怪时往下回 `floor_locked {left}`；全部打倒以后能下；没有怪的层进来就能下；往上随时能走。
5. 岩石不敲也能下；敲一块扣 2 体力，掉落按本段 `drops`；矿脉 F1–9 主矿权重低，F10 起高。
6. 入层费：今天第一次进一层扣 2；同一天再进不扣；换日以后再扣。
7. 纪录：进更深的层就更新 deepest 并发 `mine_record`；资历是所有矿 deepest 的最大值。
8. 电梯：站是 ≤ deepest 的 10 的倍数（不含 F1）；从 F1 或站点出发才能坐；从别的层坐、或去非站点，都回 `bad_floor`；只扣目标层的入层费（今天没进过才扣）；view 的 `stations[].paid` 和这一致。
9. 守关：打倒以后 `guards` 记下这一层；第一次打倒必掉王冠碎片并写 `guard_firsts`，第二次不掉；每次都有主产包；在这座矿打过以后，再进这一层就没有守关。
10. 伤害：木剑或铜剑打 T2 守关伤害减半（最少 1）；铁剑打 T2 全额；硬直的岩甲虫 ×2；`stunned` 里放了不在 targets 里、或不是岩甲虫的下标，不加倍。
11. 出手节奏：间隔小于 `1000 / speed × 0.9` ms 的一下作废；一下打中超过 4 只只算前 4 只。
12. 倒地：F1–10 不扣东西；F11 起扣掉本层捡到的一半，向下取整；人回到矿口，`notice.ko` 写清楚丢了什么。
12a. 离开一层（倒地、出矿、上下楼、坐电梯），这一层还活着的守关和精英回满血，已经打倒的不回来，普通怪不回血。用例：守关打到一半出矿，坐电梯回来，血是满的。
13. 日切（人在矿里）：过了 04:00，人留在原层，`at` 和血量不变；这一层换成新一天的怪和岩石，算已付费；`notice.reset` 带层号；带着旧 `day` 的 `mine_attack` / `mine_rock` 回 `new_day`，对新层没有影响；view 和下一条命令算出同一层。人不在矿里时日切只清 `day`。
13a. 下一层的锁：矿脉 F40 清完以后，`next.locked` 是 `not_open`，往 F41 回 `bad_floor`（detail 带 `not_open: true`）；浅坑到底时 `next` 是 null。
14. 击杀：每种怪的击杀数累加；精英史莱姆打倒不会掉石英；数据里带 `once_a_day` 的掉落每天只给一次（测试用一个测试专用的怪来验这个机制）。
15. 不能进：不在那座矿（`not_here`）、目录里没有（`unknown_place`）、类型没开（`not_open`）、背包放不下（`bag_full`）、体力不够（`need_energy`）。
16. 回血药：只能在矿里喝；扣 1 瓶；回血量、能喝的层、价格、库存**都从 `content.mine.potions` 读**，不写死数字（待用户定）；回血不超过上限；冷却中回 `potion_cooldown`；血满回 `hp_full`；没有药回 `no_potion`。
17. 武器（id 都是 `weapon_*`）：新档只有木剑并已装上；`equip` 能换成拥有的武器，没有的回 `not_owned`；工作台做铁剑进 `weapons`（Homestead 不到门槛不能做），有了不能再做；Pip 的 floor 委托在资历到 N 时算凑够，交了以后得到铜剑并自动换上（当前是木剑时），只给一次。
18. 旧命令 `mine_new_run`、`mine_express` 回 `unknown_command`（reducer 现有的码）。
19. 开发矿：`wd-dev-quarry`、`wd-dev-vein` 不检查 here；没有 `dev_sites` 时回 `unknown_place`。

### 12.2 客户端
- 周瑜（E）：
  - 按 view 的 `mobs` 生成怪，按岩石数摆岩石；
  - 本层没清完时下梯子是灰的，清完就亮；
  - 电梯只列站点；
  - 倒地和日切各弹一次通知，然后出矿回地图；
  - 状态行不再有 Run 和 Express。
- 刘邦（F）：
  - 每种怪的 brain：蝙蝠的俯冲节奏；岩甲虫硬直 2 秒、期间 `stunned()` 为 true；菇菇怪缩回 1 秒不进 targets、按 `spore_at` 打中；
  - `MonsterArt.view`：有文件用文件、没文件用占位体；精英和守关的材质参数和头饰；
  - 读 json 里的 hit_at / 时长。
- 刘邦（G）：
  - 换武器以后手上的剑跟着换；
  - 快捷栏的药显示数量和冷却，点了发 `mine_drink`；
  - Pip 的「Reach Floor N」进度。

## 13. 还没定、默认先这样（q 行 E / F / G 或用户定；都是数据，改它不改代码）
1. 离开一层，这一层还活着的守关和精英回满血（第 5 节第 9 条；v4q(5) 复核 ①，奕星已转李白改 q 行）。
2. 打过的守关层以后不再有守关；每周重打放第二批（第 5 节第 5 条；李白会把 q 行 ⑨ 的每周重打标成第二批）。
3. **回血药**：售卖处、价格、库存、回血量、哪些层能喝（v4q(7) G，早上报用户）。初值取现行方案文档的数。
4. **精英史莱姆的掉落**：不掉石英已定（以 v4 为准）；「每天一次」要不要、掉什么，交 v4q(6) 定。
5. **矿脉门槛**：v4 写 Homestead Lv8；有人提议开局就能去（冲突清单第 2 节第 2 条），待定。
6. **副产 `side`** 第一批掉不掉：三方说法不一，统一后标〔待用户定〕。
7. **Pip 委托**：Lv3 直接出现在 Today，还是要去驿站接（冲突清单第 2 节第 18 条，待定）。
8. 所有数值：怪的血量和伤害、武器、配方、Pip 的 N、主产包的数量、掉落权重（李白校准）。
9. 进矿时血量回满，出矿和倒地后也回满（v4q(5) 已写：进矿满血，倒地或出矿后下次进矿也满血）。日切留在原层时血量不变（我定的，q 行没写）。
10. 日切留在原层（v4q(5) ⑥ 已定，周瑜按实现确认可行，不改成送回矿口）；文案见第 7.4 节；矿口卡、矿层、电梯、守关层、倒地卡的帧由安其拉出（E1–E6）。
11. 「每层当天第一次进 2 体力」里的「当天」是 v4q(5) 补定的，〔待用户定〕；数值在 `floor_energy`，是不是按天由数据定（`fee_per_day: true`）。

# MANIFEST · group npc (batch 1 · 2026-10-03)

Pages in `ui/batch1/`, canvas 1080 × 2400, shared `../kit.css` + `../icons.svg` plus this group's `../kit-npc.css` + `../icons-npc.svg` (kit.css / icons.svg untouched). Not screenshotted (left to the batch screenshot pass). HUD two rows, place chip "City · Space", quick bar collapsed to a handle on every scene page (no action in an outpost / on the map), cards 1 px edge no shadow, numbers tabular.

## Base images (scenes/)

| File | Size | How | Check |
|---|---|---|---|
| `scenes/outpost.png` | 1024 × 1536 | `gen_scene.sh outpost outpost.prompt.txt farm.png ref1-map-social-ui.png ref3-farm-house-stages.jpg` — first call succeeded (size 1024x1536, no retry, 5192 tokens; see `outpost.log`, `outpost.prompt.txt`, `outpost.response.json` is git-ignored) | Three clay buildings as asked: Market with wood eave + produce crates and a tea window at the counter's right end (kettle + cups, host holding a cup), Tackle Shop with hanging rods / bobbers / net, Travel Post tower with clock + blank map board; tea table with parasol in the middle; wooden request board with blank cards; keeper behind the counter, tea host at the window, courier kid with cap by the board, two other players; temperate coastal skin (sand, pebbles, sea, gull). All signs blank, no text found. Island top ≈ 11 % (flag tip), bottom ≈ 74 % → top 12 % / bottom 24 % clear. Extras the model added, harmless: a small dock with a rowing boat and a life ring. Not generated (not in the brief's list): Old Kai mending a net, the passport stamp desk. |
| `scenes/map-tile.png` | 1080 × 2400 | No generation. No real map screenshot in the repo qualifies (farm-ui-2026-09-05/*.png, vivo-map-*.png, ref-gensen-map.png are street-level Mapbox captures with UI overlays), so the repo's existing pastel 3D city-map background `social-background-2026-09-28/variant-a.png` (already shipped in-app as `assets/ui/backgrounds/map-social.png`) was cover-cropped with ffmpeg (scale 1600 × 2400, centre crop 1080 × 2400). Provenance in `scenes/map-tile.SOURCE.txt`. | City-level, pastel, low contrast, bay + island + green blocks, no UI, no text. It is a generated "map-like" tile, not a real tile render — if a true Mapbox pastel style is wanted, swap the file; every overlay is positioned on canvas px, not on map features. |

Outpost camera on scene pages: `body.scene-cam`, canvas = source × 1.22 + (−73, 360) (island y 566…1756, player ≈ 55 %). NPC-6 zooms the same png: × 2.4 + (−425, −272) with the tea window at canvas (540, 1000).

## Pages

| ID | File | Base | Fig 1 | Fig 2 | Not done / deviations |
|---|---|---|---|---|---|
| MAP-1 | `MAP-1.html` | `scenes/map-tile.png` (cover 1:1) | Home city full colour inside a feathered hole of a #B9BDC4 60 % fog (CSS mask); 4 grey cities under the fog ("Suzhou · Unexplored" etc.); city bubble "Shanghai · 14 online"; 3 outpost pins "Pudong Market · 3 online" (gold !), "Hongkou Market · 5 online" (green ✓), "Xuhui Market · 4 online"; 2 pond pins "Willow Pond / Beginner pond · 1.2 km" (cyan ◆), "Reed Pond / Beginner pond · 3.4 km"; farm crest pin "Homestead" + you-dot; friends Mira / Kai; 7 lit POI discs with no badge / label; HUD "142/200 · +1 in 2:41", Today chip, place chip "Shanghai · Homestead ›"; bottom = handle + Bag + "Nearby Cities"; no Map button, no FAB, no switch | — (country-level view not requested this round) | Pond pin text is two lines ("Willow Pond" / "Beginner pond · 1.2 km") rather than one. Base is a generated map look-alike (see above). |
| NPC-1 | `NPC-1.html` | `scenes/outpost.png` | (facility-tap revision 2026-10-04: facilities are tapped on the scene, the main action key never shows a facility verb) Plaza with sign "Pudong Market" on the market roof; fingertip card "Market · Tap to shop" (2 px primary stroke, `../kit-facility.css`) on the stall awning's front edge; "Market Keeper · Mei" tag moved under her (pointer on her apron, card over the counter front); "Tea Counter" sign slid 40 right; "Market Board" label moved under the board (pointer on its bottom rail, clear of Pip); Pip's yellow ! bubble kept; under-HUD "Free · Home Outpost"; bottom = handle + Bag only (no main action key, no switch); place chip "Shanghai · Pudong Market" | `NPC-1-2.html`: unchanged (its 2 × 2 climate skins carry no main action key, so nothing to remove; the tap card is not repeated there) | "Shop · Free" FAB removed; the keeper tag could not stay on Mei's head (the band above the counter is Mei's face, where the tap card now sits), so it points at her apron instead; NPC-1-2 keeps its old labels (Mei tag on her head, Market Board label above the board). |
| NPC-2 | `NPC-2.html` | outpost, dimmed | 60 % drawer: title "Pudong Market · Shop", tabs Buy / Sell / Market Board, keeper portrait + "Market Keeper · Mei" + the full line, "Shared stock · all Shanghai outposts", rows Sweet Potato Seeds · 15 coins · Stock 8/10 (selected, − 1 + stepper) / Apple Sapling · 40 coins · grey "Locked · Farming Lv7" / Orchard Feed · 6 coins / Compost · 2 coins "Sold out today · resets in 9h 12m" (example row) / City Specialty shelf: Recipe Card · Regional · 200 coins · cyan ◆ "New for you"; footer "Buy" | `NPC-2-2.html`: Tackle Shop variant — "Tackle Keeper · Finn", Bite Board side card "Perch bite at dusk here", Reed Rod · 80 coins · Fishing Lv3 ✓ (selected) / Carbon Rod · 350 coins grey Fishing Lv6 / Spinner Lure · 6 coins · Stock 10/10 / Fish Trap · 120 coins grey Fishing Lv5; "Buy" | Drawer is 60 % (1440) not half-screen, to fit the City Specialty shelf. "Sold out today" is shown on an extra Compost row instead of a top-right line. |
| NPC-3 | `NPC-3.html` | outpost, dimmed | Sell tab: amber bar "Buyback today 64/80" + "Counts across all Shanghai outposts"; rows "Sweet Potato ×12 · 5 each · 60 coins", "Fisher's Stew ×2 · 18 each · 36 coins", "Smelt ×3 · 4 each · 12 coins" (regional fish) with Sell; grey "Radish ×24 · Sell at home" | `NPC-3-2.html`: bar red "Buyback limit reached today 80/80 · Resets in 9h 12m", row buttons grey "Limit reached", wide grey footer button "Buyback limit reached today · resets in 9h 12m" | Row buttons carry the short reason; the full sentence is on the footer button, not on each row. |
| NPC-4 | `NPC-4.html` | outpost, dimmed | Wooden board "Market Board" with 3 pinned cards: Dusk Haul (Open · 4 Fine fish · any kind · 24 coins · +1 city stamp · Deliver at any Shanghai outpost · Track / Show on map), Morning Greens (Tracked · Drop / Show on map), Harbor Lunch (Ready to deliver · Deliver here · Shanghai Market · Deliver); corner "Requests today 4 of 6 · Next request in 3h 58m" + "Same board at all 6 outposts"; handle + Bag below | `NPC-4-2.html`: Together card "Harvest Together · Together · 2–6 players / 3 joined · 7:12 to start / joined avatars 3 of 6 / Everyone gets the full reward / Join", beside it the fallback "Not enough players · solo request" card, plus the open Dusk Haul card | Card 1 uses the spec's mandatory "Deliver at any Shanghai outpost"; the brief's "Deliver here · Shanghai Market" is on the ready card instead. Status words Done / Dropped not shown (no card in that state). |
| NPC-5 | `NPC-5.html` | outpost | Bottom dialogue bar: Pip portrait, "Pip · Courier Kid", "Acquainted" tag + progress bar + "next · Familiar", line "Got a Common fish for me? Any kind.", buttons Gift (lit — bag has Common fish) / Request; Pip's ! bubble replaced by a "Pip" name tag; FAB and quick bar hidden | `NPC-5-2.html`: "Granny Wu shared a meal with you · +20 Energy" card with granny → bowl → you hand-over frame, "+20 Energy" over the player, HUD 162/200, "+2 · first chat today" above the bar, Gift greyed "Gift already given today" | The grey Gift reason "Nothing he likes in your bag" is not shown (Gift is lit in fig 1). Granny Wu is a name tag on the straw-hat NPC in the png (no dedicated granny model in the base). Five stage names only appear as Acquainted / Familiar / Trusted. |
| NPC-6 | `NPC-6.html` | outpost, zoomed on the tea window | "Tea Counter" sign on the window, "Tea Host · Ama" tag, glow ring on the cup she holds out, card "Hot Tea · +30 Energy · 40 coins (1/3)" + "Next cups today 50 coins · 60 coins · Counts across all outposts", buttons "Hot Tea · +30 Energy" / "Coffee · +30 Energy", inset top-right "Sip at the tea table · 2 s" with "+30 Energy"; handle + Bag | `NPC-6-2.html`: "Tea 3/3 today · back tomorrow" card, both buttons grey, "Counts across all outposts"; side frame "When Energy is full" with the grey "Energy full" button; HUD amber 42/200 | Spec's sub-line "Coffee · at the Travel Post" dropped in favour of the brief's Coffee button. The "player carries the cup and sits" moment is an inset crop of the tea table, not an animation frame. |
| OUTPOST-DIAGRAM | `OUTPOST-DIAGRAM.html` | none (HTML/SVG) | Title "Outposts, Ponds & POI"; figure: Shanghai tier-6 circle with 6 group icons, 2 ponds in dashed 0.5° cells, 3 farm crests, 14 grey POI dots; small town (1 group · 1 pond) and San Francisco tier-3 (3 groups) circles; legend (group / pond / farm / POI); table "City tier → outpost groups" (<0.5 M 1 · 0.5–1.5 M 2 · 1.5–3 M 3 · 3–8 M 4 · 8–15 M 5 · >15 M 6, examples Shanghai 6 · London 5 · San Francisco 3 · Small town 1); rule "Every city guarantees ≥1 outpost group + ≥1 beginner pond" | — | Tiers 2 / 4 / 5 are table rows only (no circle drawn for them). |

## Self-check

- `python3` scan of all group files: no CJK characters; none of "Row Tool / Map 按钮 / Passport 小书 / Enter mine · 10 / Tea Stand / Pick an ingredient". The only "Passport" string is the avatar button's `title="Profile · Passport"` attribute inherited from the v4 pages (not visible text); "Map button" appears once inside an HTML comment in MAP-1 ("no Map button").
- Every mandatory string from §16.3 for MAP-1 / NPC-1…6 is present (checked by substring).
- Pages render at exactly 1080 × 2400 (checked in a headless browser while building; those check shots were not kept).

## Files

```
scenes/outpost.png · outpost.prompt.txt · outpost.log          (outpost.response.json git-ignored)
scenes/map-tile.png · map-tile.SOURCE.txt
ui/kit-npc.css · ui/icons-npc.svg
ui/batch1/MAP-1.html
ui/batch1/NPC-1.html · NPC-1-2.html
ui/batch1/NPC-2.html · NPC-2-2.html
ui/batch1/NPC-3.html · NPC-3-2.html
ui/batch1/NPC-4.html · NPC-4-2.html
ui/batch1/NPC-5.html · NPC-5-2.html
ui/batch1/NPC-6.html · NPC-6-2.html
ui/batch1/OUTPOST-DIAGRAM.html
ui/batch1/MANIFEST-npc.md
```

## 第四轮（2026-10-04）：据点拆散为每岗位一处，除集市广场外全部室内

用户定稿：尽可能利用真实地图——每个功能 NPC 单独一处空间、一枚 pin；空间全部室内（两面墙切开的单间 diorama，相机同农场 / 厨房）；只有集市广场例外为室外；角色按职业住进据点；落点可参考 POI 密度但不认领店铺。评估见 `docs/product/research/gameplay-plan-v2-2026-10-02/round4-npc-rooms/`。

新底图（`scenes/gen_scene.sh`，refs = kitchen.png + farm.png；集市广场用 outpost.png + farm.png）：`tea-house.png` · `tackle-shop.png` · `travel-post.png` · `trading-post.png` · `market-square.png`（首版带黑色暗角，页面用 `mask-image` 径向遮罩淡出到奶油渐变；`market-square-v2.png` 为去暗角重出版）。室内页统一相机 `--cam-scale:1.12 --cam-x:-30 --cam-y:360`，集市广场 `1.1 / −32 / 307`。

| 编号 | 文件 | 底图 | 画面 | 备注 |
|---|---|---|---|---|
| NPC-1a | `NPC-1a.html` | tea-house | 门头 "Lotus Tea House"；Tea Host · Ama 名牌在柜台前；指尖卡 "Tea House · Tap to order"（柜台下）、"Sit · Party room"（前排茶桌）、"Door · Back to map"（台阶）；Hana · Café Owner + ♥；Free · Home Set；芯片 "Shanghai · Lotus Tea House"；底部 Bag + 把手 | 原 NPC-1 据点组广场作废，Figma 卡 NPC-1 改名 NPC-1a |
| NPC-1b | `NPC-1b.html` | tackle-shop | 门头 "Pudong Tackle Shop"；Tackle Keeper · Finn；"Tackle Shop · Tap to shop"、"Bite Board · Tap to read"；Old Kai + !；Door | 原 NPC-1-2 四气候皮肤作废，Figma 卡改名 NPC-1b |
| NPC-1c | `NPC-1c.html` | market-square | 门头 "Shanghai Market Square"；Market Keeper · Mei；"Market · Tap to shop"、"Market Board · Tap to read"、"Weekend market · Sat 10:00"；Nadia · Market Baker + !、Theo · Gardener；Door | 唯一室外据点 |
| NPC-1d | `NPC-1d.html` | travel-post | 门头 "Shanghai Travel Post"；Post Clerk · Sigrid；"Travel Post · Tap to book"、"Stamp desk · Tap to stamp"；Pip · Courier Kid + !、Sam；Door | — |
| NPC-1e | `NPC-1e.html` | trading-post | 门头 "Tundra Trading Post"；四张指尖卡 Tea / Tackle / Market / Travel Post；Granny Wu + ♥；Pip + !；芯片 "Tromsø · Trading Post" | S 档与荒野 |
| NPC-2 / 3 / 3-2 / 4 / 4-2 | 同名 | market-square（压暗） | 文案改 "all Shanghai markets" / "Same board at all 3 market squares" / "Deliver at any Shanghai market"；芯片 "Market Square" | 抽屉内容不变 |
| NPC-2-2 | 同名 | tackle-shop（压暗） | "Shared stock · all Shanghai tackle shops"；芯片 "Pudong Tackle Shop" | — |
| NPC-5 | 同名 | travel-post | 门头 "Shanghai Travel Post"，Pip 名牌在头顶；芯片 "Travel Post" | Market/Tea/Board 标签删除 |
| NPC-5-2 | 同名 | trading-post | 门头 "Tundra Trading Post"，Granny Wu 名牌在头顶；芯片 "Tromsø · Trading Post" | — |
| NPC-6 / 6-2 | 同名 | tea-house（相机 2.0 / −220 / −440 推到柜台） | "Counts across all tea houses"；小图端杯到茶桌；"sit at a tea table to open the party room"；芯片 "Lotus Tea House" | 墙上招牌去掉（被小图遮挡） |
| MAP-1 | 同名 | map-tile | pin 改为按岗位：Shanghai Market Square（!）/ Hongkou Tackle Shop（✓，贴 Reed Pond）/ Lotus Tea House / Shanghai Travel Post + 聚合 pin "Tea House ×5 · 12 online · Tap to list"（`.pin.is-cluster`、`.mk.is-count`） | — |
| OUTPOST-DIAGRAM | 同名 | — | v2：上海 15 处（6 茶馆 · 4 渔具铺贴塘 · 3 集市广场 · 2 驿站）、小城 1 间小木屋、旧金山 3 · 1 · 2 · 2；分档 → 数量表（`.dg-table.is-wide`）；家一套 | — |

截图：本机 headless Chrome 经 `python3 -m http.server 8765`（file:// 下 svg sprite 不加载）。

### 2026-10-04 傍晚：柜台与背包同屏（Sell Tab 取消）

用户审图后定稿：集市广场与渔具铺的柜台抽屉统一成 FARM-6 的"柜台 + 背包"版式。页面 `NPC-2 / NPC-2-2 / NPC-3 / NPC-3-2` 重写：`<section class="drawer is-stall-bag is-counter">`，复用 `kit-farm.css` 的 `.srow / .stepper / .quota / .detail` 与背包网格（页面须额外链接 `../kit-farm.css`，否则商品行全部塌成纯文本——第一次截图就是这样）；`kit-npc.css` 末尾加 `.drawer.is-counter` 段（掌柜一行 `.kline`、`.tab.is-here`、`.quota.is-full` 红条、格上绿签 `.cap-s`、`.price-tag`）。

| 编号 | 画面 | 备注 |
|---|---|---|
| NPC-2 | 上半 Buy / Market Board + "Market Keeper · Mei · Sweet potato seeds, fresh in. · Shared stock · all Shanghai markets" + 4 行（Sweet Potato Seeds · Bag ×0 · − 1 + · 15 · Buy / Apple Sapling 灰锁 / Orchard Feed / Recipe Card ◆ New for you · City Specialty）；下半 Bag 19/25，Tab "Sell here 3"（绿描边）/ All（选中）…，详情卡 Grilled Crucian ×3 · "Not from this region · sells at the Homestead Stall" + Pin / 灰 Sell at home / 灰 Sell All · at home；格里 Sweet Potato / Fisher's Stew / Smelt 带绿签 Sell here | 商品行 meta 超长时省略号；无额度条（Buy 态） |
| NPC-2-2 | 渔具铺：Buy / Bite Board，"Tackle Keeper · Finn"，Reed Rod / Carbon Rod 灰锁 / Spinner Lure · Bag ×3 / Fish Trap 灰锁；额度条 "Fish buyback today 30/80 · all tackle shops · resets in 9h 12m"，Tab "Sell here 4" 选中，详情卡 Pond Crucian ×3 · 2 each · Sell All = 6 coins · Pin / Sell / Sell All，格 4 条鱼 | — |
| NPC-3 | 集市卖态：掌柜改说 "Sweet potatoes and stew, I'll take those…"，额度条 "Buyback today 24/80 · all Shanghai markets"，Tab "Sell here 3" 选中（3 格 + 22 空），详情卡 Sweet Potato ×12 · Regional crop · Subtropical · 5 each · Sell All = 60 coins | — |
| NPC-3-2 | 额度满：红条 "Buyback limit reached today 80/80"，掌柜 "That's all I can take today…"，按钮灰 "Limit reached" / "Limit reached · 9h 12m" | — |

网格底边约 y 2370（比 FARM-6-2 多了掌柜一行 + 额度条）；真机实现时柜台区限高 4 行、背包网格可滚。

### 2026-10-04 晚：掌柜先打招呼，柜台抽屉带掌柜栏

用户定稿：点 NPC 不直接弹商店——先问候卡，选 **Trade** 才开柜台；售卖界面要突出 NPC 形象。

| 编号 | 文件 | 画面 | 备注 |
|---|---|---|---|
| NPC-G1 / G1-2 / G1-3 / G1-4 | `NPC-G1*.html` | 房间轻压暗，掌柜头顶指尖卡亮成 "<名字> · Talking"（`.tag-tap.is-on`）；底部问候卡 `.greet`（560 高）：左 300 × 512 掌柜近景（场景 png 的 `background-image` 裁切，底部渐变名字），右 岗位 · 名牌 / "Keeps the …" / 一句带今日信息的问候 / 三个选项：主按钮 **Trade**（副文案 open the stall / order tea / see the rods / book a trip）、信息问句（What's fresh today? / Any news in town? / Where are they biting? / Fares today?）、灰字 Just passing by | 近景裁切参数在 `PORT` 表（页面内 `background-size:1500px 2250px` + position）；没有 Bag 与把手 |
| NPC-2 / 2-2 / 3 / 3-2 | 同名 | 抽屉顶 270（`--drawer-h:2130`），标题 "Mei's Stall · Market Square" / "Finn's Tackle · Pudong"；掌柜一行换成**掌柜栏** `.kpanel`（116 近景 + 岗位 · 名牌 + 两行气泡 + 小字；配色 `.is-market` 蜜色 / `.is-tackle` 海蓝 / `.is-tea` 鼠尾草 / `.is-travel` 藏青）；背包网格减为 4 行（20 格，可滚） | 网格底边 ≈ 2257，回到安全区内 |
| NPC-1a–1e | 同名 | 掌柜指尖卡一律改 "<名字> · Tap to talk"（图标 i-talk）；设施卡（Market Board / Bite Board / Stamp desk / Sit）不变 | 小木屋四张写 Tea / Tackle / Market / Post · Tap to talk |

### 2026-10-04 夜：补齐三张

| 编号 | 画面 | 备注 |
|---|---|---|
| NPC-6 / 6-2 | 点单卡顶部加 "Ama's Tea · Lotus Tea House" + ✕ 与掌柜栏 `.kpanel.is-tea`（Ama 近景 + 气泡 + 小字）；原柜台上方的 Tea Host 名牌去掉 | `.kpanel` 规则已做成全局（不只 `.drawer.is-counter`） |
| NPC-7（新） | 驿站室内压暗；抽屉 `.drawer.is-counter.is-post`（1720 高）："Sigrid's Desk · Travel Post"，Tab Permits / Passport / Fares，掌柜栏藏青底；两张 `.pcard`（Travel Permit / Long-haul Ticket）：`.how` 配方行、`.pchip` 材料 / 条件芯片（✓ 绿框、灰不满足）、Craft / Buy；页脚 Coffee · Travel Biscuits · 盖章台 | **坑**：卡内类名不能叫 `.recipe` / `.chip`，会撞 kit.css 的配方行与 HUD 芯片样式 |

- 2026-10-04 夜清理：删除作废的据点组广场底图 `scenes/outpost.png`（含 .log / .prompt.txt）与旧页面 `NPC-1.html` / `NPC-1-2.html` 及其渲染图（Figma 卡已分别换成 NPC-1a / NPC-1b）；`contact-batch1-C` 对应两格改指 NPC-1a / NPC-1b 并重出。

## 2026-10-04 夜 · NPC-G1-5 农场驿站伙计 Bao（p(4)：NPC 之后都先要打招呼）

| 页 | 文件 | 画面 | 备注 |
|---|---|---|---|
| NPC-G1-5 | `NPC-G1-5.html` | 底图 `scenes/homestead-stall.png`（新生成的驿站棚近景：Bao 戴草帽站柜后挥手，柜上种子包 / 堆肥袋 / 蚯蚓罐 / 小秤，右侧 Stall Board，玩家背影），相机 1.1 / −32 / 307；牌子 "Homestead Stall"、指尖卡 "Bao · Talking"；问候卡 "Stallhand · Bao" / "Keeps your stall · Homestead" / “Morning! Radishes sell for 5 each today. Worm Bait's sold out — back in 9h 12m.” / Trade · buy & sell / What's selling today? / Just passing by | 近景裁切 `background-size:1434px 2150px; background-position:-602px -637px`；HUD 位置芯片 "Shanghai · Homestead" |

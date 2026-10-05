# 批次 1 截图巡检报告（2026-10-03）

> **资料范围（2026-10-05 清理）**：此页保留美术来源、技术或原日期的验证过程；旧界面/布局不是当前验收稿。当前规则和有效稿入口见 [设计索引](../../../README.md)。已移除的旧图按清理记录中的固定 Git 版本查阅。

- 来源：`ui/batch1/*.html` 51 页（farm 组 20 · cook 组 17 · npc 组 14），经 `python3 -m http.server 8795` 本地服打开（file:// 下外链 `<use>` 图标不渲染）。
- 工具：Playwright（Chromium）视口 1080 × 2400，逐页 `goto` → 等 networkidle + `document.fonts.ready` → 截 1080 × 2400 画布；原图落 `.playwright-mcp/batch1/`，再 cp 到本目录。
- 产出：本目录 55 张 PNG = 51 张单页 + 4 张对比图（`contact-A/B/C/D.png`，1912 宽，每行 5 张、每张缩到 360 宽、带编号标题）；对比图源文件 `ui/contact-batch1-A..D.html`。
- 自动检查（每页）：`scrollWidth × scrollHeight` 均为 1080 × 2400；无元素越出画布（未被祖先裁剪的 bbox 全在 0–1080 / 0–2400 内）；`<img>` 无加载失败；`<svg><use>` 全部有渲染尺寸（例外见下）；Google Fonts（Nunito）`document.fonts.status = loaded`。

## 控制台

- 51 页 **无 JS 错误、无 pageerror、无资源 404**（kit*.css / icons*.svg / scenes/*.png 全部 200）。
- 唯一的控制台条目是每页一条 `GET /favicon.ico 404`（本地服没有 favicon，与页面无关）。
- `<use>` 零尺寸的条目：BAG-3 / BAG-4 / BAG-4-2 / BAR-2 / FARM-6 / FARM-6-2 的 `icons.svg#i-home`，COOK-2a / COOK-2b 的 `i-stove-off · i-steam · i-check · i-cabinet · i-cookbook`——都是被抽屉盖住、`display:none` 的场景标签里的图标（symbol 本身在 icons.svg 里存在），不是缺图。

## 修过的页面（一轮，已重截）

| 页 | 问题 | 改法 |
|---|---|---|
| `HUD-1.html` | 底部标注 "quick bar · 5 consumable slots … ghost slot = dashed, no plus sign" 一行 nowrap 超出右缘，截成 "…ghost slot = dashe" | 去掉与下一行重复的 "· bottom 124"，该标注改 `font-size:18px`；现在右缘 989 px |
| `CTRL-1.html` | ① `--cam-x:60px` 让 png 左缘空出 60 px，左侧露出上青下米的底色竖条，像破图；② "camera pans only…" 标注（850,1612，宽 200）折 6 行压到切换键上；③ "touch anywhere…" 居中标注右端被切换键盖住 | ① `--cam-x` 改 0，四个场景标签、三团尘云、软连线一并左移 60 px（角色仍在虚线安全框内，框左缘 324，角色约 350–450）；② 标注改 top 1556 / 宽 210（现在 1556–1676，在切换键 1756 之上）；③ 居中标注 left 540 → 480（现在 67–893，切换键从 912 起） |
| `MAP-1.html` | 底部灰城市芯片 Hangzhou (240,1990) 与 Jiaxing (580,1990) 互相叠压，Jiaxing 又被 "Nearby Cities" 钮盖住 | Hangzhou → (230,1880)，Jiaxing → (520,2020)，三者不再相交 |

其余 48 页未改动。

## 逐页状态

A 农场 / HUD / 操控（20）

| # | 页 | 状态 | 备注 |
|---|---|---|---|
| A01 | HUD-1 | 正常（已修） | Today 芯片仍按 kit 规则省略成 "Shanghai Ma…"（builder 已知） |
| A02 | HUD-1-2 | 正常 | |
| A03 | HUD-3 | 正常 | |
| A04 | HUD-4 | 正常 | 芯片同 A01 截断 |
| A05 | CTRL-1 | 正常（已修） | 标注 "camera pans only…" 压在岛右缘石头上，对比度一般但可读；田右缘两列与 Explore 牌被裁是相机右移的既定取舍 |
| A06 | CTRL-1-2 | 正常 | 最近帧是 png ×4 放大，发糊属预期 |
| A07 | FARM-2 | 正常 | |
| A08 | FARM-3 | 正常 | "+2 Farming XP" 小飘字与 "+1 Radish" 轻微相压，可读 |
| A09 | FARM-6 | 正常 | |
| A10 | FARM-6-2 | 正常 | |
| A11 | FARM-7 | 正常 | |
| A12 | FARM-7-2 | 正常 | |
| A13 | BAR-1 | 正常 | |
| A14 | BAR-1-2 | 正常 | |
| A15 | BAR-2 | 正常 | |
| A16 | BAR-3 | 正常 | |
| A17 | SKILL-3 | 正常 | |
| A18 | SKILL-3-2 | 正常 | |
| A19 | TUT-2 | 正常 | |
| A20 | TUT-2-2 | 正常 | |

B 钓鱼 / 烹饪 / 背包（17）

| # | 页 | 状态 | 备注 |
|---|---|---|---|
| B01 | FISH-2 | 正常 | 三联 0.30 缩放帧内文字很小，属并排图预期 |
| B02 | FISH-3 | 正常 | |
| B03 | FISH-4 | 正常 | |
| B04 | FISH-5 | 正常 | 四件事卡右下角与切换键 ⇄ 相压（卡盖在键上，键露出一角） |
| B05 | FISH-5-2 | 正常 | |
| B06 | COOK-2a | 正常 | |
| B07 | COOK-2b | 正常 | |
| B08 | COOK-2b-2 | 正常 | 五格排布信息密，缩略帧文字小 |
| B09 | COOK-3 | 正常 | |
| B10 | COOK-3-2 | 正常 | |
| B11 | COOK-4 | 正常 | |
| B12 | COOK-6 | 正常 | |
| B13 | COOK-7 | 正常 | CSS 替身 Avatar 是色块，属预期 |
| B14 | COOK-7-2 | 正常 | |
| B15 | BAG-3 | 正常 | |
| B16 | BAG-4 | 正常 | 拖拽影子盖住 "Bag 19/25" 条和 Fish Tab（拖拽中间帧，故意的） |
| B17 | BAG-4-2 | 正常 | |

C 地图 / NPC（14）

| # | 页 | 状态 | 备注 |
|---|---|---|---|
| C01 | MAP-1 | 正常（已修） | |
| C02 | NPC-1 | 正常 | |
| C03 | NPC-1-2 | 正常 | |
| C04 | NPC-2 | 正常 | |
| C05 | NPC-2-2 | 正常 | |
| C06 | NPC-3 | 正常 | |
| C07 | NPC-3-2 | 正常 | |
| C08 | NPC-4 | 正常 | |
| C09 | NPC-4-2 | 正常 | |
| C10 | NPC-5 | 正常 | |
| C11 | NPC-5-2 | 正常 | |
| C12 | NPC-6 | 正常 | 右上小图里 "+30 Energy" 飘字被小图说明条压住一角 |
| C13 | NPC-6-2 | 正常 | |
| C14 | OUTPOST-DIAGRAM | 正常 | |

D 已有锚定图回顾（8，仅拼图，未重截）：out/v4 FARM-1 · FISH-1 · BAG-1 · EQUIP-1，out/v3 COOK-1 · ACTION-RADIAL · COOK-2a-recipes · COOK-2b-experiment。

## 仍有问题 / 需要 builder 或评审决定的页

没有破图级问题；以下是肉眼看到的小瑕疵，本轮未改：

1. **HUD-1 / HUD-1-2 / HUD-4 / MAP-1 / NPC-* 的 Today 芯片截断**（"Deliver 4 Fine fish · Shanghai Ma…"）——kit 规则是省略号，builder 在 MANIFEST 里已标；要么改短文案要么 24 px。
2. **CTRL-1**：标注文字压在岛缘石头上；田右缘 / Explore 牌被裁（相机右移的取舍）。
3. **FISH-5**：四件事卡与切换键相压，建议卡再上提约 60 px 或在卡态下隐藏切换键。
4. **FARM-3**："+2 Farming XP" 与 "+1 Radish" 两枚飘字轻微相压。
5. **NPC-6**：小图内 "+30 Energy" 飘字被说明条压住一角。
6. **BAG-4**：拖拽影子遮住容量条与 Fish Tab——是中间帧，如评审觉得干扰可把影子再往下挪到 Tab 行以下。

## 文件

- 单页：`out/batch1/<ID>.png`（51，1080 × 2400）
- 对比图：`out/batch1/contact-A.png`（20 页，1912 × 3644）、`contact-B.png`（17 页，1912 × 3644）、`contact-C.png`（14 页，1912 × 2758）、`contact-D.png`（8 张，1912 × 1872）
- 对比图源：`ui/contact-batch1-{A,B,C,D}.html`（引用 `../out/batch1/*.png` 与 `../out/v4|v3/*.png`，需经 http 打开）
- 服务器已 `pkill -f 'http.server 8795'`。

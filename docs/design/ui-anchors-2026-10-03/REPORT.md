# UI 风格锚定 · 三张合成图报告（2026-10-03）

目标：FARM-1 / FISH-1 / COOK-1 三张"AI 场景底图 + HTML UI 层"合成图，供用户审阅风格后再批量出图。
画布 1080 × 2400（9 : 20），Playwright 视口 1080 × 2400、dpr 1，经 `127.0.0.1:8791` 本地 http 服务加载（截完已关闭）。

## 1. 产出

| 编号 | 界面 | 文件（POSIX 绝对路径） | 尺寸 |
|---|---|---|---|
| FARM-1 | Farm Overview | `/Volumes/ACASIS/projects/sensen-godot/docs/design/ui-anchors-2026-10-03/out/FARM-1.png` | 1080 × 2400 |
| FISH-1 | Pond Scene | `/Volumes/ACASIS/projects/sensen-godot/docs/design/ui-anchors-2026-10-03/out/FISH-1.png` | 1080 × 2400 |
| COOK-1 | Kitchen & Stove Select | `/Volumes/ACASIS/projects/sensen-godot/docs/design/ui-anchors-2026-10-03/out/COOK-1.png` | 1080 × 2400 |
| — | 三联对比图 | `/Volumes/ACASIS/projects/sensen-godot/docs/design/ui-anchors-2026-10-03/out/contact-sheet.png` | 1780 × 1360 |

源文件：`ui/farm.html` · `ui/pond.html` · `ui/kitchen.html` · `ui/contact.html` · `ui/kit.css`（本轮新增 `.cast-ring`）。
Playwright 过程截图：`/Volumes/ACASIS/projects/sensen-godot/.playwright-mcp/anchor-{farm,pond,kitchen}-r{0,1}.png`、`anchor-contact-sheet.png`。

## 2. 底图选择

| 页面 | 使用的底图 | 说明 |
|---|---|---|
| farm.html | `scenes/farm.png`（1024 × 1536） | 无文字、无 UI；门牌与矿洞指示牌为空白木板，正好被 UI 标签覆盖 |
| pond.html | `scenes/pond.png`（1024 × 1536） | 无文字、无 UI；两名邻居无昵称；落点处是水波纹而非光圈 → 由 UI 画 `.cast-ring` |
| kitchen.html | `scenes/kitchen-v2.png` → 已复制为 `scenes/kitchen.png`（1024 × 1536） | v2 风格与 farm.png 一致（同款基座 / 草沿），一本素封面 Cookbook、三块空白墙牌、三灶各自状态分明。原 v1（1145 × 1374，两本带叉勺纹章的书、三灶全有火、多出餐桌）改名为 `scenes/kitchen-v1.png`（连同 `.log/.prompt.txt/.response.json`），不再使用 |

三张底图均未发现文字残留或 UI 残留。

## 3. 快捷栏一致性（browser_evaluate 读取 getBoundingClientRect）

三页数据完全一致：

| 元素 | farm.html | pond.html | kitchen.html |
|---|---|---|---|
| `.quickbar` | x 30 · y 2076 · 1020 × 200 | x 30 · y 2076 · 1020 × 200 | x 30 · y 2076 · 1020 × 200 |
| `.chip`（场景芯片） | 30, 2116, 160 × 160 | 30, 2116, 160 × 160 | 30, 2116, 160 × 160 |
| `.slot` ×4 的 x | 202 / 374 / 546 / 718 | 202 / 374 / 546 / 718 | 202 / 374 / 546 / 718 |
| `.slot` 的 y / 尺寸 | 2116 · 160 × 160（第 2 格选中态上抬 12 px → y 2104，按 §16.1.3 设计） | 2116 · 160 × 160 | 2116 · 160 × 160 |
| `.bag` | 890, 2116, 160 × 160 | 890, 2116, 160 × 160 | 890, 2116, 160 × 160 |
| 格子圆角 | 32px | 32px | 32px |

快捷栏底边 2276 = 屏底 124 px；底部安全区 100 px；HUD 三行 y 48–112 / 124–172 / 188–252，三页同。
三页所有用户可见文案均为英文，已逐字核对（innerText 导出 + 截图目视），无错字。

## 4. 标签位置调整记录（坐标为 1080 × 2400 画布 px；fit 模式：canvas = source × 1.0547 + 顶边 y）

仅做了一轮位置调整（r0 → r1），r1 即为最终图。

### farm.html（底图顶边 y 484）
| 标签 | r0 | r1（最终） | 依据 |
|---|---|---|---|
| Homestead Lv2（卡 + 下指尖） | --x 430 · --y 1040 · dx −40 | --x 430 · **--y 1054** · dx −40 | 指尖落在门右侧的空白门牌上沿（门牌 canvas ≈ 428, 1052–1104） |
| Sell 12 | 570 · 948 | **548 · 936** | 指尖落在驿站小棚屋脊（≈ 545, 935） |
| Ready ① | 575 · 1252 | **447 · 1260** | 原位置是幼苗格；改到田左缘的成熟小萝卜格 |
| Ready ② | 886 · 1358 | **882 · 1350** | 右侧成熟格微调 |
| Ready ③ | 728 · 1432 | **727 · 1440** | 下方成熟格微调 |
| Explore 木牌 | 846 · 780（悬在矿洞上方，与底图空白指示牌并存） | **960 · 948**，并缩为 height 58 / font 26 / padding 0 22 | 直接盖在底图的空白指示牌上，木牌自带的桩与底图木桩重合，不再出现两块牌 |

### pond.html（底图顶边 y 507）
| 标签 | r0 | r1（最终） | 依据 |
|---|---|---|---|
| Willow Pond · Beginner pond | 548 · 760，带下指尖，压到左柳树冠顶 | **540 · 660**，去掉指尖，作为场景名牌悬在 diorama 正上方 | 不再压柳树（树冠顶 ≈ y 696），也不指向某个无关物体 |
| Casting uses 5 Energy | 475 · 1168 · dx −60 | **478 · 1174** · dx −60 | 指尖落在浮漂正上方（浮漂 ≈ 478, 1188–1204） |
| 落点光圈（新增） | — | `.cast-ring` --x 480 · --y 1210 · 176 × 84 | 包住底图的同心波纹（≈ 395–565 × 1170–1250）；白边 + 主色柔光 |

### kitchen.html（底图顶边 y 468，v2 三灶一排）
| 标签 | r0 | r1（最终） | 依据 |
|---|---|---|---|
| Stove 1/3 · Empty | anchor-top · 454 · 1096 · dx −40（卡片盖住灶 1 灶面与冷灶口） | anchor-top · **452 · 1222** · dx 0 | 改为灶 1 正前方地板上的标牌，指尖抵灶体底沿（≈ 1215）；灶 1 上方是 Cookbook 挂书，放不下卡片 |
| Stove 2/3 · Cooking 0:22 | leader · 585 · 1055 · lead 270 | leader · **578 · 1056 · lead 266** · dx 0 | 引线落在锅盖左侧（锅 560–660），避开蒸汽（590–670）与墙牌 1 右沿；卡片在墙顶上方 y 726–790 |
| Stove · Ready · Grilled Crucian | leader · 790 · 1090 · lead 158 · dx 40 | leader · **740 · 1104 · lead 224 · dx 78** | 引线落在盘子左半（盘 710–820，顶 1105）；卡片 y 816–880、x 590–1045，右移 78 以避开灶 2 引线（x 578） |
| Ready 发光角标 | 724 · 1076（压在锅右侧） | **786 · 1162** | 贴在盘子前右沿，不压锅、不压保温柜（柜左沿 845） |
| Cookbook | 挂环式 422 · 842 | 卡 + 下指尖 **423 · 866** · dx −20 | 指尖抵书顶（书 380–465 × 880–995），与其他标签一致 |
| Warming Cabinet 4/6 | anchor-top · 918 · 1262 · dx −70 | 未改 | 指尖抵柜底（≈ 1250） |
| All stoves busy 横幅 | hidden | hidden | COOK-1 常态不显示 |

## 5. 已知问题与取舍

1. **fit（contain）模式 vs §16.1.2 "基座下边缘被快捷栏遮住 1/3"**：三张底图都是 2:3，按 1080 宽等比放置为 1080 × 1620 并上下补渐变带（`--scene-top/--scene-bottom` 按各图顶/底行采样），diorama 完整可见、不裁切；代价是基座底边悬在快捷栏上方 ~500 px，而非被快捷栏遮住。若要严格按规格，二选一：① 把 `--scene-fit-w` 调到 ~1400 并下移 `--scene-fit-pos`（左右会裁掉农舍/矿洞一部分）；② 批量出图时直接按 9:20 出底图（当前中转 API 对 1024 × 1792 的支持见 scenes/REPORT.md）。
2. **厨房三块空白墙牌仍可见**：底图的三块木牌（≈ 510–575 / 675–740 / 760–835 × 860–1000）尺寸只有 ~70 × 55，装不下 24 px 文案，且正对挂书与锅，所以灶口状态牌改为引线式 callout，墙牌作为空白装饰留在画面里；灶 3 的引线穿过墙牌 2 的右半。批量出图时建议提示词里去掉 "blank plaques"，或改为 "three small empty wooden signs above the stoves" 并要求更大。
3. **Stove 1 标牌在灶下方、Stove 2/3 在上方**：三灶一排且灶 1 上方被 Cookbook 占住，统一放上方会把引线拉到 320 px 以上；当前取舍是 Empty 态放地板前方。若用户不接受，可换成把 Cookbook 标签做成贴在书上的小贴纸，再把三灶卡全部改为上方 callout。
4. **FISH-1 两名邻居无昵称**：规格写"远处两名其他玩家（头顶昵称）"，底图故意未画文字，本轮 UI 层也未加（任务只列了塘名牌 / 教学标 / 落点圈）。需要时在 pond.html 加两个 `.tag-card.is-small`（建议位置 ≈ 564, 800 与 740, 820）。
5. **FISH-1 落点光圈**是 UI 画的（`.cast-ring`），底图只有波纹；批量出图时 Scene 提示词里可去掉 "glowing cast target ring"，一律交给 UI 层。
6. **Explore 木牌**：UI 木牌比底图空白牌大一圈，正好完全覆盖；木桩 44 px 与底图木桩重合，细看底图木桩略露在 UI 桩之下 ~10 px，整体不违和。
7. 上一阶段遗留：四次生图 API 返回 quality 均为 "low"（请求 "high"），细节与 round9 持平；见 `scenes/REPORT.md`。该报告里提到的 `kitchen.png (v1)` 已改名为 `kitchen-v1.png`，现在的 `kitchen.png` 即 v2。
8. 过程产物：`.playwright-mcp/` 已被 .gitignore 忽略（anchor-*.png / page-*.yml 不入库）；out/ 四张图、ui/ 源文件与本报告是交付物，目前均为未跟踪文件，尚未 git add。

## v2 修订（2026-10-03，用户审阅后：取景 + HUD 重排）

产出（POSIX 绝对路径均在 `/Volumes/ACASIS/projects/sensen-godot/docs/design/ui-anchors-2026-10-03/` 下）：
`out/v2/FARM-1.png` · `out/v2/FISH-1.png` · `out/v2/COOK-1.png`（1080 × 2400）· `out/v2/contact-sheet.png`（1780 × 1360，由新增的 `ui/contact-v2.html` 截得）。
源文件变更：`ui/kit.css`（新增 `.scene-cam` 相机模式；HUD 段整体改为 v2，旧 row2/row3/regen/level-ring/hud-btn 规则删除）、`ui/farm.html` / `ui/pond.html` / `ui/kitchen.html`（body 改 `scene-cam`、HUD 标记重写、标签坐标重定位、guide 线更新）、`ui/contact-v2.html`（新增，指向 out/v2）。
Playwright 过程图：`.playwright-mcp/v2-{farm,pond,kitchen}-r{0,1}.png`、`.playwright-mcp/v2-contact-sheet.png`（未入库）。
快捷栏与 Map / Cast 按钮未改动（`.quickbar` 30, 2076, 1020 × 200，与 v1 §3 完全一致）。

### v2-A. 取景参数（相机模式）

机制：`body.scene-cam` + 三个变量 `--cam-scale`（无单位）/ `--cam-x` / `--cam-y`，`canvas = source × scale + (cam-x, cam-y)`；超出 1080 × 2400 的部分由 `.scene-layer` 裁掉，`--cam-y` 以上仍是按底图顶行采样的色带（HUD 后面）。源图均为 1024 × 1536。

| 页面 | scale | cam-x | cam-y | 可见源区 x | 焦点物 → canvas y | 岛顶 / 岛底 canvas y | 两侧裁切 |
|---|---|---|---|---|---|---|---|
| farm.html | **1.22** | **−127** | **356**（r0 为 380） | 104 – 989 | 角色中心 src 810 → **1344（56 %）**；头 735 → 1253，脚 885 → 1436 | 225 → 631 / 1180 → 1796 | 左：灌木+岩石约 100 src px；右：围栏外岩石约 35 px。农舍（src 108 起）、田右缘（src ≈ 978）、驿站、矿洞、Explore 牌全部完整 |
| pond.html | **1.45** | **−207** | **246**（r0 = r1） | 143 – 888 | 垂钓角色中心 src 790 → **1392（58 %）**；头 690 → 1247，脚 890 → 1537 | 柳树顶 170 → 492 / 基座底 1085 → 1819 | 左右两簇柳树各裁 ~130 src px；水面 450–930 → 898–1595，浮漂 (452, 655) → (448, 1196)，木栈桥完整 |
| kitchen.html | **1.39**（r0 为 1.36） | **−229**（r0 −211） | **280**（r0 350） | 165 – 942 | 无角色：灶台行 src 620 → **1142（47.6 %）**；地板前缘 1000 → 1670 | 墙顶 245 → 621 / 基座底 1140 → 1865 | 左墙裁到窗左框（窗 src 170 完整），右侧立柱裁一半（保温柜右缘 src 936 完整） |

scale 上限由横向关键物决定：farm = 农舍左缘 108 → 田右缘 985（877 src px → scale ≤ 1.23）；kitchen = 窗左缘 168 → 保温柜右缘 936（768 → ≤ 1.40）；pond 关键物（水面+角色+栈桥）只占 165–875，所以能放到 1.45。
三页所有可互动物都落在 HUD 底（≈ 270）与快捷栏顶（2076；pond 的 Cast 按钮顶 1940）之间；角色（farm / pond）落在 55–62 % 区间。

### v2-B. HUD 新布局（三页 getBoundingClientRect 实测，px，三页一致）

| 元素 | x, y | 尺寸 | 内容 / 说明 |
|---|---|---|---|
| `.avatar-btn` | 30, 56 | 112 × 112 圆 | 可点目标 112；外圈 `.skill-ring` r 52 / 描边 8：Farming 绿占右半圈（12→6 点，进度 45 % 示意 F4），Fishing 蓝占左半圈（6→12 点，60 % 示意 F6），底色 8 % 墨灰；未画 Lv 角标（按"可省"） |
| `.avatar-face` | 42, 68 | 88 × 88 圆 | `background: url(../scenes/farm.png)`，`background-size: 805px auto; background-position: -206px -560px` ＝ 以源图头部中心 (318, 768)、直径 ≈ 112 src px 裁取，三页同一份裁剪（变量 `--face-size` / `--face-pos` 可调） |
| `.energy-card` | 154, 56 | 282 × 112，r 32 | 第 1 行 ⚡ 36 + **142**/200（40 px / 800，"/200" 用 ink-2）；`.energy-track` 173, 119 → 240 × 12，三段底色（红 0–10 % / 琥珀 10–25 % / 中性 25–100 %）+ 绿色填充 71 % + 10 % / 25 % 白刻度；第 3 行 "+1 in **2:41**" 22 px |
| `.coins` | 786, 76 | 156 × 72，r 36 | "230" 32 px / 800 + 金币 40 |
| `.inbox-btn` | 954, 64 | 96 × 96 圆 | 铃铛 46；红角标 `.badge` 1015, 63 → 36 × 36，"3" 22 px |
| `.today` | 30, 192 | farm 433 × 64 / pond·kitchen 672 × 64 | "Today · … ▾" 28 px；`flex: 0 1 auto` + 文本 ellipsis，位置芯片永远放得下 |
| `.place` | 740, 192 | 310 × 64 | 📍(i-map) 32 + "Shanghai" 28 px / 800 + "· Home" ink-2；外城时文案改为 "Tokyo · Day Pass 7h 12m" |
| `.creel`（仅 pond） | 30, 272 | 292 × 64 | 与芯片同高同字号（28 px） |

第 1 行 y 48–176（flex 居中，所以 avatar/energy 56–168，coins 76–148，inbox 64–160），第 2 行 y 192–256。删除：Passport 小书按钮、"F4 · F6" 环形胶囊、独立的 "+1 in 2:41" 小胶囊、第 3 行。第 1 行体力卡（→436）与金币（786）之间空 350 px，第 2 行 Today 与位置芯片之间 farm 空 277 px、pond/kitchen 空 38 px。所有卡片无投影、1 px `--card-edge` 描边，Nunito + tabular-nums。

### v2-C. 标签新坐标（`--x / --y`，canvas px；由 v1 坐标反推到源图再按新相机映射，再微调）

farm.html（canvas = src × 1.22 + (−127, 356)）
| 标签 | v1 | v2 | 备注 |
|---|---|---|---|
| Homestead Lv2 | 430 · 1054 · dx −40 | **370 · 1015 · dx −40** | 指尖仍在门右空白门牌上沿（src 408, 540） |
| Sell 12 | 548 · 936 | **507 · 879** | 驿站屋脊 |
| Ready ①②③ | 447·1260 / 882·1350 / 727·1440 | **390·1254 / 893·1358 / 714·1462** | 三块成熟格 |
| Explore 木牌 | 960 · 948（h 58 / 26 px） | **983 · 893**，恢复默认 h 64 / 28 px，padding 0 22 | 底图空白牌在新取景下放大到 ≈ 79 × 61，木牌完全盖住；牌右缘 1058，越出 30 px 边距 8 px |

pond.html（canvas = src × 1.45 + (−207, 246)）
| 标签 | v1 | v2 | 备注 |
|---|---|---|---|
| Willow Pond · Beginner pond | 540 · 660 | **540 · 420**（卡 296–784 × 388–452） | 悬在 Creel（272–336）与柳树顶（492）之间，不压任何物件 |
| Casting uses 5 Energy | pointer 478 · 1174 · dx −60 | **leader 450 · 1170 · lead 96 · dx −60**（卡 223–557 × 1018–1074） | r0 用下指尖时卡片压到栈桥右桩顶并顶到竿尖，改为 96 px 引线悬在水面上，引线落在浮漂正上方 |
| 落点光圈 `.cast-ring` | 480 · 1210 · 176 × 84 | **453 · 1212 · 242 × 115** | 包住底图同心波纹（src 390–520 × 630–700） |

kitchen.html（canvas = src × 1.39 + (−229, 280)）
| 标签 | v1 | v2 | 备注 |
|---|---|---|---|
| Stove 1/3 · Empty | anchor-top 452 · 1222 | **anchor-top 367 · 1274 · dx 0** | 灶 1 正前地板，指尖抵灶体底沿 |
| Stove 2/3 · Cooking 0:22 | leader 578 · 1056 · lead 266 | **leader 533 · 1055 · lead 290 · dx 0** | 引线落锅盖左侧，卡片在墙顶上方 y 701–765 |
| Stove · Ready · Grilled Crucian | leader 740 · 1104 · lead 224 · dx 78 | **leader 746 · 1118 · lead 264 · dx 60** | 引线落盘子左半，卡片 y 790–854 |
| Ready 发光角标 | 786 · 1162 | **807 · 1195** | 盘子前右沿 |
| Warming Cabinet 4/6 | anchor-top 918 · 1262 · dx −70 | **anchor-top 981 · 1326 · dx −128** | 指尖抵柜底，卡片右缘 ≈ 1046 |
| Cookbook | 423 · 866 · dx −20 | **328 · 805 · dx −27** | 指尖抵书顶 |

### v2-D. 没做到 / 取舍

1. **顶部天空仍有 ≈ 350–400 px**（farm：HUD 底 270 → 岛顶 631；pond → 柳树顶 492；kitchen → 墙顶 621）。原因是上面的横向 scale 上限：再放大就要裁农舍左墙 / 田右缘（farm）或窗 / 保温柜（kitchen），违反"裁掉的不能是关键物件"。想让 HUD 后面是草地而不是天空，只能①底图按竖屏构图重出（岛更高更窄，或直接 9:16 / 9:20 出图），或②允许裁掉农舍左墙 / 厨房窗。
2. 厨房底图没有角色，② 的 55–62 % 用灶台行（47.6 %）和地板（1670）代替。
3. **头像是角色后脑勺**：farm.png 里玩家背对镜头，裁出来是棕色卷发 + 右下一点脸颊；三页一致但不算正式头像，正式版需单独的正面立绘，再把 `--face-size / --face-pos` 换掉即可。
4. 外城态位置芯片（"Tokyo · Day Pass 7h 12m"）与头像面板（Passport 入口）本轮按要求未画。
5. Explore 木牌右缘越出 30 px 边距 8 px（为了桩对准底图木桩）。
6. FISH-1 两名邻居仍无昵称（同 v1 已知问题 4）。
7. 过程产物 `.playwright-mcp/` 仍被 .gitignore 忽略；out/v2、ui/contact-v2.html、本节与所有 ui/ 修改目前为未跟踪 / 未暂存。

## v3 控制层（2026-10-03，用户确认新"操作模型"后：摇杆 + 主行动键 + 切换键 + 6 格快捷栏 + 抽屉）

产出（均在 `docs/design/ui-anchors-2026-10-03/` 下，1080 × 2400）：
`out/v3/FARM-1.png` · `out/v3/FISH-1.png` · `out/v3/COOK-1.png` · `out/v3/ACTION-RADIAL.png` · `out/v3/COOK-2a-recipes.png` · `out/v3/COOK-2b-experiment.png` · `out/v3/BAG-1.png`，合成页 `out/v3/contact-sheet.png`（1880 × 2100，上 4 下 3，由新增的 `ui/contact-v3.html` 截得）。
源文件：`ui/kit.css`（`.place` 改版；末尾新增 "v3 control layer" 段）、`ui/icons.svg`（**新增**：三页原来各自内联的 50 个 symbol 抽成一份共享图标表 + 新增 chev-r/close/lock/switch/question/sort/sow/pot/pickaxe/sword/carrot-seeds/carrot/lure/apple/wood/stone/carp/minnow/4 道菜/eat/gift，所有页面用 `<use href="icons.svg#i-…">` 引用）、`ui/farm.html` / `ui/pond.html` / `ui/kitchen.html`（控制层重写，相机参数、HUD 第 1 行、场景标签坐标不变）、新增 `ui/action-radial.html`、`ui/cook-recipes.html`、`ui/cook-experiment.html`、`ui/bag.html`、`ui/contact-v3.html`。
过程图 `.playwright-mcp/v3-*-r0/r1.png`、`v3-final-*.png`（未入库）。底图未重新生成，三页 `--cam-scale/--cam-x/--cam-y` 与 v2 完全一致。

### v3-A. 新组件尺寸（getBoundingClientRect 实测，canvas px）

| 组件 | 位置 / 尺寸 | 说明 |
|---|---|---|
| 位置芯片 `.place` | 右对齐 1050，y 192，高 64；farm 416 宽（634–1050）、pond ≈ 430、kitchen ≈ 362 | 左 🏠 `i-home` 34（家城），`Shanghai · Homestead / Willow Pond / Kitchen` 28 px/800，右端 › `i-chev-r` 26（Map / 城市面板入口）。独立 Map 按钮删除；pond 场景内 "Willow Pond · Beginner pond" 名牌删除 |
| Today 芯片 | 30, 192，高 64，`flex: 0 1 auto` | pond / kitchen 文案改为 `Deliver 4 Fine fish`（原 "… · Shanghai Market" 在新位置芯片旁只剩 ≈ 580 px，会被省略号截断，改短而不是截断） |
| 浮动摇杆 `.joystick`（仅 farm） | 中心 (300, 1600)，外圈 260（170–430 × 1470–1730） | 外圈奶油白 45 % + 1 px 95 % 白描边 + 中心 14 px 淡点；内圈 120 主色 70 %，中心偏移 (+40, −40) 表示正在向右上推。比 brief 的 y 1560 下移 40，避免压住角色脚（脚底 1436） |
| 主行动键 `.fab` | 874, 1876 → 176 × 176 圆（右 30、底 348 = 124 + 200 + 24，即原 Map 位置） | 奶油白实色 + 4 px `--primary-deep` 描边；图标 68 + 标签 30 px/800 + 价格行 20 px/700 ink-2。farm `Sow / 2 Energy`（`i-sow`）· pond `Cast / 5 Energy`（`i-rod`）· kitchen `Cook / Free`（`i-pot`，Free 用主色深） |
| 切换键 `.switch` | 914, 1756 → 96 × 96 圆，与 FAB 同心、间距 24 | 灰底 #E4E0D6 + 1 px `--card-edge-2`，⇄ `i-switch` 50 ink-2；按下态 `.is-on` 主色渐变 + 白图标（ACTION-RADIAL 页） |
| 快捷栏 `.quickbar` | 30, 2076, 1020 × 200（不变）；格 y 2116–2276 | **去掉左端场景芯片**：5 格 + 右端 Bag = 6 × 160（r 32），12 px 间距正好铺满 1020（30 / 202 / 374 / 546 / 718 / 890）。格内：图标 76（top 14，居中）· 物品名 22 px/700 左对齐、底 12、≤ 2 行（有数量时右侧留 52）· 数量 `×N` 胶囊 32 高、右下 (8, 8)。**不再显示体力价**。选中态上抬 12 px（y 2104）+ 3 px 主色描边；幽灵格仅虚线框 + 28 % 灰剪影（无文字） |
| 锁定格 | pond 第 4 格 Fish Trap | 灰底 `--disabled-bg` + 整格 78 % + 图标去色，右下 🔒 `i-lock` 22 + `Lv5` 胶囊 |
| Equipped 标 | pond 第 1 格 Starter Rod | 30 高主色胶囊，18 px 白字，悬在格顶边上方 12 px（top −12，right 10） |
| kitchen 底部 | 无快捷栏 | 只剩 FAB（Cook）+ `.bag-fixed` Bag 160 × 160（890, 2116，与其他页 Bag 同位）；"Pick an ingredient" 气泡与 notice 删除；`.bar-veil` 保留 |

### v3-B. ACTION-RADIAL（farm 底图、farm 参数；角色中心 canvas (300, 1344)）

| 项 | 圆心 (x, y) | 极坐标（相对角色） | 状态 / 标签 |
|---|---|---|---|
| Farming `i-field` | (131, 1026) | 118°, r 360 | 选中：4 px 主色描边 + 6 px 28 % 主色外环；标签 `Farming`（2 px 主色描边） |
| Fishing `i-fish` | (338, 986) | 84°, r 360 | 置灰：灰卡 + 图标去色 60 %；标签两行 `Fishing / No water nearby` 灰字；引线虚线 |
| Mining `i-pickaxe` | (548, 1069) | 48°, r 370 | 正常；`Mining / Mine entrance 20 m` |
| Combat `i-sword` | (717, 1240) | 14°, r 430 | 置灰；`Combat / Mine floors 3–5`；引线虚线 |

图标 128 圆（`.radial-item`），标签是图标下方 10 px 的两行胶囊（名 24 px/800 + 状态 20 px/700），引线 4 px 奶油白从角色外 70 px 画到圆外 72 px（`<svg class="radial-lines">` 四条 `<line>`）。半径 / 角度不等距是为了绕开场景物：r 360 的扇形会压到 Homestead 门牌，所以 **radial 打开时场景标签整体隐藏**（`.radial-open .tag { display:none }`）；Combat 放到 14° / r 430 是为了不压第 2、3 块 Ready 田。切换键为按下态，FAB 仍是 `Sow / 2 Energy`，快捷栏与 farm 一致，不画摇杆（radial 是停步状态）。

### v3-C. 抽屉（`.drawer`：底部对齐、顶圆角 48、奶油白 92 % + 1 px 顶边；`.scene-dim` 30 % 墨色压暗场景层，HUD z 5 不压暗；抽屉打开时场景标签隐藏——否则 92 % 的抽屉会透出引线）

COOK-2a / COOK-2b（kitchen 底图、kitchen 参数）：抽屉 1440 高（y 960–2400）
| 行 | y | 内容 |
|---|---|---|
| 顶栏 | 992–1088 | 左 `⊙ Stove 1/3 · Empty` 34 px/800（Empty ink-2）；右 ✕ 96 圆 |
| Tab | 1112–1192 | `Recipes` / `Experiment` 各占一半（flex 1），80 高 r 40，选中主色渐变白字 |
| 配方行 ×4 | 1216–1776，每行 140，1 px 底边 | 左 96 圆底 + 左上 28 px 稀有度点；中 名 30 px/800 + `Common · +20 Energy · 5 s` 24 px ink-2（Fine 用蓝）；右 96 高按钮（≥ 96 可点）+ 下方 22 px 小字：`Cook` / `Pond Crucian ×1 · have 3`（绿）· `Cook` / `Radish ×2 · Rock Salt ×1` · `Need Wild Herb ×1`（灰显）/ `have 0`（红）· `Need Fine fish ×1` / `have 0` |
| 底行 | 1776–1848 | `12 more to discover · try Experiment ›` 24 px ink-2 |
| Experiment：投料槽 | 1236–1396 | 3 × 160 圆，间距 56：Pond Crucian · Wild Herb · 虚线空槽 `+ Add` |
| 锅 | 1420–1740 | 320 圆奶油白 + 左右 72 × 40 把手 + 内沿椭圆 + 112 px `?` |
| 预览条 | 1764–1828 | `? · Fine · 15 s · Unknown dish` 26 px 胶囊 |
| From your bag | 标题 1864；格 1912–2040 | 6 × 128（r 28）等距：Pond Crucian ×3（稀有度点）/ Radish ×12 / Rock Salt ×2 / Wild Herb ×1 / Apple ×2 / Carrot ×4；已投入的两格 3 px 主色描边；格内图标 58 + 名 18 px + 右上 ×N |
| 底部 | 按钮 2148–2260 | `Cook · Free` 主色 600 宽（右）+ 左侧两行小字 `Mystery dishes still / restore 5 Energy` 22 px |

Recipes 页列表下方到安全区仍有 ≈ 450 px 空白（4 行 × 140 是 brief 给定的行高；真实列表会滚动填满）。

BAG-1（farm 底图、farm 参数）：抽屉 1600 高（y 800–2400）
| 行 | y | 内容 |
|---|---|---|
| 快捷栏 | 833–993 | 5 格与 farm 同内容（Radish Seeds 选中上抬）+ 右端 ✕ 160 × 160（代替 Bag） |
| 标题行 | 1017–1081 | `Bag 19/25` 32 px/800（/25 ink-2）+ 12 px 容量条 76 % + 右 `Sort · Recent` 56 高芯片 |
| Tab | 1101–1165 | 64 高紧凑版 24 px：All（选中）/ Seeds / Fish（角标 7）/ Produce / Dishes / Materials / Gear，总宽 917 |
| 详情卡 | 1185–1405（1020 × 220，r 40） | 左 120 圆 + 稀有度点；中 `Grilled Crucian` 32 + `Common dish · +20 Energy` 24 + 斜体 `Simple grilled pond fish. / Tastes like home.` 22；右 `Pin` 96 圆（小）· `Gift` 96 高 2 px 主色描边 · `Eat` 主色 |
| 网格 | 1425–2289（864 × 864，x 108–972） | 5 × 5，160 格 r 32，间距 16。19 格有物：Grilled Crucian ×3（选中：4 px 主色 + 外环）· Pond Crucian ×3 · Pond Carp ×2（蓝点）· Silver Minnow ×2 · Radish Soup ×1 · Radish ×12 · Carrot ×4 · Apple ×2 · Radish Seeds ×24 · Carrot Seeds ×10 · Compost ×6 · Rock Salt ×2 · Wild Herb ×1 · Wood ×20 · Stone ×8 · Worm Bait ×12 · Spinner Lure ×3 · Row Tool · Starter Rod；6 空格浅虚线。鱼 3+2+2 = 7 与 Fish 角标一致 |

### v3-D. 没做到 / 取舍

1. **ACTION-RADIAL 页隐藏了全部场景标签**（Homestead / Sell / Explore / Ready）：以角色为圆心、半径 300–450 的向上扇形必然压到 Homestead 门牌；按"radial 打开 = 短暂模态、场景标签淡出"处理，关闭后恢复。brief 没规定这一点。
2. 三个抽屉页同样隐藏场景标签（引线会透过 92 % 抽屉），只保留压暗的场景。
3. pond / kitchen 的 Today 文案缩短为 `Deliver 4 Fine fish`（见 v3-A），不是 brief 原文 "Deliver 4 Fine fish · Shanghai Market"。
4. 摇杆中心 y 1600 而非 1560（避开角色脚）。
5. 快捷栏物品名用 700 字重（kit 其他文字 800）：160 格减去数量胶囊后名字只剩 ≈ 96 px，800 字重下 "Compost" 会被裁掉最后一个字母。
6. 置灰项（radial 的 Fishing / Combat、Fish Trap）没有用整体 60 % 透明——在底图上 60 % 透明几乎看不见，改为灰卡 + 图标去色 60 %。
7. Recipes 抽屉下半截空白（见 v3-C）；Experiment 的锅只是圆 + 把手 + 问号的简笔。
8. 外城态位置芯片（护照章 + Day Pass）、FAB 体力不足态（`.sub.is-short` 琥珀色已留在 kit，未出图）本轮未画。
9. `ui/icons.svg` 走外链 `<use>`，需要 http 服务；直接 file:// 打开页面图标不显示（Chromium 同源限制）。
10. out/v3、ui/icons.svg、四个新页面、本节与所有 ui/ 修改目前为未跟踪 / 未暂存。

## v4 工具分离（2026-10-03，用户决定：快捷栏只放"当前行动可消耗的物品"，它只是背包物品的快捷使用栏；工具与功能性饰品进独立的 Tools & Gear 装备界面，角色默认自带四件初级工具；时装另开界面）

产出（均在 `docs/design/ui-anchors-2026-10-03/` 下，1080 × 2400）：
`out/v4/FARM-1.png` · `out/v4/FISH-1.png` · `out/v4/BAG-1.png` · `out/v4/EQUIP-1.png`，合成页 `out/v4/contact-sheet.png`（1880 × 1100，4 张一行各 420 宽 + 编号标题，由新增的 `ui/contact-v4.html` 截得）。
源文件：`ui/kit.css`（末尾新增 "v4 tools split" 段：`.fab .gear-badge`、`.drawer.is-equip`、`.tab.is-off/.later`、`.eq-sec/.eq-grid/.eq-card/.btn-xs`、`.owned/.own-row`、`.eq-foot`）、`ui/icons.svg`（新增 `i-hoe`、`i-feed-bag`、`i-ring`、`i-charm`；`i-pickaxe`/`i-sword` 沿用 v3 radial 的）、`ui/farm.html` / `ui/pond.html` / `ui/bag.html`（仅快捷栏 + FAB 改动，相机参数、HUD、场景标签不变）、新增 `ui/equip.html`、`ui/contact-v4.html`。
过程图 `.playwright-mcp/v4-{farm,pond,bag,equip}-r0.png`、`v4-contact-sheet.png`（未入库）。四页一轮出图即过，没有 r1。

### v4-A. 快捷栏 / 主行动键改动（getBoundingClientRect 实测，canvas px；格位不变：30 / 202 / 374 / 546 / 718，y 2116–2276，选中格上抬到 2104）

| 页 | 快捷栏 5 格（左 → 右） | 主行动键 `.fab`（874, 1876，176 圆） | 其他 |
|---|---|---|---|
| farm.html / bag.html | Radish Seeds ×24（选中）· Carrot Seeds ×10 · Compost ×6 · **Orchard Feed ×2**（新图标 `i-feed-bag`，小肥料袋）· 幽灵格 | `Sow ×1` / `2 Energy`（×1 = 初级锄每次 1 格） | **Row Tool 格删除**；bag 网格里原 Row Tool / Starter Rod 两格换成 Orchard Feed ×2 / Fish Trap ×1，仍 19/25；Tab `Gear` 改名 `Tackle`（847–966，总宽仍 < 1020） |
| pond.html | Worm Bait ×12（选中）· Spinner Lure ×3 · **Fish Trap ×1**（可投放物，正常显示，不再 🔒 Lv5）· 幽灵 · 幽灵（蚯蚓 / 拟饵剪影） | 图标 `i-rod`，`Cast` / `5 Energy`；**左上角 `.gear-badge`**：56 圆（870, 1872 → FAB 左上 −8/−8），奶油白实色 + 2 px `--primary-deep` 描边 + 34 px 竿图标，表示当前鱼竿来自 Tools & Gear | **Starter Rod 格 + Equipped 标删除**；`.quickbar` 加 `has-selection`（未选中格 85 % 亮度） |

### v4-B. EQUIP-1（`ui/equip.html`：farm 底图 + farm 相机参数，`.scene-dim` 30 % 压暗，HUD 不压暗，场景标签隐藏）

抽屉 `.drawer.is-equip`：(0, 720) 1080 × 1680（70 %），顶圆角 48，奶油白 92 % + 1 px 顶边。
| 行 | y（实测） | 内容 |
|---|---|---|
| 顶栏 `.drawer-head` | 753–849 | 左 `Tools & Gear` 34 px/800；右 ✕ 96 圆 |
| Tab | 873–953（80 高 r 40） | `Tools` 选中主色渐变白字；`Outfit` 置灰（`--disabled-bg` + `--disabled-ink`）+ 右侧 `Later` 30 高 18 px 胶囊 |
| `Equipped · one tool per action` | 985（26 px/800 + 22 px ink-2 副标） | |
| 工具槽卡 ×4 `.eq-card` | (30, 1035) (570, 1035) (30, 1255) (570, 1255)，各 480 × 200 r 40，行距 20，列间距 60（1020 − 2 × 480） | 左 120 圆底 #F1EADA（20, 40）+ 76 图标；右侧文字从 x 160 起：行动名 20 px/800（按行动着色：Farming `--primary-deep` · Fishing `--rar-fine` · Mining `--wood-deep` · Combat `--energy-red`）· 物品名 28 px/800 · 效果 20 px/700 ink-2；右下 `Change` 52 高 2 px 主色描边胶囊（右 16 底 16）。内容：Starter Hoe `i-hoe` / Sows 1 plot per action · Starter Rod `i-rod` / Bite window 2.2 s · Starter Pickaxe `i-pickaxe` / 1 rock per swing · Wooden Sword `i-sword` / Attack 3。效果行最长 "Sows 1 plot per action" 实测未溢出（298 / 298） |
| `Accessories` | 1487 | |
| 饰品槽 ×2 `.eq-card.is-acc` | (30, 1535) (570, 1535)，480 × 140 | 96 圆底（20, 22）+ 60 图标；Ring 空槽 `.is-empty`：奶油白 50 % + 3 px 虚线 `--card-edge-2`，图标 30 % 去色，`Ring / No ring`（ink-2）；Charm：`i-charm` 四叶草，`Charm / Lucky Charm / +5% Fine fish`，`Change` 垂直居中 |
| `Owned · 3` | 1707 | |
| 列表 ×3 `.own-row` | 1752 / 1872 / 1992，各 120 高，1 px 底边 | 88 圆底 + 56 图标；名 28 px/800 + 22 px meta：Reed Rod · `Bite window 2.6 s · Fishing Lv3 ✓`（✓ `i-check` 主色深）· **[Equip]** 主色 80 高 ≥ 180；Row Hoe（整行灰显：图标去色 55 %、名 `--disabled-ink`）· `Sows 3 plots · needs Farming Lv4` · **[🔒 Farming Lv4]** 灰按钮；Copper Pickaxe · `2 rocks per swing` · **[Equip]** |
| 底注 `.eq-foot` | 2220–2276（底 = safe 100 + 24） | 两行居中 22 px/700 ink-2：`Tools come from Market, Tackle Shop and the mine. / Upgrades and crafting arrive in a later phase.` |

### v4-C. 新图标（`ui/icons.svg`，64 viewBox，圆润无描边 2–3 色，与既有一致）

`i-hoe`（木柄 40° + 深灰颈 + 灰刃，刃带高光）· `i-feed-bag`（米色麻袋 + 深色扎口 + 白标签上一片绿叶）· `i-ring`（金环 evenodd 双色 + 高光 + 蓝宝石两面）· `i-charm`（金环挂扣 + 四叶草双绿 + 茎）。`i-pickaxe` / `i-sword` 已在 v3 为 radial 画过，直接复用。

### v4-D. 没做到 / 取舍

1. **farm 的 FAB 没加工具徽章**（brief 只要求 pond 加鱼竿徽章）。按同一逻辑 Sow 键左上也该挂一个锄头徽章，建议下轮补齐保持一致。
2. bag 页两处 brief 没要求的改动：网格里 Row Tool / Starter Rod 两格换成 Orchard Feed ×2 / Fish Trap ×1（工具已出背包，且让快捷栏物品在背包里都找得到，总数仍 19/25）；Tab `Gear` 改名 `Tackle`（避免与 Tools & Gear 混淆）。两处都可回退。
3. Equipped 2 × 2 卡按 brief 保持 480 宽，因此列间距是 60（不是常用的 20/24）；卡外沿与 30 / 1050 边距对齐。
4. Ring 空槽只有虚线 + `No ring`，没有按钮（没有可装备的戒指，放 `Equip` 会误导）。
5. Owned 行给 Reed Rod 补了 `Bite window 2.6 s`、Row Hoe 补了 `needs Farming Lv4` 小字——brief 只给了名字 + 条件，补效果是为了行与 Equipped 卡信息对齐。
6. Outfit 只是置灰 Tab + Later，没有画时装页；新手引导逐槽解锁未画（本切片全解锁）。
7. kit 里 v3 的 `.slot .eq`（Equipped 标）与 `.slot.is-locked` 样式保留但本轮没有页面再用到。
8. `i-hoe` 在 76 px 下刃与柄的连接处略松（看得出是锄，但不如 `i-rod` 利落）；如果要上真图标应重画。
9. `ui/icons.svg` 仍走外链 `<use>`，需要 http 服务；file:// 打开图标不显示。
10. out/v4、ui/equip.html、ui/contact-v4.html、本节与所有 ui/ 修改目前为未跟踪 / 未暂存。

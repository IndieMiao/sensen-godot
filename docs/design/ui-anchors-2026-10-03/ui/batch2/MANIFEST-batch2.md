# 批次 2 · 内容与成长（2026-10-05）

页面由 `_gen.py` 生成（`python3 _gen.py [skill1 skill2 fish6 pass3 hud2 bag2 bag5 mine1 home2 farm4 farm5]`）；样式 `../kit-b2.css`（前缀 `.b2-`）+ `../kit-need.css`（材料进度格）；图标补在 `../icons-home.svg`。截图：`python3 -m http.server 8765`（在 ui-anchors-2026-10-03 下）+ `/tmp/shot.sh batch2 <ID>`（headless Chrome 1080 × 2400）→ `out/batch2/<ID>.png`；总览 `ui/contact-batch2.html` → `out/batch2/contact-batch2.png`。

| 页 | 底图 / 相机 | 要点 |
|---|---|---|
| HOME-1 | farm.png 1.22 / −60 / −150 | 农场等级面板；材料进度格（p(5) 起点）；抽屉按内容高度 |
| HOME-2 | **farm-lv3.png**（新）1.15 / −48 / 321 | 升级时刻：扬尘 / 星点 + 横幅 + 三枚后果胶囊；体力 220/220 Full；Bag 闪一次 |
| SKILL-1 | farm.png 压暗 | 三张轨卡（等级环）；Farming 展开 Lv1–10；First times 三枚 M 号格（收集用绿环）；Farming 改 412/500（原稿 212 与阈值矛盾） |
| SKILL-2 | FARM-6 v3 为底 | 锁定行浮起 + 下方门禁卡（XP 32/50 进度格 + Lv2 unlocks + Show my plots / Got it） |
| FISH-6 | farm.png 压暗 | 6 列四段；未钓 = 剪影 + 在哪 / 何时；Legendary 等级锁；顶部 Kinds 9/20 |
| PASS-3 | farm.png 压暗 | 2 × 2 四卡，各一枚 L 号格 + 下一个奖励 |
| HUD-2 | farm.png 常态 | 体力下拉：Max 200 + 四枚 S 号用量格（Meals 100/300 祝福期上限）+ 新手祝福条 |
| BAG-2 / BAG-2-2 | farm.png 压暗 | Tackle Tab（Equipped / Equip）；Materials Tab（仓库堆房子角标 + Take 10 / Take all） |
| BAG-5 / BAG-5-2 | farm.png | 满包琥珀；Keep which? |
| MINE-1 | **mine-floor1.png**（新）1.15 / −48 / 361 | 六块岩石、楼梯灰牌、电梯、脚前高亮；Torch ×8；Mine · 2 Energy；Run 1/2 today |
| FARM-4 | **farm-orchard.png**（新）1.15 / −48 / 361 | 苹果 Ready / 柑橘 First fruit in 31h / 葡萄 Regrow 22h / Orchard 3/5；Pick · 2 Energy（树不响应点击） |
| FARM-5 | **farm-facilities.png**（新）1.0 / 28 / 75 | 工作台抽屉三张蓝图卡（M 号格 + 缺口写在按钮上）；放置预览未出（新底图那块田已有洒水器） |

收集类进度（图鉴、First times）与今日用量（HUD-2）用绿环部分填充；琥珀只用于"需要但不够"。

## 10-05 下午修订（用户审 Figma Section 06，改动清单 p(6)–p(9)）

生成：`python3 _gen_rev.py [farm6 skill2 profile1 profile2 bag2 soc4 bag5b]`（**在 `_gen.py` 之后跑**——`_gen.py` 的 bag2 / bag5 / pass3 是旧稿）；样式 `../kit-profile.css`（前缀 `.pf-` / `.gr-` / `.ib-`）；图标 `../icons-profile.svg`（cog / hanger / parcel / copy / people / medal / pencil / flag / plaque）。

| 页 | 底图 | 要点 |
|---|---|---|
| FARM-6 / FARM-6-2（batch1） | **homestead-stall-v2.png**（新，无人值守：诚实箱 + 小铃） | p(6)：去掉掌柜栏，标题 `Homestead Stall`；`_gen_rev.farm6()` 原地改 batch1 页 |
| SKILL-2 | 同上 | 由新 FARM-6 派生；浮起行 top 600 / 门禁卡 748（环境变量 LIFT 可调） |
| PROFILE-1 | **profile-avatar.png**（新）1.05 / 2 / 79 | p(7)：全屏个人页，图上部角色立绘、880 起奶油底板 |
| PROFILE-2 | **profile-avatar-mia.png**（新） | 他人页：Visit farm / Send a gift / Following + 密友进度一行 |
| BAG-2 | farm.png 压暗 | p(8)：背包抽屉 `Bag | Gear`，六槽 + 当前槽列表；无 Outfit |
| BAG-5-2 | farm.png | p(9)：满包奖励直接进包裹——铃铛下飘条 + 信箱 `Parcel` 小牌；Keep which? 删除 |
| SOC-4 | farm.png 压暗 | p(9)：收件箱 To do / Parcels / Updates，Parcels 页 |

作废：PASS-3（并入 PROFILE-1）、EQUIP-1（并入 BAG-2）、NPC-G1-5（驿站无人值守）——页面与截图已删，Figma 卡已删 / 改名。

# 操作模型定稿（2026-10-03，用户逐条确认；写回 v2 文档时以本文为准）

## A. 位移与相机
- 位移 = 浮动虚拟摇杆：在场景区（HUD 下沿到底部 UI 上沿之间）任意处按下即在按下点出现摇杆（外圈 260 px、内圈 120 px，半透明），左手拇指操作；抬手消失。
- 相机 = 安全框跟随：屏幕中部有一个不可见的安全框（约宽 40%、高 45%），角色在框内移动时相机不动，碰到框边才平移；角色停下后相机在 0.6 s 内缓动回中。双指缩放保留，范围从"整座岛加一圈边"到"约 3 格田宽"；双击回中到角色。初始取景 = 把"角色 + 当前场景的可互动集合"框进中间 60% 高度。
- 取消 v2 原来的"单指拖动平移相机"与"手指划过一行格子连播"。
- 岛/房间可以小，但必须留可走动的路和空地；默认视角必须同时看到角色与可互动物。

## B. 行动与主行动键
- 四种"行动"：Farming / Fishing / Mining / Combat。行动是消耗体力、用工具做的事；烹饪、商店、对话、布置是"设施交互"，不是行动。
- 右下主行动键（176 px 圆）显示当前行动图标 + 动词 + 体力价：`Sow ×1 · 2 Energy`（Row Hoe 时 `Sow ×3 · 6 Energy`）/ `Cast · 5 Energy` / `Mine · 2 Energy`（进矿另收 10/局）/ `Attack`（0 体力）；靠近设施时变为设施动词：`Cook`、`Talk`、`Shop`、`Sell`、`Rest`（0 体力写 `Free`）。按下执行一次；Farming 可按住连续执行（边走边播）。主行动键左上角 56 px 小徽标显示当前装备的工具。
- 切换键（96 px，主行动键正上方）：按下从角色扇出四个行动的径向菜单；进入明确场景时自动预选对应行动（进水边 → Fishing），此处做不了的行动置灰并写原因（`Fishing · No water nearby`、`Combat · Mine floors 3–5`）。径向打开时场景标签淡出。
- 设施交互两种触发都保留：走近按主行动键，或直接点设施自动走过去。
- 体力不足：主行动键变琥珀并写 `Sow ×1 · Need 2 Energy`，按下弹"四件事卡"（要什么 / 有什么 / 差多少与多久 / 现在能做什么），不再有"按格裁剪 cell_ids"的批量逻辑。

## C. 快捷栏（Quick Bar）
- 只放**当前行动的可消耗品**：Farming = 种子、肥料；Fishing = 鱼饵、亮片、鱼笼（可投放物）；Mining = 火把、炸药等；Combat = 药水等消耗品。工具（锄/铲、鱼竿、镐、武器）不占格。
- 固定 5 格 + 右端 Bag（6 个 160×160 圆角 32，等距铺满），不随农场等级变化；格内只写图标 + 物品名 + 数量，不写体力价（体力价在主行动键上）；选中格上抬 12 px 主色描边；空格为浅虚线幽灵格，点它打开背包对应 Tab。
- 未选行动时快捷栏收起成一个把手；选了行动后展开并按该行动的候选表自动填充（已选中 → 上次用过 → 数量最多 → 最近获得）；长按可钉住（每个行动各记各的）；拖格互换；上滑整条打开背包。
- 厨房等纯设施空间没有快捷栏，只有 Bag 按钮与主行动键。

## D. 背包抽屉（Bag）
- 底部升起到约 y=800（高 1600）；抽屉第一行就是快捷栏（5 格 + ✕ 关闭）；第二行 `Bag 19/25` + 容量条 + `Sort · Recent / Value / Name`；第三行 Tab：All / Seeds / Fish / Produce / Dishes / Materials / Tackle（Tackle 显示工具与渔具但**不计容量**，Equip 跳 Tools & Gear）。
- 5 列网格；容量 25，扩容三档各 +5 → 30 / 35 / 40（挂 Homestead Lv3 / 6 / 9，金币 150 / 400 / 1,000 + 材料），每档正好加一行。
- 点格 = 详情卡（Tab 行与网格之间浮出：大图标、名字、稀有度/效果、一句描述、按钮 Eat / Gift / Sell / Equip / Pin 按物品类型出现）；长按 = 快速钉住；拖到快捷栏 = 替换该格；点空白处关闭。
- 鱼篓 Creel 仍 = 背包空格数（HUD 下角标 `Creel 7 · 6 free`）；堆叠鱼 10 / 料理 5 / 作物 50 / 材料 99 不变。

## E. 工具与装备（Tools & Gear）
- 入口：头像面板 → Tools & Gear；背包 Tackle 页的 Equip。
- 两个 Tab：Tools（本阶段）/ Outfit（置灰 Later；时装走 Avatar 换装系统，抽卡/付费，本轮不做）。
- Equipped：四个工具槽一行动一槽：Farming 锄（Starter Hoe · Sows 1 plot per action → Row Hoe · Sows 3 plots，Farming Lv4，集市 240 金币）、Fishing 鱼竿（Starter Rod → Reed Rod Lv3 80 金币 → Carbon Rod Lv6 350 金币，修正沿用第 6 章）、Mining 镐（Starter Pickaxe · 1 rock per swing → Copper Pickaxe · 2 rocks per swing）、Combat 武器（Wooden Sword · Attack 3 → 沿用矿洞装备表）；Accessories 两槽 Ring / Charm（功能性饰品，如 Lucky Charm · +5% Fine fish）。角色默认自带四件初级工具；新手引导逐槽解锁留以后，本切片全解锁。
- 工具来源：集市 / 渔具店购买、矿洞掉落；升级与合成为 P3 预留。装备不占背包容量。
- 原 v2 的"Row Tool 行工具（快捷栏道具）"全部改为"Row Hoe 锄等级"；"体力按格、工具只省时间不省体力"不变：Sow ×3 一次扣 3 格的体力。

## F. 顶栏 HUD
- 第 1 行：左头像按钮 112 px（外圈双色技能环：Farming 绿半圈 / Fishing 蓝半圈；点开个人面板：Skills / Passport / Inbox / Tools & Gear / Settings）；头像右紧贴体力卡（⚡ `142/200` 40 px 粗体 + 240×12 三段色条 + `+1 in 2:41` 22 px）；右侧金币胶囊 `230` + Inbox 圆钮 96 px（铃铛 + 红角标）。删除 Passport 小书按钮与 `F4 · F6` 文字环。
- 第 2 行：左 Today 芯片（`Today · Radishes ready in 1h 12m ▾`）；右位置芯片 = **城市 · 空间**（`Shanghai · Homestead` / `Shanghai · Willow Pond` / `Shanghai · Kitchen`，家城带小房子图标，右端 › ），点它进地图（Map 按钮删除）；外城时写 `Tokyo · Sumida Pond · Day Pass 7h`。
- 钓点页第 2 行下方左侧 `Creel 7 · 6 free`。场景内不再放塘名牌。
- 所有可点目标 ≥ 96 px。

## G. 烹饪入口
- 厨房无快捷栏；走近灶台按主行动键 `Cook`（或点灶台）打开烹饪面板（60% 高抽屉）：顶栏 `Stove 1/3 · Empty` + ✕；两个 Tab：`Recipes`（已知配方列表，材料够的一键 Cook，不够的按钮写 `Need Wild Herb ×1`；列表底 `12 more to discover · try Experiment`）/ `Experiment`（三槽自由投料 + 预览 `? · Fine · 15 s · Unknown dish` + `From your bag` 食材行 + `Cook · Free`；黑暗料理回 5 体力）。火候点按、5–60 s 灶时、图鉴稀有度规则不变。

## H. 服务端规则随之简化
- 播种：每格一条命令（Row Hoe 一条命令 3 格），服务端按格校验体力、不足整条拒绝；删除 v2 第 3 章"一次提交最多 64 格、客户端按剩余体力裁剪 cell_ids"的描述。
- 行动模式只是客户端状态，服务端只校验"该动作在该位置是否合法"（如 Cast 需在渔场范围内）。

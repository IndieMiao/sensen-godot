# Avatar 换装：沿用旧布局的复原依据

用户本轮明确要求：上半角色试穿预览，下半分类与部件网格，选择后要看到真实效果。以既有运行实现与已保存真机证据为依据，不把新补稿的衣架占位当成既有换装系统。

## 既有权威来源

| 来源 | 已确认内容 |
|---|---|
| `scenes/dressing_room/dressing_room.tscn` | 顶栏 Back / Dressing / Reset / Done；中部 `RigAnchor + Camera3D`；底部 Drawer / TabsScroll / PartsGrid。PartsGrid 是 **3 列**。 |
| `scenes/dressing_room/parts_panel.gd` | 分类是 Hair、Outfits、Shoes、Bags、Glasses，对应 hairHat、cloth、shoes、messengerBag、glass。只有可选择的槽位出现；真实缩略图位于格子上方，名称在下方。点击即装配编辑中的 rig。 |
| `scenes/dressing_room/dressing_room.gd` | `_on_back()` 不保存草稿；`_on_done()` 等 rig 装配结束后调用 `Avatar.save_outfit`，成功返回原页；加载、试穿、保存中有独立按钮状态。拖角色转身，点角色切换全身／当前分类取景。 |
| `scenes/dressing_room/dressing_camera.gd` | 固定参考盒保证换高发型不使角色忽大忽小；切分类才推近头部、躯干、鞋子。 |
| `tests/scenes/test_dressing_room_layout.gd` | 底部抽屉不超过屏高 44%；Done 只在右上；3 列网格；不重复显示 Selected 行。 |
| [旧真机已保存外观](../farm-ui-2026-09-05/qa/vivo/dressing-outfit-save-final.png) | `../farm-ui-2026-09-05/qa/vivo/dressing-outfit-save-final.png`：Blonde Bob、Navy Utility、Gray Sneakers，上半大角色，下半 3×2 Hair 网格。 |
| [旧真机取消前草稿](../farm-ui-2026-09-05/qa/vivo/dressing-outfit-cancel-draft-final.png) | 改成 Silver Crop 后，角色与格子选中态同步变化；其它衣服、鞋子保持一致。 |

主方案 §0.3 / §17 明确 Avatar 是沿用系统，§16 的 KEEP-1 又写了 Hair/Top/Bottom/Shoes/Hat 与 5 列，这是与当前已运行槽位和真机布局不一致的旧描述。本轮用户的新指令要求保持以前布局，因此采用现有 **五分类、三列格**；不擅自拆分 cloth 为 Top/Bottom，也不把 hairHat 拆成两套独立部件。

## KEEP-P0-1 / KEEP-P0-2 原补稿偏差

`../p0-flow-2026-10-05/qa/wardrobe-final.png` 虽保留上下分区，但上半是统一 AI 农夫图片，不是既有 Avatar 模型。下半只有 Blue/Green/Cream/Rose/Brown 五个相同衣架图标，没有真实部件；分类不对应实际槽位。KEEP-P0-2 继续用同一张人物图，无法证明选择、保存后的外观一致。当前通用列表式重构进一步丢掉了衣柜的预览／网格结构，不能作为最终换装页。

## 真实资产与渲染证据

`assets/avatar/parts_manifest.json` 共 29 个部件：2 个固定基础件（body/eyes）与 **27 个可选外观件**（Hair 6、Outfits 6、Shoes 6、Bags 4、Glasses 5）。Bags / Glasses 另有卸下选项。`assets/avatar/demo_denylist.json` 当前为空。

`assets/avatar/thumbs/` 的原 PNG 是灰色占位，不能使用。既有 `modules/avatar/thumbs/part_thumbnailer.gd` 已明确说明该问题，并在运行时离屏渲染真实 Mesh/PackedScene。本轮在隔离临时 Godot 工程复用这个渲染器与 AvatarRig，输出：

- `avatar-assets/thumbs/`：27 张真实部件缩略图，160×160。
- `avatar-assets/previews/`：27 张逐件试穿的完整角色 + base + defaults，共 29 张，480×560、透明背景。
- `avatar-assets/render-records.json`：每张图实际使用的槽位配置。
- `avatar-assets/manifest.json`：规范 ID、显示名称、来源路径、尺寸与 SHA-256。
- `avatar-assets/render_avatar.gd` / `render-project.godot`：可审阅的导出脚本与隔离配置。

基准为 `hairhat43 + cloth28 + shoes0`，包和眼镜为空。每个试穿图只替换一个对应槽位，镜头和静止姿势相同。已目视核对基准、Reset 默认整套、Silver Crop、最高的 Playful Hood、Blue Overalls、Explorer Kit、Lime Frames 与 Cream Suit 缩略图；角色完整落在画面中，效果确实变化。

隔离项目仅加载 Avatar 服务，不加载 Net / Voice / AppRouter，不运行主游戏，不读取或保存玩家装扮。Reset 的额外导出使用同一脚本的 `--defaults-only`，读取原 `slot_table.default_config()`（hairhat0 / cloth0 / shoes0），不把“恢复默认”偷换为当前基准外观。脚本使用 `default_config()`、`apply_config()`，没有 `load_outfit()` / `save_outfit()`。ADB 使用独立 5069 端口。子代理本地窗口启动 exit 134 后由主代理在其已授权环境运行，日志以 `AVATAR_RENDER_COMPLETE 28` 结束。

## 原生 Figma 复原方案

独立扩展文件：`figma-plugin/avatar-fixes.js`，应放在现有 current/legacy 扩展之后。其输入是 `BUNDLE.avatarAssets`，来自 `avatar-assets/figma-payload.json`；云端建议先把真实 PNG 上传为 Figma image hash，再将 `images[key].bytes` 替换为 `images[key].hash`，避免重复大图数据。

- 360×800 原生页面：顶栏 Back / Dressing / Reset / Done；上半角色预览；下半五分类与三列真实缩略图。
- 27 个实际部件 + 两个卸下选项，29 个单件／卸下变体，另加 1 个 Reset 默认整套变体（共 30 个）。点击格子使用 `CHANGE_TO` 同时切换真实角色图与选中边框；跳过当前变体的 self reaction。
- 每种真实选中示例都有对应保存结果 Frame，**Done 不会统一跳到默认外观**。再次 Edit look 回到该图对应的选中变体；Back 使用 Figma BACK，返回进入衣柜时的 Profile 并丢弃草稿，不跳到“保存成功”。base Profile 不显示 Look saved。
- KEEP-P0-1 以已保存的 Blonde Bob 基准进入；KEEP-P0-2 展示 Silver Crop 已保存示例。额外保存／再次编辑结果在独立审阅区，以准确 Frame ID 连线。
- 部件缩略图是共享资产组件；Avatar Part Tile 是统一主组件（Thumbnail INSTANCE_SWAP、Name TEXT、Default/Selected 变体），No bag/No glasses 使用原 none.svg；分类使用从原版图标和选中下划线整理出的 Avatar Category 共享变体；Back 使用原版 20px 箭头和 44px 触区。标题、分类、网格、按钮均为原生文本与控件。没有完整 UI 截图铺底。
- 使用当前 Gensen token、Nunito 与已有 Command / Navigation 组件；不增加 Outfit 到 Bag/Gear。

Figma 的单件变体是有真实渲染依据的**单件试穿分镜**，不是任意跨分类组合的实时 3D 引擎。分类按钮进入各自基准试穿样例；自由多槽组合、拖转、分类推近继续由既有 Godot 实现负责。这个边界只写在组件说明和画外交接，不放入玩家界面。不得把有限 Figma 变体声称为整个衣柜运行实现。

## 当前执行与验收记录

主代理已在 Figma 写入全部 57 张实际图片、27 个缩略图资产、30 个 wardrobe 变体、29 个保存 Profile 和 29 个再次编辑 continuation，并填充正式 `PROFILE-1-P0`（482:310）、`KEEP-P0-1`（482:312）、`KEEP-P0-2`（482:314）。记录见 `cloud/avatar/state.json`；该状态有 387 条已连线记录。Profile→再次编辑明确重置交互组件，避免取消后重开仍显示未保存草稿。

已实际查看三个正式页面截图。换装的角色大小与抽屉顶部 474/800 跟旧真机归一化比例一致，真实部件、选中边框和字符均清楚。随后针对用户要求的精细度修复了返回箭头及分类图标/下划线；30 个主件的定点脚本已执行，回执确认 355 条现有反应未改变，最新换装截图已目视通过。原人物、抽屉位置、三列格与页面 ID 均保留。

Profile 精修脚本另将重复的 Profile 状态与泛说明收起，三个技能整理为同一行，将 My farm / Collections 的身份和进度并为两条紧凑信息行；31 个 Profile 已定点执行；对应 `avatar-polish-fixes.js`，所有保存页继续携带完整 Profile 内容与原返回目标。现有 Details 实例已移至顶栏右侧，消除原滚动边界的半行残留，节点及 overlay 反应不变。`cloud/avatar/polish-state.json` 保存独立精修回执，不混入图片上传/变体构建的账本。

静态离线审阅器已专门还原换装上下结构，使用真实 PNG 与原分类 SVG。保存、取消后重开、Reset、取消 Reset、保存 Reset、完整 Profile 内容的本地状态检查通过。标准插件已将 Avatar 资产、专属 renderer、精修扩展及四张独立流程补态整合；288 张主卡构建通过，未改动原 Prototype。上述本地检查使用 mock DOM / Plugin API，**不等于浏览器或 Figma 真实点击验收**。

最后的真实连线回读使用 `cloud/avatar/verify-interactions.js`，校验全部 387 条记录、保存后同一外观、Back、分类切换及再次编辑的 reset。该脚本已由主代理实际执行：386 条有效连线、1 条合法 self skip、31 个再次编辑 reset，错误 0。31 个 Profile 精修及 Details 搬移分别确认全部 93 条原反应保留。最终三张云端截图已逐张目视通过，保存在 `cloud/avatar/{profile,dressing,saved}-polished.png`，并合成自含三联对照 `cloud/avatar/avatar-final-review.svg`。这证明节点、连线与静态视觉结果，不冒充浏览器中的真实点击测试。

`SAVE-RETRY`（482:320）现复用已验收 Silver Crop 主件 602:37618，仅新增一个实例与可隐藏错误面板。Close / Keep editing 只隐藏面板，实际两态截图确认仍是同一草稿实例 805:77457、同一选中发型和完整五分类／三列网格。Retry 指向 Silver 已保存 Profile，Discard 指向原始 Profile。真实回读断言主件未变；该测试未模拟网络请求或宣称浏览器点击。两张实际图与哈希见 `cloud/avatar/recovery-review.json`。

本子代理没有直接写入 Figma；写入由主代理执行，子代理负责真实素材、源码、局部审计及截图验收。没有玩家数据读写、后端请求或游戏运行发布。

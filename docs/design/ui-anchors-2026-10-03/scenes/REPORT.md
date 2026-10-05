# 风格锚定 · 场景底图报告（2026-10-03）

> **资料范围（2026-10-05 清理）**：此页保留美术来源、技术或原日期的验证过程；旧界面/布局不是当前验收稿。当前规则和有效稿入口见 [设计索引](../../README.md)。已移除的旧图按清理记录中的固定 Git 版本查阅。

目录：`docs/design/ui-anchors-2026-10-03/scenes/`
用途：FARM-1 / FISH-1 / COOK-1 三张"风格锚定"图的 3D diorama 场景底图。底图不含任何 UI 与文字；HUD / 快捷栏 / 面板 / 标牌文案全部由 HTML UI 层叠加后截图。

## 接口与参数

- 接口：Sensenjoy `POST https://sub.sensenjoy.cn/v1/images/edits`，`model=gpt-image-2`，`quality=high`（请求值），参考图经 `image[]` 传入。
- 调用脚本：`gen_scene.sh`（基于 `la-map-round9-2026-09-23/mockups/call_image_api.sh` 加了尺寸回退 1024x1536 → 1024x1792 → auto，以及对 "No available compatible accounts" 类错误间隔 20 s 最多重试 3 次）。
- 尺寸：全部按 `1024x1536` 请求，**无一次被拒绝，无一次触发重试**（四次调用均首发成功，见各 `*.log`）。
- 注意：四次响应 json 的 `quality` 字段都回报 `"low"`，与请求的 `high` 不一致；疑为中转侧降级，但出图细节与此前 round9 相当，未影响本轮审阅。
- 提示词结构：§16.1.5 STYLE 前缀去掉全部 UI/文字句（"Mobile game UI mockup / Clean readable English UI…"），改为 "No user interface, no text, no labels, no HUD, no buttons… Keep the top 12% and the bottom 24% of the frame as calm, uncluttered pastel backdrop…"，并加一句"参考图只定义风格/相机/材质/配色，忽略其中任何界面与文字"；再接 "Scene: …"（§16.4 对应行实体物件，去掉 HUD / quick bar / badge / button / sign text）；末尾 "Avoid: …" = §16.1.5 NEGATIVE + "text, letters, numbers, UI panels, buttons, icons, watermark"。各图最终提示词见 `<name>.prompt.txt`。
- 参考图预处理：`pond-reference-2026-09-29/reference.png` 左上有 "Gensen Fishing Gameplay : Grassland & Pond" 白字，为防文字渗入，用 ffmpeg 裁掉顶部 180 px → `refs/pond-ref-cropped.png`（1410×744，无文字）。

## 产出一览

| 编号 | 文件 | 实际像素 | 参考图 | 重试 | 建议 |
|---|---|---|---|---|---|
| FARM-1 | `farm.png` | 1024×1536 | ref3-farm-house-stages.jpg、farm-restyle-mockup-v1.png、ref2-dungeon-rooms.jpg | 0 | 采用 |
| FISH-1 | `pond.png` | 1024×1536 | refs/pond-ref-cropped.png、farm-restyle-mockup-v1.png、ref3-farm-house-stages.jpg | 0 | 采用 |
| COOK-1 v1 | `kitchen.png` | **1145×1374**（接口未遵守请求尺寸） | ref2-dungeon-rooms.jpg、ref3-farm-house-stages.jpg | 0 | 保留备选，不建议叠 UI |
| COOK-1 v2 | `kitchen-v2.png` | 1024×1536 | ref2-dungeon-rooms.jpg、**farm.png（本轮成品，作竖幅与渲染风格锚）**、ref3-farm-house-stages.jpg | 0 | **采用** |

每张图的原始响应 json：`<name>.response.json`（含 b64 图）；调用日志：`<name>.log`。

## 逐图肉眼检查

### FARM-1 · farm.png
- 文字/UI 残留：无。门边木牌与矿洞木牌均为空白木板，无字。
- 顶部/底部留白：基座顶缘约在 15% 处，顶部 12% 为纯渐变；基座底缘约在 77%，底部 23–24% 为纯渐变（奶黄→青绿）。满足叠 HUD 两行 + Today 行与快捷栏的需求。
- 实体清单：奶白墙橙红顶农舍 ✓、门口长椅 ✓、开放式驿站小棚（堆干草）✓、红色信箱 ✓、田格约 6×7–6×8 有苗有红顶萝卜 ✓、2×2 苹果树挂果 ✓、洒水器出水弧 ✓、矿洞入口带矿车轨与灯笼 ✓、大头 Avatar 站田边 ✓。多出一只装石头的小筐（矿洞旁），无害。
- 风格：粉彩黏土、圆角大倒角、左上柔光、短接触阴影、无描边，基座石缘可见；相机近正交约 45° 俯角，与 ref3 / farm-restyle-mockup 的草地与房屋配色一致。贴近参考。

### FISH-1 · pond.png
- 文字/UI 残留：无。两名小玩家头顶无名字。
- 顶部/底部留白：柳树冠顶约在 11% 处，刚好贴到 12% 边界（HUD 卡为不透明奶白卡，可压住）；基座底缘约在 71%，底部约 29% 为纯渐变（青绿→粉橙）。
- 实体清单：三棵垂柳 ✓、半透明软胶粉蓝水面带深度渐变 ✓、浮漂处同心波纹 ✓、荷叶与一朵粉莲 ✓、岸石与草丛 ✓、持竿大头 Avatar ✓、远岸两名小玩家 ✓（一坐一立）。多出一座小木栈桥，无害。
- 偏差：提示词要的"水面落点光圈"只以同心波纹呈现，没有明显发光环；落点光圈本身属于点击反馈，建议由 UI 层在浮漂位置叠一个半透明圆环，不再为此重出图。
- 风格：与 pond-reference 的水色与岸石高度接近，整体贴近参考。

### COOK-1 · kitchen.png（v1）与 kitchen-v2.png（v2）
- v1 问题：接口返回 1145×1374（纵横比 0.83，不是 0.67），与另两张不同幅面，无法共用同一套 HTML 叠层尺寸；墙上出现两本挂书且封面有刀叉浮雕符号（接近"图标"）；三口灶的灶膛全部有火，无法区分"空 / 烹饪中 / 已完成"；多出餐桌与两张凳子，地面偏挤。文字残留：无；三块空白木牌：有。
- v2 修正：加入 farm.png 作第二张参考（竖幅 + 同一渲染风格），提示词明确"只有第二口灶有火光，第一口冷灶黑口，第三口无火只有盘子发光；恰好一本素封面挂书；不要餐桌与多余家具"。结果 1024×1536 ✓；无文字 ✓；一本红色素封面挂书 ✓；三块空白木牌 ✓；灶 1 黑口无火 ✓、灶 2 陶锅冒蒸汽且唯一有橙光 ✓、灶 3 盛菜盘微发光 ✓；调味架两罐（白盐/绿草）✓；保温柜琥珀光 ✓；窗 ✓；地面开阔 ✓。
- v2 顶部/底部留白：墙顶约在 16% 处，顶部 12% 纯渐变；基座底缘约在 74%，底部约 26% 纯渐变。
- v2 风格：基座石缘 + 草皮边与 farm.png 完全同一语言（室内 diorama 外圈带草皮略显奇特，但三图一致性更重要）。贴近参考。

## 结论

- 三张底图全部成功；farm.png、pond.png、kitchen-v2.png 均为 1024×1536，无文字、无 UI，顶部 ≥12%、底部 ≥23% 为纯渐变背景，可直接叠 HTML UI 层。
- kitchen.png（v1）因幅面不一致仅作备选保留。
- 本轮 0 次尺寸回退、0 次账号重试；4 次调用 total_tokens 分别 3892 / 3946 / 2479 / 4017。

---
2026-10-03 合成阶段备注：`kitchen.png`（v1，1145×1374）已改名为 `kitchen-v1.png`（连同 .log/.prompt.txt/.response.json）；`kitchen-v2.png` 复制为新的 `kitchen.png`，供 `ui/kitchen.html` 引用。合成报告见 `../REPORT.md`。

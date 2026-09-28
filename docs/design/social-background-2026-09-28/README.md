# 登录 / 选城背景：3D 地图风（2026-09-28）

用户要求：背景从游戏风景插画换成更像社交 App 的简洁风格，采用符合项目风格的 3D 地图，可适当抽象。

- 生图：Sensenjoy `gpt-image-2` `/images/edits`，1024×1536，参考图 `ref-gensen-map.png`（Gensen Map 展板，仅取 3D 地图画风）。提示词 = `prompt-common.txt` + 各方案 `variant-*.txt`。密钥只从环境变量 `SENSENJOY_API_KEY` 读取。
- 方案 A（海湾，已采用）→ `assets/ui/backgrounds/map-social.png`；B（河流贯穿城区）、C（漂浮地图方块）留作备选。
- 使用位置：选城页、账号面板。场景切换的加载遮罩仍用原 `assets/ui/game/city-background.png`。

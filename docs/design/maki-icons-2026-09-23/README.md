# POI 改为 maki 图标（2026-09-23）

用户定案：普通 POI 不画建筑，改用简单、有含义的 3D 物件图标（参考 `reference-style.png`）；地标仍用建筑贴图。
- 选型：Mapbox Tilequery 在洛杉矶可玩范围 15×15 网格采样 `poi_label`，得 6227 个 POI；按 filterrank≤3（实际会显示的）计数，剔除 marker（通用）、bridge（桥名）、parking（噪音）后取前 10：park、restaurant、school、religious-christian、fast-food、shop、grocery（含 convenience）、fuel、lodging、cafe。
- 每种 2 张，gpt-image-2 `/images/edits` 以参考图为风格输入；`extract_icons.py` 色键抠图后缩到 256px WebP（底边锚点 y=240），20 张共 247KB。
- 运行时：`CityMapData.icon_key()` 取 maki（同义 maki 走 `ICON_ALIAS`），按名字哈希在 2 张中固定选一；不在表内的 maki 不上图。
- 旧的 103 张建筑 POI 贴图已删除（`assets/map/poi` 34MB→9MB，APK 191MB→172MB）。

## 数量按频次放大（同日第二版）
每种 maki 图标数 = ceil(filterrank<5 采样数 / 10)，最少 2；共 27 种 maki、125 张（`sheet-all.png`），1.5MB。
便利店、披萨、啤酒、酒吧改为各自独立的图标组。
生成：前 108 张走 Sensenjoy `gpt-image-2`；Sensenjoy 上游返回 “No available compatible accounts” 后，余下 17 张走备用渠道 aleeai（`gpt-image-2-pro`，个别 `gpt-image-2.5-flare`，后者直接回透明底），需直连（`--noproxy`）、串行调用。

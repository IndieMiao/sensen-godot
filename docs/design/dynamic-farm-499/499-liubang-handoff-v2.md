# 给刘邦：schema-r4 已对齐的美术参数 v2

上官婉儿 · 499 · 2026-11-18。替代 v1 中待确认的 schema 映射与一格核心退让，素材原始字节不变。

## 直接接入

共享目录：`/Volumes/ACASIS/tmp/art-director/dynamic-farm-499-worktree/docs/design/dynamic-farm-499/`。
使用 `499-art-recipe.json` 的 `dynamic_farm_art_recipe_v2` / `499-v2-schema4`，以及同目录 `499-art-inventory.json`。源码资产固定于 farm-dev `99a853f7c75e917394a3f1f229bce9a82a38235c`；如果你的新基线不同，逐件核 GLB/import SHA 即可，不要求退回旧客户端。

镜头确认 **43° 俯角＋14.5°偏航**。格心与边界换算有半格差异，按 recipe.coordinates；所有几何、遮罩、道具、角色共享整体变换。

## 素材、尺度、枢轴

13 件已选：圆冠 `wild_pz_tree_20/_g`，松 `wild_pz_pine_01/03`，灌木 `wild_pz_bush_05/07`，石 `wild_pz_rock_08/13`、`wild_pz_softrock_10`，花 `wild_pz_flower_20/23`，草 `wild_pz_grass_24`、`wild_pz_foot_leafy`。均在 `res://assets/farm/art/`。

所有件为单个 identity 节点、脚底最小 Y=0、米制；保留源 XZ 原点，不按冠幅重新居中。使用清单的实际 bounds（非格宽估计）和 UID。首轮等比 scale 0.85–1.0、固定 seed 的 yaw 变化；不非等比压扁树冠或把全场缩小。按 FarmArt 的 linear 顶点色共享材质，未引入新贴图/新模型。

## 密度、保护带、碰撞

`walk_reserve.no_solid_decor_runs` 是权威保护集合，包含全 core、核心外侧两格和入口/spawn 路径保护带。首轮这里连无碰撞花草也不放，保持核心空场及保护带清楚；地表草纹不受此限制。禁止重新只画两格近似线来代替 payload 的保护 mask。

实体候选区＝extension 减 protected；tree/shrub/rock 均只在此区域放。第一版碰撞取实际网格 **完整 XZ AABB 的保守盒**（包括冠幅，不冒称精确树干半径），与模型同步旋转/缩放。碰撞占用、视觉完整范围及角色安全间隙均核，不能只判中心点。flower/groundcover 无实体碰撞，也仍限制在非保护 extension。

目标数按 eligible extension 格数分别除以 tree 48、shrub 32、rock 64、flower 16、groundcover 12 后向下取整，再与全场上限 24/32/18/48/64 取小值。是首次布景参数，不是一定要摆满；空间不足直接少放。树簇以圆冠为主，松为点缀；前景低、后缘高，不做一圈等距绿篱。尝试每类最多 512 次，禁止无限搜点。

每个实体放下后或整批完成后，按**实际角色碰撞半径**膨胀占用再验证：spawn、entry、全部核心格与 protected 仍可达，保留其余要求的扩展连通。失败时撤掉造成阻断的候选，不改 zone/权限/保护带、不把堵路树改成穿模来过关。对有洞/多部件样本也同样核。先用保守盒保证正确；若过稀，交实际图后再用实测树干调整，不能自行把半径拍小。

## 阴影、边缘、水与崖

Mobile 沿当前场景太阳设置，树/灌木/石保留 cast_shadow，小花草关闭。Compatibility 沿现有太阳不投实时影的规则，使用已有 `GroundShade` 时须保留树的 caster 标志（其扫描会过滤 cast_shadow=OFF）；不能为了 GLES 省影先把树标志关掉。既有 `MIN_H=2m` 只烘高件，低灌木/石不补额外整场遮罩。

`GroundShade.rect`、采样分块必须由动态场景范围提供，且地面材质接收对应 shade 参数；不得拿旧塘 NEAR 矩形和旧遮罩套新地形。最大长条样本要记录遮罩尺寸、字节及首帧成本，别按扩大 bbox 无限增贴图。组装完成后生成一次，布局版本变化才刷新。该接线未实渲验证前，不能写“阴影通过”。

两区内部第一批不生成水障碍/崖障碍，`geo_hints` 仅追溯/主题提示。视觉水与崖只在 `boundaries.outer` 外的不可达景观带；不侵占 core、extension，不改 outer 内孔洞权限，不自动把住宅地做成有水农场。外圈草地、侧面保持大尺度连续轮廓，拒绝小锯齿/随机三角斑块。无外部水/高差几何时先交完整干地，不因此卡首个 3D 样本。

## 交件检查

提交场景头及 art_version、对应 parcel/seed/schema、core/ext/protected/实体 occupancy、候选接受/拒绝计数、实际实例/三角/遮罩开销。至少包含 328、424、287×23 长条、双面、洞、星号与恢复例，同 seed 重进保持一致。截图用正式镜头含人物，全景＋边缘局部＋原速走动；改场景测帧时，新/改 shader 真机验。技术检查交我，屏幕画面交火舞，数据/生成交周瑜。本批参数不是已完成 3D 或真机验收。

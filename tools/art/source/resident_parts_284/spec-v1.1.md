# 居民新部件：Granny Wu 白发单髻、Ivo 矿工帽和灰短胡（设定与制作规格 v1.1，上官婉儿，2026-10-14；v1.1 加不知火舞审阅：衣服定稿、Ivo 工装裤棕色变体）

来源：Kindred 明信片邮票（q(171)，SGODOT-284）要给每位居民一张游戏渲染头像。不知火舞在 284 定了：
- Granny Wu（Campfire Elder）要白发发髻；
- Ivo（Old Miner）要带头灯的矿工帽和灰色短胡；
- 现有部件库里没有这两样，所以做 NPC 专用部件。

流程照 SGODOT-229 的 NPC 专用部件：上官婉儿出设定 → 不知火舞审 → 刘备做 → 上官婉儿技术检查 → 不知火舞验收 → 用户批准合并。PR 直接进 farm-dev（同 229，因为部件要跑提取管线和测试），交叉审核后裔。

设定页 resident_parts_v1.png（Sensenjoy 生成，参考了游戏内渲染）只用来定造型和配色。**造型和尺寸以现有部件为准。** 画面由不知火舞审，我看不到图。

## 1. hairhat80_npc_granny_wu（hairHat 槽，socket 挂法，NPC 专用）
- **只改贴图，不改几何**，做法同 229 的 Mei / Ama：
  - 复制 `assets/avatar/source/hairhat80_npc_ama/` 为新目录 `hairhat80_npc_granny_wu/`；
  - `SM_hairHat80.fbx` 原样复制，文件名、节点名、层级、变换都不动；
  - 贴图另存一份新文件名，例如 `T_granny_wu_hairHat_D.png`。
- 贴图改法：
  - 黑发改成**银白**：中间调约 #E4E0D8，暗部约 #B9B4AC，保留原有的明暗和发丝层次。用色阶或曲线整体调，不要平涂。
  - 绿玉簪改成**暖红木簪**：约 #A63830，暗部约 #7A2A25。
- 要和 Ama 一眼分得开：Ama 是深棕发（hairhat80_npc_ama），Granny Wu 是银白发加红簪。

## 2. hairhat_npc_ivo（hairHat 槽，socket 挂法，NPC 专用）
- **新几何**：圆顶矿工安全帽，前沿短帽檐，帽子正面中间一个小圆头灯；帽下两侧和后脑露出灰白短发。
- 基础件：从现有通用帽类部件中挑一件帽形最接近、落位正确的 FBX（比如 hairhat20 或 hairhat41 的源文件，以落在头上的位置为准）作底，在 Blender 里改形。
  - 保持 FBX 的轴向、单位、节点名和节点变换和原件一致（这是 SM_ 静态件，网格在骨骼坐标系里）。229 里 hairhat71 就踩过这个坑：重新导出时这些都必须和原件一样；做不到就停下来报告，不要硬凑。
- 配色：
  - 帽子：哑光芥末黄 #C99A3A，暗部 #9E7628；
  - 头灯：外圈黄铜 #9B7B46，灯面暖米白 #F3E6C4。灯面不发光，只是颜色亮一点；
  - 头发：灰白 #B8B3AB，暗部 #8C877F。
- 面数和现有 hairHat 部件相当，不超过其中最多的一件。贴图一张，尺寸和同类件一致。

## 3. mask16_npc_ivo（mask 槽，socket 挂法，NPC 专用）
- 从 `mask16_npc_kai`（Kai 的络腮胡）复制成新目录 `mask16_npc_ivo/`，**修短**：
  - 只留贴着下颌和下巴的一圈短胡，长度约为原来的三分之一，边缘修整齐；
  - 去掉垂下来的长须。
- 节点名、层级、变换不动，只改网格形状。
- 贴图改成灰色：中间调约 #A9A49C，暗部约 #7F7A73，保留层次。
- 要和 Kai 一眼分得开：Kai 是暖白长络腮胡，Ivo 是灰色短胡。

## 4. cloth42_npc_ivo（cloth 槽，mesh 挂法，NPC 专用；成本低才做）
- **只改贴图**，做法同 229 的 cloth11_npc_mei：复制 `assets/avatar/source/cloth42/` 为 `cloth42_npc_ivo/`，FBX 原样复制，贴图另存新文件名。
- 工装裤和上衣改成**暖棕**：中间调约 #7B5B3E，暗部约 #5E4430。扣子、缝线这些小细节保持原来的明暗关系。
- 要是 cloth42 的贴图结构不好改（比如颜色烤在复杂的图案里），就跳过这一件，Ivo 直接穿原版 cloth42，在 PR 里写明。

## 管线（照 assets/avatar/source/README_229.md）
- 新建 `recipes_284.json`，只放这 3 件（做了 cloth42_npc_ivo 就是 4 件），格式照 recipes_229.json。
- 导入 → `extract_parts.gd -- res://assets/avatar/source/recipes_284.json --append`，期望输出“追加完成: 3 部件, 0 错误”（4 件就是 4）。
  - 自查：`git diff assets/avatar/parts_manifest.json` 只在末尾多出 3 条（或 4 条）。
- 这几个 id 都追加进 `assets/avatar/npc_only.json`。
- 测试：tests/catalog、tests/pipeline、tests/assembly/test_socket_placement.gd 全过。mask 槽不在 socket 测试里，用 npc_lineup 渲正面和 3/4 侧核对落位。

## 造型（不知火舞定稿，284）
- Granny Wu：hairhat80_npc_granny_wu + cloth11（绿围裙）+ shoes3，**不戴眼镜**。glass8 是墨镜；glass0 会和 Tomo 撞；库里没有金丝眼镜，也不另做。
- Ivo：hairhat_npc_ivo + mask16_npc_ivo + cloth42_npc_ivo（没做就用 cloth42）+ shoes4。
- 不用 cloth28（那是警服）。交通锥、警服、黄瓜片、花朵墨镜这类玩笑款部件，居民一律不用。

## 交付
- 截图传 SGODOT-284，署刘备的 id：
  - npc_lineup 正面和 3/4 侧；
  - 用 `bake_resident_portraits.gd`（在 ~/incoming/resident-parts/，**放到 tools/art/ 下运行，但不要提交**，它会随头像整合另外进库）出两人的全身卡和邮票头像（实际 32×40 和 3 倍）。造型写在 looks 文件里，见派活说明。
- PR 进 farm-dev，注明 SGODOT-284 / q(171)。交叉审核后裔；技术检查上官婉儿；美术验收不知火舞；用户批准后合并。
- 合并后苏烈在 outpost_npcs.json 里给 Granny Wu、Ivo 加造型条目：Granny Wu 进 S 级小木屋；Ivo 等矿口小屋建好才出场。

# 设计文档清理记录（2026-10-05）

## 结果

按用户要求，以 [玩法方案 v2](product/gameplay-plan-v2-2026-10-02.md) 为唯一当前玩法基准，实际移除 **133 个过时文件**（103 个原有跟踪文件、30 个设计导入/生成伴随文件），将 **4 张当前基础锚定图原样移至 `out/current/`**。没有实施任何 P0 功能。

清理前版本：`25b7a8a6e0574f9b0c4c97f480238e98d5d9985c`（当时 HEAD 与 origin/farm-dev 相同）。本轮保留了上一轮写入的 Figma 地址和 P0 核查记录；清理完成时仅修改本地工作区，提交与推送按后续用户指令执行。

## 判定与保留

| 处理 | 内容 |
|---|---|
| 删除旧玩法规格 | 旧 G0–G4/七日章节/双地域交换/v1核心循环、24格背包、旧装备/矿井/HUD/相机规则，以及已合入或否决的过程草案 |
| 删除旧设计 | 旧合成截图与联络页、独立 EQUIP-1、旧 Recipes/2D锅、有人农场驿站和被替换的场景底图、9月旧UI概念稿与提示词 |
| 保留当前锚定图 | Figma仍使用的 FARM-1、FISH-1、COOK-1、BAG-1；仅迁目录，不冒充重新出图；Bag新Gear结构另以BAG-2为准 |
| 保留技术与证据 | Avatar/地图/钓鱼手感技术、地理/联机/迁移资料、当前美术输入、运行截图与QA、竞品来源和模拟结果；顶端/目录注明用途和历史边界 |
| 保留代码 | 运行代码、测试、工具、所有文档目录内的Python/JS/SH脚本，以及运行资产和配置；旧生成器仍可能产生旧稿，已在索引说明 |
| 提取有效内容 | 旧鱼塘提案中的Mapbox水域资料与抽样保留为 [独立技术调研](reference/mapbox-water-research-2026-09-24.md) |

P1/P2/P3未实施的有效设计没有因不属于P0被清除。当前方案内部仍待收口的冲突继续由SGODOT-153追踪，本轮没有替用户改变玩法决策。

## 当前入口与引用

- [仓库文档入口](README.md)、[产品索引](product/README.md)、[设计索引](design/README.md)。
- 根README移除了“0.16.12是最新线上版”和旧最高优先级方案，保留Avatar技术说明；AGENTS明确v2优先，旧条目只作有日期的事实。
- UI主索引和四组MANIFEST重写为当前有效约定，移除旧Bao/独立装备/旧烹饪过程说明。
- 历史QA的旧设计链接固定到清理前Git版本，不能将旧验收替换成“按v2通过”。源码/JSON中的历史来源元数据保持原样：例如`assets/farm/data/crops.json`的旧`_source`和旧UI对比manifest中的路径可按下述方式追溯。

## 校验与恢复

- 删除前建立逐文件SHA-256清单，打包并逐项读回核验；移动的4张图哈希保持一致。
- 4108个运行/源码/测试/工具文件与清理前逐字节一致。文档链接按清理前基线比较，未因本轮产生新断链；原有历史外部产物或缺失链接不计作本轮回归。
- 没有运行游戏测试、重生图、修改云端Figma/Plane、部署或安装应用；本轮验证的是文档引用和文件完整性。

历史跟踪文件可用以下命令查看：

```sh
git show 25b7a8a6e0574f9b0c4c97f480238e98d5d9985c:docs/product/inventory-2026-09-14.md
```

原始删除/移动文件和未追踪伴随文件已备份到本地 `output/design-doc-cleanup-2026-10-05/removed-and-moved-originals.tar.gz`；改写文档原文在同目录的 `edited-originals/` 与 `edited-docs-before.tar.gz`。目录保留在现有 `output/.gdignore` 保护下，不进入Godot导入。
结构化计划、备份校验、受保护文件校验和链接变更记录也保存在该目录。

## 原样迁移

| 原路径 | 当前路径 |
|---|---|
| `docs/design/ui-anchors-2026-10-03/out/v4/FARM-1.png` | `docs/design/ui-anchors-2026-10-03/out/current/FARM-1.png` |
| `docs/design/ui-anchors-2026-10-03/out/v4/FISH-1.png` | `docs/design/ui-anchors-2026-10-03/out/current/FISH-1.png` |
| `docs/design/ui-anchors-2026-10-03/out/v4/BAG-1.png` | `docs/design/ui-anchors-2026-10-03/out/current/BAG-1.png` |
| `docs/design/ui-anchors-2026-10-03/out/v3/COOK-1.png` | `docs/design/ui-anchors-2026-10-03/out/current/COOK-1.png` |

## 删除清单

以下路径均为清理前路径；逐文件的原因、替代项、大小和SHA-256见 [机器可读清单](design-cleanup-manifest-2026-10-05.json)。

<details>
<summary>docs/product：34 个文件</summary>

- `docs/product/prd-brief-2026-09-10.md`
- `docs/product/partner-gdd-2026-09-07.md`
- `docs/product/inventory-2026-09-14.md`
- `docs/product/npc-requests-2026-09-14.md`
- `docs/product/regional-growth-gdd-2026-09-10.md`
- `docs/product/mine-combat-2026-09-15.md`
- `docs/product/investor-build-2026-09-13.md`
- `docs/product/equipment-main-hand-2026-09-19.md`
- `docs/product/game-ui-2026-09-21.md`
- `docs/product/character-equipment-2026-09-14.md`
- `docs/product/mine-camera-2026-09-24.md`
- `docs/product/mine-max-view-2026-09-25.md`
- `docs/product/fun-first-rework-2026-09-07.md`
- `docs/product/map-farm-game-design.md`
- `docs/product/map-farm-life-sim-direction.md`
- `docs/product/starter-mine-2026-09-14.md`
- `docs/product/next-stage-action-blueprint-2026-09-10.md`
- `docs/product/core-loop-redesign-2026-10-02.md`
- `docs/product/multiplayer-mine-notes-2026-09-15.md`
- `docs/product/research/core-loop-2026-10-02/fix_log.md`
- `docs/product/research/core-loop-2026-10-02/verify_consistency.md`
- `docs/product/research/core-loop-2026-10-02/verify_feasibility.md`
- `docs/product/research/core-loop-2026-10-02/verify_simulation.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round2-interaction/interaction_model.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/decisions_r3.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/A_proficiency.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/B_kitchen_upgrade.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/C_homestead.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/mine_floors.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/npc_poi_rules.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/redteam.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round3-cooking-mine-npc/eval/verdict.md`
- `docs/product/research/gameplay-plan-v2-2026-10-02/round4-npc-rooms/eval-npc-rooms-2026-10-04.md`
- `docs/product/map-fishing-ponds-proposal-2026-09-24.md`

</details>

<details>
<summary>docs/superpowers：8 个文件</summary>

- `docs/superpowers/plans/2026-09-03-map-farm-mvp-implementation.md`
- `docs/superpowers/plans/2026-09-03-g0a-blueprint-pipeline.md`
- `docs/superpowers/plans/2026-09-03-g0b-map-select-farm-greybox.md`
- `docs/superpowers/plans/2026-09-04-g1a-farm-server.md`
- `docs/superpowers/plans/2026-09-04-g1b-farm-client.md`
- `docs/superpowers/plans/2026-09-04-g2-visit-skeleton.md`
- `docs/superpowers/specs/2026-09-04-g1a-farm-server-design.md`
- `docs/superpowers/plans/2026-09-03-map-farm-mvp-implementation.html`

</details>

<details>
<summary>docs/design：90 个文件</summary>

- `docs/design/ui-anchors-2026-10-03/out/COOK-1.png`
- `docs/design/ui-anchors-2026-10-03/out/COOK-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/FARM-1.png`
- `docs/design/ui-anchors-2026-10-03/out/FARM-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/FISH-1.png`
- `docs/design/ui-anchors-2026-10-03/out/FISH-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/contact-sheet.png`
- `docs/design/ui-anchors-2026-10-03/out/contact-sheet.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v2/COOK-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v2/COOK-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v2/FARM-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v2/FARM-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v2/FISH-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v2/FISH-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v2/contact-sheet.png`
- `docs/design/ui-anchors-2026-10-03/out/v2/contact-sheet.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/ACTION-RADIAL.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/ACTION-RADIAL.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/BAG-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/BAG-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/COOK-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/COOK-2a-recipes.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/COOK-2a-recipes.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/COOK-2b-experiment.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/COOK-2b-experiment.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/FARM-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/FARM-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/FISH-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/FISH-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v3/contact-sheet.png`
- `docs/design/ui-anchors-2026-10-03/out/v3/contact-sheet.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v4/BAG-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v4/EQUIP-1.png`
- `docs/design/ui-anchors-2026-10-03/out/v4/EQUIP-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v4/FARM-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v4/FISH-1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/v4/contact-sheet.png`
- `docs/design/ui-anchors-2026-10-03/out/v4/contact-sheet.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/batch1/contact-D.png`
- `docs/design/ui-anchors-2026-10-03/out/batch1/contact-D.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/ui/action-radial.html`
- `docs/design/ui-anchors-2026-10-03/ui/contact-batch1-D.html`
- `docs/design/ui-anchors-2026-10-03/ui/contact-v2.html`
- `docs/design/ui-anchors-2026-10-03/ui/contact-v3.html`
- `docs/design/ui-anchors-2026-10-03/ui/contact-v4.html`
- `docs/design/ui-anchors-2026-10-03/ui/contact.html`
- `docs/design/ui-anchors-2026-10-03/ui/cook-experiment.html`
- `docs/design/ui-anchors-2026-10-03/ui/cook-recipes.html`
- `docs/design/ui-anchors-2026-10-03/ui/equip.html`
- `docs/design/ui-anchors-2026-10-03/scenes/kitchen-v1.log`
- `docs/design/ui-anchors-2026-10-03/scenes/kitchen-v1.png`
- `docs/design/ui-anchors-2026-10-03/scenes/kitchen-v1.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/scenes/kitchen-v1.prompt.txt`
- `docs/design/ui-anchors-2026-10-03/scenes/kitchen-v1.response.json`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/scenes/homestead-stall.log`
- `docs/design/ui-anchors-2026-10-03/scenes/homestead-stall.png`
- `docs/design/ui-anchors-2026-10-03/scenes/homestead-stall.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/scenes/homestead-stall.prompt.txt`
- `docs/design/ui-anchors-2026-10-03/scenes/homestead-stall.response.json`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/scenes/market-square.log`
- `docs/design/ui-anchors-2026-10-03/scenes/market-square.png`
- `docs/design/ui-anchors-2026-10-03/scenes/market-square.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/scenes/market-square.prompt.txt`
- `docs/design/ui-anchors-2026-10-03/scenes/market-square.response.json`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/farm-ui-2026-09-05/generated/farm-design.png`
- `docs/design/farm-ui-2026-09-05/generated/map-design.png`
- `docs/design/farm-ui-2026-09-05/generated/panels-design.png`
- `docs/design/farm-ui-2026-09-05/generated/secondary-design.png`
- `docs/design/farm-ui-2026-09-05/image-prompts.md`
- `docs/design/farm-ui-2026-09-05/index.html`
- `docs/design/farm-ui-2026-09-05/prompts/01-map.txt`
- `docs/design/farm-ui-2026-09-05/prompts/02-farm-final.txt`
- `docs/design/farm-ui-2026-09-05/prompts/02-farm-refinement.txt`
- `docs/design/farm-ui-2026-09-05/prompts/02-farm.txt`
- `docs/design/farm-ui-2026-09-05/prompts/03-panels-refinement.txt`
- `docs/design/farm-ui-2026-09-05/prompts/03-panels.txt`
- `docs/design/farm-ui-2026-09-05/prompts/04-secondary-refinement.txt`
- `docs/design/farm-ui-2026-09-05/prompts/04-secondary.txt`
- `docs/design/game-ui-2026-09-21/generated/bag-design.png`
- `docs/design/game-ui-2026-09-21/generated/bag-design.png.import`
- `docs/design/game-ui-2026-09-21/generated/farm-design.png`
- `docs/design/game-ui-2026-09-21/generated/farm-design.png.import`
- `docs/design/game-ui-2026-09-21/generated/secondary-design.png`
- `docs/design/game-ui-2026-09-21/generated/secondary-design.png.import`
- `docs/design/game-ui-2026-09-21/prompts/bag.txt`
- `docs/design/game-ui-2026-09-21/prompts/farm.txt`
- `docs/design/game-ui-2026-09-21/prompts/system.txt`
- `docs/design/maki-icons-2026-09-23/sheet.png.import`
- `docs/design/ui-anchors-2026-10-03/out/batch1/NPC-G1-5.png.import`（原未跟踪/忽略的伴随文件，已备份）
- `docs/design/ui-anchors-2026-10-03/out/batch2/PASS-3.png.import`（原未跟踪/忽略的伴随文件，已备份）

</details>

<details>
<summary>docs/partner_demo_runbook.md：1 个文件</summary>

- `docs/partner_demo_runbook.md`

</details>

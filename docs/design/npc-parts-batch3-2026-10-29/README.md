# NPC Batch 3 · 部件审阅

第二段 Nadia 的帽子、围裙及三人新造型并排已补到 [Nadia 审阅](nadia/README.md)。
下方保留第一段换色的完整证据。

赵云，2026-10-29。规格：SGODOT-362 `ba1dcbd1` / `27ea8b86` 和上官婉儿 10-29 派工。
参考 `362_before_after_v1.png` 仅是 2D 颜色方向；本目录六张审阅图全部来自游戏实渲。
运行时基于最新拉取的 farm-dev `f0cde4aa`，美术分支基于 wp-3d-scene `fadcaa19`。

| 部件 | 底件 | 改动 | 面数 / 增量 |
| --- | --- | --- | --- |
| hairhat51_npc_lena | hairhat51 | 芥末黄雨帽，藏青徽章，头发原色 | 1,103 / 0 |
| hairhat36_npc_rafa | hairhat36_npc_pip | 白帽顶，保留藏青帽檐 / 金带 / 金徽 / 棕发 | 1,214 / 0 |
| cloth1_1_npc_rafa | cloth1_1 | 白底藏青横纹，卡其短裤原色 | 1,629 / 0 |

每件一个 mesh / surface。三件 FBX 字节相同；节点、层级、轴向、变换、UV、权重与骨架不变，
衣服的 59 个 skin binds 逐项相同。新 PNG 使用新文件名，材质所有参数来自底件的实际
runtime resource。来源纹理 2048² / 1024² / 1024²，导入后均 512²。

Rafa 躯干横纹在原 UV 上按静止姿态高度绘制，周期 6 cm；袖子随下垂骨骼转向。
保留裤子 UV 像素与 2 px 保护区，帽子按连通组件 UV 保护头发和装饰。
生成 / 像素核对见 [texture-validation.json](texture-validation.json) 与
`tools/art/source/npc_batch3/*_mask.png`。

## 审阅图

- [01 · Lena / Rafa 原造型与新造型](SGODOT-362_PARTS_v1_01_before_after.png)
- [02 · Lena 帽子底件 / 新件正背近景](SGODOT-362_PARTS_v1_02_lena_hat.png)
- [03 · Rafa 帽子底件 / 新件正背近景](SGODOT-362_PARTS_v1_03_rafa_hat.png)
- [04 · Rafa 衣服底件 / 新件正背近景](SGODOT-362_PARTS_v1_04_rafa_cloth.png)
- [05 · 茶馆 Ama / Hana / Lena 与驿站 Sigrid / Pip / Sam](SGODOT-362_PARTS_v1_05_room_lineups.png)
- [06 · 邮票与圆脸：旧框 / 建议框](SGODOT-362_PARTS_v1_06_portrait_crops.png)

原 resident portrait baker 未改，直接在 farm-dev checkout 开窗口运行，用游戏
P0KeeperPortraits 的舞台、光照和镜头。正背近景使用同一舞台和固定成对镜头。
Godot 4.7.2 / Vulkan Mobile / RTX 2060，渲染前检查 GPU 空闲，每次进程自行退出。
导入 / 编辑器使用 ADB 5099 和独立 QA 用户目录；没有真实用户数据或线上造型修改。

旧头像框会裁掉 Lena 新帽子的边缘。本次建议 stamp `[38,42,224,280]`、
face `[34,40,232,232]`，在两种使用场景中保留整顶帽子。
建议只写 [suggested-portrait-crops.json](suggested-portrait-crops.json)，未改正式配置。
Hana 并排使用已通过方案 A；其他对照用实际 NPC slots。Nadia 的新造型并排待 347 完成补交。

## 验证与交付

115 项专用检查通过（含 FBX / 导入层级、逐 surface 顶点数组、59 个皮肤绑定、
实际纹理路径、底件材质参数、NPC 可用且玩家不可用）；38 项原 catalog / pipeline /
socket 测试通过。见 [godot-validation.json](godot-validation.json) 和 [tests.xml](tests.xml)。

manifest 45 → 48，只追加；45 个原条目的文本前缀、原资源与缩略图逐字节一致。
npc_only 16 → 19，只追加。`assets/p0/outpost_npcs.json` 未修改。
[phase1-evidence.json](phase1-evidence.json) 保存基线和媒体哈希。

运行时分支 `art/npc-parts-batch3`，第一段头 `109789661e51cd165fb043caddb0f48004952636`，只推、不建 PR；美术分支
`art/npc-parts-batch3-review` 开 PR 到 wp-3d-scene。六张署名图上传 SGODOT-362，
附件署名和 SHA-256 回读保存在 `delivery-phase1.json`。技术 / 画面通过后仍需用户批准。

## 复现

从美术工位执行，`RUNTIME` 指另一个 farm-dev checkout：

```sh
source ~/.codex-zhaoyun/env.sh
RUNTIME=/home/zhangshaoji/.herdr/worktrees/sensen-godot/zy-npc-parts-batch3
blender --background --factory-startup --threads 4 --python-exit-code 1 \
  --python "$PWD/tools/art/inspect_npc_batch3.py" -- \
  --runtime-root "$RUNTIME" --out "$PWD/output/npc-batch3/source-inspection"
output/art-setup/venv/bin/python tools/art/recolor_npc_batch3.py \
  --runtime-root "$RUNTIME" --inspection output/npc-batch3/source-inspection
python3 tools/art/stage_npc_batch3_review.py --runtime-root "$RUNTIME"
godot --headless --path "$RUNTIME" --editor --import --quit
godot --headless --path "$RUNTIME" --script res://tools/art/prepare_npc_batch3.gd
godot --headless --path "$RUNTIME" --script res://tools/pipeline/extract_parts.gd -- \
  res://assets/avatar/source/recipes_batch3.json --append
godot --headless --path "$RUNTIME" --editor --import --quit
godot --headless --path "$RUNTIME" --script res://tools/art/verify_npc_batch3.gd
```

在运行时工位执行窗口渲染（先检查 `nvidia-smi`）：

```sh
godot --path . --rendering-method mobile --rendering-driver vulkan \
  --script res://tools/art/bake_resident_portraits.gd -- \
  --looks=res://output/npc-batch3/looks-phase1.json --out=output/npc-batch3/portraits \
  --ids=lena_now,lena_a,lena_new,rafa_now,rafa_r1,rafa_new,rafa_hat_only,nadia_now,sigrid,finn,mei,theo,sam_now,hana_a,ama,pip --cols=4
godot --path . --rendering-method mobile --rendering-driver vulkan \
  --script res://tools/art/review_npc_batch3.gd
```

上述复制到运行时的 `tools/art/*.gd` 仅用于本地审阅，不进入运行时提交。
原始 FBX 保留旧纹理路径，import 有旧纹理缺失警告；recipe 显式绑定新 PNG，实际材质已验证。
变体提取成功：3 件、0 错误。首次全工程导入的已有资源警告保存在 output 日志。

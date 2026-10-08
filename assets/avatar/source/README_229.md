# SGODOT-229 NPC 专用部件：Deck 上的操作步骤

分支 `feat/229-npc-sources`（后裔，2026-10-08）。5 件 NPC 专用部件复用旧 Unity 资产（不知火舞定的方案见 229 卡），源文件已用 `tools/unity_export` 迁入：

| id | 槽位 | 挂法 | 源文件（本目录下） | 要做的美术 |
|---|---|---|---|---|
| `mask16_npc_kai` | mask | socket（Head_M） | `mask16_npc_kai/SM_mask16.fbx`，`T_skin34_mask_2_D.png`（灰白） | 不改 |
| `hairhat71_npc_kai` | hairHat | socket | `hairhat71_npc_kai/SM_hairHat71.fbx`，`T_skin59_hairHat_D.png` | 去掉帽上凸眼和鬓角粉发夹 |
| `hairhat12_npc_mei` | hairHat | socket | `hairhat12_npc_mei/SM_hairHat12.fbx`，`T_skin11_hairHat_2_D.png`（蓝格） | 不改 |
| `cloth11_npc_mei` | cloth | mesh | `cloth11_npc_mei/SK_dt_skin11.fbx`，`T_skin11_cloth_D.png`（原绿） | 贴图改成棕色围裙 |
| `hairhat80_npc_ama` | hairHat | socket | `hairhat80_npc_ama/SM_hairHat80.fbx`，`T_skin68_hairHat_D.png`（黑） | 不改 |

配方是 `recipes_229.json`，路径都指向 `res://assets/avatar/source/<id>/`。mask16 的偏移取自 Unity 资产 `ap_mask16_2`，为单位变换；现有 socket 件也都是这样，落位靠 FBX 自身的节点变换。Deck 上不需要 Unity 工程。

## 规则

- 只改上表 5 个目录里的文件，**文件名不变**。改 FBX 时保留节点名。
- 不动其他部件目录，不动 `parts_manifest.json` 里原有的 29 条。
- 提取一律用 `--append`。不带 `--append` 会用这 5 件配方整份重写清单，原有 29 条就没了。

## 命令（仓库根目录，Godot 4.7.2）

```sh
git fetch origin
git switch -c feat/229-npc-parts origin/feat/229-npc-sources

# 1. 改完美术后导入（首次、以及每次改了 FBX 或 PNG 之后）
godot --headless --path . --import

# 2. 追加提取：只处理清单里还没有的 id，原有条目和它们的 .res 不动
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_229.json --append
#    期望输出："追加完成: 5 部件, 0 错误"
#    自查：git diff assets/avatar/parts_manifest.json 只应在末尾多出 5 个条目
#    改了美术要重提某一件：先从清单里删掉它的条目，再跑一次上面这条命令

# 3. 把 5 个 id 写进 NPC 专用名单，玩家换装列表和联机外观就看不到它们
#    assets/avatar/npc_only.json:
#    {"version": 1, "npc_only": ["mask16_npc_kai", "hairhat71_npc_kai", "hairhat12_npc_mei", "cloth11_npc_mei", "hairhat80_npc_ama"]}

# 4. 测试
GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh \
  -a res://tests/catalog \
  -a res://tests/pipeline \
  -a res://tests/assembly/test_socket_placement.gd
#    test_socket_placement 检查每件 hairHat（含 NPC 专用件）都落在头上
#    mask 槽不在这个测试里，mask16 的落位由后裔用 npc_lineup 渲正面和 3/4 侧核对
```

## 开 PR

目标 farm-dev，注明依赖 #33（npc_only 过滤，已合入）。交叉审核：后裔。美术验收：不知火舞。用户批准后合并。合并后，后裔单独开小 PR 给 Old Kai、Mei、Ama 换上这些部件（`assets/p0/outpost_npcs.json`）。

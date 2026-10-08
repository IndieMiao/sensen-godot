# 第二批 NPC 专属部件：Deck 上的操作步骤

分支 `feat/npc-batch2-sources`（后裔，2026-10-09）。用户已批准第二批 NPC 专属件，方案由不知火舞在 SGODOT-227 上定。4 件都复用旧 Unity 资产，源文件已用 `tools/unity_export` 迁入，做法同 `README_229.md`：

| id | 槽位 | 挂法 | 源文件（本目录下） | 要做的美术 |
|---|---|---|---|---|
| `hairhat36_npc_sigrid` | hairHat | socket | `hairhat36_npc_sigrid/SM_hairHat36.fbx`，`T_skin28_hairHat_D.png`（藏青大檐帽、红发、白徽、白帽带） | 只改贴图：红发改棕发，帽徽和帽带改金色，帽子保持藏青 |
| `cloth36_npc_sigrid` | cloth | mesh | `cloth36_npc_sigrid/SK_dt_skin36.fbx`，`T_skin36_cloth_D.png`（黑色正装） | 只改贴图：西装和马甲改藏青，领带改红色，扣子改金色，衬衫保持白色 |
| `cloth12_npc_finn` | cloth | mesh | `cloth12_npc_finn/SK_dt_skin12.fbx`，`T_skin12_cloth_D.png`（青蓝牛仔单肩背带裤、灰格衬衫、胸前小包） | 只改贴图，不动几何，接受单肩背带：牛仔蓝压暗成灰蓝，衬衫改纯米白、去掉格纹，胸包改褐色皮革（像钓具小包） |
| `hairhat36_npc_pip` | hairHat | socket | `hairhat36_npc_pip/SM_hairHat36.fbx`，`T_skin28_hairHat_D.png`（与 Sigrid 那顶同源） | 可选，最低优先：删掉马尾几何（Pip 立绘是短发）；贴图同 Sigrid：棕发、金徽、金帽带 |

配方是 `recipes_batch2.json`，只含这 4 件，路径都指向 `res://assets/avatar/source/<id>/`。两顶帽子的偏移取自 Unity 资产 `ap_hairHat36`，为单位变换，和现有 socket 件一样，落位靠 FBX 自身的节点变换。贴图文件名都不含空格。Deck 上不需要 Unity 工程。

参考：后裔在本机做过一版按色相自动调色的预览（不是最终美术），图在 `/Volumes/ACASIS/tmp/gensen-ui-review/houyi/keeper-looks-2026-10-09/`（`candidates-close.png`、`candidates-body.png`，每格左侧是立绘），由不知火舞转给你。

## 规则

- 只改上表 4 个目录里的文件，**文件名不变**。改 FBX 时保留节点名；Pip 那顶删马尾时只删马尾的几何，帽子和挂点节点不动。
- 不动其他部件目录，不动 `parts_manifest.json` 里原有的 34 条。
- 提取一律用 `--append`。不带 `--append` 会用这 4 件配方整份重写清单，原有 34 条就没了。
- Pip 那顶如果本批不做：从 `recipes_batch2.json` 删掉 `hairhat36_npc_pip` 这一条（注意前一条末尾的逗号），删掉 `hairhat36_npc_pip/` 目录，下面期望的件数相应减 1。

## 命令（仓库根目录，Godot 4.7.2）

```sh
git fetch origin
git switch -c feat/npc-batch2-parts origin/feat/npc-batch2-sources

# 1. 改完美术后导入（首次、以及每次改了 FBX 或 PNG 之后）
godot --headless --path . --import

# 2. 追加提取：只处理清单里还没有的 id，原有条目和它们的 .res 不动
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- res://assets/avatar/source/recipes_batch2.json --append
#    期望输出："追加完成: 4 部件, 0 错误"（Pip 不做时是 3）
#    自查：git diff assets/avatar/parts_manifest.json 只应在末尾多出这几个条目
#    改了美术要重提某一件：先从清单里删掉它的条目，再跑一次上面这条命令
#    （删的若是最后一条，把前一条末尾的逗号也删掉，否则清单不是合法 JSON）

# 3. 把新 id 追加进 NPC 专用名单，玩家换装列表和联机外观就看不到它们
#    assets/avatar/npc_only.json 的 npc_only 数组末尾加上：
#    "hairhat36_npc_sigrid", "cloth36_npc_sigrid", "cloth12_npc_finn", "hairhat36_npc_pip"
#    （原有 5 个 id 保留；Pip 不做时不加最后一个）

# 4. 测试
GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh \
  -a res://tests/catalog \
  -a res://tests/pipeline \
  -a res://tests/assembly/test_socket_placement.gd
#    test_socket_placement 检查每件 hairHat（含 NPC 专用件）都落在头上
#    衣服和整体效果由后裔用 tools/dev/npc_lineup.gd 渲正面和 3/4 侧核对
```

## 开 PR

目标 farm-dev。交叉审核：后裔。美术验收：不知火舞。用户批准后合并。合并后，后裔单独开小 PR 给 Sigrid、Finn（和 Pip，若做了）换上这些部件（`assets/p0/outpost_npcs.json`）。

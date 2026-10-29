# NPC Parts Batch 3

赵云，2026-10-29。上官婉儿派工；技术检查归上官婉儿，画面验收归不知火舞，
最终由用户批准。运行时分支 `art/npc-parts-batch3` 基于 farm-dev
`f0cde4aa`；仅推分支，整合 PR 由上官婉儿后续开。

## 第一段：SGODOT-362

| ID | 底件 | 改动 | 三角形 | 增量 |
| --- | --- | --- | ---: | ---: |
| hairhat51_npc_lena | hairhat51 | 芥末雨衣黄帽、藏青徽章；棕发原色 | 1,103 | 0 |
| hairhat36_npc_rafa | hairhat36_npc_pip | 白色帽顶；保留藏青帽檐、金带金徽及棕发 | 1,214 | 0 |
| cloth1_1_npc_rafa | cloth1_1 | 白底藏青横条；短裤原色 | 1,629 | 0 |

三件均只换新文件名 PNG。原 FBX 文件名、文件字节、节点名、层级、变换、单位、
轴向、UV、权重和骨架完全不变。每件一个 mesh / 一个 surface，沿用底件导入参数，
源贴图分别为 2048² / 1024² / 1024²，运行时均 512²。

Rafa 横纹由原 FBX 静止姿态的高度投射回原 UV，周期 6 cm、藏青带宽 2.2 cm，
没有改 UV。原 UV 重叠位置的高度误差小于 0.000001 cm，能保持躯干接缝相位一致。
袖子随原骨骼下垂后条纹沿袖身转向；正背面审阅图已提供。裤子 UV 及外围 2 px
保护区域保持原像素。两顶帽子的头发 UV 原像素不变，Rafa 其他帽子组件 UV 也不变。

材质参数直接从底件 `.res` / runtime scene 读取：

| 底件 | emission_strength | smoothness | ao_strength | diffuse_strength | rim_strength |
| --- | ---: | ---: | ---: | ---: | ---: |
| hairhat51 | .3 | .1 | .1 | 1 | 0 |
| hairhat36_npc_pip | .6 | .1 | .3 | 1 | 0 |
| cloth1_1 | .3 | .1 | .3 | 1 | 0 |

`recipes_batch3.json` 目前包含第一段三件。`npc_only.json` 已追加，玩家部件池不可用；
`parts_manifest.json` 经 `extract_parts --append` 从 45 项增至 48 项，原条目文本前缀、
原 `.res` 和原缩略图保持一致。新增 thumbs 沿用提取器生成规则，NPC 不显示在换装池。
本分支不修改 `assets/p0/outpost_npcs.json` 或正式居民卡 / 裁切配置。

```sh
source ~/.codex-zhaoyun/env.sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tools/pipeline/extract_parts.gd -- \
  res://assets/avatar/source/recipes_batch3.json --append
godot --headless --path . --editor --import --quit
GODOT_BIN="$(command -v godot)" ./addons/gdUnit4/runtest.sh \
  -a res://tests/catalog -a res://tests/pipeline -a res://tests/assembly/test_socket_placement.gd
```

再次 `--append` 会跳过已注册 ID。重做某件时只移除该件 manifest 条目再追加，
不要省略 `--append`。源 FBX 保留旧纹理引用，提取器按 recipe 显式绑定新 PNG；
原始 FBX 导入时找不到旧纹理的警告不代表 runtime 材质缺失，验证已检查实际纹理绑定。

第一段验证：115 项源文件 / 导入 / 提取 / 皮肤绑定 / 材质 / NPC 隔离检查通过；
catalog、pipeline、socket 共 38 项原测试通过。渲染在此 farm-dev checkout 的独立
用户目录运行，Godot 4.7.2 / Vulkan Mobile / RTX 2060；不是手机性能结果。

生成脚本、UV 掩码、原始部件检查及署名审阅图在伴随美术分支
`art/npc-parts-batch3-review` 的 `tools/art/`、`tools/art/source/npc_batch3/` 和
`docs/design/npc-parts-batch3-2026-10-29/`。审阅使用未修改的
`bake_resident_portraits.gd`，只复制到运行时工位，不进入此分支提交。
347 的 Nadia 两件见下方；357 的 Lou 和后墙 AO 为后续增量。

## 第二段：SGODOT-347 Nadia

| ID | 底件 | 几何改动 | 三角形 | 增量 |
| --- | --- | --- | ---: | ---: |
| hairhat41_npc_nadia_baker | hairhat41_npc_auburn | 保留 592 面长发，移除花冠，新增矮软帽 / 帽带 | 1,296 | -1,016 |
| cloth1_1_npc_nadia | cloth1_1 | 保留原衬衫短裤，增加围裙、肩带、空胸袋和腰带系带 | 1,869 | +240 |

帽子仍是 Head_M socket；衣服仍使用原来的 59 个 skin binds。没有整场景重导出：
在原二进制 FBX 内仅替换对应 Geometry，衣服的新增顶点向原 skin clusters 追加权重；
原节点名、层级、transform、轴向、单位、骨骼和绑定矩阵、原顶点权重全部保留。
其他 Geometry 和对象不变；编码器仅另外规范化 FileId / CreationTime。

每件一个 mesh / surface。材质照底件：帽子 emission .7，衣服 .3；其他参数同底件。
一张 1024² PNG，runtime 512²；原纹理压入上方 1024×896 区域并对应变换 UV，
下方 128 px 为原创白 / 米白布料色块。发色保留赤褐，衬衫蓝纹改暖粉，围裙不放蔬菜。
源 blend 在美术分支 tools/art/source/npc_batch3/，包含原骨架和命名编辑组。

第二段验证：91 项实际导入 / 绑定 / 材质 / NPC 隔离检查，38 项原 catalog /
pipeline / socket 测试通过；实际权重数组为每顶点 8 项，全部归一化。
七个站立 / 行走 / 侧背姿态已实渲检查，补有原生名字条和 72 屏幕像素徽标（36 逻辑
px × 2），采用游戏 2.0 m 名字锚点。manifest 48→50、npc_only 19→21 仅追加。

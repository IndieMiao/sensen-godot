# SGODOT-347 · Nadia 帽子 v1.1

赵云，2026-10-30；按不知火舞 ef30c01c 和上官婉儿的返修要求，仅调整
hairhat41_npc_nadia_baker。围裙不做可选改动，其余五件和后墙保持已交 v1。
运行时分支 art/npc-parts-batch3，返修头 17cd10d56e62530d4bf6b7bec35386b255559d4b；
美术继续在 PR #561 增量交付。

帽子的 448 个顶点统一下压 2 cm；按火舞“必要时帽口稍微收一点”的意见，
再把帽口下部和滚边的半径参数收紧 2 cm（160 个顶点），保留帽冠原形。
原生坐标为 X-up、厘米，所以竖向变化为 X=-2 cm，不改 socket 或节点变换。
仍为 **1,296 三角面 / 一个 mesh / 一个 surface**，没有增加面数。

源 FBX 与 v1 比较：303 个头发顶点及对应法线完全相同；索引、UV、材质分配、
节点、层级、连接、单位和轴向完全相同；仅帽子顶点和帽子法线改变。
编码器 FileId / CreationTime 不计入语义比较。源 blend 与导出的顶点逐项对应。

运行时重做按 README 的方法：只临时移出帽子 manifest 条目，再运行
extract_parts --append，输出“1 部件，0 错误”。核对所有条目内容一致后，
恢复原 manifest 文本和顺序；同时保留原 socket 场景 node unique_id。
最终运行时相对 ad751863 **仅两文件变化**：

- assets/avatar/source/hairhat41_npc_nadia_baker/SM_hairHat41.fbx
- assets/avatar/parts/hairhat41_npc_nadia_baker_scene.tscn

材质、纹理、.res、导入设置、配方、缩略图、manifest、npc_only、NPC slots、
其他五件和后墙均保持原字节。没有重新生成围裙或 Lou。

## 审阅图

- [帽子正面：v1 / v1.1](SGODOT-347_NADIA_v1.1_01_hat_front.png)
- [帽子背面：v1 / v1.1](SGODOT-347_NADIA_v1.1_02_hat_back.png)
- [Mei / Theo / Nadia 集市并排](SGODOT-347_NADIA_v1.1_03_market_lineup.png)

正背对照左侧直接裁自已交 v1 审阅图，右侧为相同舞台 / 镜头 / 姿态的新游戏渲染，
没有后期调色。集市并排用未改的 resident portrait baker 重出。
Godot 4.7.2 / Vulkan Mobile / RTX 2060，farm-dev checkout，ADB 5099；
渲染前检查 GPU 空闲，所有本轮进程已退出。

三张图已查看：帽口更贴住头发，背面两端外挑减小。待不知火舞复核，
不以本轮自查替代画面验收；#561 和运行时分支均未合并。
上传 347 的三图署名和下载 SHA-256 见 delivery-verification.json。

## 验证

源 FBX 定量比较通过；91 项已有 Nadia 导入 / socket / 绑定 / 材质检查通过；
原 test_socket_placement 通过（1 case，检查全部 hairHat）。
见 geometry-validation.json、godot-validation.json、socket-tests.xml 和 scope-validation.json。

源 blend 已更新，生成脚本支持仅帽子重建，避免触碰其他部件：

~~~sh
source ~/.codex-zhaoyun/env.sh
blender --background --factory-startup --threads 4 --python-exit-code 1 \
  --python "$PWD/tools/art/build_nadia_batch3.py" -- --runtime-root "$RUNTIME" --cap-only
godot --headless --path "$RUNTIME" --editor --import --quit
python3 tools/art/reextract_nadia_hat_347.py --runtime-root "$RUNTIME"
~~~

verify_nadia_hat_revision_347.py 比较 v1 FBX 和新文件；package_nadia_hat_v11_347.py
比较所有运行时改动与 ad751863，若出现任何额外改动则失败。
正背近景使用 review_npc_batch3.gd -- --nadia-hat-v11，输出到独立 nadia-v11-closeups；
全身卡按 looks-phase2.json 的 mei / theo / nadia_new 输出到 nadia-v11-cards。
此前 v1 图片和验收记录保持原样。

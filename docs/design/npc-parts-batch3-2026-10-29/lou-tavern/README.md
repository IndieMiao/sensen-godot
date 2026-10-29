# SGODOT-357 · Lou 与牌室后墙

赵云，2026-10-29；美术 PR #561 的第三段增量。两项实施方式均在本会话确认：
Lou 改用 cloth1，加酒红马甲、黑领结和深色长裤；后墙运行时增加修正后的图集 PNG。
最终技术 / 画面验收和用户批准合并仍未完成。
运行时头 ad751863b42770d4e8f70dd3889a4bca230b4b2f，art/npc-parts-batch3。

## Lou

cloth1_npc_lou：**2,811 三角面**，比 cloth1 多 1,182；一个 mesh / surface，
1024² 源图、512² runtime。底件衬衫的 591 顶点 / 1,111 面保留，88 个下摆顶点内收；
短裤替换为 cloth36_npc_sigrid 的独立裤身（522 顶点 / 1,040 面），重新着深炭灰。
新增酒红马甲、黑色领结和小纽扣，和 Sigrid 的藏青外套 / 领带区分。

原 cloth36 上身的外套、袖子、内搭是一个 1,698 面连通块，故没有简单删除外套。
现在仅复用它可独立分离的裤身，外套完全未进入新部件。

使用 cloth1 原 FBX 容器：原节点、层级、变换、轴向、单位、骨骼、Connections 和
59 个绑定矩阵均相同；其他 Geometry 相同。cloth 的顶点索引改变，因此明确重建
对应 skin 权重数组，按同名骨骼映射裤腿，不能宣称原权重数组不变。
几何记录中的 original_skin_weights_and_bind_matrices_exact=false 对应这一预期改动；
original_bind_matrices_exact=true，且实际 Godot 逐 bind 比较通过。

75 项导入 / 绑定 / 权重 / 材质 / NPC 隔离检查通过；最终 catalog、pipeline、
socket 38 项通过。七个站立 / 行走 / 侧背姿态已查看，马甲、领结和裤腿正常随原动画。

源文件：tools/art/source/npc_batch3/lou-dealer.blend（命名 EDIT_ 编辑组、打包纹理）；
生成器 build_lou_batch3.py、prepare_lou_texture.py。参数照 cloth1 原 runtime 材质，
没有追加材质或改全局着色器。manifest 50→51、npc_only 21→22 仅追加。

## 后墙

back_wall.glb 不含图像，运行时由 coffee_shop_art.gd 统一绑定 room_albedo_ao.png；
所以按已确认的范围，把修正 PNG 同步到运行时分支。

- 只改变 **297 个像素**，图集坐标 **x=815..840、y=1027..1048**（包含端点）。
- 对应后墙局部 x=-.32..+.38 m、y=3.02..3.70 m；从同高度左右木板取样，柔和提高
  原托架阴影区域亮度，保留 RGB 比例、横向板缝与周边木色。
- 44 个独立 GLB，加实际房间的 front_dressing / back_dressing 合批均核对。
  后墙 5,812 面的合批副本被识别为同一表面；和其他道具没有 UV 覆盖重叠。
- 其他物件使用像素、8 px 保护边、alpha 和修正掩码外像素均不变。
- **重新导出 GLB：0 个。** 全部 GLB、几何、UV、碰撞、anchors 和 tavern.blend
  都保持原字节。原 asset_stats.json 的 PNG bytes 是旧几何交付记录，未改；
  修正 PNG 的实际大小 / 哈希记录在本批交付报告。

前后图调用 farm-dev 的真实 P0Outpost sf_card_room_1，use_runtime=false。
原生隐藏逻辑剔除了招牌 2,368 面、托架 188 面；原生 frame_all 确定开场镜头。
在 360×800 构图后按相同纵横比捕获 720×1600，近景 1440×900；两侧镜头矩阵相同。
旧图集使用修改前保存的真实 S3TC 导入资源，新图集使用当前实际导入资源。
灯光、NPC、材质参数和动画姿态固定。开场对照中仅 1,131 个像素发生变化，位于
[561,478,610,540]；其余画面逐像素相同。牌室中的 Lou 仍为原 slots，换装由程序接入。

## 审阅入口

- [Lou 改前 / 改后，与 Sigrid 并排](SGODOT-357_LOU_v1_01_lou_sigrid.png)
- [衣服正背近景](SGODOT-357_LOU_v1_02_cloth_closeups.png)
- [七个动画与侧背姿态](SGODOT-357_LOU_v1_03_motion.png)
- [原生牌室开场前后](SGODOT-357_LOU_v1_04_wall_opening.png)
- [原托架处近景前后](SGODOT-357_LOU_v1_05_wall_closeup.png)

全部使用 farm-dev checkout 开窗口实渲，Godot 4.7.2 / Vulkan Mobile / RTX 2060，
未作后期调色。5 张署名图传 SGODOT-357，附件下载哈希和作者见 delivery-verification.json。
运行时仅推 art/npc-parts-batch3，不开 PR；用户批准后由上官婉儿开整合 PR。

## 复现

Lou：在美术工位用 prepare_lou_texture.py / build_lou_batch3.py 生成，
然后 stage_npc_batch3_review.py 复制审阅脚本到独立运行时工位。
导入后运行 prepare_npc_batch3.gd、extract_parts.gd --append，
检查命令为 verify_nadia_batch3.gd -- --lou；只重提尚在调整的 Lou 条目，保留其他条目。
全身卡用原 bake_resident_portraits.gd 和 looks-phase3.json；
近景为 review_npc_batch3.gd -- --lou；动画为 review_nadia_motion.gd -- --lou。

后墙先在未修改图集的 farm-dev 基线 f0cde4aa 上导入，并运行 prepare_tavern_357.gd
保留真实压缩的旧图集；该脚本校验原 PNG SHA-256，防止把已修正图片当成改前。
再在美术工位运行：

~~~sh
output/art-setup/venv/bin/python tools/art/inspect_tavern_ao_357.py
output/art-setup/venv/bin/python tools/art/repair_tavern_ao_357.py --runtime-root "$RUNTIME"
~~~

修正后在运行时再次导入 PNG，复制并运行 review_tavern_357.gd。
所有 --editor / --import 先 source ~/.codex-zhaoyun/env.sh，ADB 5099；
渲染前检查 nvidia-smi，完成后进程退出。审阅脚本仅临时复制到 farm-dev 工位，不进入运行时提交。

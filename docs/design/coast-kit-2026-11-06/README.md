# SGODOT-426 · 海岸套件 v1

【赵云】2026-11-06；virtual_user_id：`8ea32e40-c0ba-4a31-864f-374a6bcbc554`。草稿交上官婉儿技术检查、不知火舞画面验收。

15 个可复用件已放入 [assets/landmarks/_shared/coast_kit](../../../assets/landmarks/_shared/coast_kit/README.md)：六种直 / 外角 / 内角高低岸石、三块散石、混凝土墙、三种木码头、小浮标、下水台阶。每件 **28–344 面、一个 mesh / surface**，总计 **2,348 面**。哑光顶点色，无木纹或石头贴图。

2 m 模数，岸石低 / 高峰值 0.8 / 1.2 m、端口统一；码头甲板 2×2 m、顶面 1.2 m；台阶踏步 0.25 m、级高 0.15 m。完整方向、接口、拼法、尺寸、色板、来源说明在[套件 README](../../../assets/landmarks/_shared/coast_kit/README.md)。散石复用恶魔岛已通过的几何，缩放 / 换色后写入新目录，原件不改。

恶魔岛目录、场景、水面材质、任何现有布局均未修改。约 20 m 示例只用于出图；示例装配与临时背景留在本机 `output/coast-kit/`，**不交 layout、运行场景或游戏注册**。可编辑 Blender 中也只保存独立件。

## 审阅图

- [件表 + 人物](SGODOT-426_COAST_v1_catalog.png)：15 格相同比例、同一 1.75 m 游戏角色，每格原始 300×300，43°。整图 1500×1160。
- [360×800 默认镜头](SGODOT-426_COAST_v1_default_360x800.png)：43° / yaw 14.5° / 正交宽 6.72 m，按示例人物的默认跟随目标取景，原始分辨率。能看到码头、台阶、内转角和浮标；岸线两端在画外。
- [完整示例岸线](SGODOT-426_COAST_v1_shore_overview.png)：相同 43° 方位，全景视宽 17.5 m，展示两个转角、码头和台阶。10 个 2 m 格，计 20 m；转角按实际弧线计算，含两个各 2 m 出入口的岸线约 19.14 m。
- [拼接近景](SGODOT-426_COAST_v1_seams.png)：低直段 → 外转角 → 高直段，观察端面连续性。

均为 Godot 4.7.2 Vulkan Mobile / RTX 2060 实渲。只做署名和版面文字，没有调色或缩放模型。示例水面和地表是隔离审阅背景，不作为水面或地表材质交付。所有图片长边 ≤1600。

## 检查结果

[独立几何与接口报告](asset-validation.json)：**238 项通过**。覆盖 15 个单 surface 网格、面数上限、底部高度、法线 / 非退化三角形、顶点色、实际 GLB SHA、UID / `nodes/root_script=null` / 其他导入参数、原恶魔岛文件不变。

43 组 out→in 配对（36 岸石、1 墙、6 码头）检查序列化 GLB 的端口顶点与实际拼接变换，最大截面错位 `1.11e-16 m`。另核对两种可延续码头与台阶的 2 m 走面接边。端口来自构造坐标，未靠放大或人为重叠掩盖缝隙。

[Godot 实渲报告](render-validation.json)：**76 项通过**。导入网格面数与交付清单一致，15 份 UID 与空 root_script 参数存在；示例端口位置一致、默认镜头口径正确，18 张原始视口图保存成功。打包时再比对实渲的 GLB SHA 与最终清单。

默认审阅视口记录为 **9,688 面 / 18 draw**，完整岸线为 **11,078 面 / 24 draw**，含角色及临时背景。这是桌面审阅视口数据，不是手机 FPS 或正式地标性能验收。

所有 `.import` 均从 Godot 最终导入结果同步，保留生成的 UID 和 `nodes/root_script=null`。交件前在仅含 15 件的隔离项目中清缓存冷导入，并在提交后同步检查字节稳定及 `git status` 干净；具体提交头和冷导入结果写在 PR 交付评论中。

## 源文件与复现

- [coast_kit.blend](../../../tools/art/source/coast_kit/coast_kit.blend)：15 个独立 collection，命名部件、材质和构造原点保留。
- [build_coast_kit.py](../../../tools/art/build_coast_kit.py)：只生成本套件 / 源文件，不写恶魔岛目录。
- [imports.py](../../../tools/art/source/coast_kit/imports.py)：15 件最小隔离导入项目，保留 null 默认项，最终导入后同步。
- [verify.py](../../../tools/art/source/coast_kit/verify.py)：独立读取导出 GLB，检查接口和实际导入参数。
- [package_review.py](../../../tools/art/source/coast_kit/package_review.py)：仅将已有截图排成审阅图，不包含示例布局。

从仓库根目录执行（验证需要 NumPy）：

```bash
source ~/.codex-zhaoyun/env.sh
nvidia-smi
flock ~/gs66-render.lock blender --background --python tools/art/build_coast_kit.py
python3 tools/art/source/coast_kit/imports.py stage
flock ~/gs66-render.lock godot --headless --path output/coast-kit/import-project --import
python3 tools/art/source/coast_kit/imports.py configure
flock ~/gs66-render.lock godot --headless --path output/coast-kit/import-project --import
python3 tools/art/source/coast_kit/imports.py sync
python3 tools/art/source/coast_kit/verify.py
```

提交后再做冷导入清洁检查：

```bash
python3 tools/art/source/coast_kit/imports.py stage
python3 tools/art/source/coast_kit/imports.py cold
flock ~/gs66-render.lock godot --headless --path output/coast-kit/import-project --import
python3 tools/art/source/coast_kit/imports.py sync
git status --short
```

所有 Blender / Godot（含 headless 导入）均持有 `~/gs66-render.lock`，私有 ADB 5099。渲染后脚本自行退出，没有挂编辑器。审阅 fixture 使用隔离 user dir，不读玩家存档、不连游戏服务。

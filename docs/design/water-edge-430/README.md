# SGODOT-430 · 通用水岸浪花审阅 v1

【刘备】5 件：直段、外转角、内转角、码头桩环、台阶下水口。2 m 模数，40 / 40 / 40 / 64 / 40 三角面，每件 1 surface。资源在 `assets/landmarks/_shared/water_edge/`；可编辑源和复现脚本在 `tools/art/source/water_edge_430/`。

## 审阅媒体

- [默认镜头 360×800](default-review.png)：原游戏镜头参数，正交宽 6.72 m、俯角 43°、偏航 14.5°；测试岸线整体朝向 65°，让约 12 m 岸线沿竖屏展开。
- [完整岸线](coast-overview.png)：六个 2 m 槽位，含两个转角、一个台阶口；码头为旁侧测试件。完整人物按 1.75 m 校准。
- [岸边近景](close-review.png)、[下水口近景](steps-review.png)。
- [4 秒无损循环动图](motion-review.apng)（[GIF 兼容版](motion-review.gif)）：540×720，60 帧 / 15 fps，默认参数，原速 4 秒一周期。逐帧用 Godot Mobile 渲染同一 shader，在隔离审阅中仅将 TIME 替换为取样时间；不是设备帧率录像。
- [Android 默认镜头](android-default.png)：API 37 / SwiftShader 软件模拟器，Godot Vulkan Mobile；底部按钮是隔离审阅控件。

使用 #831 `d72d74f4c0ccbcc922c5691cb8b6866eca1ca8f9` 的岸石、码头和台阶，仅读取到 output。**水线以上 0.25 m 的不透明湿带是本次 QA 模拟**；截止出图时 #831 尚未更新湿带。由此检查湿带与浪花的空间和透明层关系，不代表已验收赵云后续版本。没有改动海岸套件或恶魔岛文件，没有游戏接入或 layout 交付。

## 参数与适配

默认强度 0.8、颜色乘数 (1,1,1,1)、周期速度 0.25 Hz、沿岸 UV 往返幅度 0.018、透明度缓变幅度 0.06。速度设 0 即静止。新地标只需复制 / 调整 `.tres`，详细参数与端口说明见资源目录 README。

水位参考 Y=0.20 m（相对岸石 / 台阶根部），浪花放 Y=W+0.018 m。变水位仍需核对 XZ 接触线；它不是自动岸线投影。桩环对应 Ø0.22 m 的桩。岸线接头保持零端部淡出，自由末端 / 台阶口可在材质里设置单侧 0.10–0.12 的 U 淡出。

## 验证结果

- [几何检查](geometry-validation.json)：39 项通过；9 组有方向端口误差 < 0.000001 m；所有件无自交；测试摆位最多 1 层浪花。
- [Godot 资源检查](import-validation.json)：72 项通过；5 个生成 UID / `nodes/root_script=null`；1 surface；共享材质；无 next_pass；纹理 512×128 无损且带 mipmap。
- [渲染检查](render-validation.json)：Steam Deck VANGOGH / Vulkan Mobile。审阅场景启用浪花 22 draws，关闭为 14；8 个摆放实例各增加 1 draw，8 个实例合计 368 三角面，与实际计数增量相等。图片没有 HUD / 系统弹窗遮挡。
- [动画检查](motion-validation.json)：t=0 与 t=4 秒逐像素一致；相邻原始帧最大通道差 3/255，整体每帧平均变化不超过 0.0111/255。低幅缓变，不闪烁。
- [Android 冒烟](android-smoke.json)：真实按钮点击切近景、关浪花、再开；Mobile 渲染正常，安装 APK 全包读回 SHA-256 一致；测试结束停止 QA app、恢复模拟器分辨率 / 密度。
- [冷导入](cold-import-validation.json)：空 `.godot` 缓存重新导入，交付目录所有文件（含 UID、`.import`）SHA-256 完全一致。

沿用 #824 原贴图字节。每像素仍为 **1 次纹理采样、1 个透明 pass、最多 1 层浪花**；无 screen / depth 采样或额外投影 pass；湿带是岸石的不透明着色。新增少量顶点动画算术，没有物理手机 GPU 耗时结论。样稿仅作复用及画面验收，不构成上线或整岛性能验收。

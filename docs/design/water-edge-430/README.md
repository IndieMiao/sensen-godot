# SGODOT-430 · 通用水岸浪花 v1.1

【刘备】按 430 技术意见 `9ca1f169`、画面意见 `bfe0485c` 调整连续白边、外缘碎形和推收。运行实现只变 `water_edge.gdshader` 与 `water_edge_material.tres`；5 个 GLB、原纹理、UID / `.import` 均与 `13f4dcaab` 字节一致。

## 画面与运动

- [default-review：360×800](default-review.png)，[v1 / v1.1 对比](default-comparison.png)。正交宽 6.72 m、俯角 43°、偏航 14.5°；保留上一版场景、光照和岸线朝向。
- [5.5 秒 GIF](motion-review.gif)；[无损 APNG](motion-review.apng)。360×800、110 帧、20 fps，按实际时间播放完整周期。Godot Mobile 逐帧渲染同一 shader，仅在 QA 把 TIME 替换为采样时间，不是设备帧率录像。
- [岸边近景](close-review.png)、[桩根近景](pile-review.png)、[台阶口](steps-review.png)、[完整约 12 m 岸线](coast-overview.png)。
- [Android 默认图](android-default.png)：API 37 / SwiftShader 软件模拟器，Vulkan Mobile；实际运行生产 TIME 时钟，底部为隔离审阅按钮。

新 shader 将原纹理中心线的变化用于外缘噪声，贴岸使用连续约 0.7 的覆盖，不再被原图的透明断点切开。外侧软渐隐，在固定单层面片内向外展开、向内收回；没有移动模型顶点。内转角 / 台阶相接处的端部淡出设为 0，自由末端仍淡出。

## 新参数

| 参数 | v1.1 |
|---|---:|
| intensity | 0.70（现在直接表示贴岸覆盖透明度） |
| foam_color | (1,1,1,1) |
| cycle_speed_hz | 0.18181818，即 5.5 s / 周期 |
| push_distance_m | 0.10，外缘峰到峰距离 |
| edge_noise_m | 0.055，碎形幅度上限 |
| edge_softness_m | 0.14；窄桩环自动限制为可用外缘宽度的 65% |
| edge_margin_m | 0.005 |
| end_fade_uv | 接合端 (0,0)，自由端单侧 0.12 |

旧的 `drift_uv` / `breath_amount` 已移除。直段、转角和桩环共用新 shader，用局部坐标 / UV 导数换算横向米数；原图仍只读一次，提供颜色和外缘噪声。颜色、强度、周期等继续只改 `.tres`。

## 实渲量测与验证

[外缘与运动量测](edge-motion-validation.json) 用 Mobile 顶视诊断图：只把 albedo 设白、背景设黑，保留生产 alpha；将截图 RGB 解码为线性 alpha，以 alpha>0.02 定义可见轮廓。

| 检查 | 结果 |
|---|---|
| 默认展开相位直岸水侧白边宽度 | 0.298–0.340 m，均值 0.318 m |
| 贴岸 / 内转角接触线透明度 | 0.701（图像量化值） |
| 直岸外缘峰到峰位移 | 均值 0.1001 m |
| 桩环外缘峰到峰位移 | 均值 0.0933 m；窄环软边自适应使阈值轮廓略小于参数 0.10 m |
| 2 Hz 抽帧 | 直段、内角、桩环各 11 对相邻帧中 10 对有明确位移；2.5 / 3.0 s 对称于 2.75 s 转折点，轮廓相同 |
| 5.5 s 首尾 | 逐像素一致 |

默认图是展开相位；回收时外缘自然缩回约 0.10 m，贴岸保持实白。桩环沿用小桩原面片的范围，宽度按原件尺寸，运动距离与岸线一致。

- [保留检查](preservation-validation.json)：14 个模型 / 原图 / 导入 / UID / manifest 文件与 v1 完全一致；恶魔岛、海岸件和海面未改。
- [资源检查](import-validation.json)：72 项通过。5 件仍各 40 / 40 / 40 / 64 / 40 三角面、1 surface；原 512×128 无损 mipmapped RGBA 贴图。
- [渲染检查](render-validation.json)：Steam Deck VANGOGH / Vulkan Mobile；默认图仍为 22 draws，关闭浪花 14 draws，8 个单层实例合计 368 三角面，预算与 v1 一致。
- [Android 检查](android-smoke.json)：实际点击切近景、关 / 开浪花；安装 APK 全包读回一致。[包内资源](android-package-validation.json) 包含 5 场景和 1 纹理。
- [冷导入](cold-import-validation.json)：空缓存重新导入，17 个交付目录文件哈希一致。单采样、单透明 pass、单层覆盖保持 #824 预算；新增轮廓算术，无物理手机 GPU 耗时结论。

审阅仍使用 #831 `d72d74f4` 的 2 m 海岸件，水位相对根部 Y=0.20 m、浪花 Y=W+0.018 m。0.25 m 岸石湿带为上一版同样的 QA 不透明模拟；码头木板由赵云另改，本件没有动。没有 layout 或游戏接入。

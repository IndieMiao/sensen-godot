# SGODOT-428 · v1.1 沙与木返修 · 刘备

依据技术检查 `456c5d0a` 和不知火舞画面意见 `9a6eb557`，在 #830 原头 `54b76f78f` 上只修改 `assets/landmarks/_shared/ground_detail/`。已通过的草与铺石保持；恶魔岛 #827 的木纹、材质和全部文件无变化。

## 画面与结果

[default-review.png](default-review.png) 是 **360×800** 默认镜头，已标注干湿沙差；底部46px为审阅说明，完整无标注图是 [default.png](default.png)。原光照／镜头不变（宽6.72m、43°、14.5°）。[木地板近景](wood-close-review.png) 显示0.18m板宽、1.8m板长、相邻排半块错缝和逐板深浅；其脚注注明干湿沙数值来自匹配的默认视角。另保留前一版本同镜头图及[沙地近景](sand_close.png)。

**干湿沙差：默认26.15%，沙地近景26.16%，均≥15%。** 默认干沙平均Y′=0.85549，湿沙=0.63179，共54474／36061个像素。用输出sRGB `Y′=(.2126R+.7152G+.0722B)/255` 的区域平均值，差为 `(干−湿)/干`；独立分类、内缩1px、同光照控制，排除潮线深带，不挑最暗点。原始数据与遮罩见 `brightness-validation.json`、`*-sample-mask.png`、`*-sampling.png`。

已通过部分的同镜头保全：草53513像素、铺石40811像素、干沙54474像素，与54b76f78f的最大RGB差均为 **0**；深草／普通草差仍22.75%。没有通过改灯光制造亮度差。

## 参数变更

| 参数 | 原值 → v1.1 | 用途 |
|---|---|---|
| `wet_sand_color` | `#9B8F70 → #A68B63` | 同干沙的暖褐色系，压低亮度、略提饱和；识别键保持原值 |
| `tide_color` | `#817C63 → #856C4A` | 暖褐沉积深带 |
| `tide_transition_m` | `.45 → .65 m` | 加宽干湿柔边 |
| `tide_band_width_m` | `.14 → .23 m` | 加宽深带的渐隐半宽 |
| `tide_band_strength` | `.28 → .22` | 保留深带，降低污渍感 |
| `wood_color / light / dark` | `#BB8B52 / #D0A56C / #9A7046 → #A3815D / #B89972 / #795F47` | 从橙色压成暖木褐 |
| `wood_board_size_m` | 新增 `(1.8, .18)` | 沿投影X长度1.8m、Z宽0.18m |
| `wood_board_stagger` | 新增 `.5` | 相邻排板头错半块 |
| `wood_joint_width_m` | 新增 `.012 m` | 板缝总宽，像素导数抗锯齿 |
| `wood_joint_color` | 新增 `#695440` | 暗木色板缝 |
| `wood_board_tone_strength` | 新增 `.14` | 逐板反照率最大±14%，显示空间变化更柔和 |

新值同时写入shader默认值和相关 `.tres`（混合、木、湿沙），便于换地标只改材质。所有顶点色识别键不变。配色参照现有码头小件 `AB8257 / C5A173 / 795F47` 和农场木色族；仅取参考，未改其资产。

板缝、错缝与逐板色差用坐标计算；静态算术hash，无新增纹理。木仍1次采样，草3次、铺石1次、沙／湿沙2次，2个sampler、单不透明pass。新增导数与坐标计算有ALU成本，不声称GPU周期完全相等；没有新增采样／pass／透明／屏幕效果。两张打包图、import、UID与54b76f78f逐字节相同。

## 验证与复现

Godot4.7.2 / Steam Deck Vulkan Mobile完成20项渲染检查：默认、木与沙近景均1个可见地表draw，静态帧完全相同，强度0回退仅保留既有8bit舍入差。Android API37 SwiftShader上的默认／木／沙图、两次真实按钮点击及完整安装包回读通过；回读包六份材质和新参数另行加载验证。仅模拟器检查，不是物理手机性能结果。

全新缓存冷导入后13个运行资源前后hash完全相同，PNG import与shader UID保留，详见 `cold-import-validation.json`。审阅目录有`.gdignore`，不生成运行贴图或进入游戏。无新增模型导入。

本目录的脚本复用原 `tools/art/source/ground_detail_428/`，不修改它。先运行 `prepare_revision.py`，再在 `output/ground-detail-428-v11/project` 用Godot导入／渲染，最后运行 `measure_revision.py`。所有Godot命令使用 `flock /home/deck/gs66-render.lock`；桌面需有效DISPLAY/XAUTHORITY。Python测量需要NumPy/SciPy/Pillow。

Android可按旧 `prepare_android.py` 将该隔离项目复制到 `android-project`，QA标识改为`428-v1.1`，第二个视角目标改为(0,.25,0)，构建版本42802 / 428-ground-v1.1；仍用仓库 `tools/android/run_test.sh` 运行本目录 `android_smoke.py`，最后运行 `verify_revision.py`。它从实际安装包读回检查，并要求全新`cold-project`目录。输出均在忽略的output目录；审阅资料只写入本共享目录。

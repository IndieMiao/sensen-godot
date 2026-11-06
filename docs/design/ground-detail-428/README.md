# SGODOT-428 · 通用地表细节材质 · 刘备

交付目录：[`assets/landmarks/_shared/ground_detail/`](../../../assets/landmarks/_shared/ground_detail/README.md)。草坡、铺石、木纹、沙滩、湿沙／潮线共用一个 shader、两张1024²打包贴图；提供五份单材质预设和一份顶点色混合预设。**独立交审，不接入游戏、不交 layout。恶魔岛资产、模型、UV、参数及其文档均无修改。**

基础版本：`a5ff682d1031a8edb31e7c8d5081c42b4bc520d2`（#827 合并后主分支）。来源是 #827 v1.1 已审草地、克制铺石及木纹；两张共享PNG与原版逐字节相同，沙地启用原已打包的矿物细纹B通道。所有识别键、输出色、尺度、投影和潮线参数可在 `.tres` 调整；完整58项表与接入例子见资产README。

## 审阅图

| 图片 | 范围 |
|---|---|
| [默认镜头与采样轮廓](default-review.png) | 原始每侧360×800，正交宽6.72m，俯角43°，偏航14.5°；从上到下为草／石／木／干沙／湿沙 |
| [整块地形](whole-review.png) | 20×20m，浅坡高差0.5m；明确采用28m广角，便于看完整测试范围 |
| [草坡近景](grass_close-review.png) | 三色大块、碎边和短叶细纹；8m镜头 |
| [石板和木纹近景](hard_close.png) | 5.5m镜头；缝与木纹保留#827幅度 |
| [沙与湿沙近景](sand_close-review.png) | 6m镜头；柔边潮线、低对比沉积带和哑光湿沙 |
| [Android默认](android-default.png)、[草](android-grass.png)、[沙](android-sand.png) | 原生360×800软件Vulkan模拟器，底部为仅QA使用的切换按钮 |

这是材质测试台，不是地标布局。地形只存在于隔离审阅脚本：一个 surface、3200三角面，不需要UV、碰撞、导航、账号或游戏代码。所有主图都是Godot实际渲染；边框和测量说明在画面外添加。`default / whole / grass_close / sand_close.png` 是未标注原图。

## 实渲亮度

| 视角 | 深草相对普通草 | 湿沙相对干沙 |
|---|---:|---:|
| 默认360×800 | **22.75%** | **25.44%** |
| 整块地形广角 | 22.87% | 25.11% |
| 各自近景 | **22.71%** | **25.46%** |

默认深草／普通草均值为0.49763／0.64416（1029／9104像素）；湿沙／干沙均值为0.63786／0.85549（37116／54474像素）。使用输出sRGB像素 `Y′=(.2126R+.7152G+.0722B)/255` 的区域平均值，差为 `(浅均值−深均值)/浅均值`，不冒称物理线性光亮度。草深浅满足≥15%；沙与湿沙同样清楚区分。

通过独立分类渲染取得纯色内部，内缩1像素；再用统一反照率、相同暖光的控制图过滤到参考亮度±0.008。使用余下的全部样本，不挑最暗点，也不把潮线沉积暗带算进湿沙均值。原始数据见 [brightness-validation.json](brightness-validation.json)，`*-sample-mask.png` 保留逐像素集合，`*-sampling.png` 显示轮廓。

灯光复用#827数值：天空环境色#D5E4EE / 强度0.72，太阳旋转(-56,-34,0)、色(1,.965,.88)、强度0.98，阴影不透明度0.48；2048阴影、滤波2、4×MSAA。没有为满足对比而减弱暖光。

## 预算与验证

- 2个sampler，草3次／铺石1次／木1次／干沙2次／湿沙2次采样，未匹配0次；最高仍3次。单不透明pass，无TIME、alpha、深度、屏幕、法线或水采样。潮线复用宏观场，不加采样。
- 两张1024² RGB打包数据图：带mipmap、高质量BPTC／ASTC。安装包中两个ASTC资源各1,398,180字节。新着色逻辑增加颜色分类和潮线计算；没有声称GPU耗时与旧版逐周期相等。
- Godot4.7.2 / Vulkan Mobile / Steam Deck VANGOGH：23项保存／静态帧／回退检查通过，五个主视角均1个可见地表draw。固定相机的两张图逐字节一致。强度0与StandardMaterial原顶点色相比仅13个像素有1/255舍入差，平均最大通道误差0.000045/255；不是可见色差。
- 取消匹配键后，38182个草色样本与原顶点色最大RGB差0；强制类型可跳过键识别。六份材质加载及纹理mip检查通过。见 [parameter-validation.json](parameter-validation.json)、[render-validation.json](render-validation.json)。
- Android API37 / emulator-5592 / SwiftShader Mobile：五类材质均显示，两个真实ADB点击切换草和沙近景通过，截图已逐张查看。安装APK完整回读相等，回读包中的六份材质、着色器和ASTC纹理再次加载检查通过。默认与桌面画面上735行的平均RGB差0.523/255（压缩及平台边缘有差异）。见 [android-smoke.json](android-smoke.json)、[packaged-resource-validation.json](packaged-resource-validation.json)。这不是物理手机性能验收。
- 全新空 `.godot` 缓存冷导入：13个交付资源前后SHA-256完全相同，包含PNG的`.import` UID和shader UID；未生成脏资源。见 [cold-import-validation.json](cold-import-validation.json)。没有GLB／FBX场景导入，故`nodes/root_script=null`不适用于本交付的texture importer，不添加无效参数。
- 运行与导入使用 `/home/deck/gs66-render.lock`；Android通过仓库session runner运行，测试后应用停止，模拟器恢复此前720×1280／默认密度。未发布或交付APK。

## 复现

源目录 `tools/art/source/ground_detail_428/` 保持 `.gdignore`。`generate.py` 使用NumPy/SciPy/Pillow重建共享PNG；只改共享目录。`prepare.py` 建立 `output/ground-detail-428/project`（外层有`.gdignore`，避免污染主项目类扫描）。

```sh
python tools/art/source/ground_detail_428/prepare.py
flock /home/deck/gs66-render.lock godot --headless --path output/ground-detail-428/project --editor --import
flock /home/deck/gs66-render.lock godot --headless --path output/ground-detail-428/project --script res://configure_imports.gd
flock /home/deck/gs66-render.lock godot --headless --path output/ground-detail-428/project --editor --import
flock /home/deck/gs66-render.lock godot --path output/ground-detail-428/project
python tools/art/source/ground_detail_428/measure.py
python tools/art/source/ground_detail_428/cold_import.py
```

运行有图形的Godot时需要有效DISPLAY/XAUTHORITY。`cold_import.py`要求新的`cold-project`目录，保留旧证据后换一个新目录再复测，不删原文件掩盖差异。`prepare_android.py`建立独立应用`com.sensen.groundkit428qa`；按仓库`tools/android/run_test.sh`在私有ADB session内运行`android_smoke.py`，随后`verify.py`验证实际安装包与参数回退。SDK和APK仅留在忽略的output目录。

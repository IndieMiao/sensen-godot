# 环境图反射与灯光驱动的水面高光

**后续视觉方案已更新：** 用户否定本版长条高光，随后提供可访问的 80.lv 拆解。最新实现参考原作者演示和双层纹理阈值方法，见[2026-09-30 记录](../pond-water-breakdown-2026-09-30/README.md)。本页保留环境反射接入的历史证据。

2026-09-29 至 09-30。用户否定上一版像漂浮物的白斑，明确要求 env 图反射和有形状、与光照模型关联的高光。本轮替换高光生成方式；此前确认的水深色阶、石床和游戏规则保留。

参考为用户提供的[环境反射图](environment-reference.png)和[上一版问题标注](floating-highlight-feedback.png)。Pinterest 短链 `https://pin.it/5hsuma4ea` 跳转到 `api.pinterest.com` 时持续连接超时，浏览器连接列表也为空，本轮没有看到或声称复现该链接的视频。

## 修改

- 删除按网格生成、平移和呼吸的白斑函数，删除其白色 `EMISSION` 叠加。
- 恢复 Godot 标准 GGX 镜面光照。水面使用高度函数导出的动态法线，波峰弯曲时实际反射方向随之变化。法线也驱动折射和现有岸边倒影扰动。
- 增加 1024×512 线性 HDR 环境图，经 `PanoramaSkyMaterial`／`Sky` 生成 256 像素辐射立方体，接入 `Environment.REFLECTION_SOURCE_SKY`。反射由引擎按观察方向、法线、粗糙度和 Fresnel 计算。
- 太阳仍为场景里的 `DirectionalLight3D`。镜面强度 0.13、角尺寸 1°；水面基础粗糙度 0.19、`SPECULAR=0.35`，并用屏幕法线变化适当增加粗糙度以降低小画面闪烁。横向小波切分较长的波峰反光，避免整片等长亮带。
- 环境图含天空、宽云层和低处树线，太阳没有重复画进环境图。它是程序生成的远景光照环境，并非当前场景的实时全景捕获；原有近岸平面反射保留。

原有水色合成仍承担水底、吸收、散射和焦散表现；原来的少量底色填充仍保留。新增太阳高光不来自这个填充，而来自引擎灯光。反射自然会使局部像素变亮，不能再沿用上一轮“所有选定色样完全不变”的结论。

## 直接查看

- [旧白斑／新反射效果对照](../../../output/pond-reflection-2026-09-29/before-after-final.png)
- [最终 Android 动态视频](../../../output/pond-reflection-2026-09-29/android-final/water-motion-android.mp4)
- [关灯、关环境、关闭波纹及旋转视角对照](../../../output/pond-reflection-2026-09-29/lighting-controls-final.png)
- [HDR 环境图的色调映射预览](../../../output/pond-reflection-2026-09-29/environment-preview.png)
- [验证记录](../../qa/pond-reflection-2026-09-29.md)

环境图源文件是 `assets/ponds/art/pond_daylight.hdr`，绑定资源为 `pond_daylight_sky.tres`，由 `tools/art/bake_pond_environment.py` 确定性生成。运行 `tools/dev/open_pond_art.command` 查看实际动态效果。

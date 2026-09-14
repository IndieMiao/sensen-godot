# 地面与光影精修

本轮继续按原设计图调整草地、土壤、田埂、实时阴影和前后景层次。改动已接入正式农场与七种外观预览，原有田块 ID、种植规则和存档不变。

- [参考图 / 调整前 / 本次对照](comparison.png)：前后采用相同的 480 × 900 视口、1024 阴影贴图与低档柔化过滤；参考图裁取小房子方案。
- [七种外观实景](lineup.png)
- [390 × 844 正式农场](phone.png)、[360 × 640 正式农场](short-phone.png)、[1280 × 720 正式农场](desktop.png)
- [重新打开预览](../../../../tools/dev/open_farm_art.command)

## 相机与阴影

原正交相机使用默认 `near = 0.05`、`far = 4000`。Godot 在正交相机下不使用平行光的 `directional_shadow_max_distance` 来限制阴影视锥，因此原有的 24 米设置未能收紧范围。可在 [Godot 渲染器源码](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_scene_cull.cpp) 的 `_light_instance_setup_directional_shadow()` 中确认这一分支。

现在 `FarmCamera.fit_ground_depth()` 依据整个可见视口、地面高度和 4 米树冠上界计算 near/far，保留 0.5 米余量，以 0.5 米为步长向外取整。极端拉远时，必要的后移沿相机视线进行，保持正交投影中的构图。正式农场会在跟随、拖动和缩放后更新这两个裁剪面；地图原有的相机适配函数调用方式保持兼容。

七款预览的裁剪范围为 3～23 米或 2.5～23.5 米。正式农场各视口的数值保存在 [交互检查结果](checks.json)。阴影继续使用单张正交贴图，`shadow_bias = 0.1`、`shadow_normal_bias = 1.0`、`shadow_blur = 0.9`，关闭距离淡出；pancake 范围为 4 米。阳光方向改为 `(-51, -38, 0)`，能量为 1.1；冷色环境补光降至 0.42，阴影不透明度为 0.82。

## 地面与层次

Blender 土壤顶色改为 `#af906a`、侧面为 `#96764f`，田埂从近白色改为 `#dfcb94`。512 × 512 草地纹理由各向同性、可重复的多尺度噪声生成，去掉旧纹理的斜向波纹，减弱前景的大块色差。土壤复用这张纹理的单通道色差，保持不透明。

田埂使用一个共享的透明材质，只在轮廓内侧窄幅羽化，柔化土路与草地的交界。它是贴地的单层网格，不增加网格数或灯光；其余模型仍为不透明材质。路径边缘的透明混合有少量像素开销，本机采样未增加绘制调用。

林缘在固定世界坐标中逐渐偏冷、偏深，远处树木使用同一个 MultiMesh 的实例乘色。小草和花更多集中在后方，前景留出明亮草坪。远近色差是场景配色，实时树影、房屋和作物阴影仍由同一盏太阳光产生，拖动镜头不会带着色彩分区移动。未启用 SSAO、实时 GI、景深或额外点光源。

## 验证

- Godot 4.7.2 / Metal Mobile / Apple M4。32 项相机、资产、作物和场景测试通过，包含短屏、宽屏、拖动、缩放弹性范围与人物跟随时的裁剪覆盖。
- [六组正式农场视口检查](checks.json) 检查渲染、田块触摸、行走、拖动、挂起和恢复，最小田块宽度为 49.1～56.7 像素。
- [七款外观采样](metrics.json) 检查相隔 30 帧的动画像素变化，并关闭阴影再截图，确认有足够的像素受到真实投影影响。普通场景仍为 41～49 次绘制调用、约 6.2～15.2 万渲染图元，150 帧采样的 P95 帧间隔为 8.78～9.04 ms；[调整前样本](before-metrics.json) 记录了原有的 4000 米远裁剪面。
- [12 块成熟洋甘菊采样](stress-metrics.json) 为 43 次绘制调用、175,070 渲染图元、P95 帧间隔 8.91 ms。GPU 时间计数器仍不可用；报告中的 0 不代表 GPU 零开销。
- 另外检查了 1024 贴图、硬阴影过滤的低档设置：投影存在，边缘有更明显的台阶。预览的覆盖参数只作用于该预览进程；未更改项目的全局阴影贴图大小或过滤设置。

这些是带垂直同步的短时桌面采样，不能用于推断 Android 真机帧率或温升。本轮未重复完整的历史回归；上一轮在原版本中复现的 HUD 目标排序旧断言失败见上级制作记录。

## 复现

```sh
FARM_ART_CAPTURE=output/farm-art-2026-09-10/lighting/final FARM_ART_ALL=1 \
FARM_ART_SHADOW_SIZE=1024 FARM_ART_CHECK_SHADOWS=1 \
  /Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 480x900 tools/dev/farm_art_preview.tscn

FARM_ART_CAPTURE=output/farm-art-2026-09-10/lighting/gameplay FARM_ART_SHADOW_SIZE=1024 \
  /Applications/Godot.app/Contents/MacOS/Godot --path . tools/dev/farm_art_probe.tscn

GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
  ./addons/gdUnit4/runtest.sh -a res://tests/farm/test_farm_camera.gd \
  -a res://tests/farm/test_farm_art.gd -a res://tests/farm/test_farm_props.gd \
  -a res://tests/farm/test_crop_field.gd -a res://tests/farm/test_place_scenery.gd
```

`FARM_ART_SHADOW_FILTER=0` 可检查硬阴影降级设置；`FARM_ART_STYLE=windmill FARM_ART_CROP=H` 可检查 12 块成熟洋甘菊。

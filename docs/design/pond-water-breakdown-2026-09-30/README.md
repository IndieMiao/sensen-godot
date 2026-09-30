# 根据 Josh 的水体拆解重做闪光

2026-09-30。用户再次否定长条状高光，并提供 80.lv 文章。这次已实际读取原文、作者的材质节点图和 10 秒演示，同时查看文章引用的视频讲解。

## 已核对的来源

- [80.lv：A New Breakdown on Creating Stylized Water in UE5](https://80.lv/articles/a-new-breakdown-on-creating-stylized-water-in-ue5)
- [Josh 的原始演示与拆解线程](https://x.com/heyitsjosh3D/status/1575848845153427456)
- [SingleLayerWater／吸收曲线节点图](https://x.com/heyitsjosh3D/status/1575848852866768896)
- [Josh 对闪光方法的说明](https://x.com/heyitsjosh3D/status/1575848855752495104)
- [Jasper：How scrolling textures gave Super Mario Galaxy 2 its charm，10:44 起](https://www.youtube.com/watch?v=8rCRsOLiO7k&t=644s)

关键做法是两层不同方向流动的纹理交叠，再通过两个阈值留下较柔和的表面层和极亮部分。亮部的形状会生长、合并、分裂和消退。Josh 的节点图将闪光输出接到 Emissive，并从同一个函数输出 Normal；这与上一版用少量强方向长波法线制造连续 GGX 亮带不同。

本机直接请求部分外站时连接重置。读取当前 `scutil --proxy` 后，使用系统已经启用的本地代理成功取得公开资料；没有修改系统代理、读取浏览器凭据或使用登录账号。此前未取得 Pinterest 内容的记录保留为历史，不能继续把“外站不可访问”当成本轮限制。

## 本轮适配

1. 使用自行生成的周期性纹理：R 为平滑噪声高度，G/B 为相同高度场的导数；不把教程或游戏提取纹理加入运行资产。
2. 两个尺度、方向和速度不同的采样共同形成高度场，低阈值控制环境反射表面层，高阈值形成不规则闪光。去掉产生长斜条纹的解析长波组合。
3. 保留 HDR 环境图、近岸倒影及已确认的水深色阶。法线来自同一纹理场，使表面扰动和闪光形变一致。
4. 与作者直接输出发光不同，本项目把风格化闪光放入 `light()` 的 `SPECULAR_LIGHT`，继续接受真实灯光颜色、镜面强度、阴影和观察方向影响。它是参考方法的风格化适配，不宣称是完整 UE5 SingleLayerWater 移植或严格物理水体。
5. 纹理开启 mipmap，阈值边缘按像素导数平滑；最终闪光强度降低到 4，避免一片纯白色块。

## 当前素材

- [旧斜向亮带／新版闪光](../../../output/pond-water-breakdown-2026-09-30/before-after.png)
- [Android 动态视频](../../../output/pond-water-breakdown-2026-09-30/review-android/water-motion-android.mp4)
- [连续时间帧](../../../output/pond-water-breakdown-2026-09-30/motion-frames.png)
- [验证记录](../../qa/pond-water-breakdown-2026-09-30.md)

生成器为 `tools/art/bake_pond_ripple_field.py`，水体材质为 `modules/ponds/pond_water.gdshader`。运行 `tools/dev/open_pond_art.command` 查看实际动态效果。

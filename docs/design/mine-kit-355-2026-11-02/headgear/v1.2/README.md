# 石英晶簇 v1.2

黄忠，2026-11-02。按不知火舞 355 / c3844aa6 及上官婉儿确认，只把石英 v1.1 整体放大约 1.3 倍，再将放大的底部贴合原来的头顶曲面。
王冠和铁背 GLB 保持各自已通过版本的 SHA-256，三件文件名、原点和导入 UID 不变。

**头饰按 r=1.0 归一化，游戏里随王的半径缩放。** 本次矿内图使用周瑜当前史莱姆王半径 r=0.85。

| 石英数据 | r=1.0 归一化 | 游戏 r=0.85 |
| --- | ---: | ---: |
| 宽 | 0.9004 m | 0.7653 m |
| 深 | 0.5939 m | 0.5048 m |
| 实测总高 | 0.7675 m | 0.6524 m |
| 高于头顶原点 | 0.7026 m | 0.5972 m |
| 挂载 Y | 1.4300 m | 1.2155 m |

原 v1.1 头顶以上 0.5375 m，在 r=.85 时约 0.4569 m；本次到约 0.5972 m。
X/Z 跨度实测恰为原来的 1.3 倍，底部重贴曲面使 Y 不采用整个网格简单缩放。
五根向外散开的尖端晶柱、白底淡紫尖、各面色值与材质保持；仍 280 三角形、单 surface，不透明，无骨骼/动作/碰撞。

交付一张原始 360×800 红岩矿默认 43°，游戏 zoom=.8、水平视宽 7.5 m，旁边是真实玩家 H=1.745 m。
图上明确 r=.85，避免把归一化和游戏尺寸混用；身体颜色仍由程序选择，审阅延续粉色提案。
另附 GLB/UID/颜色及贴合验证 JSON；代码仍使用实际 `_slime_body(1.0)` 三角面检查底部。
76 项独立检查通过，7,838 个有效接触射线采样无超过 1 mm 穿插，最小间隙约 0.99 mm。
渲染为 Godot 4.7.2 Vulkan Mobile / RTX 2060；未改玩法、未合并或发布，没有手机性能结论。

复现及同色验证：

```sh
git -C output/monsters-355/runtime show 46730b6d:assets/monsters/slime_king/quartz_cluster.glb > output/mine-kit-355/quartz-v11.glb
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/monsters/slime_king/build.py -- --only quartz_cluster
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/prepare_review.py headgear
source ~/.codex-huangzhong/env.sh
godot --headless --path output/mine-kit-355/headgear/project --editor --import > output/mine-kit-355/headgear/import.log 2>&1
godot --path output/mine-kit-355/headgear/project --rendering-method mobile --rendering-driver vulkan -- --quartz-v12 > output/mine-kit-355/headgear/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/verify.py headgear --compare-quartz output/mine-kit-355/quartz-v11.glb
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/package_headgear_v12.py
```

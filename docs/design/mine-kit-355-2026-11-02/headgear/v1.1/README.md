# 守关头饰 v1.1

黄忠，2026-11-02，按上官婉儿转不知火舞 355 / 89a48ae7 返修，待复验。
王冠 GLB 与通过的 v1 完全相同，只补矿内图。三件的文件名、原点、挂载 Y=1.43*r 和导入 UID 保持。

| 件 | 三角形 | surface | 宽 × 高 × 深（m） |
| --- | ---: | ---: | --- |
| crown | 728 | 1 | 0.614 × 0.428 × 0.663 |
| ironback_plates | 672 | 1 | 1.020 × 0.837 × 1.625 |
| quartz_cluster | 280 | 1 | 0.693 × 0.584 × 0.457 |

铁背五片甲扩大成相接的宽壳，前护额宽 0.94 m，超过眼睛外侧；主铁色 4B6072，暖磨损边 AD9875，八个亮铆钉 E0C99C。
总宽从 0.46 m 增至 1.02 m，覆盖 r=1 史莱姆头顶中部。几何仍贴实际非球面轮廓，背面延伸朝 -Z。
石英改五根不同长度、向外倾斜的六棱晶柱，尖端削尖；底部白，尖端淡紫，棱面明暗交替。
这次石英按返修要求保留几何棱面，王冠和铁背仍为平滑法线，均不透明、无贴图。

每件补红岩 F1 和紫灰岩 F3 默认 43° 游戏镜头。每栏保持原始 360×800，沿用游戏 FarmCamera，zoom=.8、实际水平视宽 7.5 m。
旁边是实际 Avatar 装配、按顶点实测调至 H=1.745 m 的玩家；王的审阅替身 r=1.0 m，身体配色仍为提案。
另外保留各件三视图和挂载近景，铁背加后视，合计九张图加一份验证 JSON。

70 项独立 GLB/导入/UID 检查及 Godot 4.7.2 Vulkan Mobile 实渲检查通过。
47,039 个实际史莱姆网格射线采样无超过 1 mm 穿插；最小间隙王冠 3.35 mm、铁背 0.58 mm、石英 0.98 mm。
采样方式和顶部小开口封盖说明见上一版 README。实渲、manifest 和交付 GLB 的 SHA-256 一致。
没有改客户端接入、王的半径规则或既有怪物，没有合并或发布，没有手机性能结论。

保留王冠的复现命令：

```sh
blender --background --factory-startup --threads 2 --python-exit-code 1 --python tools/art/source/monsters/slime_king/build.py -- --only ironback_plates quartz_cluster
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/prepare_review.py headgear
source ~/.codex-huangzhong/env.sh
godot --headless --path output/mine-kit-355/headgear/project --editor --import > output/mine-kit-355/headgear/import.log 2>&1
godot --path output/mine-kit-355/headgear/project --rendering-method mobile --rendering-driver vulkan > output/mine-kit-355/headgear/render.log 2>&1
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/verify.py headgear
output/art-setup/venv/bin/python tools/art/source/mine_kit_355/package_headgear.py --stage v1.1
```

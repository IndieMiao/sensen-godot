# 农场参考图美术重制 · 2026-09-10

最新一轮见 [地面与光影精修](lighting/README.md)，包含参考图对照、1024 阴影贴图验证、相机裁剪修正和最新测试结果。下文保留第一轮制作记录。

本轮将用户提供的七种农场参考图落实为 Blender 资产和 Godot 场景。正式农场默认使用橙顶小房子；七种建筑可在独立美术预览中切换。该实现不是建筑解锁系统，也不代表 Android 真机性能或自然玩家体验已验收。

## 查看

- [用户参考图](reference.jpeg)
- [Godot 七种外观实景](reference-lineup.png)
- [正式农场：390 × 844，9 块田](gameplay-phone.png)
- [正式农场：360 × 640，12 块田](gameplay-short-phone.png)
- [正式农场：1280 × 720，12 块田](gameplay-desktop.png)
- [Blender 源文件](../../../tools/art/source/farm_reference_kit.blend)
- [可交互预览场景](../../../tools/dev/farm_art_preview.tscn)

macOS 可以运行 `tools/dev/open_farm_art.command`。预览中的下拉菜单切换建筑，点击草地行走，拖动与滚轮调整镜头；该入口不建立网络会话、不发送农场命令、不写入 FarmChoice 或农场存档。

## 已实现

七种房屋：橙顶小房子、蘑菇屋、茅草木屋、蓝顶圆屋、东亚屋檐、美式农舍、风车屋。共 24 个 GLB，另有一张 512 × 512 草地色彩纹理。Blender 源文件保留分组件命名、材质和可编辑倒角，导出副本合并为每个资产一个网格、一个材质面。

配套物件包括石井、种子箱、围栏、木牌、踏步石、三种树、灌木、草丛、石块和三色小花。正式农场使用连续浅色田埂、圆角土畦、更柔和的作物与垄沟，调整了地面色彩、环境补光和主光阴影。烟囱使用 5 个 GPU 动画实例；风车仅旋转一个独立网格。

镜头同时容纳房屋、田块及出生位置，房屋外轮廓在创建场景时计算一次。短屏降低俯视角，种子栏使用图标加数量；宽屏种子横排。保留作物图标、数量、选择状态、禁用状态和名称工具提示。

正式农场仍显示服务器已有的 9 块田或扩建后的 12 块田。参考图中的 4 / 9 / 12 块组合只用于美术预览，不修改播种能力、成长、解锁、服务端 ID 或存档。改动只调整客户端内部建筑、井、围栏、树干和出生位置，遮挡区域同步更新寻路网格。

## 资产预算

| 建筑 | 三角面 |
| --- | ---: |
| 小房子 | 7,504 |
| 蘑菇屋 | 2,420 |
| 小草屋 | 10,256 |
| 蓝顶圆屋 | 3,064 |
| 东亚建筑 | 6,248 |
| 美式农舍 | 6,800 |
| 风车屋 | 7,060，另有 680 面旋转叶片 |

静态重复物件通过 MultiMesh 合批；所有 GLB 共用不透明顶点色材质，局部遮蔽已烘入线性顶点色。继续使用 Godot Mobile 渲染器及一盏有阴影的平行光，不启用 SSAO、实时 GI 或额外点光源。Godot 导入保留自动 LOD 和阴影网格。作物继续使用原有固定批次，生长与成熟阶段仍由服务器时间或访客快照派生。

## 复现

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/art/build_farm_assets.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/dev/farm_art_preview.tscn
```

单独重导指定资产可在 Blender 命令末尾追加 `-- --only house_mushroom,house_windmill`；仍会刷新完整可编辑源文件。源文件位于带 `.gdignore` 的目录，正式包只需要 GLB 与草地 PNG。

原生截图与检查：

```sh
FARM_ART_CAPTURE=output/farm-art-2026-09-10/lineup FARM_ART_ALL=1 \
  /Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 480x900 tools/dev/farm_art_preview.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/dev/farm_art_probe.tscn
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
  ./addons/gdUnit4/runtest.sh -a res://tests/farm -a res://tests/journey/test_field_capacity.gd -a res://tests/map/test_map_home_anchoring.gd
```

`FARM_ART_STYLE=windmill FARM_ART_CROP=H` 可检查 12 块成熟洋甘菊的场景负载。截图性能采样只代表本机 Godot 原生运行；它不等同于设备 GPU 时间或 Android 帧率。

## 验证记录

- Godot 4.7.2、Blender 5.2.0，Apple M4，Metal / Mobile。资产导入与最终原生探针没有脚本错误。
- 213 项农场、容量与地图回归完成。只有 `test_goals_header_counts_and_highlights_the_next_open_goal` 的 2 个旧断言失败：测试仍期待先显示已完成目标，而代码先显示未完成目标。已在隔离的原版本 `def104c` 复现相同失败，未改动目标排序。
- 模型及花瓣优化之后，24 项资产、作物、场景及预算专项全部通过。最终屋面法线修正并重导后，8 项资产与建筑测试再次通过。
- [六组实际游戏视口检查](checks.json)：360 × 640、390 × 844、1280 × 720，各含 9 / 12 块田。检查了非空渲染、田块实际触摸、行走、拖动镜头、场景挂起恢复。最小田块投影宽度为 49.1～56.7 像素；另有包含顶部 40 像素安全区的镜头回归。
- 七种外观都完成原生截图和相隔 30 帧的像素变化检查。普通场景 [性能样本](runtime-metrics.json) 为 41～49 次 draw call、约 6.2～15.2 万渲染图元，150 帧采样的 P95 帧间隔为 9.43～9.77 ms。图元统计包含阴影等渲染遍数。
- [12 块成熟洋甘菊样本](stress-metrics.json)：43 次 draw call、175,266 渲染图元，P95 帧间隔 9.46 ms。降低小花瓣细分后，图元由优化前的 304,290 减少约 42%；另有整片作物网格低于 75,000 三角面的回归约束。

以上是短时桌面采样，带垂直同步，不能作为 Android 帧率或持续温升结论。Metal 的 GPU 时间计数器在本次环境返回 0，该值表示没有取得有效 GPU 时间，不代表渲染零开销。Compatibility 渲染器可以启动，但色彩与项目实际使用的 Mobile 渲染器有明显差异，尚未完成降级渲染器调色；当前视觉验收以 Mobile 为准。

> 此页为原 Opus 预览的历史记录。2026-09-23 的重新评审发现缺面、坡地投影和平台通路问题；当前实现与验证请看 [重建评审](../griffith-rebuild-2026-09-23/README.md)。原版完整留档于 `output/griffith-rebuild-2026-09-23/original/`。运行请使用 `tools/dev/open_landmark_art.command` 的隔离项目，避免原主项目的自动登录。

# 格里菲斯天文台 · 3D 场景范例（2026-09-23）

设计稿：`docs/design/landmark-scenes-2026-09-23/griffith_observatory_scene_v1.png`
对比图：[第 1 轮](comparison-r1.png) → [第 6 轮](comparison-r6.png) → [第 7 轮](comparison-r7.png)；[近景](closeup.png)；手机 390×844 [出生点](phone-spawn.png)、[走向场景外时停在边界](phone-boundary.png)。

## 复现

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/build_griffith_observatory.py
godot --headless --path . --import
tools/dev/open_landmark_art.command          # 点地面行走，拖动/滚轮看场景
LANDMARK_CAPTURE=output/landmark-griffith/rN LANDMARK_VIEW=overview godot --path output/griffith-rebuild-2026-09-23/project --resolution 1536x1024
```
`LANDMARK_VIEW` 还支持 `closeup`（建筑近景）和 `phone`（出生点 + 走向场景外测边界）。

## 结构
- `tools/art/landmark_kit.py`：共用建模工具（圆角几何、顶点色 AO 烘焙、单材质 GLB 导出）。Blender 5.2 要显式 `export_vertex_color="ACTIVE"`，否则颜色全白。
- `tools/art/build_griffith_observatory.py`：地形、草坪、建筑、平台台阶、广场方尖碑、喷泉、咖啡露台、远景城市、道具摆放，以及导航格和镜头边界，全部写入 `assets/landmarks/griffith_observatory/layout.json`。
- `modules/landmark/shaders/`：`landmark_water`（水面渐变、扩散水纹、焦散、池边白沫、闪光）、`landmark_jet`（分层半透明水花）、`landmark_terrain` / `landmark_paint`（顶点色 + 草地纹理，朝上面提亮，超出可玩区淡入雾色）。
- `tools/dev/landmark_preview.*`：只读预览，不连网，也不写存档。

## 可走区域与边界
- 0.25 m 导航格，覆盖广场步道、草坪、平台、台阶和四条下山小径；建筑、水池、植被、摊位都已挖掉。
- 平台边缘不连通，只能走台阶。
- 小径在离地形边缘 0.8 m 处截止。
- 点击场景外会走到最近的可达点。
- 镜头拖动范围限制在可玩区内。

## 已知与设计稿的差距（下一轮）
- 画面感：设计图是生图的手绘质感，有暖色柔光和景深朦胧；实时渲染靠顶点色、AO 和提亮去接近，做不到一样。
- 植被：坡面树冠还不够密，树形种类少；设计图里前景大树更多、层次更丰富。
- 建筑：侧楼弧形外墙、屋面层次、入口门楣细节还偏简。
- 远景：城市峡谷的坡壁颜色过渡偏灰。

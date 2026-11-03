# SGODOT-325 B 皮肤源与自验

获批基准：C61（325 d1e61761）、`palette-B-v0.1.md`、小样提交 `3daac452`。
本目录只用于离线生成和审阅；没有给正式房间脚本增加皮肤加载逻辑。
所有既有 GLB、A 图集、布局、场景脚本保持原字节。

## 复现

在仓库根目录执行。只在 `output/skin-325-v1/project` 导入，避免编辑器回写原资产。
首次生成新图片的 `.import` 后，`configure_imports.gd` 逐项复制对应 A 图集的参数，保留新 UID；两张门头图的 `detect_3d/compress_to` 按 v1.1 统一为 2。
后续运行先复制仓库现有 B `.import`，因此 UID 保持。

```bash
source ~/.codex-huangzhong/env.sh
output/art-setup/venv/bin/python tools/art/source/skin_325/recolor.py
output/art-setup/venv/bin/python tools/art/source/skin_325/prepare_review.py
godot --headless --path output/skin-325-v1/project --editor --import
godot --headless --path output/skin-325-v1/project --script res://configure_imports.gd
godot --headless --path output/skin-325-v1/project --editor --import
godot --headless --path output/skin-325-v1/project --script res://build_options.gd
output/art-setup/venv/bin/python tools/art/source/skin_325/collect_resources.py
output/art-setup/venv/bin/python tools/art/source/skin_325/verify.py
nvidia-smi
godot --path output/skin-325-v1/project --rendering-method mobile --rendering-driver vulkan
output/art-setup/venv/bin/python tools/art/source/skin_325/package_review.py
```

渲染前确认共享 GPU 空闲，私有 ADB 端口为 5097。审阅脚本出图后自行退出。

## variants.json

方案 4.3 规定文件名和目录，未规定字段；本批使用明确的 `schema_version: 1` 数据约定。
路径均相对所在房间目录，单位米、Godot Y 向上。A 为默认款。

- `material_source_atlas`：原房间材质匹配用图集；仅替换引用该图集的材质副本，不替换玻璃、镜面、火焰等材质。
- `variants.<A|B>.atlas`：该款的图集；N2 的 A 保留原名 `hall_albedo_ao_n2.png`。
- `variants.<A|B>.enabled_options`：该款启用的开关。A 为空，显示原有模型。
- `options.<id>.scene`：静态 PackedScene；挂在 `parent` 所指的原房间节点下，保持资源内的局部变换。
- `options.<id>.hide_meshes`：仅隐藏这些 MeshInstance3D；不能隐藏父节点或碰撞。路径相对房间根。
- 切换款式先移除前一款的选项实例、恢复被隐藏的原 mesh，再换图集并启用新选项。
- `sign.anchor` 和 `size_m`：原 `sign_name` 挂点及可写区。`offset_m` 是**房间坐标系**下的写字区中心偏移，保留原挂点朝向约定，文字面朝房间 +Z。原 marker yaw=180 指向 -Z；使用正面 +Z 的 Label3D 时相对 marker 再转 180°，不能把房间坐标的偏移再次乘 marker basis。

`review.gd` 演示以上约定，并验证 A -> B -> A。它只存在美术工具目录，不是已接入客户端的加载器。

## 门头与药瓶

N1 贴片 1.60 × 0.22 m，纯 `#F3ECE2`，没有字或标记；保留壁炉。
N2 贴片 1.28 × 0.30 m，相对原写字区向左扩出绿十字，白底 `#F7FBF7`、十字 `#3E9E6A`。
贴片中心相对原挂点左移 0.16 m。按上官婉儿 v1.1 指示，B 可写区改为 0.66 × 0.23 m，中心相对原挂点沿房间 +X 偏 0.10 m；A 仍为原 0.88 × 0.23 m。两张 PNG 本身不烤字。

门头文字近景单独运行（不用重出全套图）：

```bash
godot --path output/skin-325-v1/project --rendering-method mobile --rendering-driver vulkan -- --sign-detail
output/art-setup/venv/bin/python tools/art/source/skin_325/package_sign_review.py
```

N2 原龛框和陈列合在一个 mesh，因此不能直接开关单独陈列节点。
`build_options.gd` 离线按已批小样同一位置/UV 条件去掉陈列三角形，保留框架的顶点、UV、颜色和变换，
打包为两个 B 专用静态 TSCN，内含左二右一三只无字药瓶；原龛 GLB 不改。
切到 B 仅隐藏原龛 MeshInstance3D，启用对应 TSCN；碰撞与父节点不动。
源数组再次编码的法线误差小于 0.0002，实际值见验证 JSON。药瓶为单 surface、224 三角面/只，闭合底面和瓶盖。

药瓶、门头和空白龛框已存成静态资源，客户端无需运行几何生成或删三角形代码。
框架仍用 B 共用图集，药瓶沿用获批小样的哑光平涂颜色。

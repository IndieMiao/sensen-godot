# Homestead looks 439 — source / review

四个 house-anchor-relative 部件，交付说明和图片在 [docs/design/homestead-looks-439](../../../../docs/design/homestead-looks-439/README.md)。原点不是各件包围盒中心；几何已含门廊 / 扩建偏移。生成器会覆盖本目录 `.blend`、四个 GLB、统计和 manifest 追加项；手工修改应先回写生成器再重建。

已验证：Blender 5.2.2、Godot 4.7.2、Node 22.20、Python 3 + NumPy/Pillow。所有 Blender / Godot 调用必须持有 gs66 渲染锁；启动前查看 nvidia-smi，使用赵云私有 ADB 5099，结束立即退出。

## 重建与导入

在仓库根目录：

```bash
source ~/.codex-zhaoyun/env.sh
nvidia-smi
flock ~/gs66-render.lock blender --background --python "$PWD/tools/art/build_homestead_looks_439.py"
python3 tools/art/source/homestead_looks_439/imports.py stage
flock ~/gs66-render.lock godot --headless --path output/homestead-439/import-project --import
python3 tools/art/source/homestead_looks_439/imports.py configure
flock ~/gs66-render.lock godot --headless --path output/homestead-439/import-project --import
python3 tools/art/source/homestead_looks_439/imports.py sync
python3 tools/art/source/homestead_looks_439/verify.py
```

使用带 NumPy/Pillow 的 Python 环境。`imports.py` 只同步四件 `.import`，保留已生成 UID；不删除其他资产的缓存。提交后再执行 stage → cold → 锁内 Godot --import → sync，确认 `git status --short` 干净。

## 真实 P0 农场实拍

`prepare.py` 从固定运行时 `8493a5c4` 用 git archive 导出完整工程到 output；已有同版本 stage 会复用。源码保持在运行时版本；`apply_preview.py` 只给这个隔离工程的 `look_parts()` 换四个资源引用。独立用户目录、localhost:9、fixture transport，不连接线上。

```bash
python3 tools/art/source/homestead_looks_439/prepare.py
python3 tools/art/source/homestead_looks_439/apply_preview.py
node --experimental-strip-types --loader ./tools/art/source/homestead_looks_439/ts_resolve.mjs tools/art/source/homestead_looks_439/make_view.ts
flock ~/gs66-render.lock godot --headless --path output/homestead-439/project --import
flock ~/gs66-render.lock godot --path output/homestead-439/project --rendering-method mobile --rendering-driver vulkan --disable-vsync --max-fps 60 --quit-after 9000
```

`review.gd` 自动生成六张默认开场、两张门牌近景和四张45° / 后侧补充视角、`render-validation.json`，结束自行退出。临时移动长凳 / 灌木、隐藏两枚旧踏石的操作只在审阅节点中发生，记录在报告里。六格同一 Lv8 场地保留人物，近景 Lv10 隐藏人物。原生开场宽12.665465 m、近景宽5.6 m；没有强制室内镜头宽。

## 占地与打包

```bash
flock ~/gs66-render.lock godot --path output/homestead-439/project res://audit_scenery.tscn --rendering-method mobile --rendering-driver vulkan --max-fps 60 --quit-after 600
python3 tools/art/source/homestead_looks_439/verify_footprint.py
python3 tools/art/source/homestead_looks_439/package_review.py
```

MultiMesh 实际变换审计必须用 Vulkan，headless dummy 的 readback 会返回 identity，不能拿来证明占地。`verify_footprint.py` 按命名部件包围盒给出保守分离距离、记录旧摆件接触候选。它不把包围盒候选宣称为三角形交叠，也不代替将来的程序接入检查。

`package_review.py` 仅拼原始图并加说明标签，保留 `docs/design/homestead-looks-439/v1.1/raw/`；媒体哈希写入 media-manifest.json，Plane 上传后下载回读核哈希。默认图需另行实际看过，不能凭脚本成功就宣称通过画面验收。

## 来源

- `reference/`：用户已批 282 v1.1 设定、现房截图、原农场色板及 provenance。
- `asset_stats.json`：每件实测面数、哈希、尺寸、所有源部件的 bounds。
- 原房保持不变；导出AO可用它作遮蔽物，未经修改的原房不重复写入 blend / GLB。
- 游戏农场统一 `FarmArt` 材质需读取线性顶点色；无需图集。

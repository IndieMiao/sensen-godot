# SGODOT-448 source and verification

最新接口与获批例外见 [交付说明](../../../../docs/design/homestead-clearance-448/README.md)。六件源仍在439/440原路径，本目录只存本轮验证、冷导入、真实场景预览与排图工具。

所有命令从仓库根执行。Python依赖 NumPy、Shapely、Pillow。Blender/Godot调用须持有 `~/gs66-render.lock`，启动前查看 `nvidia-smi`，私有ADB5099；不常驻编辑器。

1. 用 `tools/art/build_homestead_looks_439.py` 重建四小件。将两个wing GLB和import同步到440的reference/439，更新provenance的对应SHA；porch参考保持#858原文件。再用 `tools/art/build_homestead_lv15.py`、`homestead_440/export_mesh.py`、`merge_components.py` 按该目录流程导出两个master。禁止直接用旧439/440预览脚本：它们演示了已废弃的移Bench方案。
2. `python3 tools/art/source/homestead_clearance_448/imports.py stage` 从固定旧art头6151fef82提取回归对照，并准备六件导入工程。`cold`只清本任务output下的缓存。
3. 执行下面冷导入流程；六个原UID保留。

```bash
source ~/.codex-zhaoyun/env.sh
nvidia-smi
python3 tools/art/source/homestead_clearance_448/imports.py stage
python3 tools/art/source/homestead_clearance_448/imports.py cold
flock ~/gs66-render.lock godot --headless --path output/homestead-448/import-project --import
python3 tools/art/source/homestead_clearance_448/imports.py sync
python3 tools/art/source/homestead_clearance_448/imports.py verify
python3 tools/art/source/homestead_looks_439/verify.py
python3 tools/art/source/homestead_440/verify.py
python3 tools/art/source/homestead_clearance_448/verify_clearance.py
```

提交后再跑冷导入、sync、verify，`git status --short`须为空。

真实场景复现：`prepare.py`把#896启用外观的b46c6ea7展开到output/homestead-448/project，使用独立用户目录与离线传输；原P0Garden/导航不改。需要该固定runtime的server依赖（按其pnpm锁文件安装）。用server的tsx执行 `output/homestead-448/make_views.ts`（cwd=output/homestead-448/project/server），生成Lv4/5/8/15两套离线fixture。执行 `audit_decor.ts`可用原server纯函数重核占格。

```bash
python3 tools/art/source/homestead_clearance_448/prepare.py
# 在隔离project/server目录用 pnpm exec tsx ../../make_views.ts 生成fixture。
SENSEN_OFFLINE=1 P0_SERVER_URL=http://127.0.0.1:9/v1 flock ~/gs66-render.lock godot --headless --path output/homestead-448/project --import
SENSEN_OFFLINE=1 P0_SERVER_URL=http://127.0.0.1:9/v1 flock ~/gs66-render.lock godot --path output/homestead-448/project --rendering-driver vulkan --fixed-fps 30 --disable-vsync
python3 tools/art/source/homestead_clearance_448/package.py
```

review.gd保存36张360×800原图与147项检查；使用原机位、真实FarmArt材质，before/after用同参数分别导入。坐姿复用sit_idle，只为穿模检查；实际入门点只暂缓室内跳转。程序生产开关WING_WAITS保持原状。package.py仅拼接和裁图，不重画场景。交付报告存docs/design/homestead-clearance-448；原始PNG分装Plane附件。

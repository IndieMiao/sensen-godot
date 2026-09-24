# 矿坑美术参考与实现

同日后续反馈已将游戏相机改为可出屏近景。当前预览和触摸验证请使用 `docs/product/mine-camera-2026-09-24.md`、`docs/qa/mine-camera-2026-09-24.md`；本页下方的输出记录美术初版。

`reference.jpg` 是用户在 2026-09-24 提供的原始设计稿。

已提交到仓库的审查截图：

- [五层美术合集](review/five-floors.png)（美术全景展示）。
- [第一层近景前后对照](review/camera-comparison-floor-1.png)（最终游戏默认视口）。
- [离屏头像和方向提示](review/offscreen-portrait.png)。

客户端实际渲染与对照输出：

- `output/mine-art-2026-09-24/five-floors.png`：五层三维效果合集。
- `output/mine-art-2026-09-24/before-after.png`：一层改前、改后，在相同构图下比较美术。
- `output/mine-art-2026-09-24/after/`：五层无 HUD 场景图、360×640 / 390×844 / 960×720 逻辑视口的实际游戏界面。无 HUD 图仅用于核对模型，游戏相机仍适配交互区域。
- `output/mine-art-2026-09-24/android/`：模拟器原始截图和验证记录。

这批图片来自 Godot 原生场景，不是生成图。具体实现范围见 `docs/product/mine-art-2026-09-24.md`，验证边界见 `docs/qa/mine-art-2026-09-24.md`。

打开本地隔离预览：

```sh
godot --headless --path . --editor --import --quit
python3 tools/dev/prepare_mine_art_preview.py
godot --headless --path output/mine-art-2026-09-24/project --editor --import --quit
godot --path output/mine-art-2026-09-24/project
```

预览中的 B1–B5 按钮和数字键用于换层，Reset 重置当前演示数据。普通点击、摇杆、拖动相机、背包和楼梯均使用真实客户端；开采和楼梯提交使用明确隔离的本地命令夹具，不连接游戏服务器。

批量截图与拼图：

```sh
godot --path output/mine-art-2026-09-24/project -- --capture
uv run --with Pillow python tools/art/mine_art_contact_sheet.py
```

拼图工具的改前对照依赖本轮已保存的 `before/chamber-1.png`；新工作区可先只查看 `after/` 的五层渲染。

# 四种矿石岩块 v1

黄忠 / SGODOT-355。各 114 三角形、单 surface、顶点色、无贴图/动画/碰撞；Y up，底面中心原点。
延续代码 `_ore` 四层七边形，最大半径 ≤.47 m、高 .63 m；程序假影半径仍 .52 m。
铁矿锈红褐矿脉、石英白粉晶面、煤黑亮、铜矿铜橙绿锈。碎裂与拾取由程序控制。
各 `.glb.import` 保留 Godot UID，挂现有 `res://assets/monsters/material_import.gd`，只开线性顶点色、关投影。
实测 bounds 和 SHA-256 见 manifest.json，源与两矿审阅在美术分支 `docs/design/mine-kit-355-2026-11-02/mine_props/`。

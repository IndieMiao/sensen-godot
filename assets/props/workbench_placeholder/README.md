# Workbench placeholder (P0, SGODOT-231)

**Placeholder only.** The P0 homestead workbench until a proper farm workbench gets its own art card.

- Source: `assets/rooms/blacksmith_shop/back_tool_bench.glb`, `bench_vise.glb` and the shared atlas
  `room_albedo_ao.png` from `origin/wp-3d-scene` commit `10e62d7` (card 178, blacksmith shop), chosen by the art
  director (Shiranui Mai, 231 comment). Copied as a pair with their atlas; `wp-3d-scene` is unchanged.
- The GLBs carry no texture: `scenes/p0/p0_farm_materials.gd` applies the atlas as an albedo override, or they render white.
- Assembly: parent scaled 1.08; vise at local [0.38, 0.98, 0.02]; bench top ≈ 0.96 m; footprint 1.50 × 0.63 m (2 × 1 farm
  cells); collision box centre [0, 0.48, 0], size [1.50, 0.96, 0.63]; front (local +Z) toward the camera.
- Anchors (Arthur's naming table): `use_workbench` [0, 0.97, 0]; `stand_workbench` [0, 0, 0.92], yaw 0.
- User approved copying it into farm-dev (奕星, 2026-10-08).

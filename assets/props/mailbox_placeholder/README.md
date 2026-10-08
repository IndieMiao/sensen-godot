# Mailbox placeholder (P0, SGODOT-234 C)

**Placeholder only.** The farmhouse Mailbox until it has its own art card. The user chose to stand in an already
finished model (gameplay-plan-v2 q(24), option B, 2026-10-07); the a / b Mailbox looks come with Homestead Lv3 in P1.

- Source: `assets/rooms/post_office/red_post_box.glb` and that room's shared atlas `room_albedo_ao.png`, from
  `origin/wp-3d-scene` commit `4f5d8364` (card 178 rooms, post office), integrated into farm-dev by `e718c9df`.
  Copied as a pair with their atlas; the post office room is unchanged.
- The GLB carries no texture: `scenes/p0/p0_farm.gd` (`_mailbox_prop`) applies the atlas as an albedo override, or it
  renders white.
- Assembly: parent scaled 0.65; model bounds 0.78 × 1.78 × 0.78 m → 0.51 × 1.16 × 0.51 m, one farm cell
  (`P0Garden.MAILBOX_CELL` (12, 16), by the farmhouse's right wall); front (local +Z) toward the camera.
- Anchors (Arthur's naming table): `use_mailbox` [0, 0.85, 0.17] (the slot, scaled); `stand_mailbox` [0, 0, 0.75],
  yaw 0.

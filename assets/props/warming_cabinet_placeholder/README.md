# Warming Cabinet placeholder (SGODOT-226)

The Homestead Lv3 Warming Cabinet in the P0 farmhouse kitchen corner, until `farmhouse_lv1` (SGODOT-213) brings
the real one. **Placeholder, not final art.**

- `kitchen_pantry.glb` and its shared albedo `room_albedo_ao.png` are copied as a pair, unchanged, from the
  Deluxe Room kitchen (SGODOT-173, accepted): `assets/rooms/deluxe_room_10/` at commit `cfd775f`
  (wp-3d-scene). Do not use the old `kitchen_end_cabinet.glb` from the same folder.
- Chosen by the art director on SGODOT-226 (the scaled sink cabinet read as a second sink); copying into the
  kitchen PR approved by the user through Yi Xing on 2026-10-08. wp-3d-scene itself is untouched.
- Placed by `assets/p0/rooms/farmhouse.anchors.json` (`props` → `warming_cabinet`): uniform scale 0.6
  (about 0.56 × 1.34 × 0.57 m), against the left wall beside the hearth, door facing the room, the albedo as
  a material override (the Basic Room atlas look), a box collider in model units, a warm light in front of
  the door. Anchors `use_warming_cabinet` (cabinet top centre) / `badge_warming_cabinet` / `stand_warming_cabinet`.
- Import settings follow the Deluxe Room originals (VRAM-compressed albedo with mipmaps; mesh without LODs).
- Delete this folder when farmhouse_lv1 lands and the anchors file goes away.

# SGODOT-344 · Nadia resident look C (2026-10-27)

Nadia's slots in `assets/p0/outpost_npcs.json` still carried the placeholder `hairhat70`
(Propeller Cap) from e82ba3ec (2026-10-10), so the market 3D NPC and her baked card both
wore it. Diagnosis: SGODOT-344 comment 3f4dd001.

Candidates (current, A–D, with Mei and Theo of the same market for reference) were rendered
on the shared keeper-portrait stage with `tools/art/bake_resident_portraits.gd`
(`looks-candidates.json` → `candidates.png`; Plane 344 107b8bff). The UI director picked
**C** (344 fd484cb7): `hairhat41_npc_auburn` + `cloth1_1` + `shoes2` (`looks-c.json`).
The apron options read as a produce stall and match Mei's outfit.

- `before-after.png`: current card vs look C.
- Runtime files: `assets/p0/art/residents/nadia_card.jpg` and the `nadia` entry of
  `portrait_crops.json` (stamp [81,46,165,207], face [84,50,160,160]).
- The `outpost_npcs.json` slots change lands from the resident programmer and merges together
  with the farm-dev integration.
- Follow-up: a dedicated baker hat and apron (npc_only parts, small-prop flow) to match the
  2D portrait RES-NADIA.

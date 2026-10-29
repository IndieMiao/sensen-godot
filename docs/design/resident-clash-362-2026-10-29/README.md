# SGODOT-362 · Resident look clashes (2026-10-29)

Found by the 284 B5 resident walkthrough (Plane 284 comment 9b7c64ab): Sam, Lena and Nadia
share hairhat41 (Nadia only recoloured), Lena, Nadia and Rafa all wear cloth1_1, and Hana's
default hairhat0 reads as the player's starting look. Hana also shared cloth11 (green apron)
with Ama, the tea-house keeper in the same room.

The public parts (6 hair styles, 6 cloths) and the 48 generated keeper sets
(`world.keeper_looks`) already use up the free style + cloth pairs, so slot changes alone
cannot separate Sam, Lena and Rafa (`candidates-round1.png`, `candidates-round2.png`;
looks in `looks-candidates.json`). Plan v1 (362 ba1dcbd1, `before-after-v1.png`), approved by
the UI director (362 27ea8b86):

1. **Stage 1, slots only (this PR):** Hana → `hairhat43_npc_black` + `cloth11_npc_mei` +
   `shoes5` (look A, `looks-hana-a.json`). No keeper set wears style 43 + cloth11_npc_mei;
   the part-id pair is unique (Lou wears the same hair with cloth1, in the card room).
2. **Stage 2, small-prop batch (刘备, with 347 / 357):** texture-only npc_only parts —
   Lena `hairhat51_npc_lena` (mustard rain-hat yellow, badge navy / white or removed),
   Rafa `hairhat36_npc_rafa` (white skipper cap) + `cloth1_1_npc_rafa` (navy stripes,
   horizontal if the same texture allows). Sam is unchanged; Nadia is SGODOT-347.
   The Lena / Rafa "after" images in `before-after-v1.png` are 2D recolour previews, not
   renders. With stage 2, `tests/p0/test_p0_outpost.gd:849` expects `tea_subtropical_0`
   and the `outpost_npcs.json` note changes.

## Stage 1 files

- `assets/p0/art/residents/hana_card.jpg`, rebaked with look A on the shared portrait stage
  (`tools/art/bake_resident_portraits.gd`, farm-dev 26416a20; avatar parts unchanged since).
- `portrait_crops.json` `hana`: stamp [100,46,162,203], face [112,56,162,162] (eyes centred, chin inside the circle; options in `hana-face-crop-options.png`, 不知火舞 362 77a4c2b7). The side tuft
  of the 43 style falls outside the stamp and face, as on Theo's card.
- `hana-rebake-check.png`: before / after, Ama · Hana · Lena of the tea house, stamp at
  32×40 and ×3, profile face at 80.

The `outpost_npcs.json` slots change comes from the resident programmer (苏烈) and merges
with the farm-dev integration (card only: jpg + crops; the .import is unchanged).

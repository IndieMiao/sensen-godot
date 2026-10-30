# SGODOT-362 stage 2 / 347 · Lena, Rafa and Nadia resident cards (2026-10-30)

Rebaked with the batch-3 NPC parts (赵云, runtime branch `art/npc-parts-batch3`, accepted by
不知火舞 on 362 499a21b6 and 347 801aad11) on the shared portrait stage
(`tools/art/bake_resident_portraits.gd`, checkout of `art/npc-batch3-integ` 0fed08b5),
looks in `looks.json`:

- Lena: `hairhat51_npc_lena` + glass1 + cloth1_1 + shoes1
- Rafa: `hairhat36_npc_rafa` + `cloth1_1_npc_rafa` + shoes4
- Nadia: `hairhat41_npc_nadia_baker` + `cloth1_1_npc_nadia` + shoes2

`portrait_crops.json` follows 不知火舞's framing (eyes centred, at 60–65 % of the circle,
face about half its width, hat complete); eye centres were measured from the black pupil
pixels, not by eye:

| | stamp | face | eyes in the face circle |
|---|---|---|---|
| lena | [46,46,212,265] | [39,16,240,240] | 50 % across, 63 % down |
| rafa | [56,50,190,238] | [44,23,240,240] | 50 % across, 63 % down |
| nadia | [58,50,210,262] | [35,29,250,250] | 56 % across, 62 % down |

Nadia's baker cap is flat and wide: with her eyes exactly centred the circle can be at most
250 px (the card width) and would cut the cap's top corners, so it sits 14 px left; accepted by
不知火舞 (362 0d120f5c, 347 7e931ef9). `before-after.png`: current farm-dev cards vs the new
ones; `crops.png`: stamps at 32×40 / ×3 / ×6 and the face circle with guides.
The cards go to farm-dev with the batch-3 integration (the `.import` files are unchanged).

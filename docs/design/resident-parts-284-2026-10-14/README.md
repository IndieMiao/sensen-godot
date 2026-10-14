# SGODOT-284 / q(171) · Granny Wu / Ivo NPC parts

**Tomo increment:** [hairhat0_npc_tomo, final four-part validation and review](tomo/README.md)
adds the approved warm dark brown hair to the same PR #407. The initial three-part
evidence below remains unchanged; the increment confirms those files are preserved.

刘备 · 2026-10-14 · base `farm-dev` at `a8e0b548`.

Three NPC-only parts provide Granny Wu's silver bun/red pin and Ivo's mustard
mining helmet/non-emissive headlamp/grey short beard. Granny Wu wears the
approved green apron and no glasses; Ivo uses the approved original cloth42
fallback. Its complex monster/stripe/multicolor atlas is why the optional
`cloth42_npc_ivo` recolor was skipped. The existing runtime resident look table
is unchanged; 苏烈 integrates the looks after approval.

## Review images

- [Two residents, front](npc-lineup-front.png)
- [Two residents, three-quarter](npc-lineup-three-quarter.png)
- [Original combined npc_lineup capture](npc-lineup-both.png)
- Full cards: [Granny Wu, 300×660](granny_wu_card.jpg), [Ivo, 300×660](ivo_card.jpg)
- [Postage heads: actual 32×40 above, 3× below](stamps.png)
- Individual heads: [Granny Wu 32×40](granny_wu_stamp_32x40.png),
  [96×120](granny_wu_stamp_96x120.png), [Ivo 32×40](ivo_stamp_32x40.png),
  [96×120](ivo_stamp_96x120.png).

Actual Godot 4.7.2 Vulkan Mobile captures on Deck AMD Custom GPU 0405 (RADV
VANGOGH). The lineup uses the production renderer with a temporary two-person
fixture and frozen idle pose. Front/three-quarter sheets are exact crops from
its combined render. The supplied `bake_resident_portraits.gd` was run with a
window, unchanged, on the P0 keeper portrait stage. Its original card outputs
and [crop metadata](portrait_crops.json) are retained. The [script provenance](review-script-provenance.json)
records hashes and the fixture-only lineup changes. The baker itself is not
committed, as requested. This is desktop art validation, not phone performance
or approval of the future integrated resident UI.

## Delivered parts and validation

| Part | Triangles | Mesh/surface | Runtime texture |
|---|---:|---|---|
| hairhat80_npc_granny_wu | 764 | 1 / 1 | 512² |
| hairhat_npc_ivo | 1423 | 1 / 1 | 512² |
| mask16_npc_ivo | 320 | 1 / 1 | 512² |

The helmet is below the existing 2784-triangle hairHat maximum. Its 2048²
source atlas matches hairhat51; original import settings reduce runtime to
512² with mipmaps/VRAM compression. Other two source PNGs are 512². Lamp
emission is zero. Granny Wu's FBX is byte-identical to Ama's. Helmet/beard
substitute only the Geometry block inside their original static FBX containers;
node names, hierarchy, connections, unit/axis settings and bone transforms are
exact. The beard retains width/depth/topology, scales vertical extent by 1/3
and fits the jaw with a 2 cm mesh-space lift. No socket offsets compensate for
coordinate changes.

- [GDUnit results](tests.xml): **38/38 passed**, 8 suites, zero failures/skips;
  `tests/catalog`, `tests/pipeline`, `test_socket_placement.gd`.
- [Actual import audit](godot-validation.json): **26/26 passed**, including
  source/imported/extracted frame comparisons, triangle and texture budgets,
  zero helmet emission and NPC catalog presence. The mask slot is checked
  visually in front/three-quarter views as specified.
- [Geometry preservation](geometry-validation.json) and [texture curves](texture-validation.json).
- [Append output](extract.log): `追加完成: 3 部件, 0 错误`.
- [Preservation audit](preservation.json): 385 existing avatar/source/pipeline/
  renderer/NPC-table files byte-identical; manifest 38 → 41 with original text
  prefix and entries intact; exactly three IDs appended to npc_only.
- [Rebuild record](reproducibility.json): six FBX/PNG outputs byte-identical
  across consecutive builds.
- [Combined validation](validation.json) includes dimensions and SHA-256 for
  all review images, the three part audits and the clothing decision.

[Source and reproduction commands](../../../assets/avatar/source/README_284.md).
[Named Blender sources and authority copies](../../../tools/art/source/resident_parts_284/README.md).

The front/three-quarter sheets, two full cards, actual/3× stamp sheet and combined
validation are delivered to SGODOT-284 as 刘备
(`0fb1de1f-ead5-443b-9537-54cbac113260`), with downloaded hashes/author checked.
[Delivery receipt](delivery-verification.json).
Cross-review: 后裔; technical: 上官婉儿; visual: 不知火舞; merge after user approval.

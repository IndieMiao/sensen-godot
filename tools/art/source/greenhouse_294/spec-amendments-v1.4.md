# SGODOT-294 R2 · approved v1.4 amendments (2026-10-10)

上官婉儿 requested this revision after 不知火舞's R1 visual review, Plane comment
`c92e7e18-1c40-4bc1-9844-e2e759253ce6`, annotation
`c8b857e5-3ae2-4de3-83fd-f07c1e3291d4`. The gable, post thickness and 10% glass
were accepted. Corner feet and perimeter eaves overlapped the covered beds.

- Set post centres to **X/Z = ±2.475 m**; nominal frame span / manifest
  `footprint` is **[4.95, 4.95]**. Add `covered_block_m: 4.55`; the 4×4 bed
  block remains between ±2.275 m. Adjacent beds start at ±2.925 m.
- Post section stays **0.16 m** square; stone feet shrink from 0.33 to
  **0.30 m** square. All four sides stay open, with no ground beams.
- Preserve eave underside **1.80 m**, eave top **1.92 m**, ridge **2.75 m**
  and `roof_center` **(0, 2.63, 0)**. Nominal eave-to-ridge pitch is 18.5°.
- Rebuild from the generator's half-width parameter; widen roof and glass
  with the frame. Keep the named source pieces, palette, common pivot, single
  surface per GLB and existing triangle limits. Collision is only four posts.
- Deliver the same three views, with actual 4×4 beds in the base-only top view.
  Push the existing branch and PR #296; do not merge.

## Coordinate clarification for integration

The instruction calls 4.95 m the outside dimension and also explicitly locates
the post centres at ±2.475 m. Those cannot both describe the physical outer
edge once the feet have thickness. This model follows the explicit centres:
**5.25 m actual outside bounds including 0.30 m feet**. The manifest keeps
4.95 m as the requested nominal centre span and reports actual mesh extents
separately in `bounds`. Do not scale it to 4.95 m during integration. Foot
inner edges at ±2.325 m leave 0.05 m from the covered block; outer edges at
±2.625 m leave 0.30 m from adjacent beds.

This amendment supersedes v1.3's footprint only. All earlier height, material,
budget, branch and review requirements continue to apply.

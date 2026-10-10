# SGODOT-294 approved amendments (2026-10-10)

The retained `spec-v1.1.md` and supplied concept remain the art direction except
for these later approvals in the task conversation:

- User approved the independent branch `wp-3d-scene-liubei-294`, targeting
  `wp-3d-scene`, because PR #283 still uses `wp-3d-scene-liubei`. Do not add
  greenhouse assets to the decoration PR.
- User approved eave underside **1.80 m**, eave top **1.92 m**, in place of the
  original approximately 1.6 m eave. This clears the **1.745 m** character at
  all four central entrances.
- 上官婉儿's **v1.3**, following 不知火舞's visual recommendation, raises the
  ridge from **2.40 m to 2.75 m**. Keep the eave underside/top unchanged and
  retain the pillar cross-section. This restores an approximately 20° gable
  instead of the flattened approximately 12° roof.
- Footprint remains **4.55 × 4.55 m**; ground-centred common origin, +Z front.
  No walls, doors or ground beams. Three GLBs, one surface each, unchanged
  budgets: base 1,500 / roof 1,000 / glass 500; total at most 3,000 triangles.

The visible glass opacity remains a runtime choice: 25% normally and 10% inside.
Source vertex alpha and source materials remain opaque. No double-sided geometry.

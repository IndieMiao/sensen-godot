# SGODOT-178 smoke R2.4 — 2026-10-08

Smoke-only follow-up to the accepted R2.3 direction (baseline cad6c626). Reference: Figma 545:2965. The smoke is now warm near-white, starts with a larger puff at the mouth, expands visibly into larger upper clouds, and retains mid-plume opacity. Awaiting art-director review; not marked Done.

## Parameters and actual growth

- 8 smoke particles, lifetime 4s; total 16 flames + 4 sparks + 8 smoke = **28**, below 40.
- Start/end size **1.2 / 2.6 m**, nominal ratio **2.17×**. The ramp reaches 94% of end size by 65% lifetime. Per-puff random size remains ±25%.
- Alpha reaches 0.98 by 2% lifetime, holds through 62%, stays at 0.86 at 88%, then fades to zero. The earlier onset and larger starting size keep a substantial puff at the existing chimney mouth; emitter position is unchanged.
- Unchanged 15° spread, drift (0.28, 0.72, -0.04) m/s ±12%, wind acceleration (0.18, 0.04, 0) m/s², random four-frame selection and rotation/turning. No geometry or emitter structure changes.
- The smoke-only billboard now enables **billboard_keep_scale**. R2.3's material discarded animated particle scale, so merely increasing end_size did not produce the promised visible growth. The smoke ramp is normalised and the particle scale range carries metres. The shared material helper and fire are untouched.

A rendered, single stationary puff control measures **115→228 px width (1.98×)** between the early and upper-life captures (requested ages 0.24 / 2.60s). The same control with billboard_keep_scale disabled stays **94→94 px (1.00×)** and intentionally fails the growth assertion. This isolates the material-scale regression; production keeps all random variation. See smoke-growth-verification.json and growth-control-without-scale.json. These are rendered-size checks, not a reference similarity score.

## Colour and preservation

Texture RGB is remapped to ivory-white highlights and shallow warm-grey lobe shadows. Its opaque 90th-percentile RGB is (245,243,238); the rendered single-puff bright-region median is **(246,244,242), #F6F4F2**. The smoke material removes the old cool-grey multiplication and uses white albedo, without HDR gain or emission. R2.3's soft alpha silhouette is **byte-identical**; only texture RGB changes.

**工作台未改动**：back_tool_bench.glb、bench_vise.glb、room_albedo_ao.png remain byte-identical to pre-edit cad6c626, independently checked against git and the starting hashes. Approved fire script/scene/textures, particle_style.gd and ForgeFireFX manifest settings are also unchanged. Room models, collisions, lighting, placements and the registered whole-room/detail cameras are unchanged. No rebake or model regeneration. See preservation.json.

PR #29 / SGODOT-236 copied the earlier shared folder but Basic Room only uses fire. This revision does not modify that PR/farm-dev. At a later wp-3d-scene integration, use the newer fx_chimney_smoke.gd and smoke_strip.png from this revision.

## Validation and media

13/13 standalone shared-FX checks passed on Godot 4.7.2 Mobile/Vulkan / RADV VANGOGH. 30 Hz, no particle collision/shadows, explicit conservative AABB includes end size, random scale and drift. Static geometry remains 87,250 triangles / plants 4,096 / 18 static surfaces + 3 particle surfaces; whole-scene draws remain 23.

The **8s smoke closeup** contains 130 wall-clock frames resampled to 30 FPS, with no acceleration. Beginning/middle/end were visually inspected; no dialogs or black frames. Whole/reference comparison, R2.3/R2.4 closeup comparison and video timeline accompany the clip. The registered whole camera retains the concept's tight upper-smoke framing; the detail clip shows the complete plume. Desktop captures do not establish physical-phone performance. Unchanged character/gameplay systems are not claimed as newly tested.

Reproduce: run render_r1.py r24 blacksmith_shop, then record_particles.py r24. Run verify_smoke_growth.gd in that isolated project with an absolute output directory; add --without-scale to reproduce the expected regression failure. Smoke texture generation uses the original render_smoke.py outputs and smoke-only soften_smoke.py; do not regenerate approved flame/spark resources.

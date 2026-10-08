# SGODOT-178 smoke R2.3 — 2026-10-08

Smoke-only revision from cfd775fb, awaiting art-director review. Actual reference: Figma 545:2965. Whole-room review camera, fire, lighting, models, atlas and collisions retained; the smoke detail camera widens to show the complete plume.

8 smoke particles, 4 s lifetime, 0.30 → 1.90 m size, ±25% per-puff size; 15° spread, initial drift (0.28, 0.72, -0.04) m/s ±12%, wind acceleration (0.18, 0.04, 0) m/s². Random static frame from four sprites, full random rotation and ±8°/s turning. Alpha holds through 40% then fades. Softened inward edges retain cloud lobes without stacked hard rims.

Total: 16 flames + 4 sparks + 8 smoke = **28 particles**, below 40. Fixed FPS 30; no collision or shadows; explicit conservative AABB includes the motion/scale envelope. Static geometry 87,250 triangles, plants 4,096; 18 static surfaces + 3 particle surfaces; whole view 23 draw calls. Fire defaults/resources and shared helper are unchanged.

**工作台未改动**：back_tool_bench.glb、bench_vise.glb、room_albedo_ao.png match the pre-edit cfd775fb bytes. See preservation.json; no rebake or model regeneration.

Smoke clip is 8 seconds of actual Mobile/Vulkan motion, captured by wall clock and resampled to 30 FPS without acceleration. Reviewed beginning/middle/end; no black frames or dialogs. Whole screenshot and comparison are included; comparison is visual reference, not pixel-fidelity measurement. Desktop RADV VANGOGH is not physical-phone performance evidence. Smoke shape/spacing varies during motion; the upper puffs progressively fade.

Reproduce: run render_r1.py r23 blacksmith_shop, then record_particles.py r23. The smoke texture is reproducible from render_smoke.py outputs via soften_smoke.py; never regenerate approved flame/spark sprites for this change. Shared FX checks are in standalone-validation.json. Prior character/colour/lighting acceptance remains R2.2; these unchanged systems were not claimed as newly retested.

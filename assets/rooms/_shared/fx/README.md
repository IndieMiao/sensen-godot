# Shared hearth fire and chimney smoke

Self-contained Godot 4.7 Mobile/Vulkan effects for SGODOT-178 R2.3. Copy this entire directory, at the same `res://assets/rooms/_shared/fx/` path, into a consumer project. No room GLB, room atlas, scene assembler or game service is required. The fire from 5e5bf6af passed art-director review; SGODOT-236 can integrate it. R2.3 changes smoke only; fire resources and shared helpers are byte-identical.

Instantiate `fx_hearth_fire.tscn` / `fx_chimney_smoke.tscn`, set properties **before** `add_child()`, then place their Node3D roots. Metres, Y up. Parameters are creation-time settings; recreate the instance to change particle geometry/count at runtime.

| Fire parameter | Default | Meaning |
|---|---:|---|
| `emission_box` | (0.32, 0.015, 0.065) | Half extents; emitter footprint, not a full width |
| `flame_count` / `spark_count` | 16 / 4 | Clamped to 1–24 / 0–6; count the combined scene budget yourself |
| `flame_height` | 0.68 | Approximate maximum flame envelope from root, also scales velocity and sprite |
| `flame_lifetime` | 0.72 | Seconds, supported 0.5–0.9 |
| `light_energy` | 3.1 | Base OmniLight brightness |
| `flicker_strength` | 0.08 | Smooth low-frequency variation, clamped to at most ±10% |
| `light_path` | empty | Relative path to an existing OmniLight3D, retaining its name, placement, range and colour |
| `light_range` / `light_color` | 4.25 / FF8B36 | Used only when creating a light instead of borrowing one |

Existing `HearthGlow` can be borrowed via `light_path`. Stop any previous animation of its brightness; this effect becomes the sole flicker writer. Public owner references such as Basic Room's `fire: Node3D` may point to the root. Do not add a second light when one already exists.

| Smoke parameter | Default | Meaning |
|---|---:|---|
| `smoke_count` / `lifetime` | 8 / 4.0 | 8–10 particles / 3–4 seconds |
| `drift` | (0.28, 0.72, -0.04) | Metres/second; initial upward/sideways velocity ±12% |
| `emission_box` | (0.055, 0.01, 0.035) | Half extents around chimney mouth |
| `start_size` / `end_size` | 0.30 / 1.9 | Sprite size over lifetime, per-puff scale 0.75–1.25 |

Smoke uses 15° emission spread and wind acceleration (0.18, 0.04, 0) m/s². Each puff randomly chooses one of four static frames, rotates from −180° to 180° and slowly turns at ±8°/s. Alpha rises in the first 6%, holds through 40%, then fades to zero. Soft inward alpha edges retain the rendered cloud lobes. The explicit AABB includes spread, random scale, velocity and wind travel.

Three GPU particle draws for fire + sparks + smoke; Basic Room fire alone uses two and defaults to **20 particles total**. 178 uses 16 + 4 + 8 = **28**, below 40. No particle collisions or shadow casting; fixed simulation FPS 30; explicit visibility AABBs derive from the declared motion envelope. Preprocess equals the complete lifetime, so smoke fills at first display. The sprites are alpha blended and unlit; flame/embers have modest emission, smoke has none. The light uses smooth bounded sinusoidal variation, not strobe or random per-frame jumps. GPU simulation can differ across devices; fixed seeds support repeatable local captures, not cross-GPU identity.

Textures: flame and smoke strips each 1024 × 256 RGBA, four 256px frames; spark 64 × 64 RGBA. Original smoke sprites are rendered from the accepted R2.1 cloud meshes. Flame silhouettes are four authored curves with red/orange/gold colour stops following 172's accepted direction. Source generators: `tools/art/source/shared_fx/render_smoke.py` (Blender) and `pack_sprites.py` (Pillow/NumPy), followed by smoke-only `soften_smoke.py` for R2.3. They are authoring tools; the runtime folder has no dependency on those scenes/tools. Import with mipmaps and VRAM compression.

Review requires actual moving clips, whole-scene evidence and renderer draw counts; static screenshots alone do not establish particle acceptance. No physical-device performance claim.

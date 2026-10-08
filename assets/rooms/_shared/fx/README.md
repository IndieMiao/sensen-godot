# Shared hearth fire and chimney smoke

Self-contained Godot 4.7 Mobile/Vulkan hearth and chimney effects. Copy this entire directory, at the same `res://assets/rooms/_shared/fx/` path, into a consumer project. No room GLB, room atlas, scene assembler or game service is required. The fire from 5e5bf6af passed art-director review; SGODOT-236 can integrate it. The SGODOT-236 interface follow-up adds only `glow_boost` to the fire script; default 1.0 preserves its previous output. Fire textures and the shared helper are byte-identical.

Instantiate `fx_hearth_fire.tscn` / `fx_chimney_smoke.tscn`, set properties **before** `add_child()`, then place their Node3D roots. Metres, Y up. Particle geometry/count parameters are creation-time settings; recreate the instance to change them. `glow_boost` is a runtime multiplier: external consumers may set or tween it while this effect remains the sole light-energy writer.

| Fire parameter | Default | Meaning |
|---|---:|---|
| `emission_box` | (0.32, 0.015, 0.065) | Half extents; emitter footprint, not a full width |
| `flame_count` / `spark_count` | 16 / 4 | Clamped to 1–24 / 0–6; count the combined scene budget yourself |
| `flame_height` | 0.68 | Approximate maximum flame envelope from root, also scales velocity and sprite |
| `flame_lifetime` | 0.72 | Seconds, supported 0.5–0.9 |
| `light_energy` | 3.1 | Base OmniLight brightness |
| `glow_boost` | 1.0 | 外部临时调亮（如厨房开火 ×2.2），特效仍是唯一的闪烁写入者。Runtime multiplier (editor range 0–4); tween back to 1.0 after cooking |
| `flicker_strength` | 0.08 | Smooth low-frequency variation, clamped to at most ±10% |
| `light_path` | empty | Relative path to an existing OmniLight3D, retaining its name, placement, range and colour |
| `light_range` / `light_color` | 4.25 / FF8B36 | Used only when creating a light instead of borrowing one |

Existing `HearthGlow` can be borrowed via `light_path`. Stop any previous animation of its brightness; this effect becomes the sole flicker writer. Public owner references such as Basic Room's `fire: Node3D` may point to the root. Do not add a second light when one already exists.

| Smoke parameter | Default | Meaning |
|---|---:|---|
| `smoke_count` / `lifetime` | 8 / 4.0 | 8–10 particles / 3–4 seconds |
| `drift` | (0.28, 0.72, -0.04) | Metres/second; initial upward/sideways velocity ±12% |
| `emission_box` | (0.055, 0.01, 0.035) | Half extents around chimney mouth |
| `start_size` / `end_size` | See revision below | Sprite size over lifetime, per-puff scale 0.75–1.25 |

Smoke uses 15° emission spread and wind acceleration (0.18, 0.04, 0) m/s². Each puff randomly chooses one of four static frames, rotates from −180° to 180° and slowly turns at ±8°/s. The explicit AABB includes spread, random scale, velocity and wind travel.

The two branches intentionally retain their existing smoke revisions during this fire-interface change:

- `liubei/sgodot-236-basic-room-fire` / PR #29: R2.3 smoke copied from d04ce72e, sizes 0.30 / 1.9, alpha holds through 40%. Basic Room does not instantiate smoke.
- `wp-3d-scene` / `wp-3d-scene-liubei`: R2.5 smoke, sizes 1.2 / 2.6, alpha holds through 62%, smoke-only `billboard_keep_scale` preserves the normalised growth curve. Warm-white lit lobes, cool-grey shaded lobes and a narrow soft edge. No emission or HDR gain.

The fire script and this README are byte-identical between the two branches. The pre-existing smoke script/texture differences are retained; no smoke resource is changed by `glow_boost`. A later art integration should retain the newer smoke.

Three GPU particle draws for fire + sparks + smoke; Basic Room fire alone uses two and defaults to **20 particles total**. 178 uses 16 + 4 + 8 = **28**, below 40. No particle collisions or shadow casting; fixed simulation FPS 30; explicit visibility AABBs derive from the declared motion envelope. Preprocess equals the complete lifetime, so smoke fills at first display. The sprites are alpha blended and unlit; flame/embers have modest emission, smoke has none. The light uses smooth bounded sinusoidal variation, not strobe or random per-frame jumps. GPU simulation can differ across devices; fixed seeds support repeatable local captures, not cross-GPU identity.

Textures: flame and smoke strips each 1024 × 256 RGBA, four 256px frames; spark 64 × 64 RGBA. Original smoke sprites are rendered from the accepted R2.1 cloud meshes. Flame silhouettes are four authored curves with red/orange/gold colour stops following 172's accepted direction. Source generators: `tools/art/source/shared_fx/render_smoke.py` (Blender) and `pack_sprites.py` (Pillow/NumPy), followed by the revision-specific smoke-only `soften_smoke.py`. They are authoring tools; the runtime folder has no dependency on those scenes/tools. Import with mipmaps and VRAM compression.

Review requires actual moving clips, whole-scene evidence and renderer draw counts; static screenshots alone do not establish particle acceptance. No physical-device performance claim.

R2.4 growth control: `tools/art/source/shared_fx/verify_smoke_growth.gd` renders one fixed-frame puff at 0.24s / 2.60s. Production still uses 8 puffs, ±25% random size, four random frames and random rotation. PR #29 / Basic Room uses fire only. The `glow_boost` interface does not require re-recording 172/173/175/178 at its unchanged default.

# Stove Pot / Big Pot · SGODOT-282

`stove_pot.glb` contains two alternatives at the same bottom-centre pivot. Metres,
Y up, +Z front; import at scale 1. Select one variant's visibility per stove.

| Variant | Width × depth × height (m) | Triangles | Surfaces |
|---|---|---:|---:|
| `pot_normal` | 0.235981 × 0.212 × 0.140 | 380 | 1 |
| `pot_big` | 0.280 × 0.214 × 0.242 | 684 | 3 (body 1, lid 2) |

The complete GLB has 1,064 triangles, three meshes, two opaque matte materials,
no emission, no lights. Both pots are hollow and contain no food/soup surface.
The small 256² pottery/copper palette is shared; the wood knob also samples the
unchanged `../warming_cabinet/room_albedo_ao.png` atlas.

Paths after Godot import:

- `pot_normal/mouth`: `(0, 0.14, 0)`.
- `pot_big/mouth`: `(0, 0.18, 0)`.
- `pot_big/lid`: rear-edge pivot `(0, 0.181, -0.107)`; its mesh includes the knob
  and steam outlet. Retain its resting transform. Open by adding `(0,.06,0)`
  to the resting position and setting local X rotation to **−20 degrees**.
- `pot_big/vent`: `(0.062, 0.213, 0.039)`, direct child, marks the CLOSED outlet.
  This socket does not follow the lid; emit cooking steam when closed.

**Keep `stove_pot_import.gd` and the `.glb.import` together.** Godot 4.7 globally
uniquifies the second `mouth` to `mouth2`; the import script restores the two
local names, so the specified paths work without runtime repair.
`gltf/texture_map_mode=1` is explicitly committed.

`manifest.json` records dimensions, sockets, topology and the nine specified
stove coordinates. Integration reminders from actual room validation:

- Hide Basic `kettle`.
- Standard stove 3 uses **yaw 45°** to clear both the door frame and rear wall.
  Stoves 1–2 use yaw 0° and retain a 0.02 m gap between two Big Pots.
- Deluxe has another old kettle merged into `kitchen_fittings.glb`. The approved
  review fixture removes its exact 1,144 triangles; runtime integration must
  split/remove that obsolete part before placing new pots. Source room files
  and anchors are not changed by this art PR.
- Deluxe's highest grate surface measures **Y=1.292 m**, 1 mm above the spec's
  1.291. Review keeps 1.291 and records this small support contact explicitly.
  It is not included in the zero obstacle-penetration claim.

[Review, reproduction and detailed evidence](../../../docs/design/stove-pot-282-2026-10-15/README.md).

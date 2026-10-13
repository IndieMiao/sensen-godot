# Chef's Sign editable source

刘备 / SGODOT-282 / specification v1.3 / target 0.2.5.

`chef_sign_282.blend` contains two named collections with separate editable
construction objects: post, foot blocks, arm, knee, six interlocking eye/link
rings, four eye-bolt shanks, solid frame, red inset and graphic reliefs.
`reference.png` is the supplied concept; its proportions are not dimensions.
`spec-v1.3.md` includes 不知火舞's review, left-facing requirement and the final
0.50 m board / (5,14) placement revision. The v1.2 document remains historical.

Rebuild from the repository root:

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_chef_sign.py"
python3 tools/art/verify_chef_sign.py
```

The generator reuses the SGODOT-290 modeling/export helpers but only exports
the two chef signs and updates those two manifest entries. It overwrites this
generated `.blend`; preserve manual edits by incorporating them into the script.
Source collection `chef_sign_b` is displayed 1.2 m to the right of `chef_sign_a`;
the collection property records this presentation-only offset. Both GLBs export
about their own foot-bottom centre with identity transforms and +Z front.

The arm is authored directly to -X (left in the 43°/14.5° default camera).
Runtime scale is positive; do not apply the old concept's additional X mirror.
The two exported empty nodes are both named `board_center`, at
`(-0.332, 1.285, 0)` in Godot metres. Source empties include variant prefixes to
avoid Blender's global duplicate-name suffix. The full PackedScene retains the
empty; `FarmArt.instance()` extracts only the mesh, so recreate the hook from
the manifest when using that path.

The board is 0.50 × 0.45 m with a 0.05 m frame and 1.06 m bottom; icons are
uniformly scaled 5/6, preserving the frame rim. The arm is shortened to match.
The requested +0.18 m X placement offset is applied only by the integrator or
review fixture, never baked into the GLBs. It leaves 0.077 m path intrusion;
final bench/click overlap must be checked in the integrated scene.

See the [review and integration contract](../../../../docs/design/chef-sign-282-2026-10-13/README.md).

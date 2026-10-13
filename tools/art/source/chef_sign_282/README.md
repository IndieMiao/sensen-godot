# Chef's Sign editable source

刘备 / SGODOT-282 / specification v1.2 / target 0.2.5.

`chef_sign_282.blend` contains two named collections with separate editable
construction objects: post, foot blocks, arm, knee, six interlocking eye/link
rings, four eye-bolt shanks, solid frame, red inset and graphic reliefs.
`reference.png` is the supplied concept; its proportions are not dimensions.
`spec-v1.2.md` includes 不知火舞's review and the latest left-facing requirement.

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
`(-0.382, 1.285, 0)` in Godot metres. Source empties include variant prefixes to
avoid Blender's global duplicate-name suffix. The full PackedScene retains the
empty; `FarmArt.instance()` extracts only the mesh, so recreate the hook from
the manifest when using that path.

See the [review and integration contract](../../../../docs/design/chef-sign-282-2026-10-13/README.md).

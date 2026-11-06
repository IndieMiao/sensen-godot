# Monster Art Contract

Runtime delivery branch: `art/monsters-355`, based on `farm-dev`. Each monster has
`<id>/<id>.glb`, `<id>/<id>.json` and the Godot-generated `.glb.import` with UID.
Models use metres, Y up, front +Z, one surface, linear vertex colour, rigid skinning
and a stationary `root` bone. `UV2.x` is the tint mask: 1 for tintable parts, 0 for
protected face/detail colours.

The client reads `radius`, `hit_point`, `durations` (seconds by animation name),
top-level `hit_at` (attack event time), and `spore_at` for shroomling. Additional
`anims`, bounds and art metadata are informational. Idle/move/fly_high/stunned
looping is selected by the client. Movement, hit flash, variant tint and the
existing circular blob shadow belong to runtime code.

`material_import.gd` only enables linear vertex colours on imported materials and
disables real mesh shadow casting. It does not implement tinting, hit flashes or
other runtime effects. Keep its `.gd.uid` alongside it. Every monster's
`.glb.import` references the shared script in `[params]`:

```ini
import_script/path="res://assets/monsters/material_import.gd"
gltf/texture_map_mode=1
```

Run Godot import after fetching the files. This fixes the Godot 4.7.2 import case
where COLOR_0 is present but vertex colour is not enabled on the material.

Editable Blender sources and review records are on
`wp-3d-scene-huangzhong-monsters-355`, under `tools/art/source/monsters/` and
`docs/design/monsters-355-2026-11-02/`. Stage and dimensions are recorded per asset;
blockout delivery is not final visual acceptance or permission to merge/release.

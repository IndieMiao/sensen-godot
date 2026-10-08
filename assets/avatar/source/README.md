# Avatar part sources

`assets/avatar/source/<part id>/` holds each part's source files as `tools/unity_export` staged them from the Unity
backup: the FBX, its albedo texture and their `.import` settings. `tools/pipeline/extract_parts.gd` turns them into
`assets/avatar/parts/<id>.res` (plus `<id>_scene.tscn` for socket parts) and the entries in
`assets/avatar/parts_manifest.json`. The built parts reference the textures here at runtime, so these folders are
imported like any other asset and must not get a `.gdignore`.

Adding parts without touching the existing ones: `extract_parts.gd -- <recipes> --append` (see `README_229.md`).

## Import errors from the Unity FBX files are expected

A fresh import (a new clone, or a cleared `.godot` cache) prints a batch of errors such as

```
ERROR: Can't open file from path 'res://assets/avatar/source/cloth11/T_skin02_eyes_D.png'.
WARNING: FBX: Image index '0' couldn't be loaded from path: res://assets/avatar/source/cloth11/T_skin02_eyes_D.png …
```

The Unity FBX files still name textures from the old Unity and UE projects that were never copied over. Godot's FBX
importer looks for those files before it reads any import option, so `fbx/embedded_image_handling` cannot silence it.
Nothing uses those textures: each recipe names the part's albedo and the extractor builds its own material. The
errors come once per working copy and change neither the parts nor the extraction.

FBX files that name missing textures (scanned 2026-10-08, missing textures per file):

| Source | Missing |
|---|---|
| `base/SK_DtBase.fbx` | 5 |
| `body00/SK_DtBase.fbx` | 5 |
| `cloth0/SK_DtBase.fbx` | 4 |
| `cloth1/SK_dt_skin01.fbx` | 7 |
| `cloth1_1/SK_dt_skin01.fbx` | 7 |
| `cloth11/SK_dt_skin11.fbx` | 4 |
| `cloth11_npc_mei/SK_dt_skin11.fbx` | 4 |
| `cloth28/SK_dt_skin28.fbx` | 3 |
| `cloth42/SK_dt_skin42.fbx` | 3 |
| `eyes00/SK_DtBase.fbx` | 5 |
| `glass1/SK_dt_skin01.fbx` | 6 |
| `hairhat12_npc_mei/SM_hairHat12.fbx` | 1 |
| `messengerbag1/SK_dt_skin01.fbx` | 6 |
| `messengerbag2/SK_dt_skin06.fbx` | 5 |
| `messengerbag3/SK_dt_skin40.fbx` | 4 |
| `messengerbag4/SK_dt_skin47.fbx` | 4 |
| `shoes0/SK_DtBase.fbx` | 4 |
| `shoes1/SK_dt_skin01.fbx` | 6 |
| `shoes2/SK_dt_skin02.fbx` | 4 |
| `shoes3/SK_dt_skin03.fbx` | 4 |
| `shoes4/SK_dt_skin04.fbx` | 4 |
| `shoes5/SK_dt_skin05.fbx` | 5 |

Any other error during import is real and worth a look.

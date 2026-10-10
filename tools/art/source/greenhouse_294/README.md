# SGODOT-294 editable greenhouse

刘备 · Blender 5.2.2. Reference: `greenhouse_sheet_v1.png`, Plane SGODOT-294
comment `8dd3e15a-46b7-44d4-ae6c-75c0b5c743fe`, with 不知火舞's annotated
review `ab8d4bde-92fe-4d73-998e-0b5dc64a76ad`.

The retained [original brief](spec-v1.1.md) is amended by the later approved
[clearance, ridge and branch decisions](spec-amendments-v1.3.md). Dimensions
come from those specifications, not measurements of the concept image.

```sh
blender --background --factory-startup --python "$PWD/tools/art/build_greenhouse.py"
```

Rebuild writes only the three `greenhouse_*.glb` files, their three manifest
entries and `greenhouse_294.blend`. Other farm kit assets are untouched.
The script is standalone and has no dependency on PR #283's decoration files.
It uses the same deterministic rounded geometry and vertex-colour export method.

Three collections stay assembled on a common world origin. Corner posts,
plinths, eave beams, knee braces, leaves, watering can, ridge, rafters, gable posts
and panes have editable names. Runtime export joins evaluated copies only.
Rerunning the generator replaces manual source edits; update the script for
persistent changes. `.gdignore` excludes this directory from Godot imports.

Coordinates are Godot metres `(x, y, z)`, mapped to Blender `(x, -z, y)`.
All three exports have identity transforms and an origin at ground centre.
The roof and glass vertices retain their absolute height above this shared origin;
do not drop either part independently onto the floor or recenter it on its bounds.

Colours use linear RGB vertex paint, opaque alpha 1, no textures/UVs. The GLB
material is an opaque fallback. Base and roof use `FarmArt.material()` in Godot.
Glass uses a duplicate at runtime so alpha changes cannot affect other farm assets.
The glass is six triangles: two slope quads and two gable triangles, no back copies.
The preview enables two-sided rasterization on the glass material, not geometry.

See the [delivery and integration notes](../../../../docs/design/greenhouse-294-2026-10-10/README.md)
for review commands, dimensions, opacity settings and the optional roof socket.

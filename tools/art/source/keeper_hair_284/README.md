# Keeper hair variants · SGODOT-284

刘备 · 2026-10-14. 上官婉儿 assigned two texture-only variants selected by
不知火舞 for generated-city keepers, outside 0.2.6.

hairhat41_npc_auburn copies hairhat41's SM_hairHat41.fbx unchanged and maps only
hair pixels to #5E2F1C / #8A4A2E / #B06A45. The ochre and pale pink-white
accessories retain original RGBA. hairhat43_npc_black copies SM_hairHat43.fbx
unchanged and maps only golden hair to #161312 / #2A2624 / #4A4440, retaining
the pink accessories. Original baked luminance variation remains monotone.

The source FBXs and base/recolored PNGs live under assets/avatar/source in the
runtime PR. No geometry is changed and no new Blender source is needed.
Run the art script against the separate runtime checkout:

~~~sh
python3 tools/art/recolor_keeper_hair_284.py --runtime-root /path/to/runtime
~~~

Requires Pillow and NumPy. [texture-validation.json](texture-validation.json)
records each palette, mask, luminance knots, preserved pixel counts and source
hashes. Import parameters and all material floats match the original part;
hairhat41 emission is 0.7 and hairhat43 emission is 0.3, both smoothness 0.1.
[Review and reproduction instructions](../../../../docs/design/keeper-hair-284-2026-10-14/README.md).

# Post Office SGODOT-215 additions

Editable named source: `post_215.blend`, Godot metres Y-up/+Z-front through Blender `(x,-z,y)`. `build_post_215.py` exports evaluated joined copies, keeping source pieces editable. `arrange_post_215.py` writes the approved left-desk layout and actual GLB statistics. The original Post Office source and all original GLBs/atlas stay unchanged.

`atlas-swatches.json` pins the original shared PNG and sampled color regions. No new pixels, bake, texture or per-part texture duplicate. Reused parcels, mailbag and desk dressing keep the original UVs. Geometry has no baked direct light; Godot uses the kit's shared atlas material.

See `docs/design/post-215-2026-10-16/README.md` for placement consent, preserved pieces, exact metrics, generation/render commands, collision scope and programmer handoff.

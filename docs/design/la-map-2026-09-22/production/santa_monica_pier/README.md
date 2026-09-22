# Santa Monica Pier production sprite

Final game asset: `assets/map/poi/santa_monica_pier.png` — 512×512 RGBA.

Generated with the Sensenjoy API, `gpt-image-2`, using the bundled imagegen CLI in explicit API mode. `reference-crop.png` is a crop of the approved `generated/la-map-main-v1.png`, attached as the image input. The complete generation prompt is in `prompt.txt`. The request asked for 1024×1024 at high quality; the provider returned a 1254×1254 raster. No credentials are stored here.

`raw-magenta.png` is the API output. `transparent-master.png` was extracted with the bundled `remove_chroma_key.py` using `#ff00ff`, soft matte, transparent threshold 18, opaque threshold 110 and spill cleanup. The production image is cropped to alpha > 32, scaled within 464×464, and placed in a 512×512 canvas with a 24 px bottom margin. Final alpha values below 8 are cleared. Its ground anchor is `(0.5, 0.953125)` in normalized sprite coordinates.

Visual QA in `qa-light-dark-small.png` checks cream and dark blue backgrounds plus 160, 112 and 80 px map sizes. The wheel, pilings and complete narrow water footprint remain intact; there is no full ocean rectangle, UI, text or person. No visible magenta halo remains. At 80 px the Ferris wheel and diagonal pier are recognizable; larger display sizes preserve pavilion detail.

`provenance.json` records source crop, requested and returned dimensions, extraction parameters, final bounds and SHA-256.

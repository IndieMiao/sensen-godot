# Venice Beach production sprite

Final game asset: `assets/map/poi/beach.png` — 512×512 RGBA, ground anchor `(256, 480)`.

Generated through the Sensenjoy API with `gpt-image-2`, using the bundled imagegen CLI in explicit API mode. The attached image input, `reference-crop.png`, comes from the Venice Beach corner of the approved `generated/la-map-main-v1.png`. `prompt.txt` contains the complete prompt. Requested size: 1024×1024, high quality. The provider returned 1254×1254. No credentials are stored here.

`raw-magenta.png` is the provider output. `transparent-master.png` uses the bundled chroma-removal script with key `#ff00ff`, soft matte, transparent threshold 18, opaque threshold 110 and spill cleanup. The final sprite is cropped to alpha > 32, fit within 464×464, and placed in a 512×512 canvas with 32 px below the base. Final alpha values below 8 are cleared.

The complete hut, exactly two surfboards, both palm crowns and small sand/water footprint were visually checked. `qa-light-dark-small.png` shows the sprite on cream and dark blue, plus 160, 112 and 80 px sizes. No visible magenta edge remains; there are no people, UI, text or large ocean backdrop.

See `provenance.json` for crop coordinates, parameters, bounds and SHA-256.

# Universal Studios Hollywood production sprite

Final game asset: `assets/map/poi/theme_park.png` — 512×512 RGBA, ground anchor `(256, 480)`.

Generated through the Sensenjoy API with `gpt-image-2` and the bundled imagegen CLI in explicit API mode. Two actual image inputs were attached: `reference-globe-crop.png` from the supplied design board for the globe subject, and `reference-approved-style.png` from the approved LA main visual for material and lighting. The full prompt is stored in `prompt.txt`. Requested size: 1024×1024 at high quality; provider returned 1254×1254. No credentials are stored here.

`raw-magenta.png` preserves the API output. `transparent-master.png` uses the bundled chroma-removal script: key `#ff00ff`, soft matte, transparent threshold 18, opaque threshold 110, spill cleanup enabled. The final sprite is cropped using alpha > 32, fitted inside 464×464, then positioned on a 512×512 canvas with 32 px bottom padding. Final alpha values below 8 are cleared.

Visual inspection covers the complete globe, blank ring and entrance, both palms and the full low plaza base. `qa-light-dark-small.png` shows cream/dark backgrounds and 160, 112 and 80 px map sizes. The globe remains identifiable at the smallest size, with no readable text, person, UI, clipped element or visible magenta halo.

Crop coordinates, parameters, final bounds and SHA-256 are stored in `provenance.json`.

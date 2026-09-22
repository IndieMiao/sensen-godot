# Map secondary panels — design QA, 2026-09-22

Scope: apply the approved compact LA map visual style to neighbour browsing, NPC cards and the place list, then check interaction and multiple viewports. The user accepted the size adjustment and requested continuation.

Source visual truth: `docs/design/la-map-2026-09-22/generated/la-map-main-v1.png` (848×1855), plus the accepted compact implementation from `docs/design/la-map-scale-2026-09-22/qa/`. There is no separate approved neighbour-sheet mock. The main visual is the source for palette, typography, image treatment and component proportions; old runtime captures are the concrete before state.

Implementation: emulator-5560, `com.sensen.journeyuiqa / 0.16.13-mapqa3`. Main viewport720×1560 physical /360×780 logical. Short720×1280 /360×640 and wide960×1280 /480×640 were exercised in the same session, then the original dimensions restored.

## Evidence inspected together

- `docs/design/la-map-panels-2026-09-22/qa/reference-neighbours.png`: source, before and after in one input, proportionally fitted to360px widths; no aspect stretching. Source content differs from the real map; this is style comparison, not identical geography.
- `panels-comparison.png` in the same directory: matched before/after neighbour, NPC and list crops. Each pair has the same crop and scale. NPC points can have different provider labels between captures; controls are in the same selected-resident state.
- `responsive-comparison.png`: actual short/wide screenshots at a common0.625 pixel scale. It shows the selected-neighbour preview and NPC action with the dock still visible.

All three combined images were opened and visually inspected. Original screenshots, native control rectangles and scenario logs are retained under `output/la-map-panels-2026-09-22/android/`.

## Findings and fixes

- [P1, fixed] The neighbour drawer still used the old purple nine-slice material and repeated the farmer title. Replaced with one white panel/count header, neutral cards and lime selection. Runtime height is108 logical pixels without selection,170 with the farm preview; the dock has8px clearance.
- [P2, fixed] NPC action used a wide white button and its status repeated the city. A compact lime104×44 action and existing resident status now carry the next action. The same server-owned NPC route remains.
- [P2, fixed] New landmark thumbnails inherited the icon text tint and rendered nearly black. Initial proof is `iteration-1-places.png`. Raster icon color is now white in all active states, preserving original asset colors; final list capture confirms the correction.
- [P1, fixed] A cached farm with no journey data could miss the close button. City-map setup now makes the close control available independently. The regression test checks it and the count label in four logical viewport shapes.
- [P2, fixed] Independent map sheets could overlap and the navigation always looked selected on Map. Opening neighbours, the place list or a detail now dismisses the other sheet; the active navigation color follows the drawer. Native and Android flows prove those transitions without changing the saved farm choice.

## Five required fidelity surfaces

- Typography: existing Nunito/Noto Sans SC retained;13px count title,11px card names/actions and10px secondary information remain readable. Long names use existing ellipsis. No missing Chinese glyphs in inspected states.
- Layout: duplicate header removed,118×48 cards,50px farm preview,44px primary touch heights. Short/wide captures and control rectangles confirm close/visit/navigation remain inside the viewport and separate from the dock.
- Colors: charcoal copy, white surfaces, pale neutral cards and lime selection/actions extend the approved palette. Old purple texture borders removed from these panels.
- Image quality: actual farm thumbnails and Sensenjoy landmark assets reused; original colors preserved. NPC portraits use cached real game outfits. No generated placeholder data or replacement CSS/vector art.
- Copy/content: farm counts and crop summaries remain from existing responses; NPC identity, unlocks and status remain authoritative. No new rewards or invented venue details.

## Verification

151 native map checks passed (`reports/report_1323/results.xml`); the final Android APK passed36 touches including the primary flow, real neighbour-farm access, mutually exclusive sheets and two additional viewport sizes. Wallet, bag, cells and farm identity were compared on the isolated account. Runtime log contains no script/parse/compile errors. Installed APK readback hash matches the built artifact (`output/la-map-panels-2026-09-22/verification/build.json`).

No actionable P0/P1/P2 findings remain in this scope. This is an Android development sample; physical-device/iOS acceptance and complete application-wide redesign are not claimed. Prior QA is preserved at `docs/design/la-map-panels-2026-09-22/qa/previous-design-qa.md`.

final result: passed

Phone follow-up: user requested installation for their review. Observer-free Journey0.16.13 is installed onV2509A; exact APK/signature, cold login and current-save preservation verified. Full new map flow was not repeated on the phone. See `docs/qa/la-map-phone-2026-09-22.md`.

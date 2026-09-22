# LA map interactions — design QA, 2026-09-22

User feedback from the installed map and the self-sent Feishu recording replaces the prior neighbour-drawer and collision-avoidance design. Other players now expand from portraits into matching 3D characters at their own coordinates. A foot-centered 0.52-second squash/stretch popup operates independently of camera scale. One remote character is expanded at a time; selection does not move the camera.

The LA map no longer creates a nearby-player drawer or neighbour navigation item. Player data feeds geographic markers directly. Landmarks, NPC portraits, player portraits and POIs use direct projection, including at screen edges and beneath panels. There is no avoidance offset, spatial cluster expansion, farm-miniature layout or reservation feedback. POI updates merge stable source IDs in a bounded browsing-session cache. Source rank and zoom determine detail; category art scales smoothly from 32 to 64 logical pixels so dense streets do not form an oversized row of shops.

Compact white/lime UI, Chinese font coverage and the approved visual assets remain. The three bottom actions are Map, Farm and Me. POI cards remain basic source information; NPC unlocks and the resident destination still follow the existing state.

Evidence: [portrait / selected-character comparison](docs/design/la-map-interactions-2026-09-22/qa/player-comparison.jpg), [12-second interaction recording](docs/design/la-map-interactions-2026-09-22/qa/map-interactions.mp4), [full QA and delivery receipt](docs/qa/la-map-interactions-2026-09-22.md).

157 native map tests and 28 isolated Android touches passed, including three viewport shapes, rapid replacement, dragging from the selected actor, NPC/POI/farm/outfit routes and save preservation. Four frame traces contain 16,596 projection checks with maximum error below 0.00002 logical pixels. The final screenshots and recording were visually reviewed. Overlapping real anchors remain overlapping; zooming exposes geographic separation, rather than moving features to make room.

The exact observer-free Journey 0.16.14 / 2026092208 update is installed and readback-verified on V2509A with the original certificate, five identity/appearance/preferences files and current save preserved. Cold login passed. Full map interaction verification is from the emulator; phone interaction acceptance remains the user's review. No server deployment, public publication or external delivery.

Prior panel design QA is preserved at `docs/design/la-map-interactions-2026-09-22/qa/previous-design-qa.md`.

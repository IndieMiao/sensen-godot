# SGODOT-318 Culture Hall - Module List (R3)

- **Inventory groups:** 15. Group quantities and individual object quantities are not summed into an ambiguous instance total.
- **Seating:** 1 bench: 3 seats; 1 round stool: 1 seat. Total 4.
- **Scale:** 6.8 x 6.4 m design footprint; wall height 3.7 m. Drawing is schematic, not a measured survey.
- **Approved main:** retained byte-for-byte. This revision corrects companion documents only.
- **Reuse status:** reuse sources are design references/candidates, not proof of model extraction or runtime integration.

| Code | Module ID | Name | Quantity | New / Reuse | Reuse source | Notes |
|---|---|---|---:|---|---|---|
| M01 | CULT-SHELL-WALL | Common hall wall shell | 1 | Reuse | Hotel Lobby common shell | Cream walls, top trim and wainscot; do not claim geometry re-measured. |
| M02 | CULT-FLOOR-TILE | Terracotta floor slab | 1 | New | Common hall floor footprint | Keep current slab thickness and footprint. Physical dimensions require approved plan. |
| M03 | CULT-DEC-MOSAIC | Circular floor mosaic | 1 | New | None | Centered decorative medallion, not a raised obstacle. |
| M04 | CULT-FURN-CASE | Glass display case | 2 | New | Shared case design | Two instances; left and front-right. No additional case behind the central mosaic. |
| M05 | CULT-DISPLAY-PLINTH | Corner display plinth | 1 | New | None | User-approved back corner position. Together with two cases, total display stands = 3. |
| M06 | CULT-DEC-ART | Framed abstract artwork | 6 | New | Shared frame design | Six frames, two rows of three. Abstract color blocks. |
| M07 | CULT-SEAT-BENCH | Green upholstered bench | 1 | Reuse | Shared Seating | Three designated seat positions S01-S03; quantity is one bench, not three benches. |
| M08 | CULT-SEAT-STOOL | Round wooden stool | 1 | Reuse | Shared Furniture | S04 is on the round stool, not a fourth point on the bench. |
| M09 | CULT-VEG-PLANT | Potted monstera | 1 | Reuse | Shared Plant Library | Front-left planting. |
| M10 | CULT-LIGHT-TRACK | Spotlight track rail | 1 | Reuse | Shared Lighting | One continuous rail. Lamp heads are listed separately. |
| M11 | CULT-LIGHT-SPOT | Track spotlight head | 3 | Reuse | Shared Lighting | Three heads on one rail; do not count as three rails. |
| M12 | CULT-WALL-WINDOW | Multi-pane window | 2 | Reuse | Common Hall Shell | Two left-wall windows. |
| M13 | CULT-LIGHT-SCONCE | Wall sconce | 2 | Reuse | Shared Lighting | Two left-wall lights. |
| M14 | CULT-PROP-EXHIBITS | Exhibit object set | 1 set | New | None | Seven displayed objects visible: three in each glass case plus the corner ammonite. Classify fossils/vessels during 3D asset specification rather than retaining old mismatched totals. |
| M15 | CULT-SIGN-RUNTIME | Blank runtime sign plaque | 1 | New | Shared runtime signage | Blank plaque above artwork under right-wall trim; no baked text. |

## Consistency notes

- This card is SGODOT-318; replace all SGODOT-315 references in supplied culture documents.
- Use 4 designated seat positions: bench 3 plus round stool 1. Seat points indicate planned sitting locations, not measured collision bounds.
- Display stand count is 3: two glass cases and the user-approved corner plinth.
- Keep the current corner plinth position. A 2 m clear rear-wall strip is not verified by this image and must not be claimed as passed.
- The normal POI behavior is walking, sitting, emotes and meeting players; no NPC or counter transactions.
- Add a top 100 px HUD band and bottom 90 px backpack band to the 360x800 annotated portrait only; preserve the clean portrait separately.
- Current palette is A only. Do not invent additional approved color variants.
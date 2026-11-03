# SGODOT-317 Classroom - Module List (R3)

- **Inventory groups:** 19. Group quantities and individual object quantities are not summed into an ambiguous instance total.
- **Seating:** 6 student desks and 6 separate stools = 6 seats. Cushions are decoration.
- **Scale:** 6.8 x 6.4 m design footprint; wall height 3.7 m. Drawing is schematic, not a measured survey.
- **Approved main:** retained byte-for-byte. This revision corrects companion documents only.
- **Reuse status:** reuse sources are design references/candidates, not proof of model extraction or runtime integration.

| Code | Module ID | Name | Quantity | New / Reuse | Reuse source | Notes |
|---|---|---|---:|---|---|---|
| M01 | CLASS-SHELL-WALL | Wall and sage wainscot shell | 1 set | Reuse | SGODOT-315 public hall shell (design basis) | Design wall height 3.7 m. Keep two cutaway walls and aligned floor corners. |
| M02 | CLASS-FLOOR | Wood plank floor | 1 surface | Reuse | SGODOT-315 public hall shell (design basis) | Common-shell design footprint 6.8 m x 6.4 m. |
| M03 | CLASS-DESK | Student desk | 6 | Reuse | Basic Room desk (candidate) | Desk only; do not include a stool in this module count. |
| M04 | CLASS-STOOL | Student wood stool | 6 | Reuse | Basic Room stool (candidate) | Six separate stools, one per student desk, giving six sit points total. |
| M05 | CLASS-DESK-PROPS | Open book and pencil cup set | 2 | New | None | Two visible desk stationery sets. Empty desks stay empty. |
| M06 | CLASS-BLACKBOARD | Blank blackboard | 1 | New | None | No writing; ordinary classroom base variant. |
| M07 | CLASS-TEACHER-DESK | Teacher desk | 1 | New | None | Scenery centerpiece only; no teacher NPC position or transaction function. |
| M08 | CLASS-GLOBE | Globe | 1 | New | None | Placed on teacher desk; separate object count. |
| M09 | CLASS-REAR-BOOKCASE | Rear tall bookcase | 1 | Reuse | Basic Room shelving (candidate) | Blank book spines; one tall bookcase in the rear corner. |
| M10 | CLASS-RIGHT-BOOKCASE | Right storage bookcase | 1 | Reuse | Basic Room shelving (candidate) | Books, rolls and containers belong to this display assembly. |
| M11 | CLASS-LOW-BOOKCASE | Left low bookcase pair | 1 set (2 units) | Reuse | Basic Room shelving (candidate) | Two visibly adjacent low cabinet units; retain as one documented pair. |
| M12 | CLASS-STUDY-PROPS | Plaster bust and geometric study object | 1 set | New | None | One bust plus one geometric model on the low bookcase pair. |
| M13 | CLASS-CUSHION | Reading floor cushion | 2 | New | None | Decorative reading-corner objects only. Not extra sit points; do not count as the approved 0.715 m kindergarten soft stools. |
| M14 | CLASS-PENDANT | Pendant lamp | 2 | Reuse | Shared Lighting (candidate) | Two suspended lights. |
| M15 | CLASS-WINDOW | Multi-pane window | 2 | Reuse | SGODOT-315 public hall shell (design basis) | Two windows in the left wall. |
| M16 | CLASS-SCONCE | Wall sconce | 2 | Reuse | Shared Lighting (candidate) | Two wall-mounted lights. |
| M17 | CLASS-PLANTS | Potted plants | 1 set (6 visible pots) | Reuse | Shared Plant Library (candidate) | Four window pots, one on the rear bookcase and one on the right wall shelf. |
| M18 | CLASS-RIGHT-SHELVES | Wall display shelf pair | 1 set (2 shelves) | Reuse | Basic Room shelving (candidate) | Display art, books and one plant; no transaction function. |
| M19 | CLASS-RUNTIME-SIGN | Blank runtime sign | 1 | New | None | Centered below the right-wall top trim; text inserted at runtime. |

## Consistency notes

- Use SGODOT-317 in every title and metadata field; remove wrong SGODOT-315 references.
- Ordinary Classroom is the current base variant; remove the obsolete Art Classroom title from its base palette.
- Six student desks plus six separate stools. Do not count a desk-and-stool assembly and its stool again.
- Exactly six interactive student seats. Two floor cushions are decorative and are not additional runtime seating.
- Teacher desk is scenery, with no teacher NPC or trade interaction.
- Overall design dimensions: 6.8 m x 6.4 m; wall height 3.7 m. Do not infer other precise furniture dimensions from this image.
- Mark the blank right-wall panel Runtime sign.
- Show top 100 px HUD and bottom 90 px bag bands on the 360 x 800 review crop; preserve a separate clean crop.
- Any B/C/D color or theme alternative must be labelled as a proposed variant, not as the approved base or an already integrated asset.
# Los Angeles native map sample — design QA, 2026-09-22

Source visual truth: `docs/design/la-map-2026-09-22/generated/la-map-main-v1.png` (848×1855). User approved this visual and requested a working Godot map sample, with real coordinates, real POIs, existing characters and saved progress.

Implementation: Android `com.sensen.journeyuiqa`, emulator-5560, 720×1560 physical pixels, 360×780 Godot logical viewport; the safe content width is328 logical pixels. This is the existing native game, not a web implementation. Evidence is from the installed APK and native Godot control-tree-driven touches.

Full-view comparison: `docs/design/la-map-2026-09-22/qa/comparison.jpg`. Approved source and three final runtime screenshots were placed together, opened and inspected. Content-only images are proportionally scaled to360px width; the source is788px tall and runtime780px, without stretching either. Source represents a stylized city overview with a place selected. Runtime evidence includes actual city overview with a place selected, real dining POIs near the farm, and Griffith Observatory at street zoom. Geography and current accounts differ explicitly; those are not pixel-identical content states.

Focused UI comparison: `docs/design/la-map-2026-09-22/qa/ui-focused.jpg`, inspected at matching360px widths, covers the city/filter header and place-card/navigation region.

## Findings and resolved iterations

- [P1, fixed] Initial native feature/style capability checks used Object.has_method on a JavaObject. The wrapper did not advertise Java methods there, so POIs were unavailable and the map style did not change. The bridge now uses has_java_method with a tested fallback for non-Java stubs. Final device evidence has a pastel map and real provider POIs.
- [P1, fixed] The place card retained an excessive height after its empty-label construction state. Deferred layout now uses its actual minimum height; final card is90 logical pixels for the sample landmark and leaves navigation fully visible. A native regression test covers the card and refreshed list IDs.
- [P2, fixed] Initial landmark images competed with the self character and portraits. Art sizes, overlap reservations, display density and bounded screen offsets were adjusted. Geographic anchor positions remain unchanged and short offset leaders indicate them. Low-priority symbols are omitted when they cannot fit; lists and zoom retain access.
- [P2, fixed] Rebuilding the place list before queued old children were removed could suffix control names and break repeated selection. Old rows are detached before replacement. The final full scenario repeatedly opens and selects the list after returning from other scenes.
- [P2, fixed] Recenter after changing city zoom reused the previous camera's screen offset, leaving the character at an edge. City browsing now centers its actual farm coordinate, covered by a native test and real dining-view screenshot.
- [P2, fixed] The north-up metropolitan composition compressed most LA places into one horizontal band. City overview uses42° bearing /35° pitch and an explicit rotating north arrow; the N button restores0° without changing any data. Street coordinates, distances and geography remain real.

## Required fidelity surfaces

- Fonts and typography: existing Nunito/Noto Sans SC retain Chinese coverage. Dark title, compact 13px filters, 15px place heading and11–12px supporting copy are readable. Long marker names use ellipsis while the selected card shows full names. The existing bold face is somewhat heavier than the concept's address copy; this is P3 polish.
- Spacing and layout rhythm: compact top chrome, 44px minimum major controls, single white bottom navigation capsule and a short place card. Fixed safe-area layout and deferred card sizing keep actions visible. Detail screenshots show no viewport overflow.
- Colors and tokens: ivory ground, sage land use, aqua water, muted labels, white floating surfaces and a lime active filter reflect the chosen reference. Heavy purple borders were removed from map-owned controls and map owner badges. Other game screens retain their existing styles in this first map sample.
- Image quality:13 individual API-generated RGBA miniature assets share the selected matte style. Reviewed the source/output contact sheet plus light/dark alpha QA from the asset tasks; no placeholder drawings replace those assets. Unknown POI types use the existing icon library, deliberately smaller than the illustrations.
- Copy and content: names/categories come from loaded Mapbox POIs; authored LA landmarks have basic known information. Missing addresses stay absent. NPCs follow current unlocks; remote avatars use the existing game-avatar reference rather than invented profile photos. Real map distribution and existing saved outfit take precedence over concept-only scenery and sample portraits.

## Scope differences and follow-up polish

The approved image is an illustrative city composition; runtime keeps actual LA geometry. It therefore has variable density across zoom levels and does not reproduce every landmark, player and restaurant simultaneously on one street. Basemap coloring is implemented; full clay-like terrain relief is not part of this first native sample. Portraits use existing game identities because the API has no account-photo field. These limits were stated in the assessment and implementation notes; no claim of a pixel-identical map landscape is made.

P3 follow-up: further tune landmark/portrait density at metropolitan zoom and text weight after user review. Browser accessibility, iOS native POIs, physical-device performance and long-session profiling are outside this Android sample's evidence.

## Validation

149 Godot map tests passed; the final north-control layout had a further6-test check. Android native build/unit task passed. A final24-touch scenario covers city/list/landmark/dining/NPC/neighbour farm/outfit/own farm/drag/tap behavior, with unchanged isolated-account wallet, cells and bag. Runtime log contains no script/parse/compile errors. Representative screenshots sampled60fps; this is not a sustained performance claim.

The original root QA report was preserved at `docs/design/la-map-2026-09-22/qa/previous-design-qa.md`.

final result: passed

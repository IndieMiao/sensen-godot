# Farm UI Playability

2026-09-05. Branch: `feat/farm-ui-playability`.

## Implemented Design

The farm has three stable regions: status and navigation at the top, an unobstructed playfield, and one contextual action dock at the bottom. Goals, the stall, and the director share one modal layer. Opening a modal hides the dock and plot hints; close, backdrop tap, and Android Back dismiss it before navigating.

| Element | Specification |
| --- | --- |
| Type | Nunito, weight 650; labels 12-14, compact headings 16-18 logical pixels |
| Surfaces | `#fcfefa` paper, `#d2e2d6` borders; radius at most 8 |
| Primary action | `#287c59` green with light text |
| Secondary colors | `#43869f` care, `#ecc568` harvest/selection, `#ce705c` blocked movement |
| Controls | Minimum 44 logical pixels; primary farm action 52 high |
| Plot hints | 20-pixel circles, 12-pixel Lucide glyphs; 27-pixel minimum separation |
| Plot progress | Thin selection outline and a small radial arc on the active plot |
| Movement | Ground target ring, route dots, short arrival fade; coral rejected target |
| Messages | Bounded, wrapped toast below the status band; approximately 3 seconds |
| Map | Zoom 15-18, buttons/pinch/double-tap; elastic overscroll at limits |
| Farm focus | 0.55-second camera transition, matching thumbnail and boundary selection |

The same scoped theme covers city selection, map, farm, visitor, stall, goals, director and dressing controls. Lucide SVG source icons and license live in `assets/ui/icons/lucide/`; Nunito and its OFL are in `assets/ui/fonts/`.

## Behavior Fixes

- Street mode previously hid markers and skipped nearby avatars. The player's anchor also stayed at the city center while the map moved to the farm. Farm thumbnails and snapshot-backed owner representations now use the farm blueprint's coordinates.
- Nearby farms already existed on the server. These are public-farm snapshots and two system samples, not realtime presence or live multiplayer movement.
- If login completes after the map opened with bundled samples, the nearby list refreshes. Online snapshot requests take priority over bundled samples.
- Selecting another farm previously fetched its preview without moving the camera. Selection now updates the camera, thumbnail, outline and preview together. Returning to self clears the other farm's preview.
- Map zoom no longer returns early in street mode. Pinch and the zoom buttons share the same bounds; fractional pinch levels can still reach both limits.
- The joystick node is removed. Tapping ground shows movement feedback. Cancel stops pending work; an action already executing finishes before a deferred move.
- Care uses the weather recorded on the individual cell at sowing. Previously, using today's weather could produce `WRONG_CARE` after the day changed. Mixed care batches are labeled `Tend` and execute the correct action per cell.
- The camera frames all three unlocked beds across the existing blueprints and short/narrow viewports.
- On Android, leaving the map pauses Mapbox rendering while retaining its last surface buffer. This prevents the launcher from showing through Godot's outgoing transparent frame. Native map controls are disabled while paused and restored on return.

## Evidence and Validation

Physical device: vivo V2509A, serial `10AFAF162200319`, 1080 x 2344. The first two revised builds were installed successfully. Verified on that phone: farm markers and avatars, Sample A/B selection and camera focus, own-farm entry, plot care feedback, stall layout, and joystick removal.

At the final installation step the phone disappeared from ADB. The final build could not be installed on that physical device; reconnecting it is still required. Later UI and zoom checks used the already-connected Android emulator (`emulator-5554`, 1280 x 2856). Those checks supplement the physical run.

| Artifact | Source |
| --- | --- |
| [vivo-map-a.png](vivo-map-a.png), [vivo-map-b.png](vivo-map-b.png) | Physical phone, second build: farm focus and owner representations |
| [farm.png](farm.png) | Physical phone, second build: 9 visible plots, care icons and contextual progress |
| [map.png](map.png) | Android emulator: latest map controls and selected farm |
| [map-online.png](map-online.png) | Android emulator, final APK: online nearby farms and server snapshot |
| [transition-contact.png](transition-contact.png) | Android emulator, final APK: map backdrop retained during visitor entry |
| [stall.png](stall.png), [goals.png](goals.png) | Android emulator: independent modals and hidden dock |
| [movement.png](movement.png) | Android emulator: actual target ring and dotted path while walking |
| [visitor.png](visitor.png) | Android emulator: read-only visit with Wave and Stamp |
| [desktop-narrow.png](desktop-narrow.png) | Godot desktop at 320 x 640 physical window, 360 x 720 logical viewport |

Validation commands:

```sh
GODOT_BIN=/opt/homebrew/bin/godot ./addons/gdUnit4/runtest.sh -a res://tests
godot --headless --path . --export-debug Android build/sensen-farm-ui-debug.apk
git diff --check
```

480 tests pass with no failures, errors, skipped tests or orphans. Regression coverage includes cross-day care payloads, automatic ripening and icons, plot work versus movement, modal dismissal, farm-camera focus, late login, zoom limits, fractional zoom and double tap. Android export succeeds. Runtime logs, zoom recording and test reports are under the ignored `output/farm-ui-device/` and `reports/` directories.

After the Android surface handoff change, the 220 map, UI and scene tests were rerun successfully (`reports/report_720/results.xml`), and all 6 Android plugin unit tests passed. The final APK was installed on the emulator. The 40-second recording `output/farm-ui-device/handoff-revised.mp4` and its contact sheet show the map retaining its backdrop until the visitor farm appears. Return navigation and subsequent zoom also worked. This software-rendered emulator took about 17 seconds to display the visitor farm on this entry; physical-device transition latency remains unverified for this build.

The final emulator run loaded an online list containing two sample farms and one player farm. The selected online sample had nine ripe plots, confirming that the server snapshot was used rather than the bundled offline snapshot.

No farm reset or QA time/weather change was performed. Physical-device care actions and emulator visits were exercised on the existing accounts. No purchases were made.

## AI Design Boards

The user authorized the existing `sensenjoy` provider configuration. Four design boards were generated through its OpenAI-compatible Image API, requesting `gpt-image-2`, using the bundled imagegen CLI and actual game screenshots as references. Credentials were supplied through the environment and were not saved in the project.

Open the [design gallery](index.html) for the four boards. Original prompts, refinement prompts, reference images and generation settings are listed in [image-prompts.md](image-prompts.md). Files under `generated/` are AI concept art; the earlier screenshots listed in the validation table remain evidence of the running game. The concept boards do not establish implementation or device-test results.

## Remaining Limits

- Final physical-device installation and regression remain pending reconnection.
- The AI boards include proposed environment polish and layout details beyond the installed MVP. Use the actual runtime screenshots when assessing implementation.
- Existing MVP building/crop meshes and placeholder labour animations remain. This change improves UI and interaction, not the full environment art.
- Farm-owner avatars represent snapshots. There is no realtime multiplayer position stream.

Player-facing instructions: [farm-controls-guide.html](../../qa/farm-controls-guide.html).

# Product Direction

- iOS automation reference recorded on 2026-09-25 at the user's request:
  read docs/qa/ios-testflight-automation.md and tools/ios/README.md before the
  next iOS release/device task. CLI No Accounts or an empty CLI preference list
  does not prove the GUI account is logged out. If the live Xcode GUI confirms
  shaojie@gensen.app / Gensen, use the validated Organizer/cloud-signing fallback
  within the authorized release instead of repeatedly requesting login.
  Keep upload, TestFlight availability, channel installation and device-map
  verification as separate evidence-backed results. Discover the current device
  and target build, preserve fresh current data, and never reuse stale UI
  coordinates or historical identity snapshots. The CLI/GUI mismatch itself
  remains unresolved; the fallback and final TestFlight build 3 delivery passed.

- iOS black-map repair on 2026-09-25: direct iPhone TestFlight UI confirmed
  Gensen/Journey `0.16.37 (1)` installed before the repair. The
  CoreDevice builtByDeveloper flag alone must not determine its install source.
  City selection reproduced a black/loading map backdrop with a visible
  avatar/HUD and no native map controls; a cold restart of the same installed
  build restored map creation/style/READY. Subsequent fast and delayed entry
  both rendered. The first process's underlying startup error is not captured.
  Native listener failure recovery/backoff, failed-peer cleanup, foreground
  window handling and truthful READY are implemented and locally archived as
  `0.16.37 (3)`, retaining build 1's game PCK and the location purpose fix.
  Controlled device regression failed at the intended map-recovery assertion
  with old code and passed with the fix. The actual Release executable,
  re-signed under separate app.gensen.maps.mapqa with a localhost:9 game
  endpoint, passed 2 tests for recovery/city reentry/Shanghai/foreground/gestures;
  executable UUID matches the archive and screenshots were reviewed.
  The original app was first updated in place to development-signed Release
  build 3 and passed its map/gesture test, then replaced through TestFlight
  with the uploaded build 3. Final TestFlight cold/foreground/map/gesture
  checks passed (2 tests, 0 failures, screenshots reviewed). Current post-
  TestFlight install_key/region_choice files remain byte-identical before/after
  both updates and testing; no farm action or historical restore.
  QA app and runner removed; TestFlight build 3 left on phone. CLI distribution still
  reports No Accounts although the GUI shows shaojie@gensen.app / Gensen Admin.
  Organizer acquired correct cloud-managed distribution signing and uploaded
  build 3 at 12:38:46 CST. Actual IPA signature/entitlements/location purpose,
  PCK and Release native UUID verified. TestFlight processing, availability
  and installation on this phone confirmed. Mapbox dSYM warnings remain.
  See docs/qa/ios-map-black-2026-09-25.md.

- iOS metadata follow-up on 2026-09-24: Apple's email for `0.16.37 (1)`
  confirms successful delivery with ITMS-90683, missing
  `NSLocationWhenInUseUsageDescription` required by SDK API references. Add the
  foreground location purpose string in the iOS preset and export preparation;
  `0.16.37 (2)` is locally archived and its actual plist verified. Its game PCK
  is identical to build 1. No location bridge implementation or new permission
  request was added. Build 2 App Store export is blocked by new `No Accounts`
  errors; CLI account list was 0, versus 2 during the first successful
  upload. Later GUI evidence confirmed the account remained logged in and
  Organizer successfully uploaded build 3. Build 2 is not
  uploaded or installed; its metadata fix is included in build 3, which now
  supersedes build 2 and is the latest completed TestFlight upload.
  This warning is not proven to cause the missing invitation. See
  docs/qa/ios-location-purpose-2026-09-24.md.

- iOS / TestFlight preparation on 2026-09-24: Journey `0.16.37 (1)` uses
  `app.gensen.maps`, Gensen team `XN4Z77ZX73`, App Store Connect app `6815092667`,
  as supplied by the user for `shaojie@gensen.app`. Build/archive with automatic
  Apple Development signing; let App Store export apply distribution signing.
  The signed development build is installed/readback-verified on iPhone 14 Pro
  / iOS 26.3. Two XCTest cases and screenshot review cover cold launch,
  foreground recovery, native map/3D rendering, drag and pinch (zoom 16→17).
  No farm creation/relocation or asset operation was confirmed. Temporary XCTest
  runner removed and QA app process stopped; current iOS identity/preferences
  retained. Gensen distribution IPA and upload succeeded; the user's subsequent
  App Store Connect screenshots confirm processing complete and build 1 assigned
  to GensenMap Internal. The user added two internal testers; the latest group
  Builds screenshot showed green Ready to Test for 0.16.37 (1). On 2026-09-25,
  the same group's build initially showed Testing while both testers showed
  No Builds Available. A later user screenshot now confirms both are Invited
  dated 2026-09-25; the precise backend action is not independently confirmed.
  A later direct phone TestFlight check confirmed Gensen / build 1 / Open;
  installation through TestFlight was completed before the black-map repair.
  Earlier empty-list and Redeem-button observations are historical.
  gensen.app routes mail to Google, and the Lark
  connection has no corresponding mailbox. Gmail access is not yet connected;
  no inbox/spam search or invite resend is claimed. Mapbox native
  dSYM warnings remain. iOS game POIs/city styling/location and Godot voice
  adapter remain incomplete; full gameplay/performance acceptance is not claimed.
  Runtime source is release worktree commit 514fec6b with the documented iOS
  export overlay. No backend deployment/migration or chat delivery. See
  docs/qa/ios-testflight-2026-09-24.md and docs/qa/ios-readiness-2026-09-24.md.

- Avatar motion correction on 2026-09-24: Journey `0.16.37 / 2026092405`
  fixes visible pond idle/run freezing: the orthographic camera was about 37m
  from the avatar but RigActivity still slept past 16m. Use the world scenes'
  50/80m thresholds and shared play_motion pose reset; animation assets are intact.
  66 native checks, 124 emulator inputs and 33 isolated V2509A inputs passed,
  including animation-time/bone changes and hold/release reel-crank movement.
  Physical QA uses its own local account; its inventory stays unchanged. Physical
  automated catches/full-shore coverage are not claimed; an initial shore attempt
  hit FISHING_LOCATION and is recorded separately. The original signed observer-free
  APK is installed/readback/cold-login verified on phone and emulator, retaining
  each device's five fresh identity/appearance/preferences files and current farm.
  Both public full downloads, hashes, Range and manifests passed. Backend stays
  integrated-20260924/domain27; no deployment or data migration. Temporary phone QA
  package/port forward removed; display settings retained. No external delivery.
  See docs/qa/avatar-motion-2026-09-24.md.
  The user subsequently explicitly requested this APK plus brief recent-release
  notes to Joey via both Slack and Feishu. Slack's full APK attachment and message
  are readback-verified. Feishu IM's 100MB limit required the full APK in Drive,
  explicit Joey view access and a DM link; full-download hash, member grant and
  message are verified. This request does not authorize future version delivery.

- Integrated public release on 2026-09-24: Journey `0.16.36 / 2026092404`
  publishes 12 fixed system ponds (six per city, three small shapes), clearer
  2.2x-flow water, reviewed five-floor mine art/free camera/reconnect framing,
  and the Griffith map entrance. Backend `integrated-20260924` retains domain 27 /
  content 50c2dbdde04c9678; all nine tables, 75 farms, 1599 commands and 39 creation
  records were exact across the switch. Retain the 1500ms Node address-attempt
  setting, original database/voice configuration and both networks. 842 server
  checks, 423 native checks and 54 Android inputs passed; isolated production-host
  HTTP/WebSocket pond settlement and restart passed. Both public APK full downloads,
  hashes, Range and manifests passed. At the user's explicit reminder, the exact
  signed observer-free APK is installed/readback/cold-login verified on V2509A
  as well as the emulator. Each device's five fresh identity/appearance/preferences
  files and current farm/assets are preserved; phone currently has 0 cells,
  180 coins and 2 bag stacks. Never restore historical farm/identity snapshots.
  Complete new gameplay was checked on isolated emulator data, not repeated on
  the user's phone. No new Slack/Feishu delivery. Original dirty workspace stays
  intact; integrated runtime source is commit 8008bdae in the isolated
  sensen-godot-release-20260924 worktree. See docs/qa/integrated-release-2026-09-24.md.

- Mine-scene MR review on 2026-09-24 fixes authoritative online arrival framing:
  use the server-selected spawn, retain the camera through temporary empty worlds
  on same-instance/same-floor reconnect, and reframe new instances/floors/runs.
  113 native checks and a rebuilt isolated Android QA run (36 operations,
  three display sizes) passed. The extra client packet-sequence regression failed
  before the fix and passed afterward. No server/save changes or phone/production
  update. See docs/qa/mine-camera-2026-09-24.md for review evidence.

- Mine viewport feedback on 2026-09-24 supersedes whole-chamber framing:
  use the farm's close orthographic scale (6m, 7.2m on small portrait screens),
  allow the mine offscreen, free persistent pan and anchored pinch/wheel zoom.
  Walking and same-floor snapshots never follow/reframe. Show the saved-outfit
  directional portrait only offscreen; tap to recenter smoothly without changing
  movement or zoom. New floors frame arrival; suspend/resume retains the view.
  98 native checks and 36 isolated Android touches at three display sizes passed.
  No phone or production update. Four updated screenshots were added to the
  same authorized Slack self-DM review thread and read back; no APK/Joey delivery. See
  docs/product/mine-camera-2026-09-24.md and docs/qa/mine-camera-2026-09-24.md.

- Local mine art iteration on 2026-09-24 follows the user's five-floor reference:
  terracotta, moss stone, mushroom, blue crystal and violet elite chambers;
  carved walls, sand, ore seams, teal-framed ladders, hoist elevator, supplies,
  warm lanterns and crowned jelly slimes. Mine and farm share the same 43-degree
  pitch / 14.5-degree yaw orthographic view, with mine controls relative to the
  screen. Keep authoritative navigation, rock seeds/anchors, combat and saves;
  the reference's narrow double room / S-shaped passages / central obstacle are
  not new collision geometry. 87 native checks and 30 isolated Android touches
  at three requested display sizes passed. QA uses local command fixtures, not
  public settlement; no original Journey update, phone installation or server
  change. The user subsequently requested screenshots in their own Slack;
  nine PNGs were sent to their verified self-DM and read back. No Joey or APK
  delivery. See docs/product/mine-art-2026-09-24.md and
  docs/qa/mine-art-2026-09-24.md.
- Pond water reference pass on 2026-09-24: local Journey `0.16.35 / 2026092403`
  brightens shared fishing water toward clear turquoise/blue, reveals the stone
  bed, softens refraction and dark reflection coverage, and uses 2.2x texture
  flow time. System pond ground is now excluded from the shoreline reflection
  layer. Preserve pond shapes, navigation, fishing timing, inventory and saves.
  27 targeted native checks and 66 Android operations at three sizes passed;
  all three ponds sampled at 60 FPS after warm-up on the emulator. This is not
  phone performance or visual acceptance. The original-certificate observer-free
  APK is built/inspected, and 29 runtime resources match QA. No new server change,
  public publication, phone installation or message delivery; the system pond
  backend from the preceding iteration is still pending deployment. See
  docs/qa/pond-water-clarity-2026-09-24.md for before/after images and motion video.
  The user subsequently requested the PNG and MP4 via Slack to self; both were
  sent to the verified self DM and read back. No APK or other-recipient delivery.

- System fishing ponds implemented locally on 2026-09-24: Journey
  `0.16.34 / 2026092402` has 12 persisted game locations (six per city) and three
  small polygon pond templates. Seeded assignment and decoration stay fixed;
  map previews, navigation, shoreline rendering and authoritative fishing share
  the catalog. Use the farm ScenePan and existing fishing/equipment/bag rules.
  Pond rooms have 16 seats per channel, independent catches and party follow;
  existing farm geometry, domain 27 and content 50c2dbdde04c9678 remain unchanged.
  843 distinct server/PostgreSQL checks, 328 native checks, nine native rendering
  profiles and 76 Android inputs passed on isolated data. Original-package,
  original-certificate observer-free APK is built and inspected; 33 runtime
  resources match the tested QA APK. No production deployment, public publication,
  original Journey/device replacement or external delivery occurred. New pond
  entries require the compatible backend. Phone and iOS acceptance remain pending.
  See docs/product/system-fishing-ponds-2026-09-24.md and
  docs/qa/system-fishing-ponds-2026-09-24.md.
  The user then explicitly requested the pond images through Slack to self:
  the comparison plus three individual PNGs were sent to the verified self DM
  and read back on 2026-09-24. This authorizes no future or other-recipient delivery;
  APK publication, backend deployment and phone installation remain pending.

- Map fishing scope selected on 2026-09-24: this iteration uses system-generated
  game ponds only. Mapping a large real lake or river to a 1–2-screen pond would
  mismatch the player's spatial expectation; real-water POI conversion is deferred.
  Use fixed, persisted map locations and assign one of three small pond templates
  once per location. The entry name, preview and entered scene must agree; all
  players share the same location/layout, and re-entry must not reroll it. Preserve
  existing farm ponds, identity, equipment and saves. The proposal uses configured
  generation areas and the existing map POI presentation, ScenePan and authoritative
  fishing flow; template art, dimensions and density still need validation. This is
  a scope/design decision, not implemented or released functionality. See
  docs/product/map-fishing-ponds-proposal-2026-09-24.md.

- Griffith map entry on 2026-09-24: Journey `0.16.33 / 2026092401` is built
  locally with the original package/certificate and the 24 rebuilt landmark
  models. Selecting Griffith Observatory on the LA map exposes an Enter scene
  action; only that authored landmark is enabled. The local visit preserves
  the saved outfit, farm state and map camera/selection on return. Use the
  farm ScenePan controller: free drag, decaying inertia, new-touch stop, focal
  pinch with elastic zoom, background cancellation and offscreen portrait
  recenter; no farming. Independent navigation maps are released on exit.
  42 distinct native checks and 29 Android operations at three resolutions
  passed. The final observer-free APK is installed/readback/cold-login verified
  on the emulator; its five identity files and existing server farm/assets are
  preserved. The user then reconnected V2509A and requested installation:
  this exact integrated APK is now installed/readback-verified on the phone,
  with the original certificate, five current identity/appearance/preferences
  files and the current server farm/assets preserved. Fresh cold-login logging
  and the city screen passed; the full integrated scene flow remains emulator-
  verified and awaits the user's phone review. Phone display settings retained;
  test process stopped normally. No backend deployment, public APK publication
  or message delivery. See docs/qa/griffith-map-entry-2026-09-24.md.

- Griffith scene reference rebuild on 2026-09-23 is a separate offline review,
  not public landmark travel. The former Opus scene had reversed roof/paving
  faces, drifting hillside placements and disconnected terrace navigation.
  Rebuild architecture, cafe, paving, planting and scenery; keep the actual
  avatar, free camera and touch movement. Traced tree-base projection error is
  below 0.04px (not a whole-image fidelity metric). Twelve native check types
  passed at three window sizes; 42 emulator inputs passed at three resolutions.
  Use tools/dev/open_landmark_art.command / the isolated preview project, which
  disables network boot. At the user's request on 2026-09-24, the exact
  com.sensen.griffithqa / 0.1-art-review / 2026092312 preview is installed and
  APK-readback-verified on V2509A. Cold launch and five physical inputs covering
  overview, short walk, recenter and zoom passed; network never booted and five
  current Journey identity/appearance/preferences files stayed byte-identical.
  Phone display settings were retained and the QA process stopped after testing.
  This is a separate development preview, not public scene integration or full
  physical visual/performance acceptance; no publication or message delivery.
  Realtime hand-painted
  lighting, distant city and vegetation detail still differ from the concept;
  do not claim a pixel-identical or user-approved visual. See
  docs/design/griffith-rebuild-2026-09-23/README.md and validation.json.

- Map release and fresh-install repair on 2026-09-23: Journey `0.16.32 / 2026092311`
  publishes the current LA/Shanghai map, 27 semantic POI categories / 125 icons,
  zoom to country level, automatic city switching, city flights and white/lime UI.
  Landmark 3D scene travel and experimental landmark resources are excluded.
  Original package/certificate retained; 179 native map checks and emulator
  update/cold-login/identity preservation passed. Both public full downloads and
  Range verified; download-us DNS corrected to current DMIT 179.255.151.51.
  User's own Feishu delivery is sent/readback-verified; Slack remains pending
  until its callable connector is exposed. Do not send to Joey instead of self.
  User then installed on V2509A and reported first-farm generation failure.
  The reinstall initially had a new identity / NO_FARM; do not silently
  restore a historical identity/farm or confirm creation for the user.
  Production OSM connections failed at Node's default 250ms address-attempt
  limit. Setting NODE_OPTIONS=--network-family-autoselection-attempt-timeout=1500
  passed LA, Shanghai and shoreline production-host replays; retain this setting
  on future deploys. Same business image/domain27/content50c2dbdde04c9678;
  74 farms, 1599 commands and 38 creation records hash-identical across restart.
  User then successfully created a farm under the new install identity; total
  farms is now 75. The original 74 farm rows remain hash-identical. Their old
  phone identity still resolves to the existing 58-cell / 187-coin farm; no
  identity or historical farm restore was performed. Landmark reference rebuild is
  separate work in progress, never part of the public APK yet. See
  docs/qa/map-release-2026-09-23.md and docs/qa/fresh-install-geography-2026-09-23.md.

- Physical-feedback iteration on 2026-09-22: Journey `0.16.14 / 2026092208`
  keeps LA map landmarks, NPCs, POIs and player portraits at their direct
  geographic projection. Remove city collision avoidance, screen clamping,
  cluster displacement and per-frame reservation feedback. Merge partial
  loaded-tile POIs in a bounded in-memory browsing cache; use source rank/zoom
  for detail and 32–64px POI art. Default full 3D is still self only; explicitly
  selecting another player replaces their portrait with matching 3D and a
  foot-centered jelly popup, without moving the camera. One remote model at a
  time; cancel/replacement restores portraits and releases the old rig.
  LA no longer has the nearby-player drawer, neighbour nav or its visit/jump
  flow. This supersedes the earlier map panel/avoidance rules below.
  157 native map checks and 28 isolated Android touches at three viewport sizes
  passed; recorded projection checks and animation phases passed. Final signed,
  observer-free original Journey is installed/readback-verified on V2509A with
  fresh phone baseline, five identity/appearance/preferences files, 51 cells,
  187 coins, 10 bag stacks and relocation.used=true preserved. Cold login passed;
  complete new interactions were checked on emulator, not repeated on phone.
  Backend/domain/content unchanged; no public publication or external delivery.
  See docs/product/la-map-interactions-2026-09-22.md and
  docs/qa/la-map-interactions-2026-09-22.md.

- Physical review installation on 2026-09-22, explicitly requested by the user:
  Journey `0.16.13 / 2026092206` with the LA map and compact panels is installed
  on V2509A as the original `com.sensen.journeypreview`, original certificate,
  observer-free and pointed at the existing public Journey service. Installed
  APK hash/certificate, cold login and five identity/appearance/preferences
  files were verified. Current farm 51 cells, 187 coins, 10 bag stacks and
  relocation.used=true are preserved; never restore a historical farm snapshot.
  Full new map flows remain emulator-verified and await the user's phone review.
  No backend deployment/migration, public download publication or Slack/Feishu
  delivery was requested/performed. See docs/qa/la-map-phone-2026-09-22.md.

- Map secondary panels refined on 2026-09-22 after the user's "ok 继续":
  compact white neighbour drawer, one count header, lime selection/visit actions,
  coloured landmark thumbnails, and compact NPC status cards now share the
  approved map style. Map sheets are mutually exclusive; closing restores
  navigation state. Preserve snapshot validation, farm identity and assets.
  `com.sensen.journeyuiqa / 0.16.13-mapqa3` (2026092205) passed 151 native
  checks and 36 emulator touches at three viewport sizes. Original display
  size restored; no public Journey/server release or phone acceptance.
  See docs/qa/la-map-panels-2026-09-22.md.

- Map UI sizing refined on 2026-09-22 at the user's request: use the approved
  LA visual's compact proportions. Filter width 270→220, visible round controls
  44→32 with 44px touch targets, navigation height 60→48, POI card 90→72,
  portraits 46→36, and thin name labels. Keep the existing real geography,
  avatar/landmark scale, interactions, saves and unlocks. The emulator sample
  is `com.sensen.journeyuiqa` / `0.16.13-mapqa2` (2026092204); this is not a
  public Journey release. Before/reference/after comparisons and validation:
  `docs/qa/la-map-scale-2026-09-22.md`.

- Development sample implemented on 2026-09-22 after the user's explicit
  "开始": Los Angeles map browsing now has a pastel Mapbox style, city/street
  zoom, native loaded-tile POIs, 13 Sensenjoy-generated assets, one full 3D
  self avatar, other owners' cached portraits, and unlocked NPC map entries.
  Preserve real coordinates, saved outfits, unlock rules and all farms; map
  browsing never changes placement/relocation bounds or grants rewards.
  Android sample `com.sensen.journeyuiqa` / `0.16.13-mapqa` uses an isolated
  localhost:3196 service; 149 Godot checks and 24 Android touches passed.
  This is not a public release or phone/iOS acceptance. Original Journey
  remains unchanged; backend domain27/content50c2dbdde04c9678 has no migration.
  The user authorized removing historical emulator QA versions for space;
  eight old QA packages were removed with data retained, keeping Journey and
  the current map QA. See docs/qa/la-map-2026-09-22.md.

- Visual direction approved on 2026-09-22: the user accepted the Sensenjoy API
  Los Angeles map main visual at
  `docs/design/la-map-2026-09-22/generated/la-map-main-v1.png`.
  Use it as the map redesign's visual target: light pastel map, dimensional
  landmarks/category POIs and lightweight white floating UI. Only the local
  player has a full 3D map character; other players use avatar markers, and
  unlocked NPCs use distinguishable portraits with state badges. POI details
  show basic information. The image's geography, avatar examples and point
  counts are illustrative; retain real coordinates, existing identities,
  unlock rules and saves in implementation. This records visual approval,
  not completed implementation or release. See
  `docs/design/la-map-2026-09-22/README.md` and
  `docs/product/la-map-assessment-2026-09-22.md`.

- Current iteration adopted on 2026-09-22: Journey 0.16.12 / 2026092202
  restores visible Walk / Work (行走 / 种地) labels under the farm toggle icon
  within the same 52x52 touch area. The icon-only control was hard to discover;
  farming was still available and the user's current seed inventory was empty.
  Preserve mode rules and existing out-of-seeds feedback; never grant/buy seeds
  for the real user during QA. 61 native checks and an isolated Android sequence
  of 14 touches passed: walk without farming, switch modes, empty-seed feedback,
  buy seeds, till/sow/water and switch back. Final observer-free original Journey
  APK is installed and hash/certificate verified on emulator and V2509A, with
  cold login and five identity files/current farm preserved (51 tilled cells,
  187 coins, 10 bag stacks at install). Full farming actions were tested only
  on the isolated account. Both public downloads and Range verified; unchanged
  shoreline-farm backend/domain27, no migration. The user then explicitly asked
  to test on the phone and send this package to Joey via Slack. The same final
  APK passed 11 physical UI touches (mode toggle, seeds, bag, character, stall)
  with unchanged identity/assets; download links and concise release notes were
  sent to Joey and read back on 2026-09-22. See the QA delivery receipt. This
  one-version request does not authorize automatic future deliveries.
  See docs/qa/farm-mode-2026-09-22.md.

- Current iteration adopted on 2026-09-22: Journey 0.16.11 / 2026092201
  sharpens UI with 4x material/icon pixels while preserving logical layout;
  character preview renders at screen density. The avatar portrait now appears
  ONLY offscreen, moves to the corresponding safe screen edge with a direction
  arrow, and disappears after recentering. This supersedes 0.16.10's fixed
  right-side portrait. Remove the geographic water mask's half-cell pond offset
  and align shore decorations with the real ellipse; preserve water/fishing
  geometry, navigation and saves. 66 targeted native tests, 24 Android touches
  across eight directions, and 8 final pond/UI touches passed. Final signed,
  observer-free APK is installed/readback-verified on the emulator; original
  five files, account and assets preserved. Both public downloads and Range
  are verified. V2509A was disconnected at initial publication; the user then
  reconnected it and requested installation on 2026-09-22. The exact published
  APK is now installed/readback-verified with cold login, five identity/appearance
  files and current save preserved (49 cultivated cells, 10 bag stacks). The full
  eight-direction/pond flow was not repeated on the phone. Backend remains
  shoreline-farm-20260921/domain 27.
  The user explicitly requested HD images through Feishu: five messages to
  their own verified bot chat and original ZIP readback/hash were verified.
  This does not authorize unrelated recipient or future version delivery.
  See docs/product/ui-clarity-2026-09-22.md, docs/qa/ui-clarity-2026-09-22.md
  and docs/qa/pond-alignment-2026-09-22.md.

- Current iteration adopted on 2026-09-21: Journey 0.16.10 / 2026092106
  redesigns all existing UI with Sensenjoy API art, cream panels, blue/violet
  edges, teal actions and 63 Phosphor glyphs. Farm camera is free: remove the
  character dead/hard framing and automatic follow; tap the real saved-outfit
  portrait to recenter. Use compact HUD, five-column inventory, a selected-item
  strip and real 3D six-slot character view. Preserve existing 3D and all gameplay
  contracts. Hidden previews defer rig work; visible modal sheets hide online/
  voice badges without disconnecting sessions. 638 distinct native checks,
  140 gallery states, 29 isolated Android touches and 17 read-only V2509A UI
  touches passed. Final observer-free APK is installed/readback-verified on
  emulator and V2509A; both public full downloads, hashes and Range passed.
  Keep original Journey package/signature/identity. The owner independently
  confirmed relocation before this UI iteration: retain the current generated
  farm, 47 cultivated cells (46 tilled, 1 growing), 10 bag stacks and used=true opportunity. Never restore
  the historical unused-chance/legacy snapshot. Backend stays shoreline-farm-
  20260921, domain 27 / content 50c2dbdde04c9678; no server deployment/migration.
  See docs/product/game-ui-2026-09-21.md, docs/qa/game-ui-2026-09-21.md and
  design-qa.md. No Slack/Feishu delivery was requested or performed.

- Current iteration adopted on 2026-09-21: shoreline-farm-20260921 fixes the
  user's Silver Lake selection failing despite successful OSM retrieval. Fill
  missing classifications with sourced ESA WorldCover 2021 v200 data, keeping
  known OSM coverage authoritative. Never turn missing data into invented land.
  Fit facilities on connected dry land and retain real water; keep 32m farms,
  old saved terrain/previews, domain 27 and content 50c2dbdde04c9678 unchanged.
  Bound facility search to 4096 candidates/96 rasterizations. Distinguish incomplete
  geography, provider failure and client terrain validation; geographic boundary
  scenery skips water. 836 server/PostgreSQL and 544 native client checks, isolated
  Android full flows and live OSM/ESA production-host rehearsal passed.
  Production switch preserved all 74 farms and history. The user's original
  0.16.8 phone process was retained and the same selection successfully previewed:
  32m, 45 cells would move, 0 decorations; original 47 cells/assets and unused
  chance preserved. Never confirm relocation in QA. To keep that preview intact,
  the phone was NOT restarted/upgraded. The signed observer-free 0.16.9 /
  2026092105 APK is published and emulator-verified, with both downloads checked;
  do not claim 0.16.9 is installed on V2509A. No external delivery was requested.
  See docs/product/shoreline-generation-2026-09-21.md and
  docs/qa/shoreline-generation-2026-09-21.md for sources and verification limits.

- Current iteration adopted on 2026-09-21: Journey 0.16.8 / 2026092104
  uses exact 32m farms for generation version 2: 40x40 cells at 0.8m, sampled
  from a 160m real geographic area. This is the user's explicit choice, replacing
  the provisional 36m design. Preserve legacy/v1 farms and frozen v1 previews;
  v1 requests retain 64x64 at 0.75m, 48m farms and 240m samples. Domain 27 and
  content 50c2dbdde04c9678 remain. Relocation remains voluntary and lossless;
  insufficient capacity rejects without consuming the owner's opportunity.
  Blue selection outlines with light borders replace yellow. The relocation map
  explicitly takes camera ownership; separate 8px tap slop prevents a short drag
  from recentering again on release. Compact pond geometry follows the host farm
  for navigation, rendering and fishing, including visitors' independent rewards.
  806 server/PostgreSQL and 562 native Godot tests, isolated Android compact-farm
  relocation/farming/fishing/mine flows and V2509A selection drag/cancel passed.
  Production live OSM rehearsal and exact preservation checks passed; release
  compact-farm-20260921 retains all 74 farms and 1,429 historical commands.
  The original signed observer-free 0.16.8 update is installed on V2509A; original
  identity, appearance, assets, 47 cells and unused relocation chance are preserved.
  Never spend the real user's chance in QA or send Joey updates without a new request.
  See docs/product/compact-farm-2026-09-21.md and docs/qa/compact-farm-2026-09-21.md
  for final artifact/download evidence and upstream geography availability limits.

- Current iteration adopted on 2026-09-21: Journey 0.16.6 / 2026092102,
  domain 27 / content 50c2dbdde04c9678, is deployed. Existing legacy farms receive one
  voluntary free relocation opportunity. Preview a real-geography farm in the
  original city, then explicitly confirm; cancel/failure must not consume it.
  Preserve account/farm identity, assets, crop contents and ready_at, mine/quest
  progress and history; move only conflicting coordinates and reject insufficient
  space. Commit terrain, relocated positions and entitlement atomically; refresh
  stale online rooms/visitors. Never spend the real user's opportunity in QA.
  Migration preserved all 74 farms, 288 crops and 1,429 historical commands;
  74 opportunities granted, none consumed. The real user's original terrain,
  assets and 47 cells are preserved and their opportunity remains unused.
  786 isolated server/PostgreSQL tests, Godot suites, production-host live OSM
  rehearsal and isolated Android relocation/farming/fishing/mine checks passed.
  The exact signed observer-free update is installed and verified on the emulator;
  both public downloads pass full hash and Range checks. The user then reconnected
  V2509A and requested the update: the exact public 0.16.6 APK is installed,
  original certificate/hash and five identity/appearance/preferences files verified.
  Cold launch/login passed; original farm/version/assets and 47 cells are preserved.
  No preview or confirmation was sent; their relocation opportunity remains unused.
  Phone relocation flow remains for the user's own choice. No Joey delivery requested.
  See docs/product/farm-relocation-2026-09-21.md and
  docs/qa/farm-relocation-2026-09-21.md for evidence and validation boundaries.

- Current iteration adopted on 2026-09-21: Journey 0.16.5 / 2026092101 merges street and farm into one
  private farm at the existing 48m scale. New farms are generated from a freely
  selected area within the chosen city, with persisted real geography and
  rejection of all-water, all-desert or insufficient usable land; unavailable
  data must offer retry, never silently substitute a fixed template. Include a
  reachable fishing pond and starter mine. Retain farm art/camera style, refine
  continuous roads and tune shadow/clip coverage. Preserve old saves and asset
  ownership; the user explicitly chose retaining old farms and terrain. See
  docs/product/private-geographic-farm-2026-09-21.md and
  docs/qa/private-geographic-farm-2026-09-21.md. Server/Godot, Android emulator
  and V2509A existing-farm checks passed. User explicitly authorized online
  deployment: domain 26 / content 50c2dbdde04c9678 is live; 74 farms and all state,
  ownership, history and parties survived exact migration comparison. Two live
  OSM locations, real farming/fishing/mine and restart recovery passed in the
  production-host rehearsal. The original signed observer-free Journey update is
  installed on V2509A; account, outfit, equipment, 47 cells and 187 coins remain.
  DMIT and OSS full downloads and Range checks passed. No Joey delivery requested.

- Current iteration adopted on 2026-09-19: Journey 0.16.4 / 2026091905
  extends the water reference pass across farm pond, street lake and river:
  irregular sediment, refracted light caustics, cached planar bank reflections,
  sculpted shore stones, reeds, grass, flowers and detailed lily pads. Keep the
  common approach banks low enough to leave the float visible. Street trees
  render separately from the ground so reflected terrain cannot cover the bank.
  Preserve all navigation, fishing, equipment and server domain/content contracts.
  35 Godot tests and Android emulator pond/lake/river touch flows passed.
  The observer-free signed APK and both public downloads are verified.
  The user reconnected V2509A: pond/lake/river casts, reel motion and the
  south-bank view passed on the phone. The exact published observer-free APK is
  installed, with original identity, equipment, 47 crops and wallet preserved.
  The user subsequently explicitly authorized Slack delivery of this package to
  Joey; sent and read back on 2026-09-19. Future versions still need an explicit
  delivery request. See docs/qa/water-detail-2026-09-19.md for artifacts and delivery status.

- Current iteration adopted on 2026-09-19: Journey 0.16.3 / 2026091904
  refines farm/street water with shallow pebble beds, depth absorption, moving
  caustics, floating lilies, wet shore rocks and a static Mobile reflection probe.
  Align only visual shoreline to the existing fishing basin; preserve navigation,
  fishing geometry, multiplayer, equipment and domain 25 / content 50c2dbdde04c9678.
  Fix the initial wrapped fishing notice retaining an excessive height. 27 Godot
  tests, emulator pond/lake/river casting and V2509A fishing checks passed.
  The observer-free original Journey update is installed and both public downloads
  verified; account, 47 crop cells,
  equipment and wallet are preserved. See docs/qa/water-material-2026-09-19.md
  for evidence and performance limits. Do not send Joey messages or APK links
  without a new explicit user request.

- Current iteration adopted on 2026-09-19: SGODOT-130 six-slot equipment is
  Journey 0.16.2 / 2026091903, domain 25, content 50c2dbdde04c9678. Main hand
  merges weapons/tools; add independent fishing rod, two rings, necklace and
  gloves (all former accessories). Preserve old weapon as main hand, return
  former tool to bag/overflow with instance and attributes intact. Grant and
  equip one initial rod once, persisted for existing and newly created farms;
  require that rod for fishing. Future quest acquisition uses the configurable
  grant policy. Main-hand damage/speed and crop/ore/wood efficiency drive real
  combat and collection timing. Preserve saves, historical commands and outfits.
  Migration of 74 farms (51 legacy bags, 16 dual equipment sets), 303 planted
  crops, ownership and party history passed. 720 server tests, Godot, emulator
  and V2509A checks passed; final observer-free Journey APK is installed and
  both public downloads verified. See docs/product/equipment-main-hand-2026-09-19.md
  and docs/qa/equipment-main-hand-2026-09-19.md. Keep application updates in 0.16.x
  as the user requested; initial stats remain open to later balance feedback.

- Current iteration adopted on 2026-09-19: SGODOT-129 fishing UI feedback is
  Journey 0.16.1 / 2026091902, following the user's 0.16.x version requirement.
  Widen the catch-progress meter to 14 logical pixels, show percentage and
  bounded +/minus glyph particles, raise notices and the single action button.
  Explicitly distinguish escaped fish, missed bites, interruptions and uncertain
  results; do not overwrite a failed cancel or show an older catch on reconnect.
  Keep server domain 24 / content 38e6db02b26b8b43, free shoreline, multiplayer,
  original Journey identity and saves. Godot, emulator and V2509A real-touch
  checks passed, including missed bite, escape and successful retry. The final
  observer-free signed APK is installed on V2509A and both public downloads
  are fully verified. See docs/product/fishing-feedback-2026-09-19.md and
  docs/qa/fishing-feedback-2026-09-19.md.

- Current iteration adopted on 2026-09-19: SGODOT-129 free shoreline and
  multiplayer fishing is Journey 0.16.0 / 2026091901, domain 24, content
  38e6db02b26b8b43. Choose any reachable bank by tapping water; preserve exact
  current shore position when valid. Remove fixed stations; admitted farm
  visitors fish into their own bags. Server-confirmed casts/catches drive nearby
  rods, lines, floats and arm poses, with eight detailed rigs and existing
  300-player spaces. Late join, leave, nonce/room binding and pool cleanup are
  verified. Domain 23 migration preserves exact state JSON and all history.
  Godot, PostgreSQL, emulator and public HTTPS multiplayer checks passed; final
  Journey APK is signed and download-verified. The user subsequently connected
  V2509A and requested installation: final 0.16.0 is installed, with original
  signature, APK hash, five identity/appearance files and server save verified.
  Cold launch passed; the full new fishing flow has not been repeated on the
  phone. Keep original Journey saves and identity. See docs/product/fishing-shore-multiplayer-2026-09-19.md and
  docs/qa/fishing-shore-multiplayer-2026-09-19.md.

- Current iteration adopted on 2026-09-18: SGODOT-129 fishing presentation is
  Journey 0.15.1 / 2026091803. Fish directly in the 3D scene with a slim gauge
  and one cast/hook/reel button; hide regular HUD while fishing and restore it
  on exit. Procedural shoulders/elbows/wrists hold the pole and reel, with rod
  flex, slack/tight line, bobber, splash and confirmed-catch animation. Use the
  side view and forward grip verified against the original long-haired outfit.
  Layered water color, fine waves and interactive ripples replace white dots.
  Godot, emulator and V2509A checks passed; the final observer-free Journey
  update is installed with original identity, appearance and saves preserved.
  Server domain 23 / content 1b7a7871f9f19e49 and fishing rewards are unchanged.
  See docs/product/fishing-presentation-2026-09-18.md and
  docs/qa/fishing-presentation-2026-09-18.md. SGODOT-129 still retains natural
  player difficulty/economy observation; this presentation iteration is verified.

- Current iteration adopted on 2026-09-18: SGODOT-129 fishing is deployed as
  Journey 0.15.0 / 2026091802, domain 23, content 1b7a7871f9f19e49. Farm pond and
  street lake/river fishing use a hold/release minigame, four fish tiers and
  bag/stall sales. Validate real-time shore position, connection generation,
  timing and input traces on the server; retain confirmed catches in overflow
  when full. Domain 22 migration preserves state JSON and historical commands.
  Godot, isolated PostgreSQL, emulator and V2509A public-service validation passed.
  The final observer-free com.sensen.journeypreview update is installed with
  its original certificate, Journey identity, appearance and save retained.
  Keep SGODOT-129 In Progress for natural-player difficulty/economy validation.
  See docs/product/fishing-2026-09-18.md and docs/qa/fishing-2026-09-18.md.

- Current iteration adopted on 2026-09-18: SGODOT-128 farm cells are 0.75m
  (1.5x the previous edge length), with the avatar scale and close camera retained.
  First-screen landmarks, symmetric camera dead/hard zones with damped follow,
  curved paths and softened scenery boundaries are deployed as Journey 0.14.0 /
  2026091801, domain 22, content a19e895011110070. Preserve original Journey
  identity and saves; relocate conflicting crops/decorations without losing
  ownership or mature deadlines. Farm realtime navigation matches the new plot
  (64x64, 48m, spawn 21.375/-26.625). Only deliver com.sensen.journeypreview.
  Android emulator, real HTTP/database and V2509A physical validation passed.
  Final public APK is installed on the phone with original Journey identity and
  save verified. SGODOT-128 retains its broader original placement/woody-crop
  acceptance scope; this farm-view iteration's device verification is complete.
  See docs/qa/farm-composition-2026-09-18.md for release and evidence.

- Current iteration adopted on 2026-09-17: free farming defaults to walking;
  one toggle switches walking/farming. Ordinary ground and crop taps never farm
  while walking. Preserve explicit batch actions, command recovery, close camera,
  horizontal seed scrolling, regional art, visitor read-only access and saves.
  Free-farm writes require explicit domain 21 / content migration; merely reading
  a farm or toggling the UI is not a successful farming-loop test. Preserve planted
  crop IDs and ready_at, migrate legacy empty slots/watering timestamps, retain
  historical command results, inventory, mines and parties. Realtime navigation
  must match FarmPlot (64x64, 0.5m, spawn 14.25/-17.75).
  The user explicitly chose a single Journey Preview online update on 2026-09-17:
  keep com.sensen.journeypreview, its signing certificate, original Journey account
  and save. SensenAvatar is the separate local test app; do not replace Journey's
  identity or data with it. Version 0.13.2 / 2026091712 targets the public Journey
  service. See docs/qa/free-farm-online-2026-09-17.md for migration, real farming
  verification, device installation and release evidence.

- Current iteration adopted on 2026-09-16: SGODOT-126 party voice uses self-hosted
  LiveKit on the existing Aliyun Hong Kong ECS, with isolated dev/prod services.
  Game backend `voice-20260916` is deployed; domain 20 and content remain unchanged.
  Android 0.11.0 / 2026091607 is the single Journey preview package, delivered
  through Feishu with verified download/readback. Voice seats
  are capped at 8 per party and 32 globally in production, independent of the
  300-player game capacity. Join muted, retain voice across scene changes, and
  disconnect/reset on background or account replacement. Membership removal rotates
  the voice room generation. Keep SGODOT-126 In Progress pending real-phone and
  future iOS acceptance. See `docs/qa/party-voice-2026-09-16.md` and
  `server/deploy/voice/README.md` for deployment, evidence and limits.

- Current iteration adopted on 2026-09-16: 0.10.4 / 2026091606 keeps party
  panel closing in a fixed top-right header, dismisses on outside taps without
  activating the world, and copies invite codes with a localized timed toast.
  Keep button drag scrolling, party travel guards, accounts and saves.
  See `docs/qa/party-panel-2026-09-16.md`; deliver only the Journey update APK.

- Current iteration adopted on 2026-09-16: 0.10.3 / 2026091605 fixes scrolling
  when gestures start on buttons or cards. All 12 scroll surfaces use a shared
  touch scroll container, including nested horizontal/vertical lists and dynamic
  content. Dragging cancels clicks; toggles and dropdowns activate on release.
  Preserve native text/numeric editing, world gestures, accounts and saves.
  See `docs/qa/scroll-ui-2026-09-16.md` for validation and single-APK delivery.

- Current iteration adopted on 2026-09-16: 0.10.2 / 2026091604 adds actual saved
  outfit synchronization in all online spaces. Validate cosmetic part IDs against
  the shared catalog; publish on join/save, retain latest appearance in rosters,
  and reset pooled rigs including removed accessories. Keep the eight detailed
  nearby rigs and distant simplified crowd. Local wardrobes remain local; do not
  overwrite them with remote appearance. Preserve saves, party travel and combat
  attributes. See `docs/qa/appearance-sync-2026-09-16.md`.

- Current iteration adopted on 2026-09-16: cross-region party travel (0.10.1 /
  2026091603) is deployed, installed on V2509A and delivered through Feishu.
  Go to leader loads the target layout/channel; private
  farms require owner opt-in for the current party. Re-entry follows the mine
  leader’s current floor with explicit replacement confirmation. Preserve original
  home identity/choices, pending settlement and reconnect intent. Existing live
  parties and saves survived migration unchanged. See
  `docs/product/party-cross-region-travel-2026-09-16.md` and
  `docs/qa/party-travel-public-release-2026-09-16.md`.

- Current iteration adopted on 2026-09-16: online street/farm spaces and Warcraft-style
  private mine instances, each capped at 300 players. Mine joins are server-selected:
  grouping never teleports existing members; re-entry follows the leader's CURRENT
  mine only while that leader is inside, otherwise it uses the member's own binding.
  Shared monsters, rocks and clearance; per-contributor independent durable loot.
  Preserve personal mine saves and permanent elevators. See
  `docs/product/multiplayer-spaces-2026-09-16.md` and
  `docs/qa/multiplayer-spaces-2026-09-16.md`. User authorized public deployment,
  physical installation and Feishu APK delivery on 2026-09-16. Version 0.10.0
  (2026091602) is deployed, installed on the V2509A and delivered through Feishu;
  see `docs/qa/multiplayer-public-release-2026-09-16.md`. Preserve the existing
  domain-20 saves and the server's single realtime writer.

- Current iteration adopted on 2026-09-16: R5 farm miniatures stay on the
  selected owner's right at 75% of their former size. Mine floors 3 and 4
  open after clearing either rocks or monsters; floor 5 has only an elite.
  Kills grant stable random seed/mineral loot. The elite has 300 HP, 2.8 speed
  and resists interruption. Preserve unclaimed resources on passable floors,
  defeated enemies, old HP fractions, equipment and elevator unlocks.
  Public domain 20 is deployed. See `docs/product/mine-combat-2026-09-15.md`
  and `docs/qa/mine-routes-2026-09-16.md` for rules, delivery and test limits.
- Current iteration adopted on 2026-09-15: mine monsters and real-time weapon
  combat. See `docs/product/mine-combat-2026-09-15.md`. Floor 3 has one slime,
  floor 4 three slimes, and floor 5 one elite. Preserve old cleared floors,
  elevator unlocks, NPC requests, item ownership and saves. Validate in Godot
  and the Android emulator. On 2026-09-15 the user explicitly authorized online
  deployment and delivery of the online APK to them through Feishu.
  The initial domain-19 public preview and signed Journey/Workshop APKs were deployed;
  Feishu delivery is verified. See `docs/qa/combat-public-release-2026-09-15.md`.
  Physical feedback led to the 0.8.1/R2 client movement fix: preserve valid
  motion along obstacle edges without changing blocked cells or mine layouts.
  See `docs/qa/movement-sliding-2026-09-15.md`. Multiplayer was discussed only;
  `docs/product/multiplayer-mine-notes-2026-09-15.md` is not implemented scope.
  Further Feishu feedback is addressed by 0.8.2/R3: confirmed death automatically
  returns to the farm character page; bounded health prediction and serial
  asynchronous settlement keep combat responsive during normal HTTP latency.
  Suspended farms defer scene rebuilding until resume. Preserve server-owned
  rewards, uncertain-command recovery and R2 movement. The public APKs and
  Feishu delivery are verified; see `docs/qa/combat-latency-rescue-2026-09-15.md`.
  The user's next visual adjustment is 0.8.3/R4: hide the mine's held sword by
  default and show it only during each swing. Preserve equipment and combat
  rules. Godot, Android emulator and public APK checks passed; see
  `docs/qa/weapon-visibility-2026-09-15.md`.
- Current iteration adopted on 2026-09-14: SGODOT-114 NPC requests, acceptance,
  tracking and delivery feedback. See `docs/product/npc-requests-2026-09-14.md`.
  Preserve the three existing residents and request sequence identities;
  stopping tracking is not abandoning an accepted request.
  The user requested physical installation of 114 and removal of the farm mine
  entrance icon. The entrance is now selected through its 3D model, consistent
  with the mine's rocks, ladders and elevator; retain the existing save rules.
- Current iteration adopted on 2026-09-14: SGODOT-113 character attributes,
  equipment and consumable effects. See
  `docs/product/character-equipment-2026-09-14.md`. Preserve existing cosmetic
  ownership and saves; validate in Godot and the emulator before device updates.
  The user explicitly requested physical installation and testing of 113;
  its separate phone app and test service are installed and verified.
- Current iteration adopted on 2026-09-14: SGODOT-112 unified items and inventory.
  See `docs/product/inventory-2026-09-14.md` for ownership, capacity, overflow
  and migration rules. Use Godot and the emulator for development verification.
  The user reconnected the physical phone and explicitly requested installation
  of the inventory version on 2026-09-14; preserve existing apps and saves.
- Current iteration adopted on 2026-09-14: a five-floor starter mine entered
  from the player's farm. Clearing floor five permanently activates the
  elevator between floors one and five. Mining materials feed crafting and
  cooking. See `docs/product/starter-mine-2026-09-14.md`; retain Chinese
  coverage and save integrity while implementing this user-selected scope.
- Temporary top priority adopted on 2026-09-10: Simplified Chinese localization.
  Complete player-facing Chinese text, bundled font coverage and layout checks
  before resuming the regional-growth sequence. Keep protocol/save identifiers
  stable; localization is not a change to gameplay rules or release status.
- The user's 2026-09-07 priority is to make this a more enjoyable map-based game.
- For gameplay changes, read `docs/product/fun-first-rework-2026-09-07.md` first.
- Its direction supersedes conflicting time gates, scope freezes, UI conventions,
  balance targets, and priorities in older product documents, plans, and memos.
- Distinguish implemented behavior, proposed design, and verified player outcomes.
  The new direction is a design baseline; it does not mean the rework is shipped.
- Preserve existing work and save integrity. Update affected contracts and tests
  when implementing new rules instead of treating historical assertions as
  immutable product requirements.
- The user adopted the next-stage action blueprint on 2026-09-10. Read
  `docs/product/next-stage-action-blueprint-2026-09-10.md` for current sequencing
  and `docs/product/regional-growth-gdd-2026-09-10.md` for the design draft.
  Compact growth/resource/validation design precedes a two-region prototype;
  60-90 minute natural-session validation follows evidence of repeated choices.
  Do not resume an open-ended content/polish loop merely to fill that duration.
  Draft rules and numbers are not implemented or player-validated outcomes.

# Android QA Sessions

- Delivery preference updated on 2026-09-19: send updates or APK links to Joey
  only when the user explicitly asks for that delivery. Earlier Slack delivery
  requests do not authorize sending future iterations automatically.

- APK distribution added on 2026-09-18: use the existing DMIT Los Angeles host
  for overseas downloads at https://download-us.sensenjoy.cn:8443, with OSS as
  fallback. Preserve the existing services on ports 443/18443/1194. Publish only
  the signed Journey APK and public checksum/manifest in immutable version paths;
  verify full HTTPS downloads and Range support. See server/deploy/downloads/README.md.

- Delivery preference adopted on 2026-09-16: unless a specific exception is
  necessary, build and send only one user-facing APK, the Journey update with
  its existing package name and signing certificate. Do not routinely produce
  separate Journey / Workshop / test packages for delivery. Keep development
  QA builds separate from the single package sent to the user.

- Run installed test apps through `tools/android/run_test.sh`; see
  `tools/android/README.md`. Keep an entire multi-step scenario in one session.
  The runner force-stops the target before launch and on exit or interruption.
- Use `--clean-all` when old Sensen test processes must be stopped. Preserve
  installed applications and saves, and keep the Android emulator running.
- Background CPU diagnosis starts with measurements before application changes.
  Do not infer a runtime defect solely from the number of installed packages.

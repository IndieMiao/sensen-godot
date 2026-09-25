# Voice-match H5 in the dressing room — Android prototype (2026-09-25)

Scope: Android only. Dressing room gets a "Voice Profile" pill (right side, above
the drawer) that opens https://match.sensenapp.com/?embed=1&theme=gensen&mode=solo&lang=<game>
in a native WebView (`GodotWebView`, `native/webview/android/`).

Web-side changes are live on https://match.sensenapp.com (gensen-voice-match
`main` 9900332 embed mode, 3150f5f Gensen theme; CI + auto-deploy passed, served
bundle verified):
`embed=1` hides the language toggle, moves the demo badge left, `mode=solo`
preselects Solo, the microphone is released after every stop and on
`visibilitychange: hidden` (recording in progress is finished or marked too short).

## Emulator evidence (emulator-5560, WebView 145)

| Check | Result |
|---|---|
| Entry renders, tappable, layout test | pass (gdUnit `test_voice_profile_entry_*`) |
| Opens in-app, game language passed | pass (zh) |
| Mic permission: one system prompt, no second web prompt | pass |
| Record → review → analyze → result | pass (local DEMO_MODE backend) |
| System back closes page, stays on dressing room, try-on kept | pass after fix |
| ✕ closes page, mic released (no AudioRecord clients) | pass |
| Reopen after close, record again | pass |
| Background while recording (prod page) | **mic kept** — prod site lacks the web fix |
| Background while recording (embed branch) | mic released, returns to "too short" |

Bug found and fixed: Godot 4.7 `Godot.onBackPressed()` calls every plugin but
discards the return value and always sends GO_BACK to the engine, so the back
press closing the page also popped the dressing room. Fixed with WebView focus
plus a 600 ms swallow window in `VoiceMatchLink`.

## Follow-up the same day

- User tested on V2509A (Tailscale wireless adb): "可用". Requested (1) Gensen theme,
  (2) English by default → `theme=gensen` shipped; the game now always passes `lang=en`.
- Boot splash: Godot logo removed (`boot_splash/show_image=false`, bg `#fffdf8`);
  cold-launch screen recording on V2509A shows launcher → cream frame → city select.
- Release 0.16.38 / 2026092501 prepared with `prepare_system_pond_release.gd --voice-match`.

## Not yet verified
- Other phones (vendor WebView/ROM differences) and Bluetooth headsets; only V2509A was tested.
- Party voice active while the page records (code mutes/restores the party mic; untested).
- Incoming call interruption.
- Strict mode (server fallback to demo data still on in prod), iOS.
- Mic-denied notice screen in the Gensen theme (not reachable in headless browser).

## Release 0.16.38 and delivery (2026-09-25)

Source `aaf4585` (farm-dev). Release project from `prepare_system_pond_release.gd --voice-match`;
original certificate `38771d94…`; 178,431,631 bytes, SHA-256 `a651401a…23566`. Client-only;
backend stays integrated-20260924 (domain 27). Full suite: 1176 cases, 6 failures, all
reproduced on unchanged code (visitor farm, touch scroll, app theme ×2, design tokens, stress HUD).

- Emulator: over-install kept identity files, logged in, Voice Profile opens the live Gensen/English page.
- V2509A: over-install hash and identity files verified; launched to city select (login log not
  captured on vivo; no taps on the personal phone beyond the installer confirmation).
- DMIT + OSS: full download hash, Range 206, release.json, SHA256SUMS verified.
- User requested delivery to Joey: Slack DM with the full APK attachment (file F0C4GEU2HKK);
  Feishu Drive upload (IM limit 100 MB), view access for Joey only, DM with the link; Drive
  download hash and message read back. Not a standing authorization for future versions.

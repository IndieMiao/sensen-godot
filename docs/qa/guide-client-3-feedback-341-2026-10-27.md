# SGODOT-341 C-client-3 independent feedback draft

Su Lie, 2026-10-27. Base: `origin/farm-dev c7ee6bb6` (includes C1). This is the independent C3 feedback slice, not full C2/C3 integration or release acceptance. The PR stays Draft.

## Scope and decisions

- q(215), gameplay plan §14.3 and 341 plan `7e740ad2`: fishing progress uses the goal before settlement. The last landed fish still says `Catch 2 fish 2/2` or `Catch 1 fish 1/1` when the returned view has already advanced or cleared recovery. It joins the existing catch floats after the fish reaches the hand; no new completion toast.
- q(217) / q(229): `guide/action=resend` supplies the actual `bagged` amount. Only that portion floats/flies; a full bag uses the existing ordinary InboxNotice, with no seed pill. A first chat's affinity and the seeds share a group so they do not overlap. The explicit Pip reply survives the next-step line. Closing the conversation before a reply never reopens it. ItemFly keeps its existing visible-destination guard: no flight toward a Bag hidden under a dialogue; the confirmed quantity still floats above it.
- Replayed seq does not repeat guide feedback. A pending reel retains its original goal across an empty refresh after a lost response; a new cast clears that snapshot. Only confirmed landed catches count, not escapes, trap collection or ordinary reads.
- 341 `97156a0f`, forwarded by the director: **notification trigger amendment pending q approval**. `p0_radish_prompt_gate.gd` contains only a default-off eligibility gate and an explicit once acknowledgement. All four conditions must hold after done/timeout: own farm, at least one growing/unripe ordinary Radish, no held input, no open panel or end feedback. Legacy, Quick Radishes and ripe/unwatered plots do not qualify. Disabled checks do not consume the future question. There is no production prompt caller, permission request, local notification bridge, scheduler or new saved field. A future bridge must restore/persist the account's asked flag only on actual display, and ship real ripening reminders before enabling this gate. **This draft section must not merge before the q amendment is approved.**

## C2 interface boundary

Alignment requested on 341 `dd496d10`; Liu Bang confirmed `e028023c`. C2 retains `guide_shown`, `guide_marks`, `pip`, `target_badge`; `resident_badge(view,id,place="")` adds a compatible optional argument. `P0Ui.resident_say(id,line)` and `resident_float_at(id)` stay. C2 will put explicit `_reply` after the Pip step line. C2 owns FarmGuide frame/leave, farm suspend, NPC tags, ordinary marker restoration and Pip lifetime. C3 does not duplicate them.

This branch consumes the existing C1 guide view and resident APIs, and exercises synthetic snapshots plus an isolated real local server. C2's final head must be integrated after it merges, then verify the actual farm Pip, reopen/step-change dialogue priority and the complete sequence. The current screenshots do not claim C2's farm Pip model is present. Ordinary-account `GUIDE_V3_READY` remains false.

## Verification

- Final code head `72d14003`: `tests/p0 + tests/ui_kit` **1808/1808 passed**, 0 gdUnit errors/failures/skips/orphans, exit 0 (`report_466`, 3m 7.987s). This includes all 16 new helper/runtime cases and the repeated-first-chat assertion. Subsequent commit only records this result.
- Covered: main 1/2 and terminal 2/2, recover 1/1 and 2/2 across target changes, stale earlier progress plus server step event, lost-reply refresh, new-cast reset, empty refresh, duplicate/out-of-order seq, timeout/legacy, non-landed catches, bagged 0/1/2, late response after closing dialogue, ordinary full-bag notice, first-chat/seed layout and notification gating/once state.
- Capture fixtures are isolated `player-sulie-c3` saves produced by the existing server's freshState/viewOf. Main last catch enters t_meal with catch=2; recover catch leaves t_soup active with its fish requirement healed. Pip talk really emits resend and writes the two seeds or the parcel. No real account is used.
- Media: four 360×800 screenshots and two 6-second / 30fps / 720×800 comparison videos. Fish video: main terminal left, recovery terminal right. Resend video: bag left, Inbox right; independent scenarios aligned to their feedback, not a single session.
- Exported MP4s were probed and decoded to frame strips for inspection. Local source frames / capture logs / seed files are under `output/sulie-c3-341/`. Capture-only fixture scripts remain outside the repository at `/Volumes/ACASIS/tmp/sulie-badge/seed_c3.ts` and `c3_capture.py`.
- Scripts used normal game mode and `--script` tests only. No `--import`, `--editor`, adb, emulator, phone, server deployment or save migration. Capture processes exited; the 3146 server, temporary override.cfg and dedicated capture user directory were cleaned. Existing capture shutdown logs report 5 ObjectDB instances, separate from gdUnit orphan results; no claim of a leak-free full game session.

Review evidence and final counts: [SGODOT-341](https://plane.sensenjoy.cn/zili/browse/SGODOT-341/). Code review: Zhou Yu. Visual/video review: Bu Zhi Huo Wu. Merge and eventual release belong to the director after approvals and integration.

Test-log note: the full run also contains 39 existing freed-lambda engine diagnostics and one kitchen `_puff` backtrace. Counts match the preceding q(230) baseline run exactly; no GDScript parse/runtime errors or gdUnit failures. These existing diagnostics are not described as fixed by C3.

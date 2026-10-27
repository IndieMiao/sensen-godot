# SGODOT-341 C-client-3 independent feedback draft

Su Lie, 2026-10-27. Base: `origin/farm-dev c7ee6bb6` (includes C1). This is the independent C3 feedback slice, not full C2/C3 integration or release acceptance. The PR stays Draft.

## Scope and decisions

- q(215), gameplay plan §14.3 and 341 plan `7e740ad2`: fishing progress uses the goal before settlement. The last landed fish still says `Catch 2 fish 2/2` or `Catch 1 fish 1/1` when the returned view has already advanced or cleared recovery. It joins the existing catch floats after the fish reaches the hand; no new completion toast.
- q(217) / q(229): `guide/action=resend` supplies the actual `bagged` amount. Only that portion floats/flies; a full bag uses the existing ordinary InboxNotice, with no seed pill. A first chat's affinity and the seeds share a group so they do not overlap. The explicit Pip reply survives the next-step line. Closing the conversation before a reply never reopens it. ItemFly keeps its existing visible-destination guard: no flight toward a Bag hidden under a dialogue; the confirmed quantity still floats above it.
- Replayed seq does not repeat guide feedback. A pending reel retains its original goal across an empty refresh after a lost response; a new cast clears that snapshot. Only confirmed landed catches count, not escapes, trap collection or ordinary reads.
- Scope corrected by the director on 2026-10-27: C3 contains only catch completion feedback, seed resend feedback and C2 integration. The entire q(235) notification work, including the early-sowing fallback and q(215) clause 10, belongs to Arthur on SGODOT-350. The notification helper, switch and three notification tests have been removed from this PR; C3 has no dependency on q(235) approval.

## C2 interface boundary

Alignment requested on 341 `dd496d10`; Liu Bang confirmed `e028023c`. C2 retains `guide_shown`, `guide_marks`, `pip`, `target_badge`; `resident_badge(view,id,place="")` adds a compatible optional argument. `P0Ui.resident_say(id,line)` and `resident_float_at(id)` stay. C2 candidate PR #516 at `d0c08ff6` already puts explicit `_reply` after the Pip step line; its Draft was still open during this scope correction. C2 owns FarmGuide frame/leave, farm suspend, NPC tags, ordinary marker restoration and Pip lifetime. C3 does not duplicate them.

This branch consumes the existing C1 guide view and resident APIs, and exercises synthetic snapshots plus an isolated real local server. C2's final head must be integrated after it merges, then verify the actual farm Pip, reopen/step-change dialogue priority and the complete sequence. The current screenshots do not claim C2's farm Pip model is present. Ordinary-account `GUIDE_V3_READY` remains false.

## Verification

- After the notification scope removal: `tests/p0 + tests/ui_kit` **1805/1805 passed**, 182 suites, 0 gdUnit errors/failures/skips/orphans, exit 0 (`report_467`, 3m 8.094s). The retained feedback suite has 13 cases. The prior 1808-case report included the three notification tests that have now been removed.
- Covered: main 1/2 and terminal 2/2, recover 1/1 and 2/2 across target changes, stale earlier progress plus server step event, lost-reply refresh, new-cast reset, empty refresh, duplicate/out-of-order seq, timeout/legacy, non-landed catches, bagged 0/1/2, late response after closing dialogue, ordinary full-bag notice, first-chat/seed layout.
- Capture fixtures are isolated `player-sulie-c3` saves produced by the existing server's freshState/viewOf. Main last catch enters t_meal with catch=2; recover catch leaves t_soup active with its fish requirement healed. Pip talk really emits resend and writes the two seeds or the parcel. No real account is used.
- Media: four 360×800 screenshots and two 6-second / 30fps / 720×800 comparison videos. Fish video: main terminal left, recovery terminal right. Resend video: bag left, Inbox right; independent scenarios aligned to their feedback, not a single session.
- Exported MP4s were probed and decoded to frame strips for inspection. Local source frames / capture logs / seed files are under `output/sulie-c3-341/`. Capture-only fixture scripts remain outside the repository at `/Volumes/ACASIS/tmp/sulie-badge/seed_c3.ts` and `c3_capture.py`.
- Scripts used normal game mode and `--script` tests only. No `--import`, `--editor`, adb, emulator, phone, server deployment or save migration. Capture processes exited; the 3146 server, temporary override.cfg and dedicated capture user directory were cleaned. Existing capture shutdown logs report 5 ObjectDB instances, separate from gdUnit orphan results; no claim of a leak-free full game session.

Review evidence and final counts: [SGODOT-341](https://plane.sensenjoy.cn/zili/browse/SGODOT-341/). Code review: Zhou Yu. Visual/video review: Bu Zhi Huo Wu. Merge and eventual release belong to the director after approvals and integration.

Test-log note: the full run also contains 39 existing freed-lambda engine diagnostics and one kitchen `_puff` backtrace. Counts match the preceding q(230) baseline run exactly; no GDScript parse/runtime errors or gdUnit failures. These existing diagnostics are not described as fixed by C3.

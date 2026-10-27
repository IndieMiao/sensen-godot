# SGODOT-341 · C3 feedback and C2 integration

The final integration is **based on C2 c27deb33cd9e729b8e9f906dbe3b16ad63e96b44**, explicitly confirmed by the director after the initial 12a44f67 assignment. Merge commit and final tested code: `5b52ab9a`; the Pip dialogue fix is `9a720c9b`. The local server uses the complete #518 source **fef95d49af5663694f6a5ebe4c1d02b3b6c6dda6**, including the typed marks. No server changes are included in C3.

## Result

- The existing C3 feedback keeps the pre-settlement goal for `Catch 2 fish 2/2` and `Catch 1 fish 1/1`, including a lost reel reply followed by an empty refresh. Progress joins the existing landing float group; no new completion toast. Sequence replay does not duplicate guide feedback.
- Pip's seed resend uses the confirmed `bagged` quantity. A full bag uses the ordinary InboxNotice; first-chat affinity and seeds share separate lines. Closing the dialogue before a reply does not reopen it. ItemFly retains its existing visible-Bag guard.
- C2 owns the actual Pip, markers, pulse budgets and model lifetime. The integration found one dialogue boundary bug: the explicit resend reply remained after closing and reopening Pip, covering the current step sentence. The fix clears the old reply only for a new farm-Pip conversation. In-place rebuilds keep the confirmed answer. A regression failed at the reopened-line assertion before the fix (`report_468`), then passed with the fix.
- C3 contains only feedback and C2 integration. All q(235) notification work, including early-sowing fallback, switches, asked-state, Settings Notifications and q(215) clause 10, belongs to SGODOT-350. None is implemented here. Ordinary accounts still do not send `guide_v3`.

## Verification

- Initial 12a44f67 integration: **1826/1826 passed** (`report_470`). Final c27deb33 integration at code head `5b52ab9a`: **1829/1829 passed**, 183 suites, 0 gdUnit errors/failures/skips/orphans, exit 0 (`report_471`, 3m 23.050s). Targeted guide feedback / world / catch-moment suites: **36 passed**. C3 has 14 feedback tests including the new integration regression.
- On the unmodified #518 server snapshot, guide framework / s1 / director suites: **45 passed**. This exercises the server's main line and deviations; it is not a claim that every S0–S11 UI input was replayed on a physical device.
- Isolated real HTTP and actual game scenes produced **56 passing functional checks** across six cases. Pip was opened with viewport mouse input; S11 used the existing request card action. The records retain actual guide views and command events.

| Case | Checks | Result |
|---|---:|---|
| Pip resend into bag, close/reopen, timeout, enter farmhouse and return | 10 | Model present, reply wins, exactly two seeds, new conversation uses current step; guidance ends immediately, model stays until leave, does not respawn. |
| Full-bag resend and the same lifecycle | 11 | No seed-in-bag pill; ordinary InboxNotice appears after dialogue closes. |
| Main final fish | 7 | #518 Cast mark pulses once; confirmed final catch shows 2/2, old target/pulse clears, no completion toast. |
| Recovery final fish | 6 | No invented Cast mark; confirmed catch shows 1/1 and clears the healed recovery target. |
| S11 normal completion | 6 | Real Six Radishes card accepts; server says done; ordinary Today/pulses restored; returning home has no Pip. See exit limitation below. |
| c27deb33 water badges after a Pip resend | 16 | Confirmed resent seeds are sown into two plots, advancing to t_water. Two droplets and one Water pulse appear; Pip reads the water sentence, hides badges while speaking, and badges return after close without exceeding the pulse budget. Actual Water actions remove one badge per reply, then advance to t_sow_rest. |

## Visual review point

The c27 water-badge capture at plot 0 shows the left droplet partly behind the expanded Reed Bank name strip. This is a concrete review point in the attached `341-c2c3-two-water-badges.png`; the C3 increment does not change badge placement. It is recorded for the C2/design walkthrough rather than claimed visually accepted.

## Known process-exit limitation

The normal-completion case passes all six functional checks and captures the returned farm, then the macOS Godot 4.7.2 process crashes during application termination (signal 11, process result -6). It reproduced on an isolated checkout of **original C2 12a44f67 without C3**, with the same six functional checks passing and the same termination stack shape. Two integration attempts and one C2 control reproduced it. C3 does not claim to fix the engine-exit failure or a clean exit for that case. The other five final captures exit 0. The exit control is against the assigned 12a44f67 C2 baseline; the subsequent c27deb33 change is limited to teaching-water badge drawing, hiding and tests.

The QA driver originally checked pulse cleanup before C2's 100 ms refresh, and the dev-clock change originally lacked the following normal GET that settles the guide. These probe timing issues were corrected before final functional reports. Failed captures are kept local and not presented as passing materials. The existing capture shutdown ObjectDB warnings and full-suite engine diagnostics are not claimed fixed by C3.

## Review media and environment

Review files are in `output/sulie-c3-integration-341/`: real Pip resend and reopened dialogue, ordinary Inbox, timeout model retention/removal, main/recovery terminal fish, and normal S11 completion. Videos use wall-clock timestamps per captured frame, then encode at 30 fps; elapsed time is not inferred from sampled frame count. MP4s are decoded to strips for inspection. `341-c2c3-integration-report.json` explicitly separates functional checks and process exits, including the C2 control.

The first five cases capture the 12a44f67 integration; the added water-badge conversation/action case captures final c27deb33. The final full suite covers their combined code. No production source changed after that suite except this report.

All saves use isolated `player-sulie-c3` fixtures and a dedicated user directory. Server port 3146 and capture PIDs are owned by this run; override/user files are cleaned after each run. No Godot `--import` / `--editor`, adb, emulator, phone, production deployment or save migration. Temporary QA worktrees are disposable; no other agent's workspace is changed.

Prior independent-feedback media remains on [SGODOT-341](https://plane.sensenjoy.cn/zili/browse/SGODOT-341/) `589739d2`; its code/design approvals applied to `fbc5891a`. This integration increment requires Zhou Yu's re-review and Bu Zhi Huo Wu's visual review. The director handles combined user review and merging.

# First Week Demo

Target: 15 minutes, an isolated QA farm, and the current development build.
Production time, crop durations, rewards and chapter requirements stay unchanged.
The Director only changes the server QA clock; never edit chapter flags in a save.

Physical feature verification on vivo `10AFAF162200319` is complete, including a continuous seven-chapter touch route and ordinary-APK restart recovery. Follow [G3 Physical Android Validation](g3-physical-2026-09-05.md) for evidence and completed device restoration. Human presentation and performance acceptance remain open; the automated route took 18m24.493s.

## Before Starting

- Start `pnpm --dir server exec tsx tools/g3_qa_server.ts` from the repository root. It listens only on `127.0.0.1:3103` and uses `sensen_farm_g3_ui_qa`.
- Connect Android with `adb reverse tcp:3103 tcp:3103`. Use a backed-up QA install key and point the development client at `http://127.0.0.1:3103/v1`.
- Check that the account is a new farm in Chapter 1. Keep the personal installation key, farm choice, outfit and region selection backups outside the device.
- Long-press the farm title for three seconds to open Director. Use 60x for the first three-minute radish crop; restore 1x after harvesting. Use +1 day only after the chapter goals are complete.

## Fifteen-Minute Route

| Time | Chapter | Playable Actions And Evidence |
| --- | --- | --- |
| 0:00-2:30 | D0 | Choose Shanghai and a farm location; enter the farm. Clear and till nine plots, plant and water six radishes. Harvest, deliver the first basket, sell the other three, meet the nursery keeper. Buy six radish seeds, plant six radishes plus three chapter lettuces and water all nine. Check chapter completion. |
| 2:30-4:00 | D1 | Advance one day. Harvest, meet the bistro host and deliver three lettuces. Claim weather support, give the keeper a radish, record its use and sell the rest. Buy 4R+2L and plant 4R+5L using chapter seedlings. Drain the rainy plots. |
| 4:00-5:00 | D2 | Harvest; share one lettuce with the host and record the gift. Talk again to hear the remembered choice. Sell 4R+4L, buy 2R+3L+2C, plant 2R+3L+4C and water. |
| 5:00-7:00 | D3 | Harvest. Make the first salad in the bistro, continue the shared meal dialogue and confirm. Deliver 2C+1L to the keeper, give the host one radish and record it. Sell the remaining 1C+1L+1R. Buy 4C+2L+1H, plant 4C+2L+3H and water. |
| 7:00-8:30 | D4 | Harvest. Reserve then deliver 1C+1H; inspect the cleared nursery. Brew one tea and use the buyback. Enter a nearby farm, inspect the read-only snapshot and return. Keep one lettuce for next week. Sell 3C+1H+1L, buy 3C+3L+1H, plant 3C+3L+3H and drain. |
| 8:30-11:00 | D5 | Harvest. Meet the restorer, make two salads and deliver lunch. Deliver another H to the nursery, pick either entrance style, share one H and record it. Sell 1C+1H+1L. Choose and purchase row tools (240 coins) or the fourth bed with seed basket (484 coins). Preview courtyard pieces, move one, undo, then save. Plant the selected route's next crop and shelter it from the wind. |
| 11:00-14:00 | D6 | Harvest, reserve and deliver the last 1C+2H. Join all three residents in the courtyard and open the nursery together. Talk with residents, claim completion support, resolve the last lettuce use. Inspect the actual ending and journal pages. Sell the remaining harvest and replant. |
| 14:00-15:00 | Ending | Open the group photo, verify the player's current outfit and chosen nursery appearance, and save the rendered photo. Return to the map and reopen the farm; check balance, project and layout persistence. |

R = radish, L = lettuce, C = carrot, H = chamomile. The exact four-route action ledger is `server/test/fixtures/build_ledger.ts`.

## Alternate Ending And Recovery

- For the selling branch, sell each chapter's designated single crop and record that sale instead of a gift/keep. The six use decisions determine the ending; four or more gift/keep decisions unlock two journal pages and personalized photo staging.
- Final life-route balances: tools 305, fourth bed 145; account value 545 and XP 301. Final selling-route balances: tools 376, fourth bed 200 with two radishes unsold: D6 settles 95/100 coins, and the remaining five cannot buy another eight-coin radish.
- The week summary records its first valid completion moment. Later sales or purchases change the live wallet, not the recorded photograph/journal snapshot.
- If a request finishes without a confirmed result, use the panel's check/reconnect control. Normal in-flight plot commands do not show the farm reconnect control solely because their envelope has been saved.
- The ordinary APK persists the original envelope before sending it. After force-stop, retain the same installation key/account and server URL: login and farm identification precede recovery with the original idempotency key. Wait for reconciliation before another purchase, gift, meal or layout save. Do not switch between the direct QA server and a fault-proxy URL while an action remains unresolved; endpoint identity is part of the journal scope.
- The automated desktop runner is `godot --path . --resolution 390x844 tools/dev/g3_week_ui.tscn -- --week-path=tool --week-style=life`. It drives real controls and plot callbacks over HTTP, saves screenshots and a JSON report, and restores its local installation/farm settings.

## Acceptance Boundary

Domain tests, public HTTP persistence tests, desktop controls and Android rendering are separate evidence. The earlier desktop/emulator checkpoint in [G3 Playable Week](g3-seven-day-2026-09-05.md) is historical evidence; an emulator run does not complete physical-device acceptance. After testing, restore all device settings byte-for-byte, remove the temporary endpoint override and stop the loopback QA server. Record completion of those steps in the physical validation record; the instructions here do not assert that restoration has already occurred.

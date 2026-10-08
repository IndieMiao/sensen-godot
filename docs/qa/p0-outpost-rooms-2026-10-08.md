# P0 outpost rooms and realtime rooms — emulator walkthrough (SGODOT-227, 2026-10-08)

Scope: the four home-set outposts (Xuhui Tackle Shop, Lotus Tea House, Huangpu Travel Post, Xuhui
Market Square) on the indoor shell `P0Room` (SGODOT-226, PR #13), and their realtime rooms on the P0
playtest server (`/v1/p0/online`, `/v1/p0/presence`). All four use the Basic Room placeholder until
wp-3d-scene lands (SGODOT-208). This is an emulator check, not a physical-phone acceptance.

## Setup

- Isolated AVD `Houyi_P0` (emulator-5584, 2 GB), private ADB server on 5073 limited to that emulator,
  test package `com.sensen.p0proto.houyi`, worktree P0 server on 3197 with `adb reverse tcp:3110 tcp:3197`
  and its own state file. All of them were stopped after the run.
- Two scripted players in the tea house (one walking a loop, one seated on the bench) and twelve idle
  players filling Room 1 of the tackle shop, all over the same `/v1/p0/online` protocol.

![Walkthrough](p0-outpost-rooms-2026-10-08/emulator-walkthrough.jpg)

Left to right, top row: tea house pin `Lotus Tea House · 2 online` with its card and `Go`; the place
list with the four outposts; Xuhui Tackle Shop (Finn at the counter, Old Kai by the window); Lotus Tea
House with the two other players. Bottom row: seated at the tea table (standing pose until the sit
clips land); entering the full tackle shop lands in Room 2 with `Room 1 is full · you're in Room 2`;
Huangpu Travel Post (Sigrid, Pip); Xuhui Market Square (`Exit · Back to map`).

## Checked

| Item | Result |
|---|---|
| Map: four outpost pins from `assets/p0/p0_outposts.json`, card `Go` opens the room above the map | Pass |
| Pin label `· N online` from `/v1/p0/presence` (all rooms together), refreshed on return from a room | Pass |
| Spawn at the door facing in; place chip `Shanghai · <outpost name>` | Pass (4/4) |
| Keeper and residents at their `npc_` anchors with name tags; finger card `<Name> · Tap to talk` | Pass |
| Tapping the keeper walks to `stand_counter`, then opens the keeper entry (tackle: existing greeting until SGODOT-224) | Pass |
| Other players visible and moving (OnlineCrowd, frame v1) | Pass |
| Tea table: walks to the nearest free seat, server holds it, joystick stands up | Pass |
| Room 2: 13th player of an indoor outpost; toast only on a fresh join to Room 2+ | Pass |
| Door: Back walks out to the map; market uses `Exit · Back to map` | Pass |

## Found and fixed during the run

1. Back while seated left the room at once (no path from inside the chair collider) and the router
   then popped an empty stack into the old map. The shell now always reports Back as handled
   (bc94dd96, SGODOT-226); outposts stand up before walking to the door (7fd59052).
2. The selected city-map name tag was measured at font 9 with an 18 px pad but renders at font 10 in
   4 + 4 px margins, so `Lotus Tea House · 2 online` got a two-line box (7fd59052).
3. The room connection read the default server URL when an outpost was the first world (dev boot):
   it now waits for the P0 session (a34a041b).

## Seats and sit clips (2026-10-08, later the same night)

The user's Mixamo takes (SGODOT-230) are in the library as `sit_down`, `sit_idle`, `sit_up`, `sit_talk`
(first 8 s) and `drink_stand`; all 46 bones map and the probe contact sheet shows correct arms, no foot
sliding and an in-place hip:

![Sit clips probe](p0-outpost-rooms-2026-10-08/sit-clips-probe.jpg)

Measured on the base rig: `sit_idle` puts the hip joint 0.426 m above the rig root (standing 0.778 m), with
the thighs about 0.086 m below the joint. Basic Room seat surfaces are about 0.74 m (chairs) and 0.745 m
(window bench) in room coordinates, so the seated root sits 0.34 m below the `seat_` anchor (feet dangle on
these tall stylized seats). Sitting plays `sit_down` then loops `sit_idle` while the root eases onto the
seat (about 0.3 s); standing plays `sit_up` at 2x and releases the player after 0.55 s; Back while seated
stands up and then walks to the door. Other players on a seat are lifted onto it and play `sit_idle`.

![Seated at the tea table and on the bench](p0-outpost-rooms-2026-10-08/seated-tea-house.jpg)

Desktop render, Basic Room placeholder: player on the door-side chair, a scripted player on the bench.
Acceptance of the seated pose (hip contact within 2 cm, legs clear of the table, recording on the final
tea-house scene 179) belongs to the art director.

## NPC outfits (2026-10-08)

The thumbnails in `assets/avatar/thumbs` are grey placeholders, so the catalogue parts were rendered on the
base rig first (`tools/dev/parts_contact_sheet.gd`, front and 3/4). Only five hairHats are usable: `hairhat20`
(traffic-cone hood) is out, and `hairhat0` is the default player's hair.

![hairHat](p0-outpost-rooms-2026-10-08/parts-hairhat.jpg)
![cloth](p0-outpost-rooms-2026-10-08/parts-cloth.jpg)
![shoes](p0-outpost-rooms-2026-10-08/parts-shoes.jpg)
![messengerBag](p0-outpost-rooms-2026-10-08/parts-messengerbag.jpg)

Outfits in `assets/p0/outpost_npcs.json`, matched to the SGODOT-219 portraits (Old Kai, Ama, Mei, Pip) and
to the keepers' room-art crops (Finn, Sigrid):

| NPC | Where | hairHat | cloth | shoes | Why |
|---|---|---|---|---|---|
| Finn | Tackle shop keeper | hairhat43 | cloth1 | shoes4 | Not like Old Kai in the same room |
| Old Kai | Tackle shop resident | hairhat51 | cloth11 | shoes3 | Hat for the knit cap, apron, dark boots |
| Ama | Tea house keeper | hairhat41 | cloth11 | shoes5 | Brown hair, sage-green apron |
| Sigrid | Travel post keeper | hairhat43 | cloth1_1 | shoes3 | Blue uniform shirt |
| Pip | Travel post resident (scale 0.88) | hairhat70 | cloth1 | shoes1 | Navy cap, cream shirt, dark shorts, cross-body bag `messengerbag4` |
| Mei | Market keeper | hairhat41 | cloth1_1 | shoes2 | Brown hair; blue stripes and khaki for the scarf and apron |

No two NPCs share both hairHat and cloth, no one uses `hairhat0`, and the two NPCs in each room differ in
both. `tools/dev/npc_lineup.gd` renders the lineup next to the default player (`--portraits=<dir>` adds the
219 portraits, which stay out of the repo):

![NPC lineup](p0-outpost-rooms-2026-10-08/npc-lineup.jpg)

At the counter, with the player on `stand_counter` (market: `stand_stall_1`), finger cards hidden with the
`nomarks` shot step. The Basic Room counter stands against the wall, so keepers stand at its door end
facing the room; standing behind a counter waits for the final scenes:

![Keepers at the counter](p0-outpost-rooms-2026-10-08/npc-counters.jpg)

## Open

- Keeper and door finger cards no longer overlap: each room has a `badge_keeper` point that lifts the
  keeper's card clear above the door's (安其拉's design review of #14). Desktop render at the spawn:

  ![Keeper and door cards apart](p0-outpost-rooms-2026-10-08/keeper-door-cards.jpg)
- Seated pose not yet accepted by the art director; sitting while drinking is not done (see SGODOT-227).
- NPC outfits are accepted as the P0 placeholder (art director, 2026-10-08). Shared hairstyles (Ama / Mei on
  41, Finn / Sigrid on 43), Old Kai not reading old enough and Pip's bag not being a mail satchel wait for the
  dedicated parts in SGODOT-229; `npc_keeper` moves behind the counter when the final scenes land.
- `drink_stand` is in the library but not played in P0 (no cup prop yet; art director, SGODOT-227).
- Not covered here: physical phone (ask the user first), real network latency, more than one client
  device.

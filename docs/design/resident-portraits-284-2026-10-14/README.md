# SGODOT-284 · Resident portraits for the Kindred postcard stamps (q(171))

上官婉儿 · 2026-10-14. Visual review: 不知火舞 (SGODOT-284, 53f95d5a / 9abdc0da). Client: 苏烈.

The twelve Kindred stamps show one picture per resident. 不知火舞 decided:
- all twelve stamps use in-game renders;
- Pip and Old Kai keep their painted pictures in the dialogue bar;
- the other residents use the render card in the dialogue bar.

This batch is the nine residents whose look exists today: Pip, Old Kai, Rafa, Hana, Sam, Lena, Tomo, Theo and Nadia. Granny Wu and Ivo wait for new NPC parts (刘备, spec v1.1 on 284). Mira is not in P1.

## Runtime files (`assets/p0/art/residents/`)
- `<key>_card.jpg`: a 300 × 660 card per resident, the format of `pip-portrait.jpg`. `<key>` is the content's `portrait` field (pip, kai, rafa …), not the `res_` id.
- `portrait_crops.json`: `{key: {stamp: [x, y, w, h], face: [x, y, w, h]}}` in card pixels.
  - `stamp` is a 32:40 box for the stamp's 32 × 40 window.
  - `face` is a square for the profile's round face.
  - Both are measured from the head bone (Head_M, at the jaw) and the top of the figure, so they hold for any hat.
- Import settings are the same as `kai-portrait.jpg`.

## How they are made
- `tools/art/bake_resident_portraits.gd` draws each card on P0KeeperPortraits' own stage (#339): the same light, mint sky, three-quarter turn and card framing as the generated keepers. It does not change the renderer.
- Looks come from `assets/p0/outpost_npcs.json`, plus `--looks` for looks that are not in the game yet. This batch used `looks-v2.json`:
  - Lena gets glass1, so she no longer shares Sam's head;
  - Rafa and Tomo are new looks.
  - 苏烈 adds these looks to `outpost_npcs.json` when he places Rafa and Tomo.
- Run it with a window, not headless: `godot --path . --script res://tools/art/bake_resident_portraits.gd -- --looks=<json> --out=<dir>`.

## Review sheets (this folder)
- `residents-9-cards.png`: the nine cards, in the residents' table order.
- `residents-9-stamps.png`: each head at the stamp's 32 × 40 (top) and at 3× (bottom).
- `head-options-6x6-stamps.png` and `body-options-cards.png`: the option grids 不知火舞 picked from.
  - Head grid rows are hairhat0 / 20 / 41 / 43 / 51 / 70.
  - Head grid columns are no glasses / glass0 / 1 / 3 / 5 / 8.
  - Their looks are in `looks-head-options.json` and `looks-body-options.json`.
- `crops-review.json`: the crops with the measured head top and jaw.

## Integration
Only the runtime files go to farm-dev: the nine JPGs, their `.import` files and `portrait_crops.json`. The script and this folder stay on wp-3d-scene. 苏烈 then wires the stamp, the dialogue bar fallback and the profile face.

## Second batch (2026-10-14): Granny Wu, Ivo, Tomo
Drawn with the NPC parts of #407 (head 00ab44be), looks in `looks-final-granny-ivo-tomo.json`.
- Granny Wu: `hairhat80_npc_granny_wu` (silver-white bun, red pin) with cloth11 and shoes5.
- Ivo: `hairhat_npc_ivo` (mustard hard hat, brass lamp), `mask16_npc_ivo` (short grey beard), `cloth1_npc_ivo` (canvas shirt, charcoal shorts) and shoes3.
- Tomo: `hairhat0_npc_tomo` (warm dark brown, so he no longer reads as a new player in the default look), with glass0, cloth0, shoes2 and messengerbag3. His card replaces the first batch's.

`portrait_crops.json` now has eleven keys. `residents-11-cards.png` and `residents-11-stamps.png` show all eleven in table order (Mira is not in P1). Visual review: 不知火舞 on SGODOT-284 (87e87ff2, e07d1a16).

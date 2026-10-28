# SGODOT-354 · fast crops and early Homestead pacing (server)

Base: `farm-dev aca4070f`. Approved q(245)–q(247), including the user's Lv4 choice of 300 coins. Server implementation is separate from Liu Bang's client display work. Deployment must wait for their coordinated release and Meng Tian's US migration/deployment scripts; this work does not deploy anything.

## Rules and contracts

`assets/p0/content/farm_fast_crops.json` merges through the existing content-fragment loader into **fast_crops[]**, never crops[] or quick_seeds[]. The five rows are Cress (10s, Farming 1, seed 1 / sale 1), Pea Shoots (60s, Farming 1, 2 / 3), Baby Spinach (300s, Farming 2, 2 / 3), Scallion (1200s, Farming 2, 3 / 4), and Bok Choy (3600s, Farming 3, 3 / 4). Each seed costs 2 Energy to sow, yields one own harvest, 2 base XP and 10 first-harvest XP; ordinary level-difference and daily XP rules remain.

The plot adapter reuses the fixed-duration quick-crop path, while ordinary crop lookups still cannot see these entries. Sprinklers/greenhouses retain the teaching-radish auto-water behavior without shortening the fixed duration, including a newly placed facility. Fertilizer refuses before the ordinary crop dereference; Seed Saver, generic/explicit crop requests, resident sow and harvest counters exclude the series. Cooking, gifts, Compost, regional barter and non-Stall buyback remain unavailable. Existing q(217) Quick Radish retains its own seed, harvest and behavior.

Seed catalogs include the five unlimited Stall offers with their Farming gates and seed exception to the wallet floor. Only the Homestead Stall buys the harvest at its listed price. Bag stacking remains the ordinary crop stack rule. The server view adds `fast_crops[]` with the content fields, names and prices; plots keep `state/crop/ready_in`. Ingredient and ordinary crop lists exclude the new series. The client handles model/icons, Today counting/plurals and notification exclusions separately.

Homestead levels in `p0_content.json` now carry `energy: 40` at Lv2–4, `energy: "full"` at Lv5–10. Lv2/3/4 prices are 40/80/300; skills totals 3/4/6, with approved material lists; Lv5 skill sum is 8 and all later gates remain unchanged. Actual Energy gain is clamped to the new cap, never reducing an existing bonus-zone value. The existing `{kind:"homestead", energy:N}` field stays the actual gain, including zero; `view.homestead.next.energy` remains the new maximum, not the reward. Missing energy in older custom content retains the old full-refill fallback.

No save-version change. Current levels, upgrade history and historical spending are retained; no downgrade, refund or automatic upgrade on read. An eligible old Lv1 account may explicitly buy Lv2 and Lv3 in succession and receives each actual reward once. Command sequence checks continue to reject duplicate settlement.

## Validation

- TypeScript `npx tsc --noEmit`: passed.
- Server `npx vitest run`: **1636 passed / 115 skipped**, 162 passed files / 5 skipped. Existing optional PostgreSQL/external-service cases remain skipped; no server failures. The P0 tests do not require those external services.
- 26 new cases cover all five seed-to-sale loops, farming gates and atomic refusals, fixed times with facilities, fertilizer rejection, stack/full-bag behavior, XP discount/firsts, Seed Saver, generic and explicit requests, all sow-request residents, cooking/gift/Compost/barter exclusions, old save roundtrip, all Energy cap branches and content override behavior.
- A real localhost HTTP test buys, sows, waters, stops/restarts the JSON-backed store, preserves the growing plot and remaining time, harvests/sells, then upgrades. Repeated harvest and upgrade commands are rejected without paying twice. The test server binds an ephemeral port and closes in finally; only its temporary fixture directory is removed.
- Existing Homestead/material/garden tests were updated for the approved gate/energy numbers. Content uniqueness now includes the new crop/seed IDs. Shared content outside the Homestead level rows remains byte-equivalent in parsed structure; Lv6–10 gates are unchanged.
- Client `tests/p0 + tests/ui_kit`: **1911/1911 passed**, 0 gdUnit errors/failures/skips/orphans, exit 0 (`report_472`, 3m 19.454s). Initial scans were blocked by stale local caches after the farm-dev update (new P0Notify/Blackjack classes and casino textures). Cache entries/assets were reused only after matching source bytes and import configuration; no `--import` or `--editor` was run. No client source changes are included.

This PR has no new rendered UI. Its review evidence is the server/test report and shared wire contract on [SGODOT-354](https://plane.sensenjoy.cn/zili/browse/SGODOT-354/); paired client screenshots and countdown/upgrade presentation belong to Liu Bang's implementation. No physical device, production data, deployment or migration was used. Review: Zhou Yu; merge/release: the director.

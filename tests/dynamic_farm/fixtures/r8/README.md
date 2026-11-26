# r8 parcel fixtures (C-193)

Unmodified schema-4 farm payloads from the pinned read-only r8 dataset
(`modules/dynamic_farm/map/config.json`: `sf-dynamic-farm-20261125-r8`, full manifest
SHA-256 `ce232c99…28e9`), fetched from `/farms/<block_id>.json`; each file's SHA-256
equals that manifest's entry.

They are the two narrowest claimable parcels of the r8 starter zone found by the C-193
statistic (C-193#4): `p-0147008` (core 8 cells wide) and `p-0078042` (the one where the
greedy cottage → coop → barn → pen 8×6 pass placed only three). `test_building_fit.gd`
asserts that each, yard cleared, holds the coop, the barn (8×6 draft) and a pen up to 9×7.

`SHA256SUMS` pins the bytes; `test_building_fit.gd` fails if a file changed. These files
are read only by that test, not passed to the other tests (which take `fixtures/r4/`).
Replace them only from a pinned dataset, after rerunning the statistic
(`docs/plans/C-193.md`).

# r4 parcel fixtures (C-62)

Unmodified schema-4 farm payloads from the pinned read-only r4 dataset
(`modules/dynamic_farm/map/config.json`: `sf-dynamic-farm-20261118-r4`, client
manifest SHA-256 `645df353…ae1cf`), fetched on 2026-11-23 from `/farms/<block_id>.json`.
They are the parcels the dynamic-farm reviews already use: `p-3139010`, `p-3139019`
and `p-5402049` (C-18/C-20 review set, `BEFORE_REACHABLE` in test_outer_groves.gd) and
`p-4591A011*` (edge-decor sample with `sample_caps`, rock/flower probe).

`p-5402049` is r4 only: r8 (the current release) and r6 have no such parcel, so no
home is entered on it. Its core is a 267×3 strip, too narrow for the coop, the barn or
the sheep pen; tests keep it that way as a control (C-193), it is not a parcel to fix.

`p-4591A011-star.json` holds block `p-4591A011*`; only the file name drops the `*`.
The tests read the block ID from the payload, never from the file name.

`SHA256SUMS` pins the bytes; `tools/ci/dynamic_farm_tests.sh` refuses to run if a file
changed. Replace the set only together with the tests' audited numbers, and only from
the pinned dataset. CI never contacts the dataset service.

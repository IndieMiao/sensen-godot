# Big-yard parcel fixture (C-253)

Unmodified schema-4 farm payload from the pinned read-only r8 dataset
(`modules/dynamic_farm/map/config.json`: `sf-dynamic-farm-20261125-r8`, full manifest
SHA-256 `ce232c99…28e9`), fetched on 2026-11-28 from `/farms/p-0178001.json`; its SHA-256
equals that manifest's entry.

`p-0178001` is 711 PACIFIC AVE, the starter-zone "big yard" (4081 core cells) of the
C-190 0.4.6 full recording (C-190#94). Around its spawn the yard is crowded with rocks and
weeds, so the nearest ready coop / sheep pen spot is about 60 cells away, at (79,56).
`test_start_spot.gd` asserts that the placement preview starts near the player instead.

`SHA256SUMS` pins the bytes; `test_start_spot.gd` fails if the file changed. This file is
read only by that test, not passed to the other tests (which take `fixtures/r4/`).

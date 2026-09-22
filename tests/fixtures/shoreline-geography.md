# Recorded Silver Lake shoreline regression

These files contain recorded geographic data, not synthetic terrain:

- `shore_osm_geography.json`: five normalized OpenStreetMap features fetched on 2026-09-21. © OpenStreetMap contributors; ODbL 1.0.
- `shore_land_cover.json`: the recorded ESA WorldCover raster sample used to supply land-cover evidence where OSM has no land-use polygon. ESA WorldCover 10m 2021 v200, tile N33W120, CC BY 4.0. Attribution: ESA WorldCover 2021 v200 (Zanaga et al., 2022; DOI:10.5281/zenodo.7254221).
- `generated_shoreline_farm_terrain.json`: the exact generated response saved as `output/farm-generation-error-2026-09-21/geography/exact-west-reservoir-fixed-terrain.json`. It uses both sources, the 40×40 / 800 mm generation, and a 160 m real geographic extent. The original terrain checksum is `60c376d6bd1207be96537ea361a5975b37c81ef5378c3fabbaa9693a88586513`.

The replay center is 34.09875, -118.26627 near the west side of Silver Lake Reservoir, Los Angeles. It was recovered from the native map's five-decimal camera cache; do not claim it is a recovered six-decimal request body. The fixture is an exact copy of the recorded generated response at that replay center. It contains no account credentials, farm ownership or player save.

The regression checks that supplemental land-cover evidence makes this real land selectable while preserving the mapped reservoir, keeping the house, mine and separate fishing pond on reachable dry ground, and omitting outer decorative stone/bush clusters where the boundary opens onto water. Existing owner terrain remains immutable; the fixture is for tests, not a fallback map or permission to relocate a user.

Native `recorded-shore-owner.png` and `recorded-shore-visitor.png` captures under the same output directory use a test-only overview camera to inspect the whole shoreline. They do not change or demonstrate the default player camera distance.

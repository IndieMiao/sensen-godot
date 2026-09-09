# Partner APK Connectivity Repair

Verified 2026-09-08 at 15:08 China time.

## Incident

The partner APK displayed the Mapbox map but remained at "Connect to save your
farm". Its configured public endpoint `/preview/journey/v1/healthz` returned
404: the matching preview server had been packaged but not deployed. The map
loads independently of the gameplay API. This was a delivery gap.

The existing APK now connects without reinstalling or clearing its installation
identity. Fully close and reopen the application to retry login.

## Deployment

- APK package: `com.sensen.journeypreview`, version `0.2.0-preview.20260908`.
- APK SHA-256: `ceed517ccc02a702d6c1e6f0981f76f23c7d75a3beb4fb507a3621d3fb6e6a3d`.
- Preview URL: `https://farm.sensenjoy.cn/preview/journey/v1`.
- Preview revision: `partner-preview-20260908-eb25f02d-proxy1`.
- Preview domain: `5`; content: `0e9d1a28c3f4013e`.
- Frozen archive SHA-256: `eb25f02d15cb396565c0c1452b216b923ac76d4489be23f79973f447eaab64fe`.
- Patched archive SHA-256: `0d0924df71892e112b1f94ee5c067683e471aac66b8317cc62f173024d45320f`.
- Pinned image: `sha256:d1b68a0fdbc7acbe85c6a5261250da5c4480318857b1e3ea6bb49399cb801c82`.
- Host directory: `/opt/farm/journey-preview`.
- Compose project: `sensen-journey-preview`.
- Services: `journey-app`, `journey-db`; dedicated persistent preview DB volume.
- Preview app port is private. Only Caddy publishes HTTPS.

All 14 content JSON files in the frozen source were compared with the files
inside the APK and matched. Current workspace gameplay is newer; it was not
deployed over this frozen preview or the original database.

The server now optionally accepts `TRUSTED_PROXIES`, defaulting to no forwarded
IP trust. The preview trusts its private proxy network `172.18.0.0/16`. Without
this, every player behind Caddy shared one ten-logins-per-hour quota. Tests
verify separate quotas and reject spoofed forwarded addresses. The public
gateway also ignores incoming forged forwarding headers.

Caddy explicitly routes the original service to `farm-app-1:3000` and the
preview prefix to `journey-preview:3000`. Preview service names are unique to
avoid Docker's implicit `app` and `postgres` aliases on the shared network.
The original service remains revision `46410e6`, domain `1`, content
`661c466ed9b3c16a`; its app and DB containers were not restarted or migrated.

During deployment, source permissions caused one failed app replacement; the
script automatically restored the previous working image. Archive extraction
now preserves file permissions. A routing check also caught ambiguous default
service aliases before final acceptance; explicit routes and unique names
resolved it. Five consecutive paired public health checks passed afterward.

## Evidence

Artifacts: `output/partner-connectivity-fix-2026-09-08/`.

| Check | Result |
| --- | --- |
| Installed emulator APK hash | Exact match to partner APK |
| Original APK, public HTTPS | Login succeeds; Place Farm enabled |
| Ordinary farm creation | Los Angeles and Shanghai; journey version 1 |
| New Shanghai identity | NO_FARM, create 201, identical create replay 200, saved owner read 200 |
| Public farming | Clear, till, sow three radishes, care: version 0 to 4 |
| Natural crop growth | Three real minutes; no QA time commands or acceleration |
| Harvest | Version 5, three radishes added |
| Service replacement and relogin | Same farm, version, inventory and full state |
| Nearby API | Two visible Shanghai farms returned |
| Emulator restart | Saved farm, avatar and journey entries visible on map |
| Current emulator process crash buffer | Empty |
| Server tests | 334 passed, 53 DB-dependent cases skipped; typecheck passed |
| Proxy regression tests | Four passed, including spoofed-header cases |

Final saved-state canonical SHA-256:
`2f3ceb11602f8dd92ebe22fdf5f014980e78e66bfdcc54e8a368d111906ae89f`.

Reports: `public-readiness.json`, `smoke-plant.json`, `smoke-harvest.json`,
`smoke-verify.json`, `smoke-relogin.json`. Screenshots include
`emulator-map-connected.png` and `emulator-saved-farm-map.png`.
Early plant/harvest hashes used plain JSON serialization; final verify/relogin
hashes sort object keys. All state comparisons use structural deep equality.

Credentials and emulator installation backup are only in the ignored private
artifact directory. Server secrets were generated separately with mode 600.

## Limits

The ordinary APK has no Godot observer and its controls are not exposed in the
native UI tree. City selection used keyboard navigation. Farming was exercised
through the real public API using the emulator's own preserved test identity;
the APK then loaded that saved farm. This run does not claim full touchscreen
coverage of farm placement, the 3D farm, or all gameplay.

The Android 37 emulator still displays the previously recorded 16 KB native
library compatibility warning; it runs in compatibility mode. This connectivity
repair does not update the APK's native libraries or include newer workspace
gameplay/device changes. Validation occurred on our emulator and public API,
not on the partner's phone.

## Deployment Files

The deployed `compose.yml`, `Caddyfile.preview`, source archive, deployment logs
and scripts are in the artifact directory. Old proposed files in the partner
APK directory are superseded. Caddy configuration backups and the previous
working image remain on the server for rollback. Avoid deleting the preview
database volume or changing its token pepper, which would invalidate saves or
installation identities.

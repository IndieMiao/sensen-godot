# Farm Art Public Preview Release

Published 2026-09-10 at 15:04 China time, after explicit user authorization.

## Public Downloads

- Partner APK: https://farm.sensenjoy.cn/downloads/2026-09-10/sensen-journey-farm-2026-09-10.apk
- Workshop0909 APK: https://farm.sensenjoy.cn/downloads/2026-09-10/sensen-workshop-online-2026-09-10.apk
- Checksums: https://farm.sensenjoy.cn/downloads/2026-09-10/SHA256SUMS
- Release metadata: https://farm.sensenjoy.cn/downloads/2026-09-10/release.json
- Gameplay API: https://farm.sensenjoy.cn/preview/journey/v1

Both APKs contain the accepted farm art, including 24 Blender meshes, seven
house styles, meadow/soil/path materials, scenery batching, fitted camera clips
and directional shadows. Both use the normal city-selection entry and public
HTTPS endpoint. Neither includes the QA bootstrap, observer, QA feature flag or
local-server command-line arguments. No USB forwarding or computer service is
needed by these packages.

Version: `0.2.0-farm-online.20260910`, code `2026091002`. ARM64, minimum Android
SDK 29, target SDK 36, approximately 127 MiB per APK. Both retain the existing
Android debug signing certificate for preview upgrade compatibility; this is
direct APK distribution, not a Play Store release.

| Variant | Android package | SHA-256 |
| --- | --- | --- |
| Partner | `com.sensen.journeypreview` | `829449c6fd6e4b6ff82915c21414245b0709650a079f385cb7f68fae8972f8cf` |
| Workshop | `com.sensen.workshoppreview0909` | `02c72088332dc3bc43e86e4b07a068389338929c2056c6b6ea905c5c8aae279f` |

Install over the corresponding existing app to retain its installation identity.
The partner package preserves the September 8 public preview account. Workshop
now uses that public service; its local port-3134 database remains separate.
The earlier `com.sensen.avatarphase1` APK and its `/v1` server were not promoted
as this release. The previous phone APKs still require their local/USB setup
until updated to the appropriate public package.

## Server And Migration

- Revision: `farm-online-20260910-def104c-832c7bfc`.
- Source: current server/content at Git `def104c`, frozen with `git archive`.
- Source archive SHA-256: `832c7bfc3485da45391caba1722c0d0ffaa8504ec1f8fa334fe2776b7caa681c`.
- Image: `sha256:9b8e6cbeeb3d0d0b47da11ef63a72ed5619eed6b6595481e7701a2b505bd969d`.
- Domain: `5` to `13`; content: `0e9d1a28c3f4013e` to `12ded62adf3304d1`; schema: `1`.
- Existing preview project: `/opt/farm/journey-preview`.
- Release artifacts: `/opt/farm/journey-preview/releases/farm-20260910-def104c`.

The official domain migration was rehearsed against a restored database backup.
All seven existing farm rows were eligible; none were blocked. Full row
fingerprints before/after matched for farms (excluding only domain/content
version columns), players, tokens, commands, farm creations and snapshots.
The rehearsal also verified a preserved test account's farm read, ordinary
command, idempotent replay, re-login and QA-command denial.

Live traffic to the preview was briefly gated with HTTP 503. The old writer was
stopped, a fresh database dump taken, then the migration and row-fingerprint
comparison repeated. Traffic reopened only after the new ordinary server passed
its internal health check and read the preserved farm. The interruption was
12 seconds, 07:04:05 to 07:04:17 UTC. Database credentials and token pepper were
preserved. The separate original `/v1` remains `46410e6`, domain `1`.

Private backups include `private/pre-switch.dump`, `previous.env`,
`previous-compose.yml`, `previous-Caddyfile` and `previous-image.txt` in the
remote release directory. Do not publish these files. The deployment script's
automatic rollback applies only before public traffic reopens. Any later
database rollback must first preserve new writes.

APK downloads are served by Caddy from the existing persistent
`farm_caddy_data` volume at `/data/sensen-downloads/2026-09-10`. Only the two
APKs, checksums and public metadata were placed there. Directory listing is off.
The isolated rehearsal container and database were removed after validation;
backups and reports remain.

## Verification

- 482 server tests across 36 files passed, including database tests in an
  isolated test database. Workspace typecheck passed.
- Both extracted APKs passed loading of all 24 meshes and seven initialized
  farm styles, material/texture checks, camera/light settings and public-entry
  checks. Their 14 content JSON files match the frozen server source exactly.
- Both APK signatures passed verification and retain the original certificate.
- Both APKs were downloaded completely through the public HTTPS URLs and were
  byte-for-byte identical to the tested local packages. SHA-256 matched the
  published checksums. Caddy returns the Android APK MIME type and supports
  ranged downloads. The verification downloads needed resume because of the
  slow connection; each package is about 127 MiB.
- On `emulator-5560`, the partner app's complete files backup was identical
  before/after update. Workshop installation key and city/farm choices also
  matched exactly. No app data was cleared.
- Public old-account read, ordinary command, replay and re-login passed.
  The original farm remained available after migration.
- A test farm created through the real public API using the Workshop emulator's
  own identity passed creation replay, resource collection, request tracking,
  clear/till/sow/care, natural three-minute growth, harvest and state readback.
  Replayed commands did not duplicate rewards. No QA grants or time changes.
- The partner app cold-launched, connected and showed its saved Los Angeles
  farm and journey locations on the native map. No script, shader or fatal
  errors appeared in its process log.
- Workshop cold-launched through the normal city selector and loaded its
  public Shanghai farm, remaining timber and tracked lettuce request on the
  native map. Its process log also had no script, shader or fatal errors.
- Final container status was healthy with zero restarts. Full farming state
  after harvest was still identical when read again after the app launched.

Local evidence and deployment scripts: `output/farm-public-2026-09-10/`.
The `private/` subdirectory is not public and contains installation credentials
and before/after app backups. Farm art rendering and touch checks from the
integration run remain documented in `docs/design/farm-art-2026-09-10/integration.md`.

The physical V2509A was disconnected during public-release verification, so its
previous USB APK was not updated in this release run. Android verification used
the emulator. Native Godot map buttons are absent from the Android UI tree;
this run does not claim complete touchscreen coverage. The previously observed
16 KB native-library compatibility limitation is unchanged.

## Rebuild

Use `tools/dev/prepare_farm_app_export.gd` with `--farm-app-partner` or
`--farm-app-public-workshop`, import the respective staging project, then export
the `Android Farm App` preset with the existing Android toolchain. Staging
directories are `output/farm-app-2026-09-10/partner-project` and
`output/farm-app-2026-09-10/public-workshop-project`.

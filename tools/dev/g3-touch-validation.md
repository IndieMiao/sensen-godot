# G3 Android Touch Validation

The optional `--week-touch=true` mode runs the seven-day ledger through Android input.
Godot measures live controls with the viewport screen transform multiplied by the
control's global canvas transform, including viewport stretch, and projects plots
with the active camera, and submits one checkpoint at a time. The host worker runs
`adb -s SERIAL shell input swipe`, acknowledges once, and Godot waits up to two
seconds after acknowledgement for a matching `InputEventScreenTouch` before
continuing. A tap is one same-coordinate swipe held for 80ms; scrolling and long
presses retain their requested duration. Plot actions also verify the resulting
HTTP command and original blueprint cell ID.

Decoration menus use only public PopupMenu geometry and theme APIs. Each row's
height includes its shaped text and check/radio indicator plus the active theme's
vertical separation. Panel content margins and supported shadow margins determine
the content origin; `get_screen_transform()` converts its row center to Android
coordinates. The driver requires six uniform single-line items, matching natural
and visible menu heights, and the entire menu within the root viewport before
using this calculation. Clipped or scrolling menus fail with recorded geometry;
the driver never searches for engine-internal menu controls.

Row tools can issue one command per cell in the touched row. The plot assertion
checks the entire newly issued command group: every command must succeed with the
requested type, and the group must include the touched source cell.

Normal controls open the map's farm, locations and visitor farm, switch tabs, scroll
content, pick decorations, close sheets, and save the group photo. Director settings
use a real title long press and actual option buttons. Touch mode keeps
`Engine.time_scale=1`; only explicit QA clock/day commands accelerate game time.
The touch driver deadline is 60 minutes. The original callback mode remains the default.

Place Back respects each panel's navigation hierarchy. In particular,
`EventsPanel.consume_back()` first returns from story text to event detail, then
from event detail to the story list; only the next Back exits the place. The driver
allows at most four layers and records each before/after view or scene. It stops
immediately if a press does not change that state, rather than tapping again.

After saving the six courtyard pieces, newly exported touch runs also select a
placed piece in the world, tap a legal new position, use one available direction
control, undo that adjustment, and cancel back to the saved arrangement. Positions
come from the live camera and viewport transforms; targets avoid the content panel
and projected resident meshes. A placement tap stays within the destination grid
cell while clearing the previous pieces' selection radius. These checks change
only the preview and verify that no gameplay command or state version changed.
They validate tapping and direction controls, not dragging.

This coverage was added after `g3_vivo_tool_life_03` was exported. That run and
earlier reports must not be counted as evidence for these world interactions.

## Preparation

Restart `server/tools/g3_qa_server.ts` to register the queue. This service binds
`127.0.0.1` and uses the dedicated G3 QA database. The touch routes are not installed
in the production server. This worker never installs, exports, starts or stops an app,
and does not change port forwarding.

Use a new run ID for every launch. Before exporting the temporary `Android G3 QA`
preset, pass these extra arguments to `prepare_g3_device_export.gd`:

```text
--g3-device-export=prepare
--week-path=tool
--week-style=life
--week-touch=true
--week-run=g3_phone_tool_life_01
--week-base=http://127.0.0.1:3103/v1
--week-out=user://g3-week-device-tool-life
--g3-device-apk=build/sensen-g3-touch-tool-life.apk
```

The Android `127.0.0.1` endpoint requires the operator's existing ADB reverse to the
host QA port. For an emulator without reverse, `http://10.0.2.2:3103/v1` is supported.
Restore the export preset with `--g3-device-export=restore` after export. Preparation
and restoration retain the existing byte-for-byte backup checks. The driver backs up
and restores farm, installation, city and UI preference files for normal completion;
the operator must retain an external backup for force-stop/crash recovery.

Touch QA exports retain that run's anonymous account key in the app-private file
`user://g3_qa_accounts/<run_id>.txt`. During the run the same key is temporarily
written to `ApiClient.INSTALL_KEY_PATH`, so command-journal scopes use the actual QA
identity. The original installation file is restored on completion. Reusing an
existing account filename is refused; use a new run ID.

For persistence and cooking-failure checks with the normal APK, the main validation
agent may retrieve this private account file and temporarily use its contents as
the normal APK's installation key while preserving the original key. Archive the
retrieved file only in this run's private backup directory. Never include the key in
console output, screenshots, command transcripts, public reports or shared artifacts.
Normal callback mode does not create these account files.

Start the worker before launching the installed QA APK:

```sh
node tools/dev/g3_touch_worker.mjs \
  --serial=PHONE_SERIAL \
  --run=g3_phone_tool_life_01 \
  --base=http://127.0.0.1:3103/v1 \
  --out=output/g3-week/touch-host-tool-life
```

Use `--week-path=field` and/or `--week-style=sell` for other routes, with a new run ID
and output directory. The host `--base` always points to a loopback QA service.

## Restricted Continuation

`--week-resume=g3_vivo_tool_life_03` supports that known D5 row-tool assertion
failure; `--week-resume=g3_vivo_tool_life_04` supports its known follow-on navigation
assertion failure. These are not general save loaders. Pass either to the export helper alongside
`--week-path=tool --week-style=life --week-touch=true`, a new `--week-run`, a new
`--week-out`, and `--week-base=http://127.0.0.1:3103/v1`.

The device must retain `user://g3-vivo-tool-life-03/report.json` and the parent run's
private account file. The driver checks the single known error, touch 623, the 96
completed steps, and the three successful shelter commands at versions 270-272.
It copies the existing account identity into the new run's private account file,
logs in, and reads the existing farm. It refuses a different farm/version/day or
plot state, an altered ledger prefix, any pending command replay before validation,
or a continuation step other than the expected boundary.

Execution starts at ledger index 96. Already cared-for plots are skipped; earlier
purchases, sales and other completed steps are not replayed. The existing QA clock
is retained without another initial clock command. `steps` and `chapters` contain
only this segment's new evidence. Reports record `resumed_from`, the parent report
path/hash, inherited chapter records, completed prefix size and skipped care cells.
`continuous_seven_day_run=false` and the explicit product bypass distinguish a
validated continuation from one uninterrupted seven-day touch run. The failed
parent report remains a failed report and must be retained with the continuation.

For run 04 continuation, both device reports must remain available at their original
`user://g3-vivo-tool-life-03/report.json` and `user://g3-vivo-tool-life-04/report.json`
paths. The driver verifies run 04's recorded parent hash against the original run
03 bytes, checks its sole navigation error and acknowledged Back touch 14, and
requires exactly one new completed step (`ledger_index=96`) and the six remaining
shelter commands at versions 273-278. The combined completed prefix is 97 steps;
the existing farm must still be at D5, version 278, with all nine plots cared for.

That continuation starts with the normal D5 boundary capture and rereads the wind
story, then advances one QA day before ledger index 97's D6 harvest. It does not
rerun the old care step or inherit the old story-read counter. `resume.chain`
records both failed parent reports, hashes, segment/prefix step counts and command
versions. Inherited chapter records remain separate from newly captured chapters.
Both parent report directories are protected from use as the new output directory.

## Evidence

- Device `report.json` contains HTTP state, chapter facts, actions, screen coordinates,
  received touch events, observation wait times, and explicitly listed setup bypasses. Anonymous account/farm
  creation is setup; it is not claimed as a touch-tested onboarding flow.
- A failed device run saves `failure.png` before restoring preferences and publishing
  its report, which records the saved screenshot path.
- `place_back_transitions` records the active view/scene before and after each
  bounded Back action, including the checkpoint that delivered it.
- `popup_geometry` records menu and window dimensions, margins, font/check heights,
  vertical separation, calculated row height, clipping checks, exact target and
  selection result for each decoration picker. Earlier run 05 failed while looking
  for an internal layout node and does not establish successful picker selection.
- New device reports contain `decoration_world_interactions` with its revision,
  attempted/passed flags, checkpoint range and before/moved/adjusted/after layouts.
  A successful check also captures `courtyard-world-move.png` and
  `courtyard-world-cancel.png`. Only a report with `passed=true` in that object
  establishes completion of these additional controls.
- Host `device.json` records the selected ADB serial, transport, model, hardware,
  fingerprint, `ro.kernel.qemu`, `ro.boot.qemu`, display size and capture time.
- Host `report.json` merges device classification and actual ADB actions into the
  final result. `platform=Android` alone never means physical hardware. Unknown
  transport evidence remains `device_kind=unverified` and `physical_device=false`.
- Host `host.json` is updated after each action, including actual `adb_args` and failures. Missing or failed
  acknowledgements cannot produce a passing merged report. An acknowledgement may
  be retried; Android input itself is never automatically repeated.

The queue and worker tests use in-process HTTP and pure functions; they do not prove
Android layout, input delivery, performance, or physical-device completion.

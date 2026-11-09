# SGODOT-449 Steam candidate

Scope: Steam particle parameters, billboard material and one128²RGBA soft-edge image. Pot/soup meshes, both animation blocks and `steam_lid_clearance.gd` stay unchanged; the shader retains the exact original `above_lid` expression.

Reproduction (all engine commands hold the shared render lock):

```bash
python3 tools/art/source/steam_449/make_texture.py
python3 tools/art/source/steam_449/prepare.py --out <isolated-output>
flock ~/gs66-render.lock godot --headless --path <isolated-output>/project --editor --import
STEAM_REVIEW=<capture-output> STEAM_HDR=1 STEAM_HDR_LINEAR_FIX=1 flock ~/gs66-render.lock godot --path <isolated-output>/project --rendering-method mobile --rendering-driver vulkan --fixed-fps 30 --disable-vsync
```

The temporary host comes from the pinned farm-dev revision in reference/base.json. It is copied into the isolated project, with only BOX enlarged to200×220 at80,110. Diagnostic environment options demonstrate the host alpha-composition issue: STEAM_HDR, STEAM_PREMUL, STEAM_HDR_LINEAR_FIX. They change only the review fixture; no host/runtime code is delivered. `STEAM_SINGLE=1` isolates a puff for diameter measurements; leave it unset for the production3-puff stream. The parent preview supplies43°/500px/m, the native warm light and cream/white background controls. Source shader logical frame coordinates track the whole layer when Queue moves it down14px.

Earlier isolated diagnostics are retained for the alpha-composition comparison; they no longer certify final sizes. The current validation entry point and the native delivery are below.

## Native delivery v1.1

Native captures now use programmer branch feat/449-steam-box at5d50bf0c with the supplied cookreal save and shoot449.sh. The real camera is33°, not the earlier43° fixture: emitter localY=.150, velocity=.098m/s, growth1→1.52. The pot/animations/mask/texture are unchanged from the candidate.

`prepare_native.py --out <out> --fixture <cookreal.base.json> --shot-script <shoot449.sh> [--cache <verified-cache>]` stages the pinned runtime/server and this prop. Install the local server dependencies with `pnpm --dir <out>/project --filter farm-server... install --frozen-lockfile`. Import under the shared render lock. The supplied fixture remains outside the repository; the run uses a copy and private client userdata.

Source the normal gs66 environment, then run the supplied shoot script with `REPO=<out>/project`, `GODOT=<absolute-path-to-native_godot.sh>`, `STEAM_TEST_BASE=<fixture>`, `STEAM_LIVE_OUTPUT=<capture-dir>`, `STEAM_OBSERVER_QUIT=1`, `STEAM_REALTIME=1`. Steps are `wait:2,farmhouse,wait:2,cook:dish_grilled_crucian,wait:4.2` for recording (the still path ends inwait:1.2). The wrapper omits fixed simulation FPS for recording and caps real rendering at30Hz, so server/client clocks and particle motion share real time. Buffer images during the3s capture; compress/write them afterwards. Local port3147 must be free; stop only the server PID created by shoot449.sh.

The observer keeps the primary view unchanged, and uses a second transparent viewport sharing `host.view.find_world_3d()` and exactly the native camera to read onlySteam render layer19. This avoids accidentally counting opaque pot MSAA alpha as steam. It records all pixels asRGBA16F, without a spatial crop hiding failures. A separate `STEAM_NATIVE_SINGLE=1` control measures one puff's life; never use that control's image as the official3-puff view.

`analyze_native.py <capture-dir>` handles the ordinary or single-puff control. Then `verify.py --out <out> --live <common-dir> --single <single-dir>` checks immutable art/animations/mask plus those actual native results. Encode by the recordedwall_ms timestamps, trimming3.000s and resampling to30fps; no speed-up. Final delivery isdocs/design/steam-449-2026-11-09/native_v1.1. The older isolated images remain historical diagnostics.

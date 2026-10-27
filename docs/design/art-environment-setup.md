# Fresh environment setup for art agents

Prepare the execution environment and service access before following the [mobile 3D asset workflow](mobile-3d-asset-workflow.md). This guide includes the setup that preceded the user-accepted [Basic Room](basic-room-2026-10-06/README.md), including the Windows-browser/remote-Linux authorization problems encountered in that session.

Commands below target a **Linux x86_64 execution host**. In the tested arrangement, Herdr ran remotely on Linux while the human opened authorization links on Windows. For another OS or architecture, use matching binaries, SDK paths and display tooling. The credentials belong to the execution environment; a browser login on the client machine does not by itself configure the remote agent.

The room was built with Blender 5.2, Godot 4.7.2, JDK 21 and an Android API 35 x86_64 emulator. Figma authorization succeeded with Codex CLI 0.160.0; the MCP command syntax was rechecked with 0.160.1. Lark commands and installation artifacts were checked against CLI 1.0.97 on 2026-10-06. These are reproducible case versions, not claims that every future environment should use the same versions or workarounds.

## 1. Establish where commands, files and browsers run

Before installing or authenticating, record the executor OS/architecture, repository path, active branch, available tools and user-data locations. Reuse an already working installation or connection. Historical QA notes can describe another workstation or a previous installation.

```sh
pwd
uname -sm
git status --short
git branch --show-current
command -v git gh codex lark-cli blender godot python3 ffmpeg ffprobe
```

For a new workspace that is not yet a clone, the Git checks come after section 2. Confirm enough disk space for export templates, SDK images and caches. On Linux, check `/dev/kvm` availability and the current user's read/write access before relying on accelerated Android virtualization.

The task environment needs writes to the repository and relevant user configuration directories, HTTPS access to the required services, and a local loopback connection for OAuth callbacks. Check the actual runtime permission profile. `approval_policy=never` means no approval prompt; it does **not** establish unrestricted filesystem or network access. This case changed into a restricted mode mid-login, producing `Operation not permitted` and an unavailable login process. Restore the required permitted capabilities through the host's supported settings before starting another authorization flow; do not work around sandbox restrictions with an unrelated process.

Keep the two sides of a remote session distinct:

| Operation | Host |
|---|---|
| Git checkout, Blender/Godot execution, SDK, APK export | Agent execution host |
| MCP configuration and CLI OAuth credential storage | Host running the agent/MCP client |
| Figma/Feishu human sign-in page | May be the Windows client browser |
| `http://127.0.0.1:PORT/callback` opened by that browser | **Windows loopback**, unless forwarded |
| Callback listener created by remote `codex mcp login` | **Remote host loopback** |

A Herdr SSH session does not automatically prove that an arbitrary OAuth callback port is forwarded. Decide how the callback reaches the correct host before issuing a short-lived login link.

## 2. Prepare repository access and commit identity

If the checkout already exists, inspect its remotes and worktree instead of cloning over it. Otherwise use the user's authorized GitHub account and an approved destination. One HTTPS setup route is:

```sh
gh auth login --web --git-protocol https
gh auth setup-git
gh repo clone IndieMiao/sensen-godot -- --branch farm-dev
cd sensen-godot
```

Human browser authorization is required when no suitable GitHub credential exists. A valid existing SSH setup is also usable; there is no reason to replace it solely to follow the example. Verify the connected account and repository access without printing tokens:

```sh
gh api user --jq '{login: .login, name: .name, id: .id}'
git remote -v
git fetch origin
git config --get user.name
git config --get user.email
```

GitHub authentication and Git author identity are separate. The first art commit on this machine failed with `Author identity unknown` even though fetch/push authentication worked. Set the intended, verified identity locally or with per-command `git -c user.name=... -c user.email=...`; do not invent an email or blindly copy another contributor. In the original session, the authenticated account and consistent repository history established the intended identity.

Read `AGENTS.md`, the current product/design indexes and the art workflow. Preserve unrelated worktree edits. Create the ignored staging area before generating nested projects:

```sh
mkdir -p output/art-setup
touch output/.gdignore
```

Configuration files, OAuth responses and SDK downloads are not art source files to commit. The setup guide contains public service addresses and placeholders, never the original account's credentials or one-time links.

## 3. Install and verify the local toolchain

Install only missing or incompatible components. Keep task shell variables in the same shell session, or pass their values explicitly when the agent's command tool starts a new shell for each call.

| Tool | Role and verification |
|---|---|
| Git and GitHub CLI | Checkout/push; verify remote access and author identity separately |
| Codex or another supported MCP client | Figma tool transport and OAuth; inspect that client's current setup instructions |
| Blender | Editable models and Python-driven export; verify background Python execution |
| Godot plus matching templates | Import, actual rendering and Android export; engine/template versions must agree |
| Python 3 and a virtual environment | Staging, image comparison and QA; install Pillow/NumPy for the Android harness |
| FFmpeg and FFprobe | Recording conversion, frame inspection and media metadata |
| JDK and Android SDK | `sdkmanager`, emulator, ADB, signing/build tools and touch-fixture compilation |
| Lark CLI | Optional delivery transport when authorized; application setup and user login are separate |

### Blender

Use a matching official Blender build or an approved package. The tested machine used the user Flatpak installation:

```sh
flatpak install --user flathub org.blender.Blender
flatpak run org.blender.Blender --background --factory-startup \
  --python-expr 'import bpy; print(bpy.app.version_string)'
```

Run installation only if needed, and confirm its version before rebuilding the case. The installed `blender` command may be a Flatpak wrapper rather than a native binary. Flatpak changed the working directory to `/app/blender`; a relative script path failed. Use an absolute path, for example `--python "$PWD/tools/art/build_basic_room.py"` from the repository root. This pipeline uses Blender's Python API directly and does not require a Blender MCP plugin.

### Godot and export templates

For the recorded Linux case, the official release assets are:

```sh
mkdir -p output/art-setup/godot
gh release download 4.7.2-stable --repo godotengine/godot-builds \
  --pattern 'Godot_v4.7.2-stable_linux.x86_64.zip' \
  --pattern 'Godot_v4.7.2-stable_export_templates.tpz' \
  --dir output/art-setup/godot
```

Extract the executable into a user-owned tool directory, make it executable and place it on `PATH`. Preserve an existing launcher. On this machine the directory was `~/.local/opt/godot-4.7.2/` and `~/.local/bin/godot` pointed to the executable.

Inspect the template archive before extracting. For this non-Gradle benchmark, `templates/android_debug.apk`, `templates/android_release.apk` and `templates/version.txt` were placed in `~/.local/share/godot/export_templates/4.7.2.stable/`. Other export workflows may need additional templates or Android source. A full game build with native plugins has different requirements; follow the repository's platform documentation for that task.

```sh
godot --version
ffmpeg -version
ffprobe -version
python3 -m venv output/art-setup/venv
output/art-setup/venv/bin/pip install pillow numpy
```

The Basic Room reproduction instructions create their own dated virtual environment; use the path actually created when invoking a harness.

### Android SDK and JDK

Install an appropriate JDK and Google's command-line tools into writable tool directories. Official sources are listed at the end of this guide. The recorded locations were `~/.local/opt/jdk-21` and `~/Android/Sdk`. Google command-line tools must have the layout `cmdline-tools/latest/bin/sdkmanager`, not an extra nested `cmdline-tools` directory.

Set and retain your actual paths, then inspect available packages:

```sh
export JAVA_HOME="$HOME/.local/opt/jdk-21"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
java -version
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --list
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses
```

Use these paths only if that is where you installed the tools. Finish the SDK license prompts as required by the installation environment. Packages used by the benchmark:

```sh
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
  'platform-tools' 'build-tools;36.0.0' 'platforms;android-36' \
  'emulator' 'system-images;android-35;default;x86_64'
```

The build platform and emulator API do not have to be identical. Check the live package list: an API 37 image named in an older workstation document was unavailable during this setup. Do not keep retrying an unavailable package name or report an untested image as validated. Wait for each download/extraction process to finish before the next dependent command.

Configure Godot's actual editor settings (using the editor UI or a targeted settings-file edit that preserves other settings):

```text
export/android/android_sdk_path = <actual SDK path>
export/android/java_sdk_path = <actual JDK path>
export/android/shutdown_adb_on_exit = false
```

The last setting prevents export from shutting down another task's ADB session. The Linux case used `~/.config/godot/editor_settings-4.7.tres`; discover the actual file for the installed version/OS rather than overwriting a guessed one.

Create a separate AVD if an appropriate isolated one does not exist:

```sh
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager" create avd \
  --name Sensen_BasicRoom_API35 \
  --package 'system-images;android-35;default;x86_64' --device pixel_5
```

Inspect existing AVDs/devices first. Do not use a force/overwrite option on an existing user's AVD. Reserve free emulator and ADB ports; the Basic Room wrapper uses ADB 5061 and its harness defaults to `emulator-5588`, so adapt them deliberately if occupied. The original console port produced an emulator range warning; prefer the emulator's recommended free range for a new configuration rather than assuming 5588 is a permanent reservation.

### A real display for rendered checks

Headless import is useful, but it does not validate the rendered image or visibility-dependent animation. Remote shells can lack `DISPLAY`/`XAUTHORITY` even when the same user has an active Linux desktop. Obtain the current display environment from that user's desktop session; inspect only the needed variables, not the entire environment or authentication-cookie contents. Where applicable:

```sh
systemctl --user show-environment | rg '^(DISPLAY|XAUTHORITY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR)='
```

The tested X11 session had `DISPLAY=:0` and a session-specific Xauthority file. That filename is intentionally not prescribed here. Use legitimate session access, not `xhost +`. For another OS use its native display/capture setup. Verify the actual renderer/device from Godot logs; a launch without an error is not a screenshot check.

If the executor has no usable graphics session, arrange a supported virtual display or an approved graphics-capable executor and record the backend used. Headless imports alone do not satisfy the visual review requirement.

## 4. Connect Figma and prove access to the reference

The official remote server is `https://mcp.figma.com/mcp`. It does not require the Figma desktop app on the execution host. Use a supported Figma MCP client/plugin; this session used Codex's manual MCP connection. Consult [OpenAI's MCP documentation](https://developers.openai.com/codex/mcp/) and the [Figma remote setup guide](https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/) for the installed client.

Use the agent host's managed Codex executable if one is already supplied. If Codex itself is missing, follow its [official CLI installation guide](https://developers.openai.com/codex/cli/). An agent using another supported client should use that client's Figma integration; the Codex configuration examples below are client-specific.

### Configure the client on the correct host

```sh
codex --version
codex mcp list
codex mcp add --help
codex mcp login --help
```

Reuse an existing enabled Figma connection. To add one with the CLI:

```sh
codex mcp add figma --url https://mcp.figma.com/mcp
```

This command can immediately start OAuth. If preparing a remote callback route first, add the following table to the **existing** user configuration instead, preserving the rest of the file:

```toml
[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
```

Codex's default user config is `~/.codex/config.toml`; a custom `CODEX_HOME` changes that location. Trusted project configuration can also affect the effective server settings. Do not overwrite unrelated model/provider settings or create a second table with the same name. OAuth-managed login does not require inventing a `FIGMA_OAUTH_TOKEN` environment variable or copying another machine's credential store.

### Complete OAuth with the user

Start the login when the user is ready:

```sh
codex mcp login figma
```

Keep that process and its listener alive. Present its current authorization URL to the user, who must use the Figma account that can access the design. Configuration can be performed by the agent; account sign-in/consent belongs to the user.

For a local browser on the same host, the loopback redirect normally reaches the listener directly. For a Windows browser with a remote Linux listener, choose one of these routes.

**Route A: local SSH forwarding.** In a Windows terminal, forward a chosen free loopback port using the same SSH target used for the remote session:

```powershell
ssh -N -L 127.0.0.1:45876:127.0.0.1:45876 YOUR_EXISTING_SSH_TARGET
```

Keep that terminal open. On the remote host, run:

```sh
codex -c mcp_oauth_callback_port=45876 mcp login figma
```

Confirm the generated redirect actually uses that port; a per-server callback-port setting can override the global setting. Open the newly generated authorization URL on Windows. OpenAI documents the fixed callback-port configuration; this forwarding route is provided for remote setup, while the case itself used Route B.

**Route B: relay the current callback to the remote listener.** This was the successful route in the Basic Room session:

1. Start normal `codex mcp login figma` remotely and retain the running process/session.
2. Give the user its fresh authorization URL.
3. The user authorizes in Windows. The redirected `http://127.0.0.1:PORT/callback?...` page can fail to load because it points to Windows.
4. Obtain the **complete** current callback address and promptly submit an HTTP GET to that same address **from the remote execution host**.
5. Verify the local endpoint and the login process both report completion. In the successful run they returned `Authentication complete` and `Successfully logged in to MCP server 'figma'`.

Treat the callback as a short-lived credential-bearing value. Keep its query string intact, including `code`, `state` and `iss`; do not manually splice codes between login attempts. Before relaying, validate that it is the loopback HTTP host, port and callback path of the login process you just started. Prefer passing it through protected input to the HTTP client rather than embedding it in a persistent script, command history or shared log. Do not forward an arbitrary user-provided URL as though it were a callback.

This route does not require disabling Figma's validation: Codex still validates the flow state/issuer and performs the token exchange. If the listener has timed out, the session disappeared or the environment's permissions changed, stabilize the execution environment and start a fresh flow. Reusing the old callback will not recover the original process.

The installed CLI also offers `--no-browser`. Two attempts with that mode returned `invalid_grant` in the original session; the cause was not established. Do not turn that observation into a claim that the option is universally broken or that Windows alone caused the exchange failure. Normal login plus loopback relay succeeded. Avoid sending a succession of new links without first fixing the route, listener lifetime or permission problem.

### Verify the tool and the actual file

```sh
codex mcp list
```

Look for the enabled Figma server with OAuth credentials, then confirm that the agent can actually call its tools. Some clients require an MCP refresh/reconnect or restart; this session exposed the tools after authorization. A config file alone is not proof that the current tool catalog is connected.

For the known Basic Room reference, use the MCP tool inputs below (tool names may have a client-specific prefix):

```json
{"fileKey":"5SVgfevrLzZXqD83uyPgmV","nodeId":"3:4550"}
```

Call `get_metadata` on that node, then `download_assets` to retrieve its rendered export, or `get_screenshot` for a preview. Download the returned temporary URL promptly and **view the image**. Preserve the export with the stable design URL and node identity. Do not commit signed asset URLs. Original image fills can differ from a composed node export; choose the representation that matches the reference the user sees.

For an unknown target, start with a page list or a scoped search rather than dumping the whole document into context. A full `0:1` dump was extremely large in this file. Follow the tool's skill prerequisites when using design-to-code or Figma JavaScript tools; image retrieval does not require editing the design.

An unauthenticated design-page HTTP 403 did not prevent authorized MCP access in this case. A plain GET to the MCP endpoint can return 405 because it is a protocol endpoint, not a webpage. For genuine file-permission or rate-limit failures, use Figma's `whoami` tool and check the connected account, file membership and current plan limits. Successful OAuth alone does not grant access to every file.

## 5. Install and authorize Lark CLI for review delivery

Use the delivery service the user authorized. The Basic Room user explicitly allowed Lark CLI as an alternative to Slack. This guide does not carry that delivery permission into another task or another recipient.

### Install the CLI if missing

The [official Lark CLI repository](https://github.com/larksuite/cli) documents the npm installation route:

```sh
npx @larksuite/cli@latest install
lark-cli --version
```

If Node/npm is absent, the official release also supplies standalone binaries. The checked Linux x86_64 example is:

```sh
mkdir -p output/art-setup/lark ~/.local/bin
gh release download v1.0.97 --repo larksuite/cli \
  --pattern 'lark-cli-1.0.97-linux-amd64.tar.gz' --pattern checksums.txt \
  --dir output/art-setup/lark
(cd output/art-setup/lark && sha256sum --ignore-missing --check checksums.txt)
tar -tzf output/art-setup/lark/lark-cli-1.0.97-linux-amd64.tar.gz
tar -xzf output/art-setup/lark/lark-cli-1.0.97-linux-amd64.tar.gz -C output/art-setup/lark
install -m 755 output/art-setup/lark/lark-cli ~/.local/bin/lark-cli
export PATH="$HOME/.local/bin:$PATH"
lark-cli --version
```

Select the matching release asset for other operating systems/architectures and check its published checksum. The inspected archive contains `lark-cli` at its root. Run this installation path for a fresh/missing CLI, not to silently replace another task's working binary.

Read the installed version's usage and embedded instructions:

```sh
lark-cli --help
lark-cli skills read lark-shared
lark-cli skills read lark-im
lark-cli profile list
lark-cli whoami
```

### Configure an application before user login

Lark needs an application configuration as well as user authorization. On the original machine, the `gensen` Feishu application profile already existed and its **bot** identity was ready; no user was logged in. A new machine may have neither. Do not assume `gensen` or any credential exists because it was used in the case.

Prefer an existing approved application/profile. Use `--profile` explicitly rather than switching or deleting other profiles. Confirm the correct brand: `feishu` for this case, or `lark` for the applicable international workspace.

If the operator supplies an existing approved App ID and secret, inspect the available setup command:

```sh
lark-cli profile add --help
lark-cli config init --help
```

`profile add --name ... --app-id ... --brand ... --app-secret-stdin` can add the configuration. Provide the secret through the CLI's protected stdin path from an approved secret source or a hidden operator prompt, not a literal command argument, chat transcript or committed file. Do not copy another agent's encrypted credential files/master key as a substitute for application provisioning.

If the user wants a new application and the environment allows that provisioning path:

```sh
lark-cli config init --new --name gensen --brand feishu
```

Keep the process running and show the returned setup URL and QR code to the user. The browser step creates/configures the application; it is separate from the user OAuth step below. A managed OpenClaw/Hermes/Lark-channel environment may require `config bind` instead. Read its current help and confirm the intended existing app/identity policy; do not force initialization to create an unwanted parallel application.

### Authorize the user with device flow

First inspect the chosen profile:

```sh
lark-cli auth status --profile gensen --json --verify
```

If the intended user is already verified and has the required scopes, reuse that authorization. `bot: ready` does not mean user access is ready. A `needs_refresh` label is also not by itself a reason to start a new login: let the CLI verify/refresh and inspect the server-verification result. This case successfully refreshed an existing user token without another browser approval.

For a missing user login, request the scopes needed for the authorized image/video review workflow:

```sh
lark-cli auth login --profile gensen \
  --scope 'im:message.send_as_user im:message im:resource im:chat:read' \
  --no-wait --json
```

Use the profile chosen for the task; `gensen` is the case's label. These four requested scopes worked for user-message delivery, resources and self-chat lookup. Existing grants can be broader or cumulative; the requested scope string does not prove other grants were revoked. Check the actual reported scope list. Avoid requesting every business domain merely to send review media.

The response includes `verification_url`, `device_code` and an expiry. For that **current flow**:

1. Preserve the verification URL exactly, without rebuilding or re-encoding its query.
2. Generate a PNG QR code with the CLI:

   ```sh
   lark-cli auth qrcode 'CURRENT_VERIFICATION_URL' --output output/art-setup/lark-auth.png
   ```

3. Present the URL first and display the QR image below it. Creating a file without showing it is not sufficient.
4. Let the user finish authorization. Use the agent host's visible interaction channel; if it only delivers final-turn output, yield with the link rather than blocking before the user can see it. Continue independent permitted setup/modeling when asynchronous interaction is available.
5. After the user confirms, the agent completes the **same** pending flow:

   ```sh
   lark-cli auth login --profile gensen --device-code 'CURRENT_DEVICE_CODE'
   lark-cli auth status --profile gensen --json --verify
   ```

Replace the uppercase placeholders with values from the current response. Do not reuse expired URLs/device codes or old QR images. The case returned a 600-second expiry and required a fresh link after the user had been away. Start the next flow when the user is ready instead of repeatedly generating expiring links.

This device flow works with a Windows browser and a remote Linux CLI without relaying a `127.0.0.1` callback. Do not copy the Figma callback procedure into Lark authentication.

Application permission configuration and user consent are separate layers. For missing **user** scopes, follow the reported missing scopes with incremental user authorization. For missing **bot/application** permissions, use the app's permission configuration; another user login does not fix a bot-only permission error. Follow the installed `lark-shared` guidance and preserve the task's authorized identity.

### Resolve the recipient and verify delivery

From verified auth status, obtain the current user's Open ID. For authorized self-review, resolve that user's own conversation rather than copying a chat ID from a previous task:

```sh
lark-cli im +chat-messages-list --profile gensen --as user \
  --user-id 'VERIFIED_CURRENT_USER_OPEN_ID' --page-size 1 --no-reactions
```

Check the returned conversation and identity. If no usable self-conversation can be resolved, clarify the target rather than substituting a colleague/group. Keep personal identifiers out of shared setup templates.

Authentication is not permission to send arbitrary messages. When the current task already authorizes delivery of its review media to this verified self-chat, carry out that delivery without adding a redundant approval round. Use actual authorized artifacts to verify upload; no unrelated test message is required during setup.

Read `lark-cli im +messages-send --help` and the installed IM instructions before sending. Use `--as user` consistently for this workflow; choose bot identity only when it is the intended, authorized sender. Use relative media paths from the working directory, a video cover, and a task-specific idempotency key:

```sh
lark-cli im +messages-send --profile gensen --as user \
  --chat-id 'VERIFIED_SELF_CHAT_ID' --image output/task-review/room.png \
  --idempotency-key 'task-specific-room-image'
lark-cli im +messages-send --profile gensen --as user \
  --chat-id 'VERIFIED_SELF_CHAT_ID' --video output/task-review/room.mp4 \
  --video-cover output/task-review/cover.png --idempotency-key 'task-specific-room-video'
```

Read back the returned message IDs, then download their actual image/file resources with `+messages-resources-download` and compare the content. The Basic Room delivery used this process to verify four PNGs and two MP4s byte-for-byte.

CLI success envelopes use `ok: true`/exit code 0, not a legacy top-level `code: 0`. Inspect `--help` per command: IM shortcuts support `--jq`, while `auth status` in 1.0.97 does not. Do not retry a successful send because a wrapper parsed the envelope incorrectly.

## 6. Prove readiness with the isolated benchmark

Before changing art, establish these concrete checkpoints:

| Capability | Evidence |
|---|---|
| Repository | Correct checkout/branch, known initial dirty state, remote access if required |
| Reference | Actual target image downloaded/viewed through authorized access, or explicitly identified approved local reference |
| Blender | Background Python version probe succeeds; source directory is writable |
| Godot | Matching engine/templates, imports complete, actual rendered scene shows all geometry and avatar |
| Android | Correct isolated package/device/backend, full body visible, input smoke check works |
| Delivery | Intended application, verified user and recipient; required scopes available before sending |

A committed reference image can support preparatory work while Figma authorization is pending, but identify it as the retained reference, not a new cloud fetch. Delivery authorization can proceed alongside independent art work; don't leave the whole task idle when only the final upload is waiting.

Follow the [Basic Room reproduction commands](basic-room-2026-10-06/README.md#rebuild-and-desktop-checks) for imports, atlas settings and the desktop launcher, then its [Android section](basic-room-2026-10-06/README.md#android-reproduction) for APK export, touch-dex compilation/push and the managed test session. A fresh clone will not contain the ignored avatar-dependency manifest, virtual environment, dex or APK; generate them as documented.

The validated emulator case required a QA-only Swappy workaround and software Vulkan because host GPU translation omitted skinned bodies. These are diagnosed environment facts, not universal settings to impose on every machine. Check the actual image before trusting FPS. Physical-phone performance remains a separate measurement.

Additional image-generation service credentials are optional. Basic Room did not call image-2. Configure a service such as the project's approved image API only when the new task actually needs it, using that service's current documentation and an approved secret source; do not invent endpoint/model/key settings or make them a prerequisite for ordinary Blender modeling.

## 7. Keep a small setup handoff record

Store a non-secret record of the executor OS, tool versions, repository revision, chosen profile label/brand, Figma file/node verification, SDK/JDK paths, emulator package/backend, working rendering command and outstanding user actions. Distinguish installed, authenticated, file-access-verified and media-delivery-verified states.

Do not put app secrets, access/refresh tokens, callback URLs with authorization codes, device codes, credential-store files or private chat receipts in the shared guide. Reuse valid authorization on the same host; a fresh environment must establish its own permitted credentials.

## Sources and scope

- [OpenAI: Codex MCP configuration and OAuth callbacks](https://developers.openai.com/codex/mcp/), fetched when writing this guide.
- [Figma: remote MCP installation](https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/), read through the official Figma MCP documentation resource.
- [Official Lark CLI installation/auth documentation](https://github.com/larksuite/cli) and [v1.0.97 release](https://github.com/larksuite/cli/releases/tag/v1.0.97); installed help/embedded skills were also checked.
- [Godot 4.7.2 release assets](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), [Blender downloads](https://www.blender.org/download/), [Android command-line tools](https://developer.android.com/studio#command-line-tools-only), [Temurin JDK 21](https://adoptium.net/temurin/releases/?version=21).
- [Herdr remote-access documentation index](https://herdr.dev/llms.txt); use documentation matching the installed client/server version.
- [Recorded Basic Room verification](../qa/basic-room-2026-10-06.md), including failed setup trials and the final working conditions.

This documentation update checked current help, official sources, the existing authorized connections and published archive structure. It did not claim a second end-to-end installation on a freshly wiped machine or create a new application/account as a test.

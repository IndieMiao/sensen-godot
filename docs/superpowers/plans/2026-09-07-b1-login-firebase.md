# B1 登录页 + Firebase Auth REST（实施记录）

- 日期：2026-09-07 ｜ 分支：`feat/next-feature` ｜ Plane：SGODOT-67 ｜ 上游：`2026-09-07-dev-task-breakdown.md` §3 B1、`../specs/2026-08-30-overseas-refactor-research.md` §4.1
- 性质：实施记录 + 交接。自动化全绿；**没有真实 Firebase 项目，未做端到端登录**（等 SSLAUNCH D1）。

## 0. 结论

| 项 | 结果 |
|---|---|
| 全量测试 | **694 例 / 84 套件，0 errors / 0 failures / 0 orphans** |
| 新增测试 | `tests/net/test_firebase_auth.gd` 12 例；`tests/app/test_login_page.gd` 10 例；AuthSession 加 email 字段 |
| 无头冒烟 | `++ --qa-scene=login`、主场景 boot 均无脚本错误 |
| 未做 | 真实 Firebase 项目端到端（SSLAUNCH D1 建项目后填 `config/firebase.json` 即可）；Apple / Google 按钮仍禁用，等 C1 插件拿 id_token |

## 1. 做了什么

**`modules/net/firebase_auth.gd`（class `FirebaseAuth`）**：Identity Toolkit REST 封装，transport 与 ApiClient 同签名（测试复用 FakeTransport）。
- `sign_up` / `sign_in_with_password`（`accounts:signUp` / `signInWithPassword`，`returnSecureToken`）→ 统一字典 `{ok, code, user_id, email, id_token, refresh_token, expires_in_s, is_new_user}`。
- `sign_in_with_idp(provider_id, id_token, nonce)`：`accounts:signInWithIdp`，`postBody=id_token=…&providerId=apple.com|google.com[&nonce=…]`——C1 插件拿到 token 后调这一个方法。
- `send_verification_email` / `send_password_reset`（`sendOobCode` VERIFY_EMAIL / PASSWORD_RESET）、`lookup`（`accounts:lookup`，取 email / emailVerified）、`delete_account`（`accounts:delete`，R1 删号的 Firebase 侧）。
- `refresh(refresh_token)`：`securetoken.googleapis.com/v1/token`，表单编码；返回 `AuthSession.refresher` 契约 `{ok, id_token, refresh_token, expires_in_s, fatal, error}`；`TOKEN_EXPIRED / USER_DISABLED / USER_NOT_FOUND / INVALID_REFRESH_TOKEN / INVALID_GRANT_TYPE / MISSING_REFRESH_TOKEN` 视为致命 → 会话登出，其余（断网、5xx）保留旧会话。
- `error_code()`：取 `error.message` 第一个 token（`WEAK_PASSWORD : …` 只留标识）；`describe()` 给玩家看的文案，非 UPPER_SNAKE 的码一律按"网络不通"处理。
- 未配置 API key 时所有方法短路返回 `NOT_CONFIGURED`，不发请求。

**`modules/net/firebase_config.gd`**：读 `user://firebase.json`（开发机覆盖）→ `res://config/firebase.json`（CI 出包注入）。仓库只提交 `config/firebase.example.json`，`config/firebase.json` 已加 `.gitignore`。

**`Net`**：新增 `firebase`，`auth.refresher = firebase.refresh`——A1 的 401 刷新链路（ApiClient → AuthSession.refresh → FirebaseAuth.refresh）到此闭合。

**`AuthSession`**：加 `email`（持久化 / 恢复 / 登出清空），`complete_sign_in` 多一个可选 `p_email`。

**`scenes/app/login_page.gd`**：邮箱 + 密码（6 位起）；「Sign in」「Create account」「Forgot password」三条流；注册成功先发验证邮件再进壳（发送失败不阻塞）；失败留在页面、按钮恢复、状态文案来自 `describe()`；输入不合法不发网络请求；Firebase 未配置时三键禁用并解释原因；Apple / Google 禁用等 C1；调试构建保留 Dev 直通。`auth / firebase / navigate` 可注入。

## 2. 关键决定

1. **邮箱 + 密码 + 验证邮件，而不是"邮箱验证码"**：Firebase 没有邮箱数字 OTP；邮箱链接登录要 App Links / Universal Links 深链插件，归 C1 之后评估。08-30 文档的"邮箱验证码"按此落地，验证状态先不阻塞进壳（UGC 门禁 E1 再用）。
2. **Firebase 侧 lookup 作为 M1「登录 → 拿到用户资料」的临时出口**：后端 D2 落地前没有自有资料接口；D0/D1/D2 到位后由 ApiClient 换成自有 `/me`。
3. **API key 不入库**：Web API key 是公开标识，但按 SSLAUNCH D9 台账规矩走配置注入。

## 3. 踩坑

- **Callable 不给 RefCounted 续命**：`s.refresher = FirebaseAuth.new(...).refresh` 里的临时对象立刻释放，Callable 只存对象 id → `is_valid()` 为假、刷新静默失败。凡是把方法引用交给别人保存，宿主对象必须有变量持有（Net 里 `firebase` 是成员变量，正因如此才没事）。
- FakeTransport 现在多记 `raw`（原始 body 文本），表单编码的 securetoken 请求靠它断言。

## 4. 手工验收（待人工，需要 SSLAUNCH D1 的 Firebase 项目）

1. 在 Firebase 控制台开启 Email/Password 提供方；把 Web API key 写进 `user://firebase.json`（`{"api_key": "…"}`）。
2. `godot --path .`：注册 → 收到验证邮件 → 进壳；杀进程重开落在壳；设置 → 登出 → 登录页；错误密码提示「Email or password is incorrect.」；断网提示「No connection…」。
3. 把 `AuthSession.expires_at_ms` 改小或等一小时：任一带 token 的请求 401 → 自动刷新 → 重发成功。

## 5. 下一步

C1 原生登录插件（Android Credential Manager / iOS ASAuthorization → `FirebaseAuth.sign_in_with_idp`）→ A2 i18n。D0 后端栈决策仍待拍板（阻塞 D1 / D2）；A6 需 iOS 真机。

## 6. 真实 Firebase 验证（2026-09-07 追加）

- 项目：**gensen-overseas-dev**（Google 账号 zsjasper@gmail.com，开发 / 测试期专用，后续转公司账户）；Web 应用 `gensen-web`；Email/Password 已通过 Identity Toolkit Admin API 开启；Google / Apple 提供方待 C1 / SSLAUNCH A6。
- 配置：开发机 `user://firebase.json` 已写入 api_key / project_id / auth_domain（`tools/dev/firebase_setup.sh <project>` 可一键重做：addFirebase → 建 Web 应用取 key → 开 Email/Password → 写本机配置）。
- 探针 `tools/dev/firebase_auth_probe.gd`（`godot --headless --path . --script res://tools/dev/firebase_auth_probe.gd`）用仓库自己的 `FirebaseAuth` 走真实接口：sign_up ✔ → lookup ✔（email_verified=false）→ 错密码 `INVALID_LOGIN_CREDENTIALS` ✔ → securetoken refresh ✔ → delete ✔ → 删后登录被拒 ✔。项目里不留测试用户。
- 顺带修的两处：① Godot HTTPRequest 不读系统代理，国内开发机直连 googleapis 超时（RESULT_TIMEOUT=13）——`ApiClient.make_http_transport` 现按 `HTTPS_PROXY` / `NO_PROXY` 环境变量走代理，生产设备无变量即直连；② `test_config_prefers_user_override_then_res_file` 曾直接删掉开发机的真实 `user://firebase.json`，改为备份还原。
- 新增：`firebase-tools` 15.29 本机全局安装；CLI 登录态在 `~/.config/configstore/firebase-tools.json`。

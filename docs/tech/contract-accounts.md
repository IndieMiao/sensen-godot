# 账号接口契约 v1.6.9（禁语音增补送审稿；后裔，2026-11-15）

> 依据：tech-plan-yase.md v1.8 §2–§3；q(312)–q(317)（用户已批）；用户 11-12 定「登录必须上」、q(312) ⑨ 第二类定 C（只挡不删）；我和哪吒 / 周瑜 / 亚瑟 / 盘古 / 李白 11-12～13 的约定（answers：/Volumes/ACASIS/tmp/nezha-491/interface-answers-houyi-1112.md）。
> 本文是**写死的接口**，改动要先告诉五方（周瑜、苏烈、盘古、亚瑟、哪吒），并在文末「改动记录」里记一行。
> 分支：`feat/accounts-pr-a`（PR-A，后裔 + 周瑜的 name.ts / admin.ts）。PR-B 接在它后面。


> **本次状态**：v1.6.9 的禁语音字段为契约负责人拟定、交苏烈确认实现接点并请周瑜审；本轮只改文档，不代表 #1068/#1070 已按此补齐、已合入或客户端已接线。v1.6.8 及以前的已定内容保持。客户端接线等哪吒 QA 工具交完后另排；正式发布仍暂停。
> **依据**：奕星 11-15 指令；李白 SGODOT-484 / 92376ad2（q(315)③ 已批文案、手机本地日期；批准登记 302 / 3afd236d）；#1068 e4a355e72 与 #1070 1315bcc9b 当前回包缺期限/状态。本文统一协议，不增加玩家文案、处罚时长、存档字段或新管理权限。

## v1.6 复核补丁（11-13 后裔；奕星 v3.2 复核 forced-signin/review-v3.2-yixing-subagent-1113.md 建议 2；其余照 v1.5 / v1.4）
1. **登录凭据只用一次，失败了不再弹框**：Apple 的授权码、邮箱码只能用一次（Google 的 id_token 也只在一小段时间有效），所以 claim 失败后不能让玩家「再登一次」打转。
   - `session/claim` 回 `conflict` / `claimed` / `unknown_player` 时，回包都带 `pending`（服务端已验过的这个登录身份，10 分钟、只能用一次，同 no_farm 的票据）和 `has_farm: bool`（这个身份有没有还在的农场）。
   - 新增 **`POST /v1/p0/session/pending {pending, token}`**（不要身份）：这个身份有还在的农场 → 登录进去（顶号，同 session/apple）；没有 → `no_farm {pending}`（换一张新票据）。错误：`pending_expired`。
   - 客户端：
     - `conflict` 卡「用那个农场」→ `session/pending`（不再弹框）；「换个账号」→ 重新 claim（弹框）。
     - `unknown_player`（服务端没有本机记的老农场）→ **清掉本机 p0_player.txt**，按新玩家：has_farm 就 `session/pending` 进去，否则进 NAME → guest（带这张 pending）。
     - `claimed` → 登录页那一行「这个农场绑的是 X」；玩家要是就用刚登的这个身份，has_farm 时 `session/pending` 进去、否则 NAME → guest。本机老农场 ID 留着（以后还能用那个账号认领）。
2. **guest 竞态的 conflict**（建档前这个身份被别的、还在的农场绑了）：回包带 `pending`，客户端出**同一张二选一卡**：主键「进那个农场」→ `session/pending`；次键「换个账号」→ 丢掉 pending、回登录页，NAME 里打的名字也丢掉（**v1.6.2 改**：不知火舞 11-13 定，照诸葛亮 v3.3 §3.3 末段；只是卡上少了第二行那句提醒，服务端不变）。
3. **开关关着的回包统一 503 `provider_unavailable`**（Apple / Google 没配好、`P0_EMAIL_LOGIN` 关着，都一样）。亚瑟方案 §6 写的 404 照这个改。
4. **测试码建的空号**（`/admin/code` 不带 player，周瑜）：按新玩家建档——选家城、新手引导（`choose_home` + `guide_v3`，同新客户端的新档），流程照新玩家走。**note 带 `review` 的码号标 `test: true`，只作统计排除，不改流程**（选城、引导、AGE 照常；服务端不读 test 字段，只给离线统计用；q(322) ②，奕星 11-13 定 A）。年龄和同意在码号首启补走 AGE 后经 `account/consent` 报上去，**服务端同时把语音年龄记成「过」**（之前没答过的才记），审核员能开麦。
5. **「已认领」的判定**：认领过、绑了 Apple / Google、发过测试码、或有 user token，任一即是（服务端 `isClaimed`，fbac979fb）。新号、码号退出登录后本机 p0_player.txt 还在，`hello` 回 `legacy: {claimed: true, linked}`，客户端落到登录页那一行，不会被当成老号去认领；只带旧 ID 来回 426。
6. 文字：v1.4 节首「邮箱登录不在本版」删去；`unauthenticated` 那段的 NO-GMS 页加「邮箱关着时」。
7. 新增 P0Session `sign_in_pending(done)`（`session/pending`；票据由 P0Session 自己记着——no_farm / conflict / claimed / unknown_player 回包里的 `pending`，玩家点「换个账号」时丢掉。**v1.6.3 改**：原写 `sign_in_pending(pending, done)`）。

## v1.5 邮箱验证码登录（11-13 后裔；只加邮箱的接口，其余照 v1.4；实现：周瑜服务端、盘古页面、亚瑟胶水，卡 SGODOT-497）
> 依据：用户 11-13 定邮箱 + 验证码登录赶 11-24 提审；亚瑟邮箱方案 forced-signin/email-signin-plan-yase-1113.md 第 1 节。

- **第三种身份 `provider: "email"`**。和 Apple / Google 同等：找到绑定的号就登录（顶号），没找到回 `no_farm {pending}`，起名后由 guest 建号；`session/claim` 也认它。码号、测试码不变；Play 审核员仍用测试码。
- `POST /v1/p0/session/email/start {email, lang?}`（不要身份；**v1.6.4 加 `lang`**：`"zh"` / `"en"`，按 App 当前语言发邮件；不带或不认识的一律发英文）：一律回 `{ok: true, resend_in: 60}`，**不暴露这个邮箱有没有注册过**。错误：格式不对 `schema`（400）；限流 `rate_limited {retry_in}`（429）；全局上限到了或发信失败 `email_unavailable`（503）。码：6 位数字，10 分钟有效，只能用一次，最多试 5 次，60 秒后才能重发，新码发出后旧码作废；服务端只在内存存 `HMAC(pepper, 邮箱 + 码)`，不落盘（重启后玩家重发即可）。限流数照方案第 1 节表（每个邮箱、每个 IP、全局每天 1200 封）。
- `POST /v1/p0/session/email {email, code, token}`（不要身份）：码对 → 同 session/apple|google（登录顶号 / `no_farm {pending}`）。错误：`bad_code {attempts_left}`（401）、`code_expired`（410）、`rate_limited`。
- `POST /v1/p0/session/claim`：`provider` 多认 `"email"`，凭据是 `{email, code}`（代替 id_token / nonce）；冲突、claimed、consent、age_ok 照 v1.4。
- **存储**：`Linked` 加 `email: {sub}`（**v1.6.5 改字段名**，和 Apple / Google 一样叫 sub，好共用 link / liveOwner / 票据的代码），`sub = HMAC-SHA256(P0_ACCOUNTS_KEY, "p0-email:" + 规范化邮箱)`（trim、转小写，不去 Gmail 的点和 +）；`byIdentity('email', sub)`；删号时一起删。**不存邮箱明文**；服务端日志和限流键只用 HMAC 截断（`emailKey`），不打邮箱和码。和测试码同一把 key，没配 key 邮箱整条路由关。
- **开关 `P0_EMAIL_LOGIN=1`**：关着时两个路由回 `provider_unavailable`（503）；`hello` 回 `email: bool`，客户端据此出 `Continue with email`（没有 Google 服务的安卓机只剩邮箱和测试码）。
- 新错误码：`code_expired`（410）、`email_unavailable`（503）；`bad_code` 在这里带 `attempts_left`。
- 客户端 P0Session：`email_start(email, done)`（亚瑟加）；邮箱登录走通用的 `sign_in("email", {email, code}, done)`，老号走 `claim("email", {email, code}, done)`（**v1.6.3 改**：不单设 `sign_in_email`）。

## v1.4 必须注册（11-14 定稿，以本节为准；下文旧条目原地标了「v1.4 已改 / 已砍」）
> 依据：用户 11-13 定「必须注册」（取消游客，首次打开必须用 Apple（iOS）/ Google（安卓）登录）和「做测试码」；奕星按推荐办；草稿 forced-signin/contract-v1.4-draft.md（亚瑟起草，后裔、苏烈、周瑜、哪吒、诸葛亮逐条回）；诸葛亮 v3 第 13 节（account-firstlaunch-plan-v3-zhuge-1114.md）。

**首启顺序（客户端）**
- 新装机：AGE（含条款勾选）→ 登录 → 有农场就进；没农场（`no_farm`）就带着 pending **直接进 NAME**（不出 No farm found 页）→ `session/guest`。
- 老号（本机有 p0_player.txt）：`hello`（带 x-p0-player）回 `legacy` → 按 `legacy.age` 出 AGE / 同意卡 / AGE-BLOCK → 登录 → `session/claim`（带凭据）一步完成认领和绑定。
- 码号：登录页的「测试码」→ `session/code` → 本机记着「过 + 同意」就直接 `account/consent` 报上去，没有记录就照 `old_consent` 补走 AGE；空号的 NAME 走 `account/name`，Skip 什么都不发。**码号不走 guest。**
- `claimed`：不再有 SYS-CLAIMED 页，落到登录页，上面一行「这个农场绑的是 X」（用 `linked`）。登录失败是登录页上的 toast，不另做卡。

**接口**
| 接口 | v1.4 |
|---|---|
| `GET /v1/p0/hello` | 回 `{ok, terms_version, privacy_version, legacy_id, guest_ok, legacy?}`。带了 x-p0-player 且服务端有这个号：没认领过 → `legacy: {age: true\|false\|null, consent: {terms, privacy} \| null}`；认领过 → `legacy: {claimed: true, linked: [...]}`；号已删或没有 → 不回 `legacy`。只读，不发 token、不建档。 |
| `POST /v1/p0/session/guest` | **pending 必带**：`{age_ok: true, terms, privacy, name \| skip: true, pending, token, request_id}`。不带回 `sign_in_required`（400）。例外：① `test: true`（带主号 token 建测试号，只 OSS）；② 服务端开着 `P0_GUEST_OK=1`（devserver、拍图）。带 pending 就建档并绑上那个 Apple / Google；这个账号在这期间被别的、还在的农场绑了 → `conflict`（409），什么都不动；绑在已不在的农场上的 → 挪到新农场。回 `{ok, player, linked: "apple" \| "google"}`。 |
| `POST /v1/p0/session/claim` | **带凭据**：`{provider: "apple" \| "google", id_token, nonce, auth_code?, token, consent?: {terms, privacy}, age_ok?: true}`，带 x-p0-player。服务端先验令牌：① 这个账号没绑过任何还在的号 → 认领 + 绑定一起做，发 token；② 已经绑了别的、还在的农场 → `conflict {farm: {name, home_level, last_played_at}}`（409），什么都不动；③ 本机老号已经被认领过 → `claimed {linked}`（409）。`consent` 是老号在同意卡上点的同意（那时没 token，不能先调 account/consent），版本对得上才记。`age_ok: true` 是没答过年龄的老号过了新 AGE（服务端把语音年龄记成「过」，不然以后开麦被挡，q(312) ⑪），只收 true。回包照旧带 `age`、`consent`。幂等照旧（同号同 token 重来按成功回）。 |
| `POST /v1/p0/session/apple`、`/session/google` | 不变：找到绑定的农场就登录（撤这个号其他手机的 user token，admin token 留着）；没找到 → `no_farm {pending}`。 |
| `POST /v1/p0/session/code {code, token}` | 测试码登录（不要身份）。回 `{ok: true, player}`；错了 → `bad_code`（401）。只按 IP 限流，每分钟 5 次，不设全局桶。**不顶号**（审核员可能几台机器同时用）；不过期、可重复用，只能手动作废。码：12 位 Crockford base32，显示 `XXXX-XXXX-XXXX`，输入忽略大小写、空格、横线，I / L 当 1、O 当 0。服务端存 HMAC-SHA256(P0_ACCOUNTS_KEY, 码)，没配 key 整条路由关。码发的 token 记来源，作废码只撤它发出去的 token。存档记 `login: "code"`。码号不能绑 Apple / Google。 |
| `POST /v1/p0/session/logout` | 要身份。只撤本机这个 token，回 `{ok: true}`。客户端清掉 p0_session.json 的 token，回登录页；p0_player.txt 留着（支持码要用）。 |
| `POST /v1/p0/session/switch`、`POST /v1/p0/account/link/{apple,google}` | **第一版砍掉**，不注册路由（周瑜的 link/google 代码留着）。「换个账号」= 退出登录再登录。`discard_required`、`already_linked` 两个码随之不用。 |

**`conflict` 只在 claim（和 guest 的竞态）时出**：客户端出简化冲突卡，两个键——「用那个农场」→ 调 `session/apple|google` 正常登录（那边的其他手机会被顶号，这是用户自己选的）；「换个账号」→ 重新 claim。本机老农场不动，本机记着旧 ID，以后还能认领。

**新错误码**：`sign_in_required`（400，guest 没带 pending）；`bad_code`（401，测试码不对）；`smoke_only`（400，管理端 /admin/smoke 带了别的号）。

**`unauthenticated` 的处理（v3 ⑮）**：钥匙被撤以后（Apple 停用、码被作废、consent-revoked 撤 token、服务端不认识的 token）回 `unauthenticated`。P0Session：停掉所有请求，**回登录页，不出顶号那句**；没有 Google 服务的安卓机，**邮箱关着时**回 NO-GMS 页（邮箱开着就回登录页，只剩邮箱和测试码）。（v1.3 里我说把它当 session_replaced 交给哪吒，作废。）

**Apple 通知（§3，苏烈）**：`consent-revoked` 不解绑——只撤这个号的 user token、断 WebSocket 和语音、作废存着的 refresh token；sub 留着，同一个 Apple ID 再登录还认得出原农场，下次登录换新的 refresh token；admin token 不撤。`account-delete` 照旧删号（第一版一个号最多一种绑定）。

**dev 开关 `P0_GUEST_OK=1`**：只给 devserver 和本地服，开着时 guest 可以不带 pending。正式服绝不开：`/v1/healthz` 和 `hello` 都回 `guest_ok`，部署后 smoke.sh 断言它为 false（和 `legacy_id` 共用 `P0_SMOKE_ALLOW_LEGACY`）。客户端据此在登录页多一个 dev 用的「Continue without signing in」（只 debug 包）。

**管理端（周瑜）**：
- `/admin/smoke`（不是草稿里的 `/admin/session {create: true}`）：每次把固定号 p0-smoke-check 重置成新档（test: true），撤掉它旧的 token，发 1 小时的 admin token；body 带别的号回 `smoke_only`，什么都不动。deploy-hk.sh 冒烟前调它，token 经环境变量交给 smoke.sh，不进文件和输出。
- `POST /admin/code {player?, note}`：不带 player 就新建一个空号；一个号一个码，再发就换掉旧码；明文码只回这一次。`POST /admin/code/revoke {player}`。`/admin/players` 列出有没有码（note 和时间，不含码）。deploy-hk.sh 加 `code` / `code-revoke` / `code-batch`；正式服由 83 执行，执行前先问奕星。note 只写编号（`review-play`、`cn-tester-03`），不写个人信息；带 `review` 的统计时排除。

**P0Session（客户端）签名改动**：`claim(provider: String, creds: Dictionary, done: Callable)`（creds 同 sign_in：`{id_token, nonce, auth_code?}`，另由 P0Session 带上本机记的同意和 age_ok）；新增 `logout(done: Callable)`、`sign_in_code(code: String, done: Callable)`；删去 `switch_farm`、`link`。`first_run()` 不再有 `"claimed"`（落到登录页）。

**存档可选字段（随账号这批一起报用户批）**：`profile`、`consent`、`age_ok`、`test`、`login`。

**不变**：P0_LEGACY_ID（只是 dev 旁路）、admin token（/admin/session）、过渡期旧客户端只带 x-p0-player、认领过的号带旧 ID 回 426、deleted 名单、删号、举报、name/check、account/consent、account/name、请求头、pending 的有效期和一次性。**正式服的老号必须登录 + claim（带凭据）**；旧版本客户端在过渡期照旧只带旧 ID，直到强更。

## 0. 通用

**地址**：正式服 `https://farm.sensenjoy.cn/preview/p0/v1`（Caddy 去掉 `/preview/p0`，服务端看到的是 `/v1/…`）。

**请求头**（新客户端每个 HTTP 请求和 WebSocket 握手都带）：
| 头 | 值 | 说明 |
|---|---|---|
| `authorization` | `Bearer <64 位十六进制>` | 有 token 时带。token 是客户端生成的 32 字节随机数 |
| `x-p0-player` | 玩家 ID | **确认不回滚之前一直带**（周瑜 §2.4）；和 token 对应的号不一致时，以 token 为准，服务端记日志 |
| `x-p0-key` | 共用口令 | 照旧，`/v1/p0/*` 都要 |
| `x-p0-version` | 版本号（versionCode） | 照旧 |
| `x-p0-features` | 照旧，新增 `accounts` | 服务端靠它知道客户端会不会走首启 |
| `x-p0-platform` | `android` / `ios` / `desktop` | 新增 |
| `x-p0-channel` | `oss` / `play` / `appstore` | 新增；只决定显示什么，不当安全边界；client_error 不记它 |

**回包**：成功一律 `{ok: true, …}`。业务错误一律 4xx + `{ok: false, code, …}`，**客户端只按 `code` 分支，不看状态码**。

**错误码总表**：
| code | 状态 | 何时 | 附带字段 |
|---|---|---|---|
| `unauthenticated` | 401 | 没 token 也认不出旧 ID，或 token 不认识 | — |
| `session_replaced` | 401 | 这个号在别的手机上登录了，本机 token 已撤 | — |
| `account_deleted` | 401 | 号已删 | — |
| `suspended` | 403 | 号被停用 | `until`: ISO 字符串，或 `null`（没有到期日） |
| `VOICE_BANNED` | 403 | **v1.6.9 送审**：本人禁语音仍生效；voice join / heartbeat / join 签名后复查，不是整号停用 | **必填** `until`: UTC ISO 8601 字符串，或 `null`（明确永久）；见 §1.1 |
| `update_required` | 426 | 认领过的号只带旧 ID 来（旧版本客户端），或强更 | `url` |
| `schema` | 400 | 请求体不对 | — |
| `token_too_short` | 400 | token 不足 32 字节 | — |
| `name_rejected` | 400 | 名字不行 | `reason`: `empty` / `length` / `chars` / `blocked` |
| `rate_limited` | 429 | 限流 | — |
| `rename_too_soon` | 409 | 改名冷却没到 | `rename_at` |
| `consent_outdated` | 409 | 送上来的条款 / 隐私版本不是当前的 | `terms_version`, `privacy_version` |
| `claimed` | 409 | 这个号已经用别的 token 认领过 | `linked`: `["apple"]` / `["google"]` / `[]` |
| `unknown_player` | 404 | claim 的号服务端没有（或已删） | — |
| `no_farm` | 404 | Apple / Google 账号没绑任何号 | `pending` |
| `conflict` | 409 | 这个 Apple / Google 账号已经绑在别的号上 | `pending`, `farm: {name, home_level, last_played_at}` |
| `pending_expired` | 410 | 待绑票据过期 / 用过了 / 服务端重启 | — |
| `bad_token` | 401 | Apple / Google 令牌验不过（签名、aud、nonce、过期） | — |
| `discard_required` | 400 | switch 时眼前这份档没绑任何账号，却没带 `discard_guest: true` | — |
| `already_linked` | 409 | 本号已经绑过同一家 | — |
| `delete_failed` | 500 | **v1.6.7**：App 内删号（DELETE /v1/p0/account）前段同步写盘出错，号没删。客户端提示 Didn't go through。后段失败（号已删，存档文件或语音没清掉）照旧回 ok，由管理端补跑 | — |
| `provider_unavailable` | 503 | Apple / Google 服务一时连不上（换码、JWKS） | — |

## 1. 首启与身份（PR-A，后裔）

### `GET /v1/p0/hello`（不要身份）
回：`{ok: true, terms_version, privacy_version, legacy_id: bool, update?: {url}, maint?: {back_at}}`
- 版本号的唯一来源是 `assets/p0/legal/versions.json` `{"terms": "...", "privacy": "..."}`，客户端随包带同一份，服务端读仓库里的。
- 旧服务端没有这个接口（404），或者回包没有 `terms_version`，客户端判为 **legacy**。
- `legacy_id: true` 表示服务端开着 `P0_LEGACY_ID`（devserver / 拍图）。

### `POST /v1/p0/name/check {name}`（不要身份；限流：name/check、account/name、guest 带名字这三处**共用一个桶**，按 IP 每分钟 20 次）
回：`{ok: true}`；或 `name_rejected {reason}` / `rate_limited`。规则在 `server/src/p0/accounts/name.ts`（周瑜）。

### `POST /v1/p0/session/guest`（不要身份，带 token）——**v1.4 已改：pending 必带，见文首 v1.4 节**
请求：`{age_ok: true, terms, privacy, name | skip: true, pending?, request_id, token}`
- `request_id`、`token` 由客户端生成（各 32 字节十六进制），重试时原样带。
- 回：`{ok: true, player, linked?: "apple" | "google"}`（带了 pending 就绑上）。
- 错：`schema`（age_ok 不是 true）、`token_too_short`、`name_rejected`、`consent_outdated`、`pending_expired`。
- 幂等：同一个 `request_id` + 同一个 token 重来，回同一个 player。

### `POST /v1/p0/session/claim`（带 `x-p0-player` 和新 token）——**v1.4 已改：带凭据，见文首 v1.4 节**
请求：`{token}`
回：`{ok: true, player, age: true | false | null, consent: {terms, privacy, at} | null}`
- age 三种：true = 语音年龄卡答过「过」；false = 答过「没过」；null = 没答过（取自 voice_ages）。
- 错：`claimed {linked}`、`unknown_player`（服务端没有这个号，或在 deleted 名单里）、`token_too_short`。
- 幂等：同一个号 + 同一个 token 哈希重来，回成功；换了 token 回 `claimed`；这个 token 哈希已经绑在别的号上，拒绝。

### `POST /v1/p0/account/consent`（要身份）
请求：`{age_ok: true, terms, privacy}`。**只收 age_ok: true**，false 回 `schema`（q(312) ⑨ 定 C：答「没过」不报服务端）。
回：`{ok: true}`；错：`consent_outdated`。

### `GET /v1/p0/state` 等现有接口
- 认人统一走 `identify(req)`：token 优先；没有 token 时，只有**没认领过**的号在过渡期照旧认 `x-p0-player`。
- 新增 `view.account = {name, linked: ["apple"], rename_at, consent: {terms, privacy} | null}`。`rename_at`：按服务端时钟已经过了就回 0，没过回毫秒时间戳，客户端按 `rename_at − 现在` 写 `in %d days`（周瑜的 accountNameView 算）。
- 名字存在**存档**里：`profile.name`、`profile.name_set_at`、`profile.name_locked_until`。guest 带名字：name_set_at = 建号时间，第一次改名要等 7 天；guest 选 skip：不写 name_set_at，第一次改名不等（q(313) ②）。`name_locked_until` 由苏烈的处置「重置名字」写（q(313) ④ / q(315)：改回默认名，同时写 现在 + 7 天），renameAt 会读它。
- **不再自动建档**：按 token 认出来的号存档不在 → `unauthenticated`。旧客户端带 `x-p0-player` 来（features 里没有 `accounts`），过渡期照旧自动建档；`deleted` 名单里的号不建。

### `POST /v1/p0/account/name {name}`（要身份；周瑜）
回：`{ok: true, name, rename_at}`；错：`name_rejected`、`rate_limited`、`rename_too_soon {rename_at}`（409）。

### `DELETE /v1/p0/account`（要身份）
**被停用（403 suspended）的号也能删**（v1.6.6，周瑜提：App Store 5.1.1(v) 和 Play 都要求所有账号都能删）：这条路由调 `identify(headers, deps, {evenSuspended: true})`，其余路由照旧挡。回：`{ok: true}`（v1.6.7：号对所有请求已不可用就回 ok，后段失败也回 ok；前段写盘出错号没删，回 500 `delete_failed`）。只带 ID 不能删（401 unauthenticated）。之后这个号的 token 全部失效（`account_deleted`），WebSocket 以 4001 断开，语音 leave。绑过 Apple 的同时撤销授权。

### 客户端：`P0Session`（后裔写；哪吒的假实现照这个）
```gdscript
signal identity_changed(ready: bool)
var identity_ready := false            # 盘古 #1006 已建占位；PR-A 接上
func first_run() -> String             # hello 回调之后才有意义：
	# "ready" 有 token / 拍图跳过 · "new" 新装机 · "old_age" 老号没答过年龄 · "old_consent" 老号答过「过」只缺同意
	# "old_blocked" 老号答过「没过」 · "blocked" 本机记过「没过」 · "legacy" 旧服务端
func hello(done: Callable)             # 老号（有 p0_player.txt、没 token）在这里面先 claim
func name_check(name: String, done: Callable)
func guest(body: Dictionary, done: Callable)        # body: {age_ok, terms, privacy, name | skip, pending?}
func claim(done: Callable)                           # 只给 SYS-CLAIMED 页上重试用
func consent(body: Dictionary, done: Callable)      # body: {age_ok, terms, privacy}
func rename(name: String, done: Callable)            # POST account/name：老号在 NAME 点 Continue、个人页改名；老号 Skip 什么都不发，保留原名
func sign_in(provider: String, creds: Dictionary, done: Callable)   # creds: {id_token, nonce, auth_code?}
func switch_farm(pending: String, discard_guest: bool, done: Callable)
func link(provider: String, creds: Dictionary, done: Callable)
func delete_account(done: Callable)
```
- 回调参数一律是回包 Dictionary（网络失败时是 `{ok: false, code: "network"}`）。
- 本机文件：`user://p0_session.json` `{"v": 1, "player", "token", "linked": [], "created_at"}`；`user://p0_player.txt` 照写一份；`user://p0_first_run.json` 归哪吒的页面写。
- 跳过首启：hello 回 `legacy_id: true` 且本机有 p0_player.txt → `"ready"`（只带 x-p0-player）；桌面 debug 包 `P0_SKIP_FIRST_RUN=1` → `"ready"`；`demo_server.json` 的 `accounts: false` → `"legacy"`。
- 总闸：`identity_ready` 为 false 时，只放行 hello / name_check / guest / claim / sign_in；refresh、report、_flush_ui、P0Online 一律不发。
- 401 `session_replaced` / `account_deleted`、403 `suspended`、409 `claimed`：由 P0Session 停掉所有请求，调 `ui.show_account_state(kind, detail)`（哪吒），不算联网失败。

## 1.1 禁语音状态与拒绝（v1.6.9 送审；只复用 q(315)③）

### 错误码与作用范围

最终协议码定为大写 **`VOICE_BANNED`**，沿现有 `VOICE_*` 命名，不另造小写别名。服务端本人禁语音生效时，`POST /v1/p0/voice/join`、`POST /v1/p0/voice/heartbeat`（含 join 的异步 JWT 签名后复查）回 **HTTP 403**：

```json
{"ok": false, "code": "VOICE_BANNED", "until": "2026-11-20T08:00:00.000Z"}
```

永久禁语音：

```json
{"ok": false, "code": "VOICE_BANNED", "until": null}
```

- `until` 在这个错误上**必须存在**。不是 `at`、剩余天数、ISO 日期片段或毫秒数字；空串/缺字段不代表永久。
- 账号鉴权在前：未知/已删/token 失效照账号码回，整号停用仍为小写 `suspended` 及其 `until`。不能把 HTTP 403 一概认作停用，也不能将禁语音转为账号状态页/登出或撤账号 token。
- `VOICE_BANNED` 是当前语音尝试的终止原因，不走“网络故障”自动 join/heartbeat 重连循环；关闭/终止当前语音流程，保留游戏身份、房间和非语音操作。到期或解除后可重新由玩家触发，**不自动开麦/重连**。
- 禁语音不限制人数胶囊、人数抽屉、Block/Report；不清 `voice_ages` 或 `voice_blocks`。这两点沿已批 q(315)③及 #1068 专用 drop 语义，不新增处罚行为。

### 网络时间与存档时间明确分层

| 层 | until 形状 | 判定/用途 |
|---|---|---|
| 存档 `sanctions.voice.until`、既有管理输入 | 真实 Unix **毫秒**时间戳，或 `null` | 延续已有数据结构；不迁移、不升 SAVE_VERSION；管理期限仍须明确给出，不新设默认天数 |
| 内部有效禁令判断 | `inForce(sanctions.voice, Date.now())` | 不用 `clock_ms`、游戏换日、手机时钟；无字段或 `until <= now` 为不生效，`null` 永久 |
| 玩家接口 `VOICE_BANNED.until` / `status.ban.until` | `new Date(until_ms).toISOString()` 的 **UTC ISO 8601 完整字符串**，或 `null` | 格式 `YYYY-MM-DDTHH:mm:ss.sssZ`；同一判定结果投影，不能直接把存档毫秒值下发给这个字段 |
| 玩家日期文案 | 解析上述 UTC 时刻，再用**手机本地时区/本地化日期格式** | 限期模板填日期（英文示例 Nov 20），不是剩余 N 天，也不是按服务器 UTC 日期截取 |

判到期不要求清存档字段：读时判无效即可。`until == now` 已到期；不要因记录还在就继续出禁语音状态。序列化只能投影验证过的有效期限，若内部数据异常不能靠省略/写 null 伪装成永久。

### `GET /v1/p0/voice/status`：唯一主动查询入口

保留当前 `ok`、`available`、`age`；新增**必填** `ban`：

```ts
// 只描述玩家接口的结构，不是本轮代码实现。
type VoiceBan = null | { until: string | null };
// GET /v1/p0/voice/status → 200
{ ok: true, available: boolean, age: "ok" | "no" | "unknown", ban: VoiceBan }
```

| 权威状态 | status 下发 | 客户端语义 |
|---|---|---|
| 没有禁令、已解除或已到期 | `"ban": null` | 仅“未被禁语音”；仍受 available、房间、平台、年龄等原条件约束 |
| 有效限期禁语音 | `"ban": {"until":"2026-11-20T08:00:00.000Z"}` | 确认被禁且有到期日 |
| 永久禁语音 | `"ban": {"until":null}` | 确认被禁且明确永久 |
| 未获取、旧服务缺 ban、字段畸形、网络错误 | **不是服务端第四种业务值**；客户端本地记“未知/未更新” | 缺 ban 不等于 ban:null；缺 until 不等于 until:null |

- status 对仅禁语音的号仍回 **200**，以便恢复状态；不是把 status 自己也挡成裸 `VOICE_BANNED`。若整号被停用，仍先按鉴权回 `403 suspended`。
- `available` 只表示服务端语音能力/配置是否可用，不因禁语音改为 false；`age` 不被处罚重写。这允许客户端在原本显示麦克风的地点保留灰键和点击提示，不误把键隐藏。
- 新 status 的 `ban` 始终下发（含 null），即使语音能力目前关闭或年龄尚未通过，也能准确回答本人处罚状态；是否显示语音入口仍由已有条件决定。
- 本次**不在 `view.account` 复制 ban，不把原始 sanctions 放进 view**；不向 roster、peer 或别人状态公开。最小字段只含本人当前禁语音有效性与期限；**不下发 report、at、name_reset_at、管理员、支持码或处置原因**。
- 错误回包与 status 使用同一有效禁令读取/投影，不能由两处独立布尔缓存推断期限；到期边界和永久值须一致。

### 客户端刷新与现有文案的消费约定（只写契约，代码后排）

1. 以账号身份为缓存边界；初次已认证进入可显示麦克风的房间、重登/换号、回前台/重建语音上下文时通过 status 刷新。换号清掉前一个号的 ban，晚到的旧账号回包不得覆盖新号。
2. join/heartbeat 收到 `VOICE_BANNED + until`，立即更新本人已知禁令、终止本次语音尝试/自动重试；麦克风保持原位视觉灰，点击仍能触发已有 Info toast，不用完全吃点击的 disabled 控件。
3. 限期到达时触发一次受原请求节流约束的 status 复查，以**服务端返回**决定是否解除灰态；手机时间只负责调度/显示，不能据本地时钟直接宣布处罚结束。前台已有状态刷新、重新进入/重登、下一次点击语音入口时也复查，保证管理变化（含永久禁令解除）可取到；调度沿既有机制，避免过期时间/时钟偏差造成零间隔重试。
4. 新状态为 ban:null 时恢复原语音入口条件，不代表自动开麦。status 失败不覆盖成“未禁”或“永久”；同账号已有可信禁令可保留并标待刷新，已有期限过去时不继续声称旧日期是当前禁令。没有可信状态，或只收到旧的裸 VOICE_BANNED，先终止这次语音并请求status，不能随意选择永久/限期文案；失败沿已有通用失败处理，不新增玩家句子。
5. 仍使用已批两句：有效限期且有合法 until → **`Voice chat is off for you until %s.`**；明确永久 until:null → **`Voice chat is off for you.`**。中文沿现有键：`你的语音聊天已被关闭，%s 恢复。` / `你的语音聊天已被关闭。`。不新增自动弹出、入口、处罚天数或文案。

### 苏烈服务端增量接点与验收清单（实现另 PR）

- #1068 目前 `voiceBanned(player)` 只返回 boolean，`p0_server` 已把 `inForce` 结果压成布尔；需改为能取得有效 `until_ms|null` 的只读内部投影（方法命名由实现者定，不扩公网字段）。status 和 join/heartbeat/签名后复查共用它，永久 null 不得被 `!!until` 吃掉。
- 内部 Refusal 携带**网络层 until**，`registerP0Voice` 的 HTTP answer 明确保留这个白名单字段；不能只加内部字段却仍只序列化 ok/code。非 VOICE_BANNED 的既有错误/鉴权透传不改变。
- status 增加上述 ban；保留 available/age、专用 drop 只退租约、游戏/年龄/blocks不清。#1070 媒体失败反馈问题按周瑜6888548241独立修，不借本条修改“已施加/清理未确认”的管理语义。
- 服务端新增检查：未禁/限期/永久/准确到期点/解除；status与join/heartbeat同期限；真实HTTP answer不丢until；异步签名期间新禁令回当前期限；管理字段不进 status/view/错误；suspended鉴权优先及被停用仍能删号。
- 客户端后续检查：两句按字段正确分支、手机跨时区日期、字段缺失未知、重登/前台/到期/解除刷新、无语音重试循环、灰键仍可点击、人数与Block/Report保留。**哪吒 QA 工具交完后另排，不在本轮修改或宣称验收。**

## 2. Apple / Google（PR-B；Apple 后裔，Google 周瑜）

请求体字段照亚瑟的 P0SignIn：`{id_token, nonce, auth_code?, token}`。`nonce` 是原文，服务端核 `sha256hex(nonce)` 等于令牌里的 nonce；`auth_code` 只有 Apple 有；`token` 是客户端新生成的 32 字节。

### `POST /v1/p0/session/apple`、`/session/google`（不要身份）
- 找到绑定的号：`{ok: true, player, linked}`。服务端同时**撤掉这个号的其他 token**（顶号），旧手机下一个请求收到 `session_replaced`。
- 没找到：`no_farm {pending}`。玩家点 `Start a new farm`，起完名后 guest 带上 pending。
- 错：`bad_token`、`provider_unavailable`。

### `POST /v1/p0/session/switch {pending, discard_guest, token}`（要身份：眼前这份档）——**v1.4 已砍**
- 眼前这份档没绑任何账号：只接受 `discard_guest: true`，否则回 `discard_required`。为真时按删号删掉它。
- 绑过账号的：不删，以后用那个账号登录还能切回来。
- 回：`{ok: true, player, linked}`，给目标农场发 token、撤掉它的其他 token。错：`pending_expired`。

### `POST /v1/p0/account/link/apple`、`/account/link/google`（要身份）——**v1.4 已砍**
- 回：`{ok: true, linked}`。
- 错：`conflict {pending, farm: {name, home_level, last_played_at}}`（`last_played_at` 是毫秒时间戳，客户端照 q(28) 拼 `3 days ago`；卡上写 `Home Lv%d · Last played %s`，q(306)）、`already_linked`、`bad_token`。
- **第一版没有解绑路由**（q(314)）。

### 待绑票据 `pending`
32 字节随机串，只放内存，10 分钟有效，只能用一次。重启就没了，客户端收到 `pending_expired` 时提示再登录一次。过期没用掉的 Apple 票据，服务端顺手撤销那个授权。

### 服务端配置（`server/src/p0/accounts/config.ts`，后裔）
- `GOOGLE_CLIENT_IDS`（不是秘密，奕星 11-13 给的，部署时写进 .env.p0）：`870347303349-bkbtvblhsj7epud9cm2ma2ia9r0blj5i.apps.googleusercontent.com,870347303349-3lmi6ghlhuon2t1idp3mdbnqknj8ug2i.apps.googleusercontent.com`（Web、iOS；见 google-client-ids-1113.md）。
`APPLE_TEAM_ID`、`APPLE_KEY_ID`、`APPLE_PRIVATE_KEY_FILE`、`APPLE_BUNDLE_IDS`（session/apple 只认它）、`APPLE_SERVICES_IDS`（只给 web-delete 用）、`GOOGLE_CLIENT_IDS`（Web + iOS，逗号分隔）、`P0_LEGACY_ID`、`P0_ACCOUNTS_KEY`（Apple refresh token 字段 AES-GCM 加密用）。Apple 的 refresh token 连它的 `aud` 一起存，撤销时用 aud 当 client_id。

## 3. 不在 /v1/p0 下的（苏烈；守卫不管，各自验签 + 按 IP 限流）
- `POST /v1/apple/notifications`：Apple 服务器通知（JWS）。`consent-revoked` → `unlinkApple(player, {revoke: false})`；`account-delete` → 只绑了 Apple 的调 `deleteAccount(player)`，同时绑了 Google 的只调 `unlinkApple`。
- `POST /v1/web/delete {provider, id_token, nonce?}`：网页删号。找到 → `deleteAccount`，回 `{ok: true}`；找不到 → `no_farm`。

## 4. 给协作者的服务端函数签名（PR-A 里提供，11-13 先推骨架）
```ts
// server/src/p0/accounts/store.ts（后裔，已实现 bedf29dfc）
export interface AppleLink { sub: string; aud: string; refresh?: string }   // refresh 进出都是明文，落盘时 AES-GCM 加密
export interface Linked { apple?: AppleLink; google?: { sub: string } }
export interface AccountRow extends Linked { player: string; created_at: number; claimed_at?: number }
export type TokenKind = 'user' | 'admin';
export const hashToken: (token: string) => string;          // sha256 hex
export const tokenShapeOk: (token: unknown) => boolean;     // 十六进制、≥ 32 字节
export class P0Accounts {
  constructor(file?: string, key?: Buffer | null, now?: () => number);
  find(player): AccountRow | undefined;   ensure(player): AccountRow;   markClaimed(player); clearClaimed(player);
  byToken(token): { player; kind } | undefined;              // 传明文；admin 过期视为没有
  tokenOwner(token): string | undefined;   userTokenCount(player): number;
  issue(player, token, kind = 'user', expiresAt?);
  revokeAll(player, keep?: string /* 明文 */, opts?: { admin?: boolean }): string[];   // 默认只撤 user token：session/apple、session/google、switch 顶号都不传 admin，admin token 留着（§2.5）；admin/claim/reset 传 {admin: true}；删号走 remove()，所有 token 一起删
  byIdentity(provider, sub): string | undefined;   link(player, provider, info);   unlink(player, provider);   linked(player): Provider[];
  markDeleted(player, at);   isDeleted(player): boolean;     // 30 天
  remove(player);                                            // 只删 accounts 里的行、绑定和全部 token
  adminTokens(): { player; tail; expires_at }[];   players(): string[];   path(): string | undefined;
}
// server/src/p0/accounts/identify.ts（后裔）
export function identify(req: FastifyRequest, deps: IdentifyDeps): { player: string; via: 'token' | 'legacy' } | Refusal;
// server/src/p0/accounts/delete.ts（苏烈）
export interface DeleteDeps { store: P0Store; accounts: P0Accounts; voice: P0Voice; hub: { kick(player: string): void }; now: () => number;
  revokeApple?: (aud: string, refresh: string) => Promise<void> }
export async function deleteAccount(deps: DeleteDeps, player: string): Promise<void>;
// 顺序（§1.3）：accounts 先（revokeAll + markDeleted + remove），再 store.remove，再 voice / hub；绑过 Apple 的最后撤授权（失败只记日志）
// server/src/p0/accounts/link.ts（后裔，PR-B）
export async function unlinkApple(deps: DeleteDeps, player: string, opts: { revoke: boolean }): Promise<void>;
export function conflictFarm(store: P0Store, accounts: P0Accounts, player: string): { name: string; home_level: number; last_played_at: number };
export function createPending(info: PendingInfo): string;  export function takePending(id: string): PendingInfo | undefined;
```
- `P0Store` 已加 `find(player, now)`（不建档）和 `remove(player)`（67641ef82）。
- 周瑜的接线：accounts/name.ts 导出 `registerNameRoutes(app, deps)`（name/check、account/name，后裔在 routes 里加一行调用）、`nameForGuest(body)` → `{name, name_set_at?}` 或 name_rejected（guest 里调）、`accountNameView(state, now)`（进 view.account）。他的分支变基到 feat/accounts-pr-a，开 PR 合进来，后裔审。
- `hub.kick(player)`：后裔在 PR-A 里加（4001 关 WebSocket）。

## 4.1 管理端（周瑜；口令照现有 /admin，只在容器内 127.0.0.1）
- `POST /admin/session {player}` → `{ok, player, token, expires_at}`：token 服务端生成，32 字节十六进制，明文只回这一次；kind admin，30 天。号不存在回 404 `unknown_player`。不替它 markClaimed：没认领过的测试号照旧也认 x-p0-player。
- `POST /admin/claim/reset {player}` → `{ok, revoked: n}`：clearClaimed，再 `revokeAll(player, undefined, {admin: true})`。
- `GET /admin/players`：每个号加 `admin_tokens: [{tail, expires_at}]`（adminTokens()）。
- deploy-hk.sh 加 `token` / `claim-reset` 两个子命令（周瑜写）；正式服由 83 执行，执行前先问奕星。
- **补删（v1.6.8，苏烈 11-16 做；484 c343a157）**：
  - `POST /admin/delete {player | support_code}` → `{ok, incomplete?}`：对删号记录或者还在的号调 `deleteAccount`，可重入，从断点接着删完（#1049 的测试锁着）。支持码命中不止一个号就拒绝。删号前查一遍 `previewAccountDeletion`。
  - `GET /admin/delete/incomplete`：列出已进删号名单、但存档或账号行还在的号（支持码和删号时间），补删时照着一个个清。
  - 找号的依据：日志里的 `delete_failed_app` / `delete_incomplete_app` / `delete_incomplete`，都带支持码。
  - deploy-hk.sh 加一个 `delete <player|code>` 子命令；**正式服由 83 执行，执行前先问奕星**。

## 5. 假服务回包样例（哪吒、亚瑟本地串流程用）
```json
GET  /v1/p0/hello            → {"ok":true,"terms_version":"2026-11-13","privacy_version":"2026-11-13","legacy_id":false}
POST /v1/p0/name/check       → {"ok":false,"code":"name_rejected","reason":"blocked"}
POST /v1/p0/session/guest    → {"ok":true,"player":"p0-a1b2c3d4e5f6a7b8c9d0"}
POST /v1/p0/session/claim    → {"ok":true,"player":"p0-…","age":null,"consent":null}
POST /v1/p0/session/claim    → {"ok":false,"code":"claimed","linked":["apple"]}
POST /v1/p0/session/apple    → {"ok":false,"code":"no_farm","pending":"9f2c…(64)"}
POST /v1/p0/account/link/apple → {"ok":false,"code":"conflict","pending":"…","farm":{"name":"Mia","home_level":7,"last_played_at":1762990000000}}
POST /v1/p0/session/guest    → {"ok":false,"code":"pending_expired"}
GET  /v1/p0/state            → 401 {"ok":false,"code":"session_replaced"}
GET  /v1/p0/state            → 403 {"ok":false,"code":"suspended","until":null}
GET  /v1/p0/voice/status     → 200 {"ok":true,"available":true,"age":"ok","ban":null}
GET  /v1/p0/voice/status     → 200 {"ok":true,"available":true,"age":"ok","ban":{"until":"2026-11-20T08:00:00.000Z"}}
POST /v1/p0/voice/join       → 403 {"ok":false,"code":"VOICE_BANNED","until":null}
```

## 改动记录
- **v1.6.9 11-15 送审（后裔；奕星指令，李白484/92376ad2）**：§0定VOICE_BANNED并补必填until；新增§1.1，voice/status.ban区分未禁/限期/永久，网络UTC ISO|null与存档毫秒分层，缺字段未知；只投影本人期限、不出管理数据，不扩view.account；复用q(315)③原文案和手机本地日期。已通知五方，待苏烈确认接点、周瑜审。仅文档，不声称服务端/客户端已实现。
- v1 11-13：初版（后裔）。
- **v1.6.8 11-14（苏烈 484 c343a157 定名）**：§4.1 加补删——`POST /admin/delete {player | support_code}`（deleteAccount 可重入）和 `GET /admin/delete/incomplete`，苏烈 11-16 做；deploy-hk.sh 加 `delete`，由 83 执行。
- **v1.6.7 11-14（#1048，周瑜审）**：App 内删号路由已经接上（delete.ts 的 registerAccountDeleteRoute）；新错误码 `delete_failed`（500，前段写盘出错、号没删）；后段失败回 ok，打 delete_incomplete_app 日志，由管理端补跑；只带 ID 删不了。
- **v1.6.6 11-14（周瑜审 #1043 提）**：被停用的号也能 App 内删号——删号路由用 `identify(…, {evenSuspended: true})`，#1043 留好了这个口并配了测试；其余路由照旧回 403 suspended。
- **v1.6.5 11-14（周瑜 #1044 实现，后裔审过同意）**：只改文字——邮箱绑定的字段 `email: {h}` 改叫 `email: {sub}`，HMAC 前面加 `p0-email:`，和测试码的 HMAC 分开。接口不变。
- **v1.6.4 11-14（周瑜提，后裔同意）**：`session/email/start` 加可选的 `lang`（"zh" / "en"），按 App 当前语言发验证码邮件（李白文案要求）。不带或不认识的发英文，向后兼容。客户端 `email_start` 由亚瑟带上当前语言。
- **v1.6.3 11-13（亚瑟核出）**：签名改齐 A2 实现——`sign_in_pending(done)`（票据 P0Session 自己记）；邮箱不单设 `sign_in_email`，走 `sign_in("email", {email, code}, done)` / `claim("email", …)`；`email_start` 留着。P0Session 现行签名：`sign_in(provider, creds, done)`、`claim(provider, creds, done)`、`sign_in_pending(done)`、`sign_in_code(code, done)`、`logout(done)`、`guest(body, done)`（票据自动带上）。
- **v1.6.2 11-13（不知火舞定，哪吒转）**：v1.6 ② 改成 guest 竞态的 conflict 也出两个键（「进那个农场」→ session/pending；「换个账号」→ 丢 pending 回登录页，NAME 里的名字丢掉），照诸葛亮 v3.3 §3.3 末段。只改客户端，服务端回包不变。
- **v1.6.1 11-13（奕星定 A）**：v1.6 ④ 改成「note 带 review 的码号标 test: true，只作统计排除，不改流程」，和已批 q(322) ② 对齐（周瑜查出原写法冲突）。
- **v1.6 11-13（奕星 v3.2 复核补丁）**：文首新增「v1.6 复核补丁」一节：claim 失败带 pending + has_farm，新增 session/pending；guest 竞态 conflict 只出「进那个农场」；开关关着统一 503 provider_unavailable；测试码空号按新玩家建，AGE 补走后语音年龄记「过」；isClaimed 的判定；两处文字。
- **v1.5 11-13（邮箱验证码登录）**：文首新增「v1.5 邮箱验证码登录」一节：provider "email"、session/email/start、session/email、claim 认 email、Linked.email 只存 HMAC、开关 P0_EMAIL_LOGIN 和 hello 的 email、错误码 code_expired / email_unavailable、P0Session 的 email_start / sign_in_email。依据亚瑟邮箱方案第 1 节。
- **v1.4 11-14（必须注册，定稿）**：文首新增「v1.4 必须注册」一节，以它为准。改：hello 回 legacy、guest_ok；guest 必须带 pending（`sign_in_required`，`P0_GUEST_OK` 和测试号例外）；claim 改成带凭据，加 consent 和 age_ok；conflict 只在 claim 时出（简化冲突卡）；`unauthenticated` 回登录页；consent-revoked 不解绑；SYS-CLAIMED 页取消。新增：session/logout、session/code（测试码）、/admin/smoke（代替草稿的 /admin/session {create: true}）、/admin/code、/admin/code/revoke；错误码 sign_in_required、bad_code、smoke_only。砍：switch、link、discard_required、already_linked。P0Session：claim(provider, creds, done)、logout、sign_in_code；删 switch_farm、link。依据：草稿 forced-signin/contract-v1.4-draft.md、诸葛亮 v3 第 13 节。
- v1.3 11-13 12:1x：P0Session 加 rename(name, done)（哪吒问）；§2 配置写上 GOOGLE_CLIENT_IDS 的两个值。
- v1.2 11-13 12:0x（周瑜核出 7 处）：§0 加 rename_too_soon；§1 写明名字字段在存档里、guest 带名字 / skip 的冷却、name_locked_until 由苏烈的「重置名字」写、view.account.rename_at 过期回 0；名字相关三处共用一个按 IP 每分钟 20 次的桶；§4 revokeAll 的用法写明，AccountRow 去掉 name_set_at；新增 §4.1 管理端；周瑜的接线方式。
- v1.1 11-13 11:3x：§4 P0Accounts 照实现补齐（ensure / markClaimed / clearClaimed / tokenOwner / userTokenCount / linked / players / path；revokeAll 默认不撤 admin token，要撤带 {admin: true}；AppleLink.refresh 进出都是明文，落盘才加密）。只增不改，已用的签名不变。

# D2 账号服务 —— 实施记录（2026-09-07）

对应 Plane SGODOT-76。D0 已定「统一 Node，在现有 `server/` 上扩展」，本项是社交主线第一块后端。

## 1. 决策

| 问题 | 决定 | 理由 |
|---|---|---|
| 会话模型 | 服务端**每请求**校验 Firebase ID token，不另发自己的 token | 客户端 ApiClient 的 Bearer 本来就是 id_token，刷新也已由 AuthSession 管；RSA 验签有缓存公钥后只是几十微秒；少一套 token 生命周期 |
| 校验实现 | Node `crypto` + Google 公开 JWKS，不引 firebase-admin | admin SDK 要服务账号私钥外加一大坨依赖；校验规则照 Firebase 文档逐条写成测试 |
| 主键 | 自有 uuid `users.id`；Firebase uid 只是 `user_identities` 里的一条 | 08-30 调研 §4.1：账号主键仍为自有 user id，换掉 Firebase 或绑多个登录方式都不动业务表 |
| 与农场 `players` 的关系 | 暂不关联 | 农场在并行分支；并回主线时再决定 players → users 的映射 |
| 删号级联 | `AppDeps.accountModules` 登记 `del` / `export`，按顺序跑，任一失败整个 500 且用户保留 | 不能在服务端还留着一半数据时告诉用户「已删除」 |
| Apple revocation | 墓碑记 `apple_revocation=pending`，队列待 SSLAUNCH A6 拿到 client secret 后实现 | 现在没有 Apple 开发者组织账号 |
| Firebase 侧删用户 | 由客户端 / 网页自己调 Firebase | 服务端没有服务账号；客户端 B4 已实现 accounts:delete |

## 2. 服务端（server/）

- `src/http/firebase_token.ts`：`verifyFirebaseIdToken`（错误码 MALFORMED / BAD_ALG / UNKNOWN_KID /
  BAD_SIGNATURE / EXPIRED / ISSUED_IN_FUTURE / BAD_AUDIENCE / BAD_ISSUER / BAD_SUBJECT）、`CachedJwks`
  （max-age 缓存、未知 kid 强制刷新带 60 s 冷却、拉失败沿用旧钥匙、并发只拉一次）。
- `src/http/accounts.ts`（接口）、`src/http/memory_accounts.ts`、`src/db/pg_accounts.ts`；
  `schema.sql` 新增 users / user_identities / account_deletions；`truncateAll` 同步。
- `src/http/app.ts` 五条路由，见 server/README.md「账号服务」。`healthz.accounts` 报告是否启用。
- `src/index.ts`：`FIREBASE_PROJECT_ID` 不设只告警，账号路由 503，农场路由不受影响。
- 测试：`test/http/firebase_token.test.ts`（12）、`test/http/accounts.test.ts`（13）、
  `test/db/accounts_conformance.test.ts`（内存 + PG 各 5，真库 192.168.124.53 已跑通，含 6 路并发首登）。

## 3. 客户端

- `modules/net/account_api.gd`：`sign_in / me / delete_account / export_data`，统一返回
  `{ok, status, code, reason, ...body}`；网络层失败 code=NETWORK。挂在 `Net.account`。
- `AuthSession.server_user_id`：登录后 `AccountApi.sign_in()` 回填并落盘；换人登录或登出清空。
- 登录页：`complete_sign_in` 后 `_link_account`，失败不阻塞进壳（服务端没部署 / 断网时本地照常）。
- 设置页删号顺序改为 **服务端级联 → Firebase accounts:delete → 本地登出**：服务端要靠还有效的
  ID token 认人。放行的服务端结果：成功、404（老服务器没这条路由）、503 ACCOUNTS_NOT_CONFIGURED；
  其他失败停下让用户重试。
- 测试：`tests/net/test_account_api.gd`、`test_auth_session` 新增 1 条、`test_login_page` 新增 3 条、
  `test_compliance_pages` 新增 3 条。

## 4. 待办 / 依赖

- D1 部署后把 `Net.DEFAULT_BASE` 指到海外服务并配 `FIREBASE_PROJECT_ID=gensen-overseas-dev`；
  M1 出口「登录 → 拿到用户资料」要在海外云上端到端跑一遍。
- SSLAUNCH B4 的 Web 删号页：网页用 Firebase JS 登录后 `POST /v1/account/delete {id_token}`。
- Apple revocation 队列（SSLAUNCH A6 之后）。
- D4 资料 / 关注 / feed 通过 `accountModules` 登记导出与级联。

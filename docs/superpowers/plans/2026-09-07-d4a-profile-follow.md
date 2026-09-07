# D4-a 资料 + 关注 —— 实施记录（2026-09-07）

对应 Plane SGODOT-101（D4 feed / 关注 / 资料 API + R2）的第一块。D4 拆三块做：
**a 资料 + 关注（本篇）→ b feed（Note 时间线 / 点赞 / 一级评论）→ c R2 预签名直传 + CDN**（等 SSLAUNCH D4 开户）。

## 1. 规则来源

`Gensen_US/en-us/Gensen-follow-feature-requirements.md` v1.2（2026-05-11）：

- 单向关注，无需批准，不能关注自己，数量不限。
- 互关 = 密友（Close Friends）；取关只降级，对方仍关注我，不通知。
- 粉丝列表永远公开；「我关注的」列表与计数受隐私开关（关掉后别人看不到关注数）。
- 新粉丝聚合成一个带未读红点的入口；粉丝回关升级为密友。
- 陌生人只能发一条打招呼直到对方回复——归 D3 IM，用这里的 `relation` 判定。
- 文档里的「Rooms 已保存房间数」等语音房相关项归 B6 / D5。

## 2. 决策

| 问题 | 决定 | 理由 |
|---|---|---|
| 资料放哪 | 独立 `profiles` 表，`users.display_name` 挪走 | users 是账号（身份 / 邮箱），资料是用户自己编辑、别人能看的，读写权限与生命周期不同 |
| 密友状态 | 不存，`relation` 由两条 EXISTS 查询判定 | 存第二份状态就要维护一致性；互关本来就是两行 follows |
| 列表分页 | `(created_at, 对方 id)` 键集游标，不用 OFFSET | 大列表 OFFSET 越翻越慢；游标不带任何权限信息 |
| 卡片上的关系 | 每张卡一次 relation 查询（≤50 条） | MVP 先不合并；feed 上量后再改批量 |
| handle | 小写 `[a-z0-9_]{3,20}`，全局唯一，可空 | 与常见社交产品一致；大小写不敏感避免冒充 |
| 装扮 | `avatar` jsonb ≤4 KB，服务端不解释 | 客户端 AvatarConfig 的格式由 avatar 模块管，服务端只做大小门禁 |
| 默认资料 | 首次登录随账号建，昵称 = 邮箱本地部分 | M1 出口「登录 → 拿到用户资料」不该有「还没有资料」这一态 |

## 3. 服务端（server/）

- `src/http/social.ts`：接口、校验（`validatePatch`）、游标、视图、`socialAccountModule`（导出 + 删号级联）。
- `src/http/memory_social.ts`、`src/db/pg_social.ts`；`schema.sql` 新增 profiles / follows，
  `ALTER TABLE users DROP COLUMN IF EXISTS display_name`。
- `src/http/app.ts`：`currentUser` / `socialGuard`；路由见 server/README.md「资料与关注」。
- 测试：`test/http/social.test.ts`（9）、`test/db/social_conformance.test.ts`（4×2，真库跑通）。

## 4. 客户端

- `modules/net/profile_api.gd`（`Net.profile`）：me / update / get_profile / follow / unfollow / following /
  followers / new_followers；`AccountApi.wrap_response` 复用（不能叫 `wrap`：与 GDScript 内置函数同名）。
- 资料页：Tab 显示时拉自己的资料，卡片显示「昵称 @handle · 粉丝 · 关注」，三个输入框 + 保存；
  handle 冲突、字段错误、断网各有提示。Dev 会话与服务端不可达时静默。
- 测试：`tests/net/test_profile_api.gd`（3）、`test_compliance_pages` 新增 3 条。

## 5. 未做 / 后续

- 别人的资料页（关注按钮、粉丝 / 关注列表页、新粉丝页 UI）——B 端页面，等 feed（D4-b）一起做，
  那时才有「从哪点进别人主页」的入口。
- 关注推荐、拉黑联动（E1 UGC 四件套）、房间收藏数：文档明确本期不做或归别的任务。
- 头像图片上传：D4-c R2。

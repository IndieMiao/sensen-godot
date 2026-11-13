# 共用删号主体（SGODOT-484 PR1）

本模块给 App、管理端、网页删号和 Apple 通知复用；入口必须先验证身份及删除授权，再调用
`deleteAccount(deps, player)`。支持码只用于定位，不能证明身份。本 PR 不注册删除路由、不启用定时删除，
不执行真实账号操作。接口依据共享 `store-readiness/contract-accounts.md` §4。

依赖后裔 `feat/accounts-pr-a` 的 `P0Accounts`、`P0Store.find/remove`（开发基座 `59d7d5c0d`）。
已用 PR-A 鉴权做本地 HTTP/WS 联调：删后普通/admin token、旧 ID、claim、WS 和语音入口均拒绝，
旧 socket 排队消息不再重建在线状态，其他账号照常访问。真实部署仍不能仅凭本地测试通过就开启删除入口。

## 顺序和失败处理

1. 从 accounts 取得 Apple 绑定信息；`find()` 返回的 refresh 已解密，仅本次调用持有。
2. 同步完成 `revokeAll` → `markDeleted` → `accounts.remove`。最后一步同时清理管理端 token 和绑定索引。
   已有 deleted 记录不更新日期；其 30 天保留由 accounts 管理。此阶段写盘失败直接拒绝，尚不删除游戏存档。
3. `store.remove` 删除活动存档。写盘失败恢复内存中的存档，后续可以在当前进程或重启后重试。
4. 启动 voice 租约释放、立即 `hub.kick`（WS 4001，清房间和重连位置），再等待 voice 清理。
   删除本人年龄记录、自有和他人黑名单中对本人的关联。举报文件不动，仍按举报保留规则处理。
5. 最后调用注入的 `revokeApple(aud, refresh)`；aud 使用保存的签发方 client_id。

存档、voice 本地文件或 hub 清理失败时，其余清理仍尝试，然后抛出 `ACCOUNT_DELETE_INCOMPLETE`；
调用方不能回复删除成功，应记录需重试并使用同一 player 再调。deleted 记录让存档已不存在时仍可续清理。
同一进程、同一 accounts 实例的同账号并发删除共用一个 Promise；多个账号各自清理。

Apple 撤销按契约为 best effort：错误或缺少 refresh / 回调只记固定事件与支持码，不输出原始异常、
player ID、token 或 refresh。账号行删除后没有跨崩溃持久化的 Apple 撤销重试队列；不能声称已保证外部撤销。
LiveKit 释放沿用现有带租约校验的有限重试机制，避免把复用 peer ID 的其他玩家踢下线。
语音 join 在等待旧租约释放后、异步签名完成后重验房间和租约，避免删号期间挂起的请求再返回授权。

## 预览和验收边界

`previewAccountDeletion` 只读 `store.peek` 和 accounts，输出支持码、存在/已删除状态、绑定类型及农场摘要。
不用会结算包裹的 `store.find/get`，不创建账号、不写盘、不返回名字或第三方凭据。管理端的查号、确认与路由另接。

本模块只清活动数据，不清历史快照、旧归档、运维副本或举报。备份现状以
`store-readiness/data-retention-live.md` 为准，不能沿用早期“所有副本最多 30 天消失”的未核结论。
任何线上删数据操作先报奕星；上线前必须结合 PR-A 在获准的 devserver 隔离副本复演并取得用户批准。

本地测试覆盖：删除顺序、只读预览、全部 token/绑定撤销、账号隔离、举报保留、重复/并发调用、
accounts/存档/语音文件写失败后重试、WS 4001 与重连位置清理、真实语音类配假 LiveKit 的租约释放、
Apple aud 传递及失败日志脱敏。测试只使用临时目录和假 provider。
